----------------------------------------------------------------------------------
-- MegaZXNext: ZX Next core for the MEGA65
--
-- Mouse register testbench: the ZX Next (zxnext_top_m65) with bram_zxn, running the test boot
-- ROM of mk_mouse_reg_rom.py. The program writes nextreg 0x0A with several values and stores
-- each value at 0xA000 + n. At every store mouse_control_o must be (v(3), v(1), v(0)): bit 2 is
-- the button swap that main.vhd applies, and it must follow nextreg 0x0A bit 3 (core 3.01.07
-- moved it there from bit 2; NextZXOS 2.10 sets bit 3).
--
-- Run: see Makefile in this directory (make mouse_reg)
--
-- MEGA65 port done by Chris Freeman in 2026 and licensed under GPL v3
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

library zxnext;

entity tb_mouse_reg is
   generic (
      G_RESULTS : natural := 8                -- must match VALUES in mk_mouse_reg_rom.py
   );
end entity tb_mouse_reg;

architecture sim of tb_mouse_reg is

   constant C_T28    : time := 35714 ps;
   constant C_T_A    : time := 15 ns;         -- bram_zxn: CLK_28 edge -> ram_a_do at the ZX Next

   signal clk_28     : std_logic := '0';
   signal clk_28_n   : std_logic;
   signal clk_14     : std_logic := '0';
   signal clk_7      : std_logic := '0';
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
   signal b_do       : std_logic_vector(7 downto 0);

   signal mouse_ctrl : std_logic_vector(2 downto 0);

   signal n_ok       : natural := 0;
   signal n_bad      : natural := 0;

begin

   clk_proc : process
   begin
      while running loop
         clk_28 <= '1';
         wait for C_T28 / 2;
         clk_28 <= '0';
         wait for C_T28 / 2;
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

   a_wait_d <= transport a_wait after C_T_A;
   a_do_d   <= transport a_do   after C_T_A;

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
         RAM_B_REQ         => open,
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
         mouse_control_o   => mouse_ctrl,
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

   i_bram_zxn : entity work.bram_zxn
      port map (
         clk_i           => clk_28,
         ram_a_addr_i    => a_addr,
         ram_a_req_i     => a_req,
         ram_a_rd_n_i    => a_rd_n,
         ram_a_di_i      => a_di,
         ram_a_do_o      => a_do,
         ram_a_wait_o    => a_wait,
         ram_b_addr_i    => b_addr,
         ram_b_do_o      => b_do
      );

   -- stores to 0xA000.. (bank 2 at 0x8000 = physical 0x048000, so 0x04A000..)
   mon_proc : process (clk_28)
      variable l   : line;
      variable exp : std_logic_vector(2 downto 0);
   begin
      if rising_edge(clk_28) then
         a_req_d <= a_req;
         if a_req = '1' and a_req_d = '0' and a_rd_n = '1' and
            unsigned(a_addr) >= 16#04A000# and unsigned(a_addr) < 16#04A000# + G_RESULTS then
            exp := a_di(3) & a_di(1 downto 0);
            write(l, now, right, 14);
            write(l, string'(" nextreg 0x0A = ") & to_hstring(a_di));
            write(l, string'(": mouse_control_o = ") & to_string(mouse_ctrl));
            if mouse_ctrl = exp then
               n_ok <= n_ok + 1;
               write(l, string'(" OK"));
            else
               n_bad <= n_bad + 1;
               write(l, string'(" expected ") & to_string(exp));
            end if;
            writeline(output, l);
         end if;
      end if;
   end process mon_proc;

   stim_proc : process
   begin
      wait for 2 us;
      sw_reset <= '0';
      wait for 1 us;
      hw_reset <= '0';
      wait for 500 us;
      report "results OK " & integer'image(n_ok) & ", bad " & integer'image(n_bad);
      assert n_ok = G_RESULTS and n_bad = 0
         report "mouse register test FAILED" severity error;
      running <= false;
      wait;
   end process stim_proc;

end architecture sim;
