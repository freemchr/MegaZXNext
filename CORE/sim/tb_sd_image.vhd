----------------------------------------------------------------------------------
-- MegaZXNext: ZX Next core for the MEGA65
--
-- Testbench for sd_image.vhd (virtual SD card served from an image on the physical card)
--
-- ZX Next side: the ZX Next's own SPI master (rtl/serial/spi_master.vhd), clocked by the CPU
-- clock (28 MHz = 14 MHz SPI, and 3.5 MHz), driven byte by byte like NextZXOS drives port 0xEB.
--
-- Physical side: a behavioural SPI mode SDHC card that answers what M2M's sd_controller sends
-- (init, CMD17, ACMD23 + CMD24), with CRC16 on the read data. It holds a reference image: every
-- sector starts with a pattern derived from its number. It can fail reads with a bad CRC.
--
-- Checks: card init as the ZX Next does it, single and multiple block reads (CMD17/18, across the
-- emulator's 4-buffer wrap), single and multiple block writes (CMD24/25) read back through both
-- sides, the base offset, reads and writes beyond the image, retries after CRC errors, the error
-- counter, the CPU wait during writes, and a slow CPU clock.
--
-- Run: see Makefile in this directory
--
-- MEGA65 port done by Chris Freeman in 2026 and licensed under GPL v3
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_sd_image is
end entity tb_sd_image;

architecture sim of tb_sd_image is

   constant C_CLK_PERIOD   : time    := 35.714 ns;          -- 28 MHz
   constant C_SIZE         : natural := 100;                -- image size in sectors
   constant C_PHYS_SECTORS : natural := 2048;

   -- The image is fragmented: three extents (first virtual sector, first physical sector)
   type ext_t is array (0 to 2) of natural;
   constant C_EXT_V        : ext_t := (0, 37, 70);
   constant C_EXT_P        : ext_t := (1000, 1500, 1200);

   function phys(v : natural) return natural is
   begin
      for i in 2 downto 0 loop
         if v >= C_EXT_V(i) then
            return C_EXT_P(i) + v - C_EXT_V(i);
         end if;
      end loop;
      return 0;
   end function phys;

   subtype byte_t is std_logic_vector(7 downto 0);
   type sector_t is array (0 to 511) of byte_t;

   -- Initial content of a physical sector
   function pattern(lba : natural; idx : natural) return byte_t is
   begin
      return std_logic_vector(to_unsigned((lba * 7 + idx * 13 + lba / 256 + 1) mod 256, 8));
   end function pattern;

   function crc16(data : sector_t) return std_logic_vector is
      variable crc : std_logic_vector(15 downto 0) := (others => '0');
      variable fb  : std_logic;
   begin
      for i in 0 to 511 loop
         for b in 7 downto 0 loop
            fb  := crc(15) xor data(i)(b);
            crc := crc(14 downto 0) & '0';
            if fb = '1' then
               crc := crc xor x"1021";
            end if;
         end loop;
      end loop;
      return crc;
   end function crc16;

   -- Physical card memory
   type mem_pt is protected
      procedure write_byte(lba : natural; idx : natural; val : byte_t);
      impure function read_byte(lba : natural; idx : natural) return byte_t;
      procedure set_failures(lba : natural; n : natural);
      impure function take_failure(lba : natural) return boolean;
      procedure set_latency(n : natural);
      impure function latency return natural;
   end protected mem_pt;

   type mem_pt is protected body
      type mem_t is array (0 to C_PHYS_SECTORS * 512 - 1) of integer range -1 to 255;
      type fail_t is array (0 to C_PHYS_SECTORS - 1) of natural;
      variable mem   : mem_t := (others => -1);        -- -1: still the initial pattern
      variable fails : fail_t := (others => 0);
      variable lat   : natural := 5;               -- bytes between R1 and the data token

      procedure write_byte(lba : natural; idx : natural; val : byte_t) is
      begin
         mem(lba * 512 + idx) := to_integer(unsigned(val));
      end procedure write_byte;

      impure function read_byte(lba : natural; idx : natural) return byte_t is
      begin
         if mem(lba * 512 + idx) < 0 then
            return pattern(lba, idx);
         end if;
         return std_logic_vector(to_unsigned(mem(lba * 512 + idx), 8));
      end function read_byte;

      procedure set_failures(lba : natural; n : natural) is
      begin
         fails(lba) := n;
      end procedure set_failures;

      impure function take_failure(lba : natural) return boolean is
      begin
         if fails(lba) > 0 then
            fails(lba) := fails(lba) - 1;
            return true;
         end if;
         return false;
      end function take_failure;

      procedure set_latency(n : natural) is
      begin
         lat := n;
      end procedure set_latency;

      impure function latency return natural is
      begin
         return lat;
      end function latency;
   end protected body mem_pt;

   shared variable card : mem_pt;

   signal clk           : std_logic := '0';
   signal cpu_clk       : std_logic;
   signal cpu_div_clk   : std_logic := '0';
   signal cpu_slow      : boolean   := false;
   signal reset         : std_logic := '1';
   signal enable        : std_logic := '0';

   -- ZX Next SPI master
   signal zx_ss         : std_logic := '1';
   signal zx_sck        : std_logic;
   signal zx_mosi       : std_logic;
   signal zx_miso       : std_logic;
   signal zx_wr         : std_logic := '0';
   signal zx_dat        : byte_t    := x"FF";
   signal zx_rx         : byte_t;
   signal zx_wait_n     : std_logic;

   -- Physical card
   signal sd_cs_n       : std_logic;
   signal sd_sclk       : std_logic;
   signal sd_mosi       : std_logic;
   signal sd_miso       : std_logic;
   signal card_miso     : std_logic := '1';

   signal cpu_wait      : std_logic;
   signal active        : std_logic;
   signal err_cnt       : std_logic_vector(15 downto 0);
   signal wait_cycles   : natural := 0;
   signal ext_addr      : std_logic_vector(8 downto 0);
   signal ext_data      : std_logic_vector(63 downto 0) := (others => '0');
   signal done          : boolean := false;

begin

   clk <= not clk after C_CLK_PERIOD / 2 when not done;

   -- CPU clock: 28 MHz (the BUFGMUX passes the main clock) or 3.5 MHz
   cpu_div_proc : process (clk)
      variable cnt : natural range 0 to 3 := 0;
   begin
      if rising_edge(clk) then
         if cnt = 3 then
            cnt         := 0;
            cpu_div_clk <= not cpu_div_clk;
         else
            cnt := cnt + 1;
         end if;
      end if;
   end process cpu_div_proc;

   cpu_clk <= cpu_div_clk when cpu_slow else clk;

   i_spi_master : entity work.spi_master
      port map (
         clock_i        => cpu_clk,
         reset_i        => '0',
         spi_sck_o      => zx_sck,
         spi_mosi_o     => zx_mosi,
         spi_miso_i     => zx_miso,
         spi_mosi_wr_i  => zx_wr,
         spi_mosi_dat_i => zx_dat,
         spi_miso_rd_i  => '0',
         spi_miso_dat_o => zx_rx,
         spi_wait_n_o   => zx_wait_n
      );

   i_dut : entity work.sd_image
      generic map (
         G_CLK_HZ       => 28_000_000,
         G_TIMEOUT_MS   => 2
      )
      port map (
         clk_i          => clk,
         reset_i        => reset,
         enable_i       => enable,
         size_i         => std_logic_vector(to_unsigned(C_SIZE, 32)),
         ext_count_i    => std_logic_vector(to_unsigned(3, 10)),
         ext_addr_o     => ext_addr,
         ext_data_i     => ext_data,
         ss_i           => zx_ss,
         sck_i          => zx_sck,
         mosi_i         => zx_mosi,
         miso_o         => zx_miso,
         sd_cs_n_o      => sd_cs_n,
         sd_sclk_o      => sd_sclk,
         sd_mosi_o      => sd_mosi,
         sd_miso_i      => sd_miso,
         cpu_wait_o     => cpu_wait,
         active_o       => active,
         err_cnt_o      => err_cnt
      );

   -- Extent table RAM (one cycle read latency; entries beyond the table read as garbage)
   ext_ram : process (clk)
      variable a : natural;
   begin
      if rising_edge(clk) then
         a := to_integer(unsigned(ext_addr));
         if a <= 2 then
            ext_data <= std_logic_vector(to_unsigned(C_EXT_P(a), 32)) & std_logic_vector(to_unsigned(C_EXT_V(a), 32));
         else
            ext_data <= x"DEADBEEF00000001";
         end if;
      end if;
   end process ext_ram;

   wait_mon : process (clk)
   begin
      if rising_edge(clk) then
         if cpu_wait = '1' then
            wait_cycles <= wait_cycles + 1;
         end if;
      end if;
   end process wait_mon;

   ----------------------------------------------------------------------------------------------
   -- Physical SDHC card (SPI mode 0)
   ----------------------------------------------------------------------------------------------

   sd_miso <= card_miso when sd_cs_n = '0' else '1';

   card_proc : process
      variable rx      : byte_t;
      variable cmd     : natural;
      variable arg     : unsigned(31 downto 0);
      variable app     : boolean := false;
      variable idle    : boolean := true;
      variable data    : sector_t;
      variable crc     : std_logic_vector(15 downto 0);
      variable lba     : natural;

      procedure xfer(o : byte_t; i : out byte_t) is
      begin
         for b in 7 downto 0 loop
            card_miso <= o(b);
            wait until rising_edge(sd_sclk) and sd_cs_n = '0';
            i(b) := sd_mosi;
            wait until falling_edge(sd_sclk);
         end loop;
      end procedure xfer;

      procedure send(o : byte_t) is
         variable dummy : byte_t;
      begin
         xfer(o, dummy);
      end procedure send;

   begin
      card_miso <= '1';
      loop
         xfer(x"FF", rx);
         if rx(7 downto 6) = "01" then
            cmd := to_integer(unsigned(rx(5 downto 0)));
            for i in 3 downto 0 loop
               xfer(x"FF", rx);
               arg(i * 8 + 7 downto i * 8) := unsigned(rx);
            end loop;
            xfer(x"FF", rx);                    -- CRC (enabled by CMD59, not checked here)
            send(x"FF");                        -- NCR

            case cmd is
               when 0 =>
                  idle := true;
                  send(x"01");
               when 8 =>
                  send(x"01"); send(x"00"); send(x"00"); send(x"01"); send(x"AA");
               when 55 =>
                  if idle then send(x"01"); else send(x"00"); end if;
                  app := true;
               when 41 =>
                  if app then
                     idle := false;
                     send(x"00");
                  else
                     send(x"04");
                  end if;
               when 58 =>
                  send(x"00"); send(x"C0"); send(x"FF"); send(x"80"); send(x"00");  -- ready, CCS
               when 16 | 59 =>
                  send(x"00");
               when 23 =>
                  send(x"00");
               when 17 =>
                  lba := to_integer(arg);
                  assert lba < C_PHYS_SECTORS report "card: read beyond the card" severity failure;
                  send(x"00");
                  for i in 1 to card.latency loop send(x"FF"); end loop;
                  for i in 0 to 511 loop data(i) := card.read_byte(lba, i); end loop;
                  crc := crc16(data);
                  if card.take_failure(lba) then
                     crc := crc xor x"0001";
                  end if;
                  send(x"FE");
                  for i in 0 to 511 loop send(data(i)); end loop;
                  send(crc(15 downto 8));
                  send(crc(7 downto 0));
               when 24 =>
                  lba := to_integer(arg);
                  assert lba < C_PHYS_SECTORS report "card: write beyond the card" severity failure;
                  send(x"00");
                  loop
                     xfer(x"FF", rx);
                     exit when rx = x"FE";
                  end loop;
                  for i in 0 to 511 loop
                     xfer(x"FF", rx);
                     data(i) := rx;
                  end loop;
                  xfer(x"FF", rx);
                  crc(15 downto 8) := rx;
                  xfer(x"FF", rx);
                  crc(7 downto 0) := rx;
                  if crc = crc16(data) then
                     for i in 0 to 511 loop card.write_byte(lba, i, data(i)); end loop;
                     send(x"E5");                -- data accepted
                  else
                     report "card: write with a bad CRC" severity error;
                     send(x"EB");                -- CRC error
                  end if;
                  for i in 1 to 20 loop send(x"00"); end loop;     -- busy
               when others =>
                  report "card: unexpected command " & integer'image(cmd) severity error;
                  send(x"04");
            end case;
            if cmd /= 55 then
               app := false;
            end if;
         end if;
      end loop;
   end process card_proc;

   ----------------------------------------------------------------------------------------------
   -- ZX Next
   ----------------------------------------------------------------------------------------------

   stim_proc : process
      variable rx       : byte_t;
      variable buf      : sector_t;
      variable errors   : natural := 0;
      variable polls    : natural;
      variable waits    : natural;

      -- One byte through the ZX Next's SPI master (an OUT to port 0xEB, then IN). The Z80 stalls
      -- on its next I/O cycle while cpu_wait is high.
      procedure xfer(o : byte_t; i : out byte_t) is
      begin
         wait until rising_edge(cpu_clk) and cpu_wait = '0';
         zx_dat <= o;
         zx_wr  <= '1';
         wait until rising_edge(cpu_clk);
         zx_wr  <= '0';
         wait until rising_edge(cpu_clk) and zx_wait_n = '1';
         wait until rising_edge(cpu_clk);
         i := zx_rx;
      end procedure xfer;

      procedure send(o : byte_t) is
         variable dummy : byte_t;
      begin
         xfer(o, dummy);
      end procedure send;

      procedure select_card(s : std_logic) is
      begin
         wait until rising_edge(cpu_clk);
         zx_ss <= s;
      end procedure select_card;

      procedure check(cond : boolean; msg : string) is
      begin
         if not cond then
            report msg severity error;
            errors := errors + 1;
         end if;
      end procedure check;

      -- Send a command, return the R1 response
      procedure command(cmd : natural; arg : natural; crc : byte_t; r1 : out byte_t) is
         variable a : unsigned(31 downto 0);
      begin
         a := to_unsigned(arg, 32);
         send(x"FF");
         send(std_logic_vector(to_unsigned(64 + cmd, 8)));
         send(std_logic_vector(a(31 downto 24)));
         send(std_logic_vector(a(23 downto 16)));
         send(std_logic_vector(a(15 downto 8)));
         send(std_logic_vector(a(7 downto 0)));
         send(crc);
         for n in 1 to 16 loop
            xfer(x"FF", r1);
            exit when r1 /= x"FF";
         end loop;
      end procedure command;

      procedure wait_token(token : byte_t) is
      begin
         polls := 0;
         loop
            xfer(x"FF", rx);
            exit when rx = token;
            check(rx = x"FF", "unexpected byte while waiting for the data token");
            polls := polls + 1;
            assert polls < 200000 report "no data token" severity failure;
         end loop;
      end procedure wait_token;

      procedure read_block(b : out sector_t) is
      begin
         wait_token(x"FE");
         for i in 0 to 511 loop
            xfer(x"FF", b(i));
         end loop;
         send(x"FF");                           -- CRC (not generated by sd_card.sv)
         send(x"FF");
      end procedure read_block;

      procedure check_sector(b : sector_t; plba : natural; msg : string) is
         variable bad : natural := 0;
      begin
         for i in 0 to 511 loop
            if b(i) /= card.read_byte(plba, i) then
               bad := bad + 1;
            end if;
         end loop;
         check(bad = 0, msg & ": " & integer'image(bad) & " bytes differ");
      end procedure check_sector;

      procedure read_sector(v : natural; b : out sector_t) is
      begin
         select_card('0');
         command(17, v, x"FF", rx);
         check(rx = x"00", "CMD17 R1");
         read_block(b);
         select_card('1');
         send(x"FF");
      end procedure read_sector;

      procedure wait_not_busy is
      begin
         polls := 0;
         loop
            xfer(x"FF", rx);
            exit when rx /= x"00";
            polls := polls + 1;
            assert polls < 200000 report "card stays busy" severity failure;
         end loop;
      end procedure wait_not_busy;

      procedure write_block(token : byte_t; seed : natural) is
      begin
         send(x"FF");
         send(token);
         for i in 0 to 511 loop
            send(std_logic_vector(to_unsigned((seed * 31 + i * 5) mod 256, 8)));
         end loop;
         send(x"FF");                           -- CRC
         send(x"FF");
         xfer(x"FF", rx);
         check(rx(4 downto 0) = "00101", "data response");
         wait_not_busy;
      end procedure write_block;

      procedure write_sector(v : natural; seed : natural) is
      begin
         select_card('0');
         command(24, v, x"FF", rx);
         check(rx = x"00", "CMD24 R1");
         write_block(x"FE", seed);
         select_card('1');
         send(x"FF");
      end procedure write_sector;

      procedure check_written(b : sector_t; seed : natural; msg : string) is
         variable bad : natural := 0;
      begin
         for i in 0 to 511 loop
            if b(i) /= std_logic_vector(to_unsigned((seed * 31 + i * 5) mod 256, 8)) then
               bad := bad + 1;
            end if;
         end loop;
         check(bad = 0, msg & ": " & integer'image(bad) & " bytes differ");
      end procedure check_written;

   begin
      card.set_failures(phys(47), 1);        -- recovers on the second try
      card.set_failures(phys(48), 5);        -- fails all three tries

      wait for 1 us;
      wait until rising_edge(clk);
      reset  <= '0';
      enable <= '1';

      -- Card init, as the ZX Next does it
      select_card('1');
      for i in 1 to 10 loop send(x"FF"); end loop;
      select_card('0');
      command(0, 0, x"95", rx);
      check(rx = x"01", "CMD0");
      command(8, 16#1AA#, x"87", rx);
      check(rx = x"01", "CMD8 R1");
      xfer(x"FF", rx); xfer(x"FF", rx); xfer(x"FF", rx); check(rx = x"01", "CMD8 voltage");
      xfer(x"FF", rx); check(rx = x"AA", "CMD8 pattern");
      command(55, 0, x"FF", rx);
      command(41, 16#40000000#, x"FF", rx);
      check(rx = x"00", "ACMD41");
      command(58, 0, x"FF", rx);
      check(rx = x"00", "CMD58 R1");
      xfer(x"FF", rx); check(rx(6) = '1', "CMD58 CCS");
      xfer(x"FF", rx); xfer(x"FF", rx); xfer(x"FF", rx);
      command(9, 0, x"FF", rx);
      check(rx = x"00", "CMD9 R1");
      wait_token(x"FE");
      for i in 0 to 17 loop xfer(x"FF", rx); end loop;
      select_card('1');
      send(x"FF");
      report "init done";

      -- Single block reads, including the first and the last sector of the image
      for v in 0 to 2 loop
         read_sector(v, buf);
         check_sector(buf, phys(v), "read " & integer'image(v));
      end loop;
      read_sector(C_SIZE - 1, buf);
      check_sector(buf, phys(C_SIZE - 1), "read last sector");
      report "single reads done";

      -- Multiple block read across the 4-buffer wrap, stopped with CMD12
      select_card('0');
      command(18, 33, x"FF", rx);               -- crosses the extent boundary at 37
      check(rx = x"00", "CMD18 R1");
      for n in 0 to 8 loop
         read_block(buf);
         check_sector(buf, phys(33 + n), "multi read " & integer'image(n));
      end loop;
      command(12, 0, x"FF", rx);
      wait_not_busy;
      select_card('1');
      send(x"FF");
      report "multiple read done";

      -- CMD12 while the next sector is still being prefetched, then a write at once: the write
      -- must not complete early or land in the wrong sector. A slow card (1.5 ms read latency)
      -- makes sure that the prefetch is still running.
      card.set_latency(2000);
      for n in 0 to 2 loop
         select_card('0');
         command(18, 60 + n, x"FF", rx);
         check(rx = x"00", "CMD18 R1");
         read_block(buf);
         check_sector(buf, phys(60 + n), "short multi read");
         command(12, 0, x"FF", rx);
         wait_not_busy;
         command(24, 70 + n, x"FF", rx);
         check(rx = x"00", "CMD24 R1 after CMD12");
         write_block(x"FE", 20 + n);
         select_card('1');
         send(x"FF");
         read_sector(70 + n, buf);
         check_written(buf, 20 + n, "write after CMD12 " & integer'image(n));
         check_sector(buf, phys(70 + n), "card after CMD12 " & integer'image(n));
         check(card.read_byte(phys(71 + n), 0) = pattern(phys(71 + n), 0) or n = 2,
               "write after CMD12 went to the next sector");
      end loop;
      card.set_latency(5);
      report "CMD12 then write done";

      -- Single block write, read back through the ZX Next and checked on the card
      waits := wait_cycles;
      write_sector(20, 1);
      check(wait_cycles > waits, "no CPU wait during the write");
      read_sector(20, buf);
      check_written(buf, 1, "read back 20");
      check_sector(buf, phys(20), "card 20");
      report "single write done";

      -- Multiple block write, stopped with the stop token
      select_card('0');
      command(25, 30, x"FF", rx);
      check(rx = x"00", "CMD25 R1");
      for n in 0 to 4 loop
         write_block(x"FC", 10 + n);
      end loop;
      send(x"FD");
      send(x"FF");
      wait_not_busy;
      select_card('1');
      send(x"FF");
      for n in 0 to 4 loop
         read_sector(30 + n, buf);
         check_written(buf, 10 + n, "read back " & integer'image(30 + n));
         check_sector(buf, phys(30 + n), "card " & integer'image(30 + n));
      end loop;
      report "multiple write done";

      -- Beyond the image: reads return zeros, writes do not reach the card
      read_sector(C_SIZE, buf);
      for i in 0 to 511 loop
         check(buf(i) = x"00", "read beyond the image");
      end loop;
      write_sector(C_SIZE + 1, 7);
      for k in 0 to 3 loop                      -- the sectors behind each extent
         check(card.read_byte(phys(C_SIZE - 1) + 1 + k, 0) = pattern(phys(C_SIZE - 1) + 1 + k, 0),
               "write beyond the image reached the card");
      end loop;
      report "out of range done";

      -- CRC errors on the card: one retry recovers, three failures are counted
      read_sector(47, buf);
      check_sector(buf, phys(47), "read after a retry");
      check(unsigned(err_cnt) = 0, "error counted although the retry worked");
      read_sector(48, buf);
      check(unsigned(err_cnt) = 1, "failed sector not counted");
      read_sector(49, buf);
      check_sector(buf, phys(49), "read after a failed sector");
      report "error handling done";

      -- Slow CPU clock (3.5 MHz)
      cpu_slow <= true;
      read_sector(7, buf);
      check_sector(buf, phys(7), "slow read");
      write_sector(50, 3);
      read_sector(50, buf);
      check_written(buf, 3, "slow read back");
      report "slow CPU done";

      if errors = 0 then
         report "tb_sd_image: all tests passed" severity note;
      else
         report "tb_sd_image: " & integer'image(errors) & " errors" severity error;
      end if;
      done <= true;
      wait;
   end process stim_proc;

end architecture sim;
