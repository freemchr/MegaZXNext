----------------------------------------------------------------------------------
-- ZX Spectrum Next for MEGA65 (MegaZXNext)
--
-- Boot testbench: the ZX Next (zxnext_top_m65) from reset with an ideal memory on port A
-- (and port B), no SD card. Reports how many memory requests it makes and whether it starts
-- talking to its SD card (the boot ROM loads TBBLUE.FW from SD0).
--
-- Run: see Makefile in this directory (make boot)
--
-- MEGA65 port done by Chris Freeman in 2026 and licensed under GPL v3
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

library zxnext;

entity tb_zxnext_boot is
end entity tb_zxnext_boot;

architecture sim of tb_zxnext_boot is

   constant C_T28        : time := 35.714 ns;

   signal clk_28         : std_logic := '0';
   signal clk_28_n       : std_logic;
   signal clk_14         : std_logic := '0';
   signal clk_7          : std_logic := '0';
   signal hw_reset       : std_logic := '1';
   signal sw_reset       : std_logic := '1';

   signal ram_a_addr     : std_logic_vector(20 downto 0);
   signal ram_a_req      : std_logic;
   signal ram_a_rd_n     : std_logic;
   signal ram_a_di       : std_logic_vector(7 downto 0) := x"00";
   signal ram_a_do       : std_logic_vector(7 downto 0);
   signal ram_b_addr     : std_logic_vector(20 downto 0);
   signal ram_b_req      : std_logic;
   signal ram_b_di       : std_logic_vector(7 downto 0) := x"00";

   signal sd_cs0_n       : std_logic;
   signal sd_cs1_n       : std_logic;
   signal sd_sclk        : std_logic;
   signal sd_mosi        : std_logic;

   signal n_req          : natural := 0;
   signal n_sclk         : natural := 0;
   signal last_addr      : std_logic_vector(23 downto 0) := (others => '0');
   signal done           : boolean := false;

   type mem_t is array (0 to 2**21 - 1) of std_logic_vector(7 downto 0);

begin

   clk_28   <= not clk_28 after C_T28 / 2 when not done;
   clk_28_n <= not clk_28;

   div_proc : process (clk_28)
      variable n : unsigned(1 downto 0) := "00";
   begin
      if rising_edge(clk_28) then
         n      := n + 1;
         clk_14 <= n(0);
         clk_7  <= n(1);
      end if;
   end process div_proc;

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
         CPU_WAIT          => '0',
         RAM_A_ADDR        => ram_a_addr,
         RAM_A_REQ         => ram_a_req,
         RAM_A_RD_n        => ram_a_rd_n,
         RAM_A_DI          => ram_a_di,
         RAM_A_DO          => ram_a_do,
         RAM_B_ADDR        => ram_b_addr,
         RAM_B_REQ         => ram_b_req,
         RAM_B_DI          => ram_b_di,
         membrane_row_o    => open,
         membrane_col_i    => (others => '1'),
         fn_keys_i         => (others => '0'),
         sd_cs0_n_o        => sd_cs0_n,
         sd_cs1_n_o        => sd_cs1_n,
         sd_sclk_o         => sd_sclk,
         sd_mosi_o         => sd_mosi,
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

   -- Ideal memory: the request pulse ends at the next rising edge of CLK_28; serve it there
   -- The first 1024 requests go to boot_trace.txt in the format of the hardware trace (main.vhd):
   -- rd_n, address, data written, data read by the previous request
   mem_proc : process (clk_28)
      variable mem   : mem_t := (others => x"00");
      file trace     : text open write_mode is "boot_trace.txt";
      variable l     : line;
   begin
      if rising_edge(clk_28) then
         if ram_a_req = '1' then
            n_req     <= n_req + 1;
            last_addr <= "000" & ram_a_addr;
            if n_req mod 4096 < 64 then
               write(l, std_logic'image(ram_a_rd_n)(2)); write(l, string'(" "));
               hwrite(l, "000" & ram_a_addr); write(l, string'(" "));
               hwrite(l, ram_a_do); write(l, string'(" "));
               hwrite(l, ram_a_di);
               writeline(trace, l);
            end if;
            if ram_a_rd_n = '0' then
               ram_a_di <= mem(to_integer(unsigned(ram_a_addr)));
            else
               mem(to_integer(unsigned(ram_a_addr))) := ram_a_do;
            end if;
         end if;
         ram_b_di <= mem(to_integer(unsigned(ram_b_addr)));
      end if;
   end process mem_proc;

   spi_mon : process (sd_sclk)
   begin
      if rising_edge(sd_sclk) and sd_cs0_n = '0' then
         n_sclk <= n_sclk + 1;
      end if;
   end process spi_mon;

   stim_proc : process
   begin
      wait for 2 us;
      sw_reset <= '0';
      wait for 3 us;
      hw_reset <= '0';
      for i in 1 to 1600 loop
         wait for 250 us;
         report "t=" & integer'image(i * 250) & " us: memory requests " & integer'image(n_req) &
                ", SD0 clocks " & integer'image(n_sclk) & ", last address " & to_hstring(last_addr);
      end loop;
      done <= true;
      wait;
   end process stim_proc;

end architecture sim;
