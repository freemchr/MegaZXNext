----------------------------------------------------------------------------------
-- ZX Spectrum Next for MEGA65 (MegaZXNext)
--
-- CPU speed change testbench: the ZX Next (zxnext_top_m65) with sdram_zxn and the SDRAM model,
-- running the test boot ROM of mk_cpu_speed_rom.py. The program lowers the CPU speed at different
-- phases (28 -> 3.5/7/14, 14 -> 3.5/7, 7 -> 3.5 MHz), executes three INC HL after each change and
-- stores L at 0xA000 + n. Every result must be 3. On R6 the opcode fetch that straddled a speed
-- change was lost (zxnext_top_m65.vhd: CPU clock process); this testbench reproduces it with the
-- old clock logic.
--
-- Run: see Makefile in this directory (make speed)
--
-- MEGA65 port done by Chris Freeman in 2026 and licensed under GPL v3
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

library zxnext;

entity tb_cpu_speed is
   generic (
      G_RESULTS : natural := 48               -- must match mk_cpu_speed_rom.py
   );
end entity tb_cpu_speed;

architecture sim of tb_cpu_speed is

   constant C_T112   : time := 8929 ps;
   constant C_T_OUT  : time := 4.0 ns;       -- FPGA -> SDRAM pins
   constant C_T_IN   : time := 1.0 ns;       -- SDRAM pins -> FPGA
   constant C_T_PATH : time := 17.7 ns;      -- ram_a_wait / ram_a_do to the ZX Next (2 sdram_clk cycles)

   signal clk_112    : std_logic := '0';
   signal clk_28     : std_logic := '0';
   signal clk_28_n   : std_logic;
   signal clk_14     : std_logic := '0';
   signal clk_7      : std_logic := '0';
   signal rst_112    : std_logic := '1';
   signal hw_reset   : std_logic := '1';
   signal sw_reset   : std_logic := '1';
   signal running    : boolean   := true;

   signal a_addr     : std_logic_vector(20 downto 0);
   signal a_req      : std_logic;
   signal a_req_d    : std_logic := '0';
   signal a_rd_n     : std_logic;
   signal a_wait     : std_logic;
   signal a_wait_d   : std_logic;
   signal a_do       : std_logic_vector(7 downto 0);
   signal a_do_d     : std_logic_vector(7 downto 0);
   signal a_di       : std_logic_vector(7 downto 0);
   signal b_addr     : std_logic_vector(20 downto 0);
   signal b_req      : std_logic;
   signal b_do       : std_logic_vector(7 downto 0);

   signal f_clk, f_cke, f_cs_n, f_ras_n, f_cas_n, f_we_n, f_dqml, f_dqmh : std_logic;
   signal f_ba       : std_logic_vector(1 downto 0);
   signal f_a        : std_logic_vector(12 downto 0);
   signal f_dq_out   : std_logic_vector(15 downto 0);
   signal f_dq_oe_n  : std_logic_vector(15 downto 0);
   signal f_dq_in    : std_logic_vector(15 downto 0);
   signal f_dq_drive : std_logic_vector(15 downto 0);
   signal p_clk, p_cke, p_cs_n, p_ras_n, p_cas_n, p_we_n, p_dqml, p_dqmh : std_logic;
   signal p_ba       : std_logic_vector(1 downto 0);
   signal p_a        : std_logic_vector(12 downto 0);
   signal p_dq       : std_logic_vector(15 downto 0);

   signal n_ok       : natural := 0;
   signal n_bad      : natural := 0;

begin

   -- 112 MHz and CLK_28 phase aligned (as the MMCM in clk.vhd)
   clk_proc : process
      variable cnt : natural := 0;
   begin
      while running loop
         clk_112 <= '1';
         if cnt mod 4 = 0 then
            clk_28 <= '1';
         elsif cnt mod 4 = 2 then
            clk_28 <= '0';
         end if;
         wait for C_T112 / 2;
         clk_112 <= '0';
         wait for C_T112 / 2;
         cnt := cnt + 1;
      end loop;
      wait;
   end process clk_proc;

   clk_28_n <= not clk_28;

   div_proc : process (clk_28)
      variable n : unsigned(1 downto 0) := "00";
   begin
      if rising_edge(clk_28) then
         n := n + 1;
         clk_14 <= n(0);
         clk_7  <= n(1);
      end if;
   end process div_proc;

   rst_112  <= '1', '0' after 200 ns;
   a_wait_d <= transport a_wait after C_T_PATH;
   a_do_d   <= transport a_do   after C_T_PATH;

   i_dut : entity zxnext.zxnext_top_m65
      port map (
         g_machine_id      => x"DA",
         g_board_issue     => x"0",
         CLK_28            => clk_28,
         CLK_28_n          => clk_28_n,
         CLK_14            => clk_14,
         CLK_7             => clk_7,
         HW_RESET          => hw_reset,
         SW_RESET          => sw_reset,
         CPU_SPEED         => open,
         CPU_SPEED_SW      => '0',
         CPU_WAIT          => a_wait_d,
         RAM_A_ADDR        => a_addr,
         RAM_A_REQ         => a_req,
         RAM_A_RD_n        => a_rd_n,
         RAM_A_DI          => a_do_d,
         RAM_A_DO          => a_di,
         RAM_B_ADDR        => b_addr,
         RAM_B_REQ         => b_req,
         RAM_B_DI          => b_do,
         membrane_row_o    => open,
         membrane_col_i    => (others => '1'),
         fn_keys_i         => (others => '0'),
         sd_cs0_n_o        => open,
         sd_cs1_n_o        => open,
         sd_sclk_o         => open,
         sd_mosi_o         => open,
         sd_miso_i         => '1',
         joy_left          => (others => '0'),
         joy_right         => (others => '0'),
         audio_L           => open,
         audio_R           => open,
         ear_port_i        => '1',
         mic_port_o        => open,
         RGB               => open,
         RGB_VS_n          => open,
         RGB_HS_n          => open,
         RGB_VB_n          => open,
         RGB_HB_n          => open,
         RGB_NTSC          => open,
         center            => '0',
         i2c_scl_o         => open,
         i2c_sda_o         => open,
         i2c_sda_i         => '1',
         uart_rx_i         => '1',
         uart_tx_o         => open,
         esp_reset_o       => open
      );

   i_sdram_zxn : entity work.sdram_zxn
      port map (
         clk_i           => clk_112,
         rst_i           => rst_112,
         clk_28_i        => clk_28,
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

   p_clk   <= transport f_clk   after C_T_OUT;
   p_cke   <= transport f_cke   after C_T_OUT;
   p_cs_n  <= transport f_cs_n  after C_T_OUT;
   p_ras_n <= transport f_ras_n after C_T_OUT;
   p_cas_n <= transport f_cas_n after C_T_OUT;
   p_we_n  <= transport f_we_n  after C_T_OUT;
   p_ba    <= transport f_ba    after C_T_OUT;
   p_a     <= transport f_a     after C_T_OUT;
   p_dqml  <= transport f_dqml  after C_T_OUT;
   p_dqmh  <= transport f_dqmh  after C_T_OUT;

   dq_gen : for i in 0 to 15 generate
      f_dq_drive(i) <= f_dq_out(i) when f_dq_oe_n(i) = '0' else 'Z';
   end generate dq_gen;

   p_dq    <= transport f_dq_drive after C_T_OUT;
   f_dq_in <= transport to_x01(p_dq) after C_T_IN;

   i_sdram : entity work.sdram_sim
      generic map (
         G_RAM_DEBUG  => false,
         G_RAM_SIZE   => 21,
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

   -- results: writes to 0xA000.. (bank 2 at 0x8000 = physical 0x048000, so 0x04A000..)
   mon_proc : process (clk_28)
      variable l : line;
   begin
      if rising_edge(clk_28) then
         a_req_d <= a_req;
         if a_req = '1' and a_req_d = '0' and a_rd_n = '1' and
            unsigned(a_addr) >= 16#04A000# and unsigned(a_addr) < 16#04A000# + G_RESULTS then
            if a_di = x"03" then
               n_ok <= n_ok + 1;
            else
               n_bad <= n_bad + 1;
               write(l, now, right, 14);
               write(l, string'(" result ") & integer'image(to_integer(unsigned(a_addr)) - 16#04A000#));
               write(l, string'(" = ") & to_hstring(a_di) & string'(" (expected 03)"));
               writeline(output, l);
            end if;
         end if;
      end if;
   end process mon_proc;

   stim_proc : process
   begin
      wait for 2 us;
      sw_reset <= '0';
      wait for 150 us;                         -- SDRAM power-up and initialization
      hw_reset <= '0';
      wait for 2 ms;
      report "results OK " & integer'image(n_ok) & ", bad " & integer'image(n_bad);
      assert n_ok = G_RESULTS and n_bad = 0
         report "CPU speed change test FAILED" severity error;
      running <= false;
      wait;
   end process stim_proc;

end architecture sim;
