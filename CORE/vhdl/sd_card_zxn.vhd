----------------------------------------------------------------------------------
-- ZX Spectrum Next for MEGA65 (MegaZXNext)
--
-- Virtual SD card: emulates an SPI mode SD card on top of a sector interface
--
-- VHDL translation of MiSTer's sys/sd_card.sv (ZXNext_MiSTer submodule), which the MiSTer
-- ZX Next uses to boot from an image file instead of a real SD card. Fixed to SDHC, one SPI
-- data line (OCTAL=0) and clk_spi = clk_sys (CLK_28), as ZXNext.sv instantiates it, but with
-- the 8 bit buffer interface (WIDE=0; ZXNext.sv uses WIDE=1 for the HPS, the buffer contents
-- are identical).
--
-- The ZX Next talks SPI to this module. Each sector it reads or writes turns into a request on
-- the sector interface (sd_lba_o, sd_rd_o/sd_wr_o, sd_ack_i, sd_buff_*), which is served by
-- sd_image.vhd. Protocol (as in MiSTer's hps_io):
--    * sd_rd_o or sd_wr_o goes high with the sector number in sd_lba_o.
--    * The server raises sd_ack_i and keeps it high while it transfers the 512 bytes through
--      sd_buff_addr_i / sd_buff_dout_i / sd_buff_wr_i (reads) or sd_buff_addr_i /
--      sd_buff_din_o (writes, one clock cycle read latency). sd_rd_o/sd_wr_o drop after
--      sd_ack_i has been seen.
--    * The server drops sd_ack_i when the sector is done.
--
-- Kept bit for bit from the original, including two Verilog sizing details:
--    * "(sd_buf - spi_buf) <= 1" is evaluated in 32 bits, i.e. without wrap-around.
--    * CSD and CID are sent starting with their least significant byte.
--
-- Original: Copyright (c) 2014 Till Harbaum, (c) 2015-2018 Sorgelig, LGPL v3
--           http://elm-chan.org/docs/mmc/mmc_e.html
-- MEGA65 port done by Chris Freeman in 2026 and licensed under GPL v3
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library zxnext;

entity sd_card_zxn is
   port (
      clk_i          : in  std_logic;                       -- clk_sys = clk_spi (28 MHz)
      reset_i        : in  std_logic;

      img_mounted_i  : in  std_logic;                       -- strobe: img_size_i is valid
      img_size_i     : in  std_logic_vector(63 downto 0);   -- image size in bytes

      -- Sector interface
      sd_lba_o       : out std_logic_vector(31 downto 0);
      sd_rd_o        : out std_logic;
      sd_wr_o        : out std_logic;
      sd_ack_i       : in  std_logic;
      sd_buff_addr_i : in  std_logic_vector(8 downto 0);
      sd_buff_dout_i : in  std_logic_vector(7 downto 0);    -- server -> buffer (reads)
      sd_buff_din_o  : out std_logic_vector(7 downto 0);    -- buffer -> server (writes)
      sd_buff_wr_i   : in  std_logic;

      -- SPI interface (sck must be at most clk_i / 2)
      ss_i           : in  std_logic;
      sck_i          : in  std_logic;
      mosi_i         : in  std_logic;
      miso_o         : out std_logic;

      -- Not in the original: no read or write command is in progress
      idle_o         : out std_logic
   );
end entity sd_card_zxn;

architecture rtl of sd_card_zxn is

   constant DATA_TOKEN_CMD25     : std_logic_vector(7 downto 0) := x"FC";
   constant STOP_TRAN            : std_logic_vector(7 downto 0) := x"FD";
   constant DATA_TOKEN           : std_logic_vector(7 downto 0) := x"FE";
   constant WRITE_DATA_RESPONSE  : std_logic_vector(7 downto 0) := x"E5";

   -- number of bytes to wait after a command before sending the reply
   constant NCR                  : natural := 5 + 3;

   type rd_state_t is (RD_STATE_IDLE, RD_STATE_START, RD_STATE_WAIT_IO, RD_STATE_SEND_TOKEN,
                       RD_STATE_SEND_DATA, RD_STATE_WAIT_M);
   type wr_state_t is (WR_STATE_IDLE, WR_STATE_EXP_DTOKEN, WR_STATE_RECV_DATA, WR_STATE_RECV_CRC0,
                       WR_STATE_RECV_CRC1, WR_STATE_SEND_DRESP, WR_STATE_BUSY);
   type pref_state_t is (PREF_STATE_IDLE, PREF_STATE_RD, PREF_STATE_FINISH);

   signal csd_size      : std_logic_vector(26 downto 0) := (others => '0');
   signal csd_sdhc      : std_logic := '0';
   signal csd           : std_logic_vector(127 downto 0);
   constant CID         : std_logic_vector(127 downto 0) := x"CDC700936F2F7300004432383400003E";

   signal sd_lba        : unsigned(31 downto 0) := (others => '0');
   signal sd_rd         : std_logic := '0';
   signal sd_wr         : std_logic := '0';
   signal miso          : std_logic := '1';

   signal buffer_ptr    : unsigned(8 downto 0) := (others => '0');
   signal buffer_din    : std_logic_vector(7 downto 0) := (others => '0');
   signal buffer_dout   : std_logic_vector(7 downto 0);
   signal buffer_wr     : std_logic := '0';

   signal sd_buf        : unsigned(1 downto 0) := (others => '0');
   signal spi_buf       : unsigned(1 downto 0) := (others => '0');

   signal sbuf          : std_logic_vector(6 downto 0) := (others => '0');
   signal bit_cnt       : unsigned(2 downto 0) := (others => '0');

   signal read_state    : rd_state_t := RD_STATE_IDLE;
   signal write_state   : wr_state_t := WR_STATE_IDLE;
   signal pref_state    : pref_state_t := PREF_STATE_IDLE;
   signal cmd           : unsigned(5 downto 0) := (others => '0');
   signal cmd55         : std_logic := '0';
   signal reply         : std_logic_vector(39 downto 0) := (others => '1');
   signal byte_cnt      : unsigned(3 downto 0) := (others => '1');
   signal old_sck       : std_logic := '0';
   signal ack           : std_logic_vector(2 downto 0) := (others => '0');
   signal wait_m_cnt    : unsigned(2 downto 0) := (others => '0');
   signal arg           : std_logic_vector(31 downto 0) := (others => '0');

   signal last_bit      : std_logic;
   signal ibuf          : std_logic_vector(7 downto 0);

   signal addr_a        : std_logic_vector(10 downto 0);
   signal addr_b        : std_logic_vector(10 downto 0);
   signal wren_a        : std_logic;

begin

   -- Four sector buffers: port a = sector interface, port b = SPI side
   addr_a <= std_logic_vector(sd_buf) & sd_buff_addr_i;
   addr_b <= std_logic_vector(spi_buf) & std_logic_vector(buffer_ptr);
   wren_a <= sd_ack_i and sd_buff_wr_i;

   i_sdbuf : entity zxnext.dpram
      generic map (
         addr_width_a => 11,
         data_width_a => 8,
         addr_width_b => 11,
         data_width_b => 8
      )
      port map (
         clock0      => clk_i,
         address_a   => addr_a,
         data_a      => sd_buff_dout_i,
         wren_a      => wren_a,
         q_a         => sd_buff_din_o,
         clock1      => clk_i,
         address_b   => addr_b,
         data_b      => buffer_din,
         wren_b      => buffer_wr,
         q_b         => buffer_dout
      );

   csd_proc : process (clk_i)
   begin
      if rising_edge(clk_i) then
         if img_mounted_i = '1' then
            csd_sdhc               <= '1';
            csd_size(0)            <= '0';
            csd_size(22 downto 1)  <= img_size_i(40 downto 19);   -- in 512K units
            csd_size(26 downto 23) <= (others => '0');
         end if;
      end if;
   end process csd_proc;

   csd <= '0' & csd_sdhc & "000000" & x"0E" & x"00" & x"32" & x"5B" & x"59" & "000000" & csd_size &
          "1111111" & x"80" & x"0A" & x"40" & x"40" & x"F1";

   last_bit <= '1' when bit_cnt = "111" else '0';
   ibuf     <= sbuf & mosi_i;

   sd_lba_o <= std_logic_vector(sd_lba);
   sd_rd_o  <= sd_rd;
   sd_wr_o  <= sd_wr;
   miso_o   <= miso;
   idle_o   <= '1' when read_state = RD_STATE_IDLE and write_state = WR_STATE_IDLE else '0';

   spi_proc : process (clk_i)
      variable bit_idx : integer range 0 to 7;
   begin
      if rising_edge(clk_i) then
         bit_idx := to_integer(not bit_cnt);

         ack(1 downto 0) <= ack(0) & sd_ack_i;
         if ack(1) = ack(0) then
            ack(2) <= ack(1);
         end if;

         if ack(2) = '0' and ack(1) = '1' then
            sd_rd <= '0';
            sd_wr <= '0';
         end if;
         if ack(2) = '1' and ack(1) = '0' then
            sd_buf <= sd_buf + 1;
            sd_lba <= sd_lba + 1;
         end if;

         buffer_wr <= '0';

         if reset_i = '1' then
            bit_cnt     <= (others => '0');
            byte_cnt    <= (others => '1');
            miso        <= '1';
            cmd         <= (others => '0');
            sd_wr       <= '0';
            sd_rd       <= '0';
            read_state  <= RD_STATE_IDLE;
            write_state <= WR_STATE_IDLE;
            pref_state  <= PREF_STATE_IDLE;
         else

            if buffer_wr = '1' then
               if buffer_ptr /= "111111111" then
                  buffer_ptr <= buffer_ptr + 1;
               else
                  spi_buf <= spi_buf + 1;
                  sd_wr   <= '1';
               end if;
            end if;

            case pref_state is
               when PREF_STATE_IDLE =>
                  -- 32 bit unsigned compare in the original: no wrap-around
                  if sd_buf >= spi_buf and sd_buf - spi_buf <= 1 and read_state /= RD_STATE_IDLE and
                     (cmd = 17 or cmd = 18) then
                     sd_rd      <= '1';
                     pref_state <= PREF_STATE_RD;
                  end if;

               when PREF_STATE_RD =>
                  if read_state = RD_STATE_IDLE then
                     pref_state <= PREF_STATE_IDLE;
                  elsif ack(2) = '1' and ack(1) = '0' then
                     if cmd = 18 then
                        pref_state <= PREF_STATE_IDLE;
                     else
                        pref_state <= PREF_STATE_FINISH;
                     end if;
                  end if;

               when PREF_STATE_FINISH =>
                  if read_state = RD_STATE_IDLE then
                     pref_state <= PREF_STATE_IDLE;
                  end if;
            end case;

            old_sck <= sck_i;
            if ss_i = '1' then
               bit_cnt  <= (others => '0');
               byte_cnt <= (others => '1');
               miso     <= '1';
            elsif old_sck = '1' and sck_i = '0' then
               miso <= '1';                     -- default: send 1's (busy/wait)
               if byte_cnt >= NCR then
                  miso  <= reply(39);
                  reply <= reply(38 downto 0) & '1';
               end if;

               -- ---------- read state machine processing -------------
               case read_state is
                  when RD_STATE_IDLE =>
                     null;

                  when RD_STATE_START =>
                     if byte_cnt = NCR and last_bit = '1' then
                        if cmd = 9 or cmd = 10 then
                           read_state <= RD_STATE_SEND_TOKEN;
                        else
                           read_state <= RD_STATE_WAIT_IO;
                        end if;
                     end if;

                  -- waiting for io controller to return data
                  when RD_STATE_WAIT_IO =>
                     if sd_buf /= spi_buf and last_bit = '1' then
                        read_state <= RD_STATE_SEND_TOKEN;
                     end if;

                  -- send data token
                  when RD_STATE_SEND_TOKEN =>
                     miso <= DATA_TOKEN(bit_idx);
                     if last_bit = '1' then
                        read_state <= RD_STATE_SEND_DATA;   -- next: send data
                        buffer_ptr <= (others => '0');
                     end if;

                  -- send data
                  when RD_STATE_SEND_DATA =>
                     if cmd = 9 then
                        miso <= csd(to_integer(buffer_ptr(3 downto 0) & not bit_cnt));
                     elsif cmd = 10 then
                        miso <= CID(to_integer(buffer_ptr(3 downto 0) & not bit_cnt));
                     else
                        miso <= buffer_dout(bit_idx);
                     end if;

                     if last_bit = '1' then
                        -- sent 512 sector data bytes?
                        if cmd = 17 and buffer_ptr = "111111111" then
                           read_state <= RD_STATE_IDLE;
                        elsif cmd = 18 and buffer_ptr = "111111111" then
                           read_state <= RD_STATE_WAIT_M;
                           wait_m_cnt <= (others => '0');

                        -- sent 16 cid/csd data bytes?
                        elsif (cmd = 9 or cmd = 10) and buffer_ptr(3 downto 0) = "1111" then
                           read_state <= RD_STATE_IDLE;

                        -- not done yet -> trigger read of next data byte
                        else
                           buffer_ptr <= buffer_ptr + 1;
                        end if;
                     end if;

                  when RD_STATE_WAIT_M =>
                     if last_bit = '1' then
                        wait_m_cnt <= wait_m_cnt + 1;
                        if wait_m_cnt = "111" then
                           spi_buf    <= spi_buf + 1;
                           read_state <= RD_STATE_WAIT_IO;
                        end if;
                     end if;
               end case;

               -- ------------------ write support ----------------------
               -- send write data response
               if write_state = WR_STATE_SEND_DRESP then
                  miso <= WRITE_DATA_RESPONSE(bit_idx);
               end if;

               -- busy after write until the io controller sends ack
               if write_state = WR_STATE_BUSY then
                  miso <= '0';
               end if;

            elsif old_sck = '0' and sck_i = '1' then

               sbuf    <= sbuf(5 downto 0) & mosi_i;
               bit_cnt <= bit_cnt + 1;

               if last_bit = '1' then
                  -- finished reading one byte
                  -- byte counter runs against 15 byte boundary
                  if byte_cnt /= "1111" then
                     byte_cnt <= byte_cnt + 1;
                  end if;

                  -- byte_cnt > 6 -> complete command received
                  -- first byte of valid command is 01xxxxxx
                  -- don't accept new commands once a write or read command has been accepted
                  if byte_cnt > 5 and
                     ((write_state = WR_STATE_IDLE and read_state = RD_STATE_IDLE and ibuf(7 downto 6) = "01") or
                      (read_state /= RD_STATE_IDLE and ibuf = x"4C")) then
                     byte_cnt <= (others => '0');
                     cmd      <= unsigned(ibuf(5 downto 0));
                     cmd55    <= '1' when cmd = 55 else '0';  -- set cmd55 flag if previous command was 55
                     if unsigned(ibuf(5 downto 0)) = 12 then
                        read_state <= RD_STATE_IDLE;
                     end if;
                  end if;

                  -- parse additional command bytes
                  if byte_cnt = 0 then arg(31 downto 24) <= ibuf; end if;
                  if byte_cnt = 1 then arg(23 downto 16) <= ibuf; end if;
                  if byte_cnt = 2 then arg(15 downto 8)  <= ibuf; end if;
                  if byte_cnt = 3 then arg(7 downto 0)   <= ibuf; end if;

                  -- last byte (crc) received, evaluate
                  if byte_cnt = 4 then

                     -- default:
                     reply <= x"04FFFFFFFF";        -- illegal command

                     case to_integer(cmd) is
                        -- CMD0: GO_IDLE_STATE
                        when 0 =>
                           reply(39 downto 32) <= x"01";          -- ok, busy

                        -- CMD1: SEND_OP_COND
                        when 1 =>
                           reply(39 downto 32) <= x"00";

                        -- CMD8: SEND_IF_COND (V2 only)
                        when 8 =>
                           reply <= x"01000001AA";                -- ok, busy

                        -- CMD9: SEND_CSD, CMD10: SEND_CID
                        when 9 | 10 =>
                           reply(39 downto 32) <= x"00";
                           read_state          <= RD_STATE_START;

                        -- CMD12: STOP_TRANSMISSION
                        when 12 =>
                           reply(39 downto 32) <= x"00";

                        -- CMD13: SEND_STATUS
                        when 13 =>
                           reply(39 downto 24) <= x"0000";

                        -- CMD16: SET_BLOCKLEN (we only support a block size of 512)
                        when 16 =>
                           if unsigned(arg) = 512 then
                              reply(39 downto 32) <= x"00";
                           else
                              reply(39 downto 32) <= x"40";
                           end if;

                        -- CMD17: READ_SINGLE_BLOCK, CMD18: READ_MULTIPLE
                        when 17 | 18 =>
                           reply(39 downto 32) <= x"00";
                           read_state          <= RD_STATE_START;
                           spi_buf             <= (others => '0');
                           sd_buf              <= (others => '0');
                           if csd_sdhc = '1' then
                              sd_lba <= unsigned(arg);
                           else
                              sd_lba <= "000000000" & unsigned(arg(31 downto 9));
                           end if;

                        -- ACMD23: SET_WR_BLK_ERASE_COUNT
                        when 23 =>
                           reply(39 downto 32) <= x"00";

                        -- CMD24: WRITE_BLOCK, CMD25: WRITE_MULTIPLE
                        when 24 | 25 =>
                           reply(39 downto 32) <= x"00";
                           write_state         <= WR_STATE_EXP_DTOKEN;  -- expect data token
                           spi_buf             <= (others => '0');
                           sd_buf              <= (others => '0');
                           if csd_sdhc = '1' then
                              sd_lba <= unsigned(arg);
                           else
                              sd_lba <= "000000000" & unsigned(arg(31 downto 9));
                           end if;

                        -- ACMD41: APP_SEND_OP_COND
                        when 41 =>
                           if cmd55 = '1' then
                              reply(39 downto 32) <= x"00";     -- ok, not busy
                           end if;

                        -- CMD55: APP_COND
                        when 55 =>
                           reply(39 downto 32) <= x"01";        -- ok, busy

                        -- CMD58: READ_OCR (bit 30 = 1 -> high capacity card)
                        when 58 =>
                           reply <= x"00" & '1' & csd_sdhc & "000000000000000000000000000000";

                        -- CMD59: CRC_ON_OFF
                        when 59 =>
                           reply(39 downto 32) <= x"00";

                        when others =>
                           null;
                     end case;
                  end if;

                  -- ---------- handle write -----------
                  case write_state is
                     -- do nothing in idle state
                     when WR_STATE_IDLE =>
                        null;

                     -- waiting for data token
                     when WR_STATE_EXP_DTOKEN =>
                        buffer_ptr <= (others => '0');
                        if cmd = 24 then
                           if ibuf = DATA_TOKEN then
                              write_state <= WR_STATE_RECV_DATA;
                           end if;
                        else
                           if ibuf = DATA_TOKEN_CMD25 then
                              write_state <= WR_STATE_RECV_DATA;
                           end if;
                           if ibuf = STOP_TRAN then
                              write_state <= WR_STATE_IDLE;
                           end if;
                        end if;

                     -- transfer 512 bytes
                     when WR_STATE_RECV_DATA =>
                        -- push one byte into local buffer
                        buffer_wr  <= '1';
                        buffer_din <= ibuf;

                        -- all bytes written?
                        if buffer_ptr = "111111111" then
                           write_state <= WR_STATE_RECV_CRC0;
                        end if;

                     -- transfer 1st crc byte
                     when WR_STATE_RECV_CRC0 =>
                        write_state <= WR_STATE_RECV_CRC1;

                     -- transfer 2nd crc byte
                     when WR_STATE_RECV_CRC1 =>
                        write_state <= WR_STATE_SEND_DRESP;

                     -- send data response
                     when WR_STATE_SEND_DRESP =>
                        write_state <= WR_STATE_BUSY;

                     -- wait for io controller to accept data
                     when WR_STATE_BUSY =>
                        if spi_buf = sd_buf then
                           if cmd = 25 then
                              write_state <= WR_STATE_EXP_DTOKEN;
                           else
                              write_state <= WR_STATE_IDLE;
                           end if;
                        end if;
                  end case;
               end if;
            end if;
         end if;
      end if;
   end process spi_proc;

end architecture rtl;
