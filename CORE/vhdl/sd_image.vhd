----------------------------------------------------------------------------------
-- ZX Spectrum Next for MEGA65 (MegaZXNext)
--
-- SD card image: gives the ZX Next an SD card that is an image file on the MEGA65's SD card
--
-- The ZX Next talks SPI to a virtual SD card (sd_card_zxn.vhd, MiSTer's sd_card.sv). Every
-- sector it reads or writes is served here from the physical SD card. The QNICE Shell
-- (zxn_mount.asm) finds the image file and passes its size and its extents: the pieces of the
-- file on the card, as (first virtual sector, first physical sector) pairs, sorted by virtual
-- sector, the first one starting at 0. A contiguous file is one extent. Sector N of the virtual
-- card is found in the last extent whose first virtual sector is <= N (a linear search in the
-- extent table, at most G_EXT_MAX entries, a few microseconds). While enable_i is high this
-- module owns the physical card (mega65.vhd switches the slot's pins from the framework to the
-- core).
--
-- The physical card is driven by M2M's SD controller (sd_controller in sd_spi.vhd, the one the
-- QNICE Shell uses), clocked at 28 MHz: SPI clock 14 MHz, about 220 kHz during initialization.
-- The handshake with it mirrors QNICE's sdcard.vhd.
--
-- Sectors outside the image read as zeros and are not written. If the card fails, a sector is
-- tried three times; then the sector is acknowledged anyway (reads return whatever arrived) and
-- err_cnt_o counts the failure.
--
-- cpu_wait_o stalls the Z80N (and the DMA) while a write is being stored, as MiSTer does
-- (ZXNext.sv sd_wait). Not in MiSTer: it also stalls while a sector is transferred that nobody
-- waits for any more. sd_card.sv prefetches the next sector of a multiple block read (CMD18).
-- If CMD12 ends the read while that prefetch is still running and the next command (CMD17/24)
-- arrives before it ends, the end of the old transfer advances the new command's sector number
-- and buffer index: a write completes at once and is stored in the next sector. A physical card
-- can take milliseconds to start a read, so the window is real; holding the CPU until the old
-- transfer is done closes it. (tb_sd_image.vhd reproduces the corruption without this.)
--
-- MEGA65 port done by Chris Freeman in 2026 and licensed under GPL v3
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sd_image is
   generic (
      G_CLK_HZ       : natural := 28_000_000;
      G_TIMEOUT_MS   : natural := 500;          -- per sector attempt
      G_EXT_BITS     : natural := 9             -- extent table: 2**G_EXT_BITS entries
   );
   port (
      clk_i          : in  std_logic;           -- 28 MHz, also the ZX Next's SPI side
      reset_i        : in  std_logic;           -- ZX Next reset (resets the virtual card)

      -- Image (static while enable_i is high)
      enable_i       : in  std_logic;           -- 1 = image mounted, the core owns the card
      size_i         : in  std_logic_vector(31 downto 0);   -- in sectors
      ext_count_i    : in  std_logic_vector(G_EXT_BITS downto 0);  -- number of extents (>= 1)

      -- Extent table (a RAM outside, one clock cycle read latency)
      ext_addr_o     : out std_logic_vector(G_EXT_BITS - 1 downto 0);
      ext_data_i     : in  std_logic_vector(63 downto 0);  -- physical & virtual first sector

      -- SPI from the ZX Next (its SD0 chip select)
      ss_i           : in  std_logic;
      sck_i          : in  std_logic;
      mosi_i         : in  std_logic;
      miso_o         : out std_logic;

      -- Physical SD card
      sd_cs_n_o      : out std_logic;
      sd_sclk_o      : out std_logic;
      sd_mosi_o      : out std_logic;
      sd_miso_i      : in  std_logic;

      cpu_wait_o     : out std_logic;
      active_o       : out std_logic;           -- a sector is being transferred
      err_cnt_o      : out std_logic_vector(15 downto 0)
   );
end entity sd_image;

architecture synthesis of sd_image is

   constant C_TIMEOUT   : natural := G_CLK_HZ / 1000 * G_TIMEOUT_MS;
   constant C_RETRIES   : natural := 3;

   -- Virtual card
   signal vsd_reset     : std_logic;
   signal img_mounted   : std_logic := '0';
   signal enable_d      : std_logic := '0';
   signal sd_lba        : std_logic_vector(31 downto 0);
   signal sd_rd         : std_logic;
   signal sd_wr         : std_logic;
   signal sd_ack        : std_logic := '0';
   signal sd_buff_addr  : unsigned(8 downto 0) := (others => '0');
   signal sd_buff_dout  : std_logic_vector(7 downto 0) := (others => '0');
   signal sd_buff_din   : std_logic_vector(7 downto 0);
   signal sd_buff_wr    : std_logic := '0';
   signal sd_wait       : std_logic := '0';
   signal vsd_idle      : std_logic;

   -- Physical card
   signal ctl_reset     : std_logic;
   signal ctl_rd        : std_logic := '0';
   signal ctl_wr        : std_logic := '0';
   signal ctl_addr      : std_logic_vector(31 downto 0) := (others => '0');
   signal ctl_dout      : std_logic_vector(7 downto 0);
   signal ctl_dout_avail: std_logic;
   signal ctl_dout_taken: std_logic := '0';
   signal ctl_din       : std_logic_vector(7 downto 0) := (others => '0');
   signal ctl_din_valid : std_logic := '0';
   signal ctl_din_taken : std_logic;
   signal ctl_error     : std_logic;
   signal ctl_busy      : std_logic;

   type state_t is (
      s_idle,
      s_lookup, s_lookup_wait, s_lookup_cmp,   -- find the extent of the requested sector
      s_zero,                 -- read outside the image: fill the buffer with zeros
      s_rd_start, s_rd_data, s_rd_taken,
      s_wr_start, s_wr_fetch, s_wr_data,
      s_finish,               -- wait for the controller to become idle, check for errors
      s_ack_off               -- drop sd_ack and give sd_card_zxn time to see it
   );
   signal state         : state_t := s_idle;
   signal is_write      : std_logic := '0';
   signal started       : std_logic := '0';   -- the controller has accepted the command
   signal failed        : std_logic := '0';
   signal tries         : natural range 0 to C_RETRIES := 0;
   signal timer         : natural range 0 to C_TIMEOUT := 0;
   signal wait_cnt      : natural range 0 to 7 := 0;
   signal wait_lookup   : std_logic := '0';
   signal err_cnt       : unsigned(15 downto 0) := (others => '0');

   -- Extent lookup
   signal req_lba       : unsigned(31 downto 0) := (others => '0');
   signal ext_idx       : unsigned(G_EXT_BITS downto 0) := (others => '0');
   signal ext_addr      : unsigned(G_EXT_BITS - 1 downto 0) := (others => '0');
   signal ext_vstart    : unsigned(31 downto 0) := (others => '0');   -- of the current extent
   signal ext_pstart    : unsigned(31 downto 0) := (others => '0');

begin

   ----------------------------------------------------------------------------------------------
   -- Virtual SD card
   ----------------------------------------------------------------------------------------------

   vsd_reset <= reset_i or not enable_i;

   -- img_mounted strobe (sets the card size in the CSD)
   mount_proc : process (clk_i)
   begin
      if rising_edge(clk_i) then
         enable_d    <= enable_i;
         img_mounted <= enable_i and not enable_d;
      end if;
   end process mount_proc;

   i_sd_card : entity work.sd_card_zxn
      port map (
         clk_i          => clk_i,
         reset_i        => vsd_reset,
         img_mounted_i  => img_mounted,
         img_size_i     => "00000000000000000000000" & size_i & "000000000",   -- sectors * 512
         sd_lba_o       => sd_lba,
         sd_rd_o        => sd_rd,
         sd_wr_o        => sd_wr,
         sd_ack_i       => sd_ack,
         sd_buff_addr_i => std_logic_vector(sd_buff_addr),
         sd_buff_dout_i => sd_buff_dout,
         sd_buff_din_o  => sd_buff_din,
         sd_buff_wr_i   => sd_buff_wr,
         ss_i           => ss_i,
         sck_i          => sck_i,
         mosi_i         => mosi_i,
         miso_o         => miso_o,
         idle_o         => vsd_idle
      );

   -- Stall the CPU from the end of a write until it has been stored (MiSTer: ZXNext.sv sd_wait)
   wait_proc : process (clk_i)
   begin
      if rising_edge(clk_i) then
         sd_wait <= (sd_wait and sd_ack) or sd_wr;
      end if;
   end process wait_proc;

   cpu_wait_o <= sd_wait or (sd_ack and vsd_idle);

   ----------------------------------------------------------------------------------------------
   -- Physical SD card
   ----------------------------------------------------------------------------------------------

   ctl_reset <= not enable_i;

   i_sd_controller : entity work.sd_controller
      generic map (
         clockRate         => G_CLK_HZ
      )
      port map (
         cs                => sd_cs_n_o,
         mosi              => sd_mosi_o,
         miso              => sd_miso_i,
         sclk              => sd_sclk_o,
         card_present      => '1',
         card_write_prot   => '0',
         rd                => ctl_rd,
         rd_multiple       => '0',
         dout              => ctl_dout,
         dout_avail        => ctl_dout_avail,
         dout_taken        => ctl_dout_taken,
         wr                => ctl_wr,
         wr_multiple       => '0',
         din               => ctl_din,
         din_valid         => ctl_din_valid,
         din_taken         => ctl_din_taken,
         addr              => ctl_addr,
         erase_count       => (others => '0'),
         sd_error          => ctl_error,
         sd_busy           => ctl_busy,
         sd_error_code     => open,
         reset             => ctl_reset,
         clk               => clk_i,
         sd_type           => open,
         sd_fsm            => open
      );

   ----------------------------------------------------------------------------------------------
   -- Sector engine
   ----------------------------------------------------------------------------------------------

   engine_proc : process (clk_i)
   begin
      if rising_edge(clk_i) then
         sd_buff_wr <= '0';

         -- Watchdog for one attempt on the physical card
         if timer /= 0 then
            timer <= timer - 1;
         end if;

         -- The controller raises busy when it accepts a command; errors before that are stale
         if (ctl_rd = '1' or ctl_wr = '1') and ctl_busy = '1' then
            started <= '1';
         end if;

         case state is
            when s_idle =>
               sd_ack       <= '0';
               sd_buff_addr <= (others => '0');
               tries        <= 0;
               if enable_i = '1' and (sd_rd = '1' or sd_wr = '1') then
                  sd_ack   <= '1';
                  is_write <= sd_wr;
                  wait_cnt <= 7;                -- minimum sd_ack pulse (see s_ack_off)
                  req_lba  <= unsigned(sd_lba);
                  if unsigned(sd_lba) >= unsigned(size_i) then
                     -- Outside the image: reads return zeros, writes are dropped
                     if sd_wr = '1' then
                        state <= s_ack_off;
                     else
                        state <= s_zero;
                     end if;
                  else
                     ext_addr <= (others => '0');
                     ext_idx  <= (others => '0');
                     state    <= s_lookup_wait;
                  end if;
               end if;

            -- Extent lookup: ext_vstart/ext_pstart hold extent ext_idx, ext_addr = ext_idx + 1 is
            -- being read. Advance while the next extent starts at or before the requested sector.
            when s_lookup_wait =>               -- RAM read latency
               state <= s_lookup;

            when s_lookup =>                    -- extent 0 arrives
               ext_vstart <= unsigned(ext_data_i(31 downto 0));
               ext_pstart <= unsigned(ext_data_i(63 downto 32));
               ext_addr   <= to_unsigned(1, G_EXT_BITS);
               state      <= s_lookup_cmp;

            when s_lookup_cmp =>
               if wait_lookup = '0' then
                  wait_lookup <= '1';           -- RAM read latency for extent ext_idx + 1
               else
                  wait_lookup <= '0';
                  if ext_idx + 1 < unsigned(ext_count_i) and
                     unsigned(ext_data_i(31 downto 0)) <= req_lba then
                     ext_vstart <= unsigned(ext_data_i(31 downto 0));
                     ext_pstart <= unsigned(ext_data_i(63 downto 32));
                     ext_idx    <= ext_idx + 1;
                     ext_addr   <= resize(ext_idx + 2, G_EXT_BITS);
                  else
                     ctl_addr <= std_logic_vector(ext_pstart + (req_lba - ext_vstart));
                     timer    <= C_TIMEOUT;
                     if is_write = '1' then
                        state <= s_wr_start;
                     else
                        state <= s_rd_start;
                     end if;
                  end if;
               end if;

            when s_zero =>
               sd_buff_dout <= (others => '0');
               sd_buff_wr   <= '1';
               if sd_buff_wr = '1' then
                  sd_buff_addr <= sd_buff_addr + 1;
                  if sd_buff_addr = 511 then
                     sd_buff_wr <= '0';
                     state      <= s_ack_off;
                  end if;
               end if;

            -- Read: as sdcard.vhd, rd stays high until all 512 bytes have been taken
            when s_rd_start =>
               sd_buff_addr <= (others => '0');
               failed       <= '0';
               if ctl_busy = '0' then
                  ctl_rd  <= '1';
                  started <= '0';
                  timer   <= C_TIMEOUT;
                  state   <= s_rd_data;
               elsif timer = 0 then             -- the card does not become ready
                  failed  <= '1';
                  state   <= s_finish;
               end if;

            when s_rd_data =>
               if ctl_dout_avail = '1' then
                  sd_buff_dout   <= ctl_dout;
                  sd_buff_wr     <= '1';
                  ctl_dout_taken <= '1';
                  state          <= s_rd_taken;
               elsif (started = '1' and ctl_error = '1') or timer = 0 then
                  ctl_rd <= '0';
                  failed <= '1';
                  timer  <= C_TIMEOUT;
                  state  <= s_finish;
               end if;

            when s_rd_taken =>
               if ctl_dout_avail = '0' then
                  ctl_dout_taken <= '0';
                  if sd_buff_addr = 511 then
                     ctl_rd <= '0';
                     timer  <= C_TIMEOUT;
                     state  <= s_finish;
                  else
                     sd_buff_addr <= sd_buff_addr + 1;
                     state        <= s_rd_data;
                  end if;
               end if;

            -- Write: wr drops when the 512th byte has been taken, as in sdcard.vhd
            when s_wr_start =>
               sd_buff_addr <= (others => '0');
               failed       <= '0';
               if ctl_busy = '0' then
                  ctl_wr  <= '1';
                  started <= '0';
                  timer   <= C_TIMEOUT;
                  state   <= s_wr_fetch;
               elsif timer = 0 then             -- the card does not become ready
                  failed  <= '1';
                  state   <= s_finish;
               end if;

            when s_wr_fetch =>                  -- buffer read latency: one cycle
               state <= s_wr_data;

            when s_wr_data =>
               ctl_din       <= sd_buff_din;
               ctl_din_valid <= '1';
               if ctl_din_valid = '1' and ctl_din_taken = '1' then
                  ctl_din_valid <= '0';
                  if sd_buff_addr = 511 then
                     ctl_wr <= '0';
                     timer  <= C_TIMEOUT;
                     state  <= s_finish;
                  else
                     sd_buff_addr <= sd_buff_addr + 1;
                     state        <= s_wr_fetch;
                  end if;
               elsif (started = '1' and ctl_error = '1') or timer = 0 then
                  ctl_din_valid <= '0';
                  ctl_wr        <= '0';
                  failed        <= '1';
                  timer         <= C_TIMEOUT;
                  state         <= s_finish;
               end if;

            -- Wait until the controller is idle again (a write is complete only then)
            when s_finish =>
               if ctl_busy = '0' or timer = 0 then
                  if (failed = '1' or ctl_error = '1' or timer = 0) and tries < C_RETRIES - 1 then
                     tries <= tries + 1;
                     timer <= C_TIMEOUT;
                     if is_write = '1' then
                        state <= s_wr_start;
                     else
                        state <= s_rd_start;
                     end if;
                  else
                     if failed = '1' or ctl_error = '1' or timer = 0 then
                        err_cnt <= err_cnt + 1;
                     end if;
                     state <= s_ack_off;
                  end if;
               end if;

            -- sd_card_zxn filters sd_ack (it needs two equal samples): keep it high, and then low,
            -- for a few cycles. A sector beyond the image would otherwise give a 1 cycle pulse.
            when s_ack_off =>
               if wait_cnt /= 0 then
                  wait_cnt <= wait_cnt - 1;
               elsif sd_ack = '1' then
                  sd_ack   <= '0';
                  wait_cnt <= 7;
               else
                  state <= s_idle;
               end if;
         end case;

         if enable_i = '0' then
            state          <= s_idle;
            sd_ack         <= '0';
            ctl_rd         <= '0';
            ctl_wr         <= '0';
            ctl_dout_taken <= '0';
            ctl_din_valid  <= '0';
         end if;
      end if;
   end process engine_proc;

   ext_addr_o <= std_logic_vector(ext_addr);

   active_o  <= sd_ack;
   err_cnt_o <= std_logic_vector(err_cnt);

end architecture synthesis;
