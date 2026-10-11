----------------------------------------------------------------------------------
-- ZX Spectrum Next for MEGA65 (MegaZXNext)
--
-- Testbench for sdram_zxn.vhd
--
-- The SDRAM model (sdram_model.vhd, by MJoergen) checks the SDRAM protocol and
-- timing (tRCD, tRP, tRC, tMRD, bank states). The board is modelled with I/O
-- delays: all FPGA outputs (commands, data, SDRAM clock) are delayed by
-- C_T_OUT (IOB clock-to-pad) and the read data by C_T_IN (pad-to-IOB).
--
-- The testbench drives the ZX Next's two memory ports like zxnext.vhd does:
--    Port A (CPU):     request pulse in the 28 MHz domain, wait handshake
--    Port B (Layer 2): toggle request, no handshake
-- and checks all data against a reference memory.
--
-- Port A models the timing that CORE.xdc allows (2 cycles of the 112 MHz clock in both
-- directions):
--    * The ZX Next launches a request on a rising or a falling edge of CLK_28. Until the
--      inputs have settled (at most 2 cycles later) they carry garbage: a request glitch
--      and a write to an address that is checked later. Some cycles settle to "no request".
--    * The request is a pulse that ends after the next rising edge of CLK_28 (sram_req_t).
--    * The CPU sees ram_a_wait / ram_a_do 2 cycles after they changed, on each edge of
--      CLK_28; they must therefore only change on those edges (checked).
--
-- Run: see Makefile in this directory
--
-- MEGA65 port done by Chris Freeman in 2026 and licensed under GPL v3
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_sdram_zxn is
   generic (
      G_T_OUT : time := 4.0 ns;     -- FPGA output delay (clock-to-pad)
      G_T_IN  : time := 1.0 ns      -- FPGA input delay (pad-to-register)
   );
end entity tb_sdram_zxn;

architecture sim of tb_sdram_zxn is

   constant C_T112     : time := 8929 ps;             -- 112 MHz
   constant C_NUM_RAND : natural := 400;
   constant C_T_HOLD   : time := 800 ps;              -- min. delay ZX Next -> port A inputs
   constant C_T_PATH   : time := 2 * C_T112 - 100 ps; -- max. delay port A outputs -> CPU

   signal clk112       : std_logic := '0';
   signal clk28        : std_logic := '0';
   signal rst112       : std_logic := '1';
   signal running      : boolean := true;

   -- ZX Next ports
   signal a_addr       : std_logic_vector(20 downto 0) := (others => '0');
   signal a_req        : std_logic := '0';
   signal a_rd_n       : std_logic := '0';
   signal a_di         : std_logic_vector(7 downto 0) := (others => '0');
   signal a_do         : std_logic_vector(7 downto 0);
   signal a_wait       : std_logic;
   signal a_do_cpu     : std_logic_vector(7 downto 0);  -- as seen by the CPU
   signal a_wait_cpu   : std_logic;
   signal b_addr       : std_logic_vector(20 downto 0) := (others => '0');
   signal b_req        : std_logic := '0';
   signal b_do         : std_logic_vector(7 downto 0);

   -- FPGA side of the SDRAM interface
   signal f_clk, f_cke, f_cs_n, f_ras_n, f_cas_n, f_we_n, f_dqml, f_dqmh : std_logic;
   signal f_ba         : std_logic_vector(1 downto 0);
   signal f_a          : std_logic_vector(12 downto 0);
   signal f_dq_out     : std_logic_vector(15 downto 0);
   signal f_dq_oe_n    : std_logic_vector(15 downto 0);
   signal f_dq_in      : std_logic_vector(15 downto 0);
   signal f_dq_drive   : std_logic_vector(15 downto 0);

   -- Board side (pads of the SDRAM)
   signal p_clk, p_cke, p_cs_n, p_ras_n, p_cas_n, p_we_n, p_dqml, p_dqmh : std_logic;
   signal p_ba         : std_logic_vector(1 downto 0);
   signal p_a          : std_logic_vector(12 downto 0);
   signal p_dq         : std_logic_vector(15 downto 0);

   type ref_t is array (0 to 2**21 - 1) of std_logic_vector(7 downto 0);

   signal errors       : natural := 0;

   -- Layer 2 streaming test
   constant C_L2_BASE  : natural := 16#40000#;
   constant C_L2_LINES : natural := 24;
   signal l2_run       : boolean := false;
   signal b_addr_s     : std_logic_vector(20 downto 0) := (others => '0');   -- driven by stim_proc
   signal b_req_s      : std_logic := '0';
   signal b_addr_l     : std_logic_vector(20 downto 0) := (others => '0');   -- driven by l2_proc
   signal b_req_l      : std_logic := '0';
   signal l2_done      : boolean := false;
   signal l2_errs_seq  : natural := 0;      -- errors on sequential fetches
   signal l2_errs_jmp  : natural := 0;      -- errors right after a non-sequential jump
   signal l2_count     : natural := 0;

   -- deterministic Layer 2 test pattern
   function l2_pattern(ad : natural) return std_logic_vector is
   begin
      return std_logic_vector(to_unsigned((ad * 7 + ad / 256) mod 256, 8));
   end function l2_pattern;

begin

   ---------------------------------------------------------------------------------------
   -- Clocks: 112 MHz and 28 MHz, phase aligned
   ---------------------------------------------------------------------------------------

   clk_proc : process
      variable cnt : natural := 0;
   begin
      while running loop
         clk112 <= '1';
         if cnt mod 4 = 0 then clk28 <= '1'; end if;
         if cnt mod 4 = 2 then clk28 <= '0'; end if;
         wait for C_T112 / 2;
         clk112 <= '0';
         wait for C_T112 / 2;
         cnt := cnt + 1;
      end loop;
      wait;
   end process clk_proc;

   rst112 <= '1', '0' after 200 ns;

   b_addr <= b_addr_l when l2_run else b_addr_s;
   b_req  <= b_req_l  when l2_run else b_req_s;

   ---------------------------------------------------------------------------------------
   -- DUT
   ---------------------------------------------------------------------------------------

   i_dut : entity work.sdram_zxn
      port map (
         clk_i           => clk112,
         rst_i           => rst112,
         clk_28_i        => clk28,
         ram_a_addr_i    => a_addr,
         ram_a_req_i     => a_req,
         ram_a_rd_n_i    => a_rd_n,
         ram_a_di_i      => a_di,
         ram_a_do_o      => a_do,
         ram_a_wait_o    => a_wait,
         ram_b_addr_i    => b_addr,
         ram_b_req_i     => b_req,
         ram_b_do_o      => b_do,
         sdram_clk_o     => f_clk,
         sdram_cke_o     => f_cke,
         sdram_cs_n_o    => f_cs_n,
         sdram_ras_n_o   => f_ras_n,
         sdram_cas_n_o   => f_cas_n,
         sdram_we_n_o    => f_we_n,
         sdram_ba_o      => f_ba,
         sdram_a_o       => f_a,
         sdram_dqml_o    => f_dqml,
         sdram_dqmh_o    => f_dqmh,
         sdram_dq_out_o  => f_dq_out,
         sdram_dq_oe_n_o => f_dq_oe_n,
         sdram_dq_in_i   => f_dq_in
      );

   ---------------------------------------------------------------------------------------
   -- Port A outputs: path delay to the CPU; they may only change on an edge of CLK_28
   ---------------------------------------------------------------------------------------

   a_wait_cpu <= transport a_wait after C_T_PATH;
   a_do_cpu   <= transport a_do   after C_T_PATH;

   a_out_check : process (a_wait, a_do)
   begin
      if now > 1 us then
         assert clk28'last_event = 0 ns
            report "Port A output changed on a 112 MHz edge without a CLK_28 edge" severity error;
      end if;
   end process a_out_check;

   ---------------------------------------------------------------------------------------
   -- Board: I/O delays and tri-state bus
   ---------------------------------------------------------------------------------------

   p_clk   <= transport f_clk   after G_T_OUT;
   p_cke   <= transport f_cke   after G_T_OUT;
   p_cs_n  <= transport f_cs_n  after G_T_OUT;
   p_ras_n <= transport f_ras_n after G_T_OUT;
   p_cas_n <= transport f_cas_n after G_T_OUT;
   p_we_n  <= transport f_we_n  after G_T_OUT;
   p_ba    <= transport f_ba    after G_T_OUT;
   p_a     <= transport f_a     after G_T_OUT;
   p_dqml  <= transport f_dqml  after G_T_OUT;
   p_dqmh  <= transport f_dqmh  after G_T_OUT;

   dq_gen : for i in 0 to 15 generate
      f_dq_drive(i) <= f_dq_out(i) when f_dq_oe_n(i) = '0' else 'Z';
   end generate dq_gen;

   p_dq    <= transport f_dq_drive after G_T_OUT;
   f_dq_in <= transport to_x01(p_dq) after G_T_IN;

   i_sdram : entity work.sdram_sim
      generic map (
         G_RAM_DEBUG  => false,
         G_RAM_SIZE   => 21,           -- row (11 bits) & column (10 bits)
         G_CLK_PERIOD => C_T112
      )
      port map (
         sdram_clk_i   => p_clk,
         sdram_cke_i   => p_cke,
         sdram_ras_n_i => p_ras_n,
         sdram_cas_n_i => p_cas_n,
         sdram_we_n_i  => p_we_n,
         sdram_cs_n_i  => p_cs_n,
         sdram_ba_i    => p_ba,
         sdram_a_i     => p_a,
         sdram_dqml_i  => p_dqml,
         sdram_dqmh_i  => p_dqmh,
         sdram_dq_io   => p_dq
      );

   ---------------------------------------------------------------------------------------
   -- Stimulus
   ---------------------------------------------------------------------------------------

   stim_proc : process
      variable ref     : ref_t;
      variable written : std_logic_vector(0 to 2**21 - 1) := (others => '0');
      variable lfsr    : unsigned(31 downto 0) := x"1234_5678";
      variable addr    : std_logic_vector(20 downto 0);
      variable data    : std_logic_vector(7 downto 0);
      variable rdata   : std_logic_vector(7 downto 0);
      variable t0      : time;
      type addr_list_t is array (0 to C_NUM_RAND - 1) of std_logic_vector(20 downto 0);
      variable alist   : addr_list_t := (others => (others => '0'));
      variable errs    : natural := 0;
      variable cpu_n   : natural := 0;

      impure function rnd return unsigned is
      begin
         lfsr := lfsr(30 downto 0) & (lfsr(31) xor lfsr(21) xor lfsr(1) xor lfsr(0));
         return lfsr;
      end function rnd;

      -- Start a bus cycle on a rising or a falling edge of CLK_28. Until the inputs settle they
      -- show a request and a write of random data to an address that is checked later.
      procedure a_launch(constant ad : in std_logic_vector(20 downto 0); constant rd_n : in std_logic;
                         constant wd : in std_logic_vector(7 downto 0); constant req : in std_logic) is
         variable t_end : time;
         variable t_set : time;
      begin
         if rnd(0) = '1' then
            wait until falling_edge(clk28);
            t_end := 2 * C_T112 + C_T_HOLD;
         else
            wait until rising_edge(clk28);
            t_end := 4 * C_T112 + C_T_HOLD;
         end if;
         -- settle between C_T_HOLD and 2 cycles minus 1.9 ns
         t_set := C_T_HOLD + 100 ps + (to_integer(rnd(9 downto 0)) mod 150) * 100 ps;
         a_addr <= transport alist(to_integer(rnd(15 downto 0)) mod C_NUM_RAND) after C_T_HOLD, ad after t_set;
         a_rd_n <= transport '1' after C_T_HOLD, rd_n after t_set;
         a_di   <= transport std_logic_vector(rnd(7 downto 0)) after C_T_HOLD, wd after t_set;
         if req = '1' then
            a_req <= transport '1' after C_T_HOLD, '0' after t_end;
         else
            a_req <= transport '1' after C_T_HOLD, '0' after t_set;
         end if;
      end procedure a_launch;

      procedure a_access(constant ad : in std_logic_vector(20 downto 0); constant rd_n : in std_logic;
                         constant wd : in std_logic_vector(7 downto 0); variable rd : out std_logic_vector(7 downto 0)) is
      begin
         -- sometimes a bus cycle without a memory request first
         if rnd(1 downto 0) = "00" then
            a_launch(ad, rd_n, wd, '0');
         end if;
         a_launch(ad, rd_n, wd, '1');
         -- the CPU samples wait (and data) on each edge of CLK_28, starting one cycle after the launch
         wait on clk28;
         wait on clk28;
         while a_wait_cpu = '1' loop
            wait on clk28;
         end loop;
         rd := a_do_cpu;
      end procedure a_access;

      procedure a_write(constant ad : in std_logic_vector(20 downto 0); constant wd : in std_logic_vector(7 downto 0)) is
         variable dummy : std_logic_vector(7 downto 0);
      begin
         a_access(ad, '1', wd, dummy);
         ref(to_integer(unsigned(ad)))     := wd;
         written(to_integer(unsigned(ad))) := '1';
      end procedure a_write;

      procedure a_check(constant ad : in std_logic_vector(20 downto 0)) is
         variable rd : std_logic_vector(7 downto 0);
      begin
         a_access(ad, '0', x"00", rd);
         if written(to_integer(unsigned(ad))) = '1' and rd /= ref(to_integer(unsigned(ad))) then
            report "Port A mismatch @ " & to_hstring(ad) & ": read " & to_hstring(rd) &
                   " expected " & to_hstring(ref(to_integer(unsigned(ad)))) severity error;
            errs := errs + 1;
         end if;
      end procedure a_check;

      procedure b_check(constant ad : in std_logic_vector(20 downto 0)) is
      begin
         wait until rising_edge(clk28);
         b_addr_s <= ad;
         b_req_s  <= not b_req_s;
         t0     := now;
         -- data must arrive within 250 ns (the ZX Next's Layer 2 has no wait handshake)
         for i in 1 to 7 loop
            wait until rising_edge(clk28);
         end loop;
         if written(to_integer(unsigned(ad))) = '1' and b_do /= ref(to_integer(unsigned(ad))) then
            report "Port B mismatch @ " & to_hstring(ad) & ": read " & to_hstring(b_do) &
                   " expected " & to_hstring(ref(to_integer(unsigned(ad)))) severity error;
            errs := errs + 1;
         end if;
      end procedure b_check;

   begin
      -- wait for the SDRAM initialization (100 us power-up + init sequence)
      wait for 120 us;
      report "SDRAM initialized, starting test";

      -- 1) random byte writes over the whole 2 MB address space
      for i in 0 to C_NUM_RAND - 1 loop
         addr     := std_logic_vector(rnd(20 downto 0));
         alist(i) := addr;
         data     := std_logic_vector(rnd(7 downto 0));
         a_write(addr, data);
      end loop;
      report "random writes done";

      -- 2) read back through port A
      for i in 0 to C_NUM_RAND - 1 loop
         a_check(alist(i));
      end loop;
      report "port A random reads done";

      -- 3) read back through port B
      for i in 0 to C_NUM_RAND - 1 loop
         b_check(alist(i));
      end loop;
      report "port B random reads done";

      -- 4) sequential writes and reads (exercises the 32-bit read cache)
      for i in 0 to 255 loop
         a_write(std_logic_vector(to_unsigned(16#10000# + i, 21)), std_logic_vector(to_unsigned(255 - i, 8)));
      end loop;
      for i in 0 to 255 loop
         a_check(std_logic_vector(to_unsigned(16#10000# + i, 21)));
      end loop;
      for i in 0 to 255 loop
         b_check(std_logic_vector(to_unsigned(16#10000# + i, 21)));
      end loop;
      report "sequential access done";

      -- 5) write after cached read to the same 32-bit word (cache invalidation)
      a_check(std_logic_vector(to_unsigned(16#10004#, 21)));
      a_write(std_logic_vector(to_unsigned(16#10005#, 21)), x"A5");
      a_check(std_logic_vector(to_unsigned(16#10005#, 21)));
      a_check(std_logic_vector(to_unsigned(16#10004#, 21)));

      -- 5b) CPU write to a word cached by port B (port B cache invalidation)
      for i in 0 to 15 loop
         b_check(std_logic_vector(to_unsigned(16#10020# + i * 4, 21)));
         a_write(std_logic_vector(to_unsigned(16#10020# + i * 4 + (i mod 4), 21)), std_logic_vector(to_unsigned(16#C0# + i, 8)));
         b_check(std_logic_vector(to_unsigned(16#10020# + i * 4 + (i mod 4), 21)));
         b_check(std_logic_vector(to_unsigned(16#10020# + i * 4 + ((i + 1) mod 4), 21)));
      end loop;

      -- 6) concurrent port A and port B traffic
      for i in 0 to C_NUM_RAND - 1 loop
         wait until rising_edge(clk28);
         b_addr_s <= alist(i);
         b_req_s  <= not b_req_s;
         a_check(alist((i + 7) mod C_NUM_RAND));
         for j in 1 to 6 loop
            wait until rising_edge(clk28);
         end loop;
         if written(to_integer(unsigned(alist(i)))) = '1' and b_do /= ref(to_integer(unsigned(alist(i)))) then
            report "Port B (concurrent) mismatch @ " & to_hstring(alist(i)) severity error;
            errs := errs + 1;
         end if;
      end loop;
      report "concurrent access done";

      -- 7) idle for a while (refresh), then check again
      wait for 30 us;
      for i in 0 to 63 loop
         a_check(alist(i));
      end loop;

      -- 8) Layer 2 streaming under maximum CPU load
      for ad in C_L2_BASE to C_L2_BASE + C_L2_LINES * 256 - 1 loop
         a_write(std_logic_vector(to_unsigned(ad, 21)), l2_pattern(ad));
      end loop;
      report "Layer 2 pattern written";
      l2_run <= true;
      t0 := now;
      cpu_n := 0;
      while not l2_done loop
         cpu_n := cpu_n + 1;
         -- back to back CPU accesses outside of the Layer 2 area (random reads and writes)
         addr := std_logic_vector(rnd(20 downto 0));
         if unsigned(addr) >= C_L2_BASE and unsigned(addr) < C_L2_BASE + C_L2_LINES * 256 then
            addr(20) := not addr(20);
         end if;
         if rnd(0) = '1' then
            a_write(addr, std_logic_vector(rnd(7 downto 0)));
         else
            a_check(addr);
         end if;
      end loop;
      report "Layer 2 streaming: " & integer'image(l2_count) & " fetches, " &
             integer'image(l2_errs_seq) & " errors on sequential fetches, " &
             integer'image(l2_errs_jmp) & " errors on non-sequential fetches; CPU: " &
             integer'image(cpu_n) & " accesses (avg. " & time'image((now - t0) / cpu_n) & " per access)";
      errs := errs + l2_errs_seq + l2_errs_jmp;

      errors <= errs;
      wait for 1 us;
      if errs = 0 then
         report "TEST PASSED" severity note;
      else
         report "TEST FAILED: " & integer'image(errs) & " errors" severity failure;
      end if;
      running <= false;
      wait;
   end process stim_proc;

   ---------------------------------------------------------------------------------------
   -- Layer 2 emulation: exactly like layer2.vhd, every 4 cycles of CLK_28 the result of the
   -- previous request is latched and a new request is toggled. Each 256 byte line is read with
   -- a horizontal scroll offset, i.e. there is one non-sequential jump per line.
   ---------------------------------------------------------------------------------------

   l2_proc : process
      variable prev_ad  : natural;
      variable prev_jmp : boolean;
      variable ad       : natural;
      variable jmp      : boolean;
      variable first    : boolean := true;
      variable es, ej   : natural := 0;
      variable cnt      : natural := 0;
   begin
      wait until l2_run;
      b_req_l <= b_req_s;
      -- pass 0: 256x192 mode (row major, one byte per pixel, horizontal scroll => one jump per line)
      -- pass 1: 320x256 / 640x256 modes (column major: consecutive pixels are 256 bytes apart)
      for pass in 0 to 1 loop
         for line in 0 to C_L2_LINES - 1 loop
            for x in 0 to 255 loop
               if pass = 0 then
                  ad  := C_L2_BASE + line * 256 + ((x + 37 + line * 11) mod 256);
                  jmp := x = 0 or ((x + 37 + line * 11) mod 256) = 0;
               else
                  ad  := C_L2_BASE + (x mod C_L2_LINES) * 256 + line;
                  jmp := true;
               end if;
               -- sc = "00": latch previous result, request next
               wait until rising_edge(clk28);
               if not first then
                  cnt := cnt + 1;
                  if b_do /= l2_pattern(prev_ad) then
                     if prev_jmp then ej := ej + 1; else es := es + 1; end if;
                  end if;
               end if;
               first    := false;
               b_addr_l <= std_logic_vector(to_unsigned(ad, 21));
               b_req_l  <= not b_req_l;
               prev_ad  := ad;
               prev_jmp := jmp;
               for i in 1 to 3 loop
                  wait until rising_edge(clk28);
               end loop;
            end loop;
         end loop;
      end loop;
      l2_errs_seq <= es;
      l2_errs_jmp <= ej;
      l2_count    <= cnt;
      l2_done     <= true;
      wait;
   end process l2_proc;

end architecture sim;
