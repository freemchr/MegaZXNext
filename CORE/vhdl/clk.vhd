-------------------------------------------------------------------------------------------------------------
-- MegaZXNext: ZX Next core for the MEGA65
--
-- Clock Generator using the Xilinx specific MMCME2_ADV
--
-- The ZX Next core expects the following phase aligned clocks:
--    28 MHz      main clock (CLK_28)
--    28 MHz      phase shifted by 180 degrees (CLK_28_n)
--    14 MHz      hi-res pixel clock (CLK_14)
--     7 MHz      pixel clock (CLK_7)
--   112 MHz      SDRAM controller (4 x 28 MHz)
--
-- VCO = 100 MHz / 5 * 35 = 700 MHz, which is an integer multiple of 28, 14 and 7 MHz.
-- 112 MHz uses the fractional divider of CLKOUT0 (700 / 6.25).
--
-- A PLL makes a copy of the 112 MHz clock that is 56.25 degrees (1.40 ns) late. It only clocks the
-- ODDR that drives the SDRAM clock pin (see sdram_zxn.vhd): with the plain controller clock the
-- SDRAM read data was sampled after the end of its valid window (hold slack -0.9 ns against the
-- datasheet). The MMCM cannot make it: only CLKOUT0 has a fractional divider.
--
-- MiSTer2MEGA65 done by sy2002 and MJoergen in 2022 and licensed under GPL v3
-- MEGA65 port done by Chris Freeman in 2026 and licensed under GPL v3
-------------------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

library unisim;
use unisim.vcomponents.all;

library xpm;
use xpm.vcomponents.all;

entity clk is
   port (
      sys_clk_i       : in  std_logic;   -- expects 100 MHz

      main_clk_o      : out std_logic;   -- 28 MHz main clock
      main_clk_n_o    : out std_logic;   -- 28 MHz, 180 degrees
      clk_14_o        : out std_logic;   -- 14 MHz
      clk_7_o         : out std_logic;   --  7 MHz
      sdram_clk_o     : out std_logic;   -- 112 MHz
      sdram_out_clk_o : out std_logic;   -- 112 MHz, 56.25 degrees late: SDRAM clock pin only

      main_rst_o      : out std_logic;   -- main's reset, synchronized
      sdram_rst_o     : out std_logic    -- SDRAM controller reset, synchronized
   );
end entity clk;

architecture rtl of clk is

signal clkfb              : std_logic;
signal clkfb_mmcm         : std_logic;
signal sdram_clk_mmcm     : std_logic;
signal main_clk_mmcm      : std_logic;
signal main_clk_n_mmcm    : std_logic;
signal clk_14_mmcm        : std_logic;
signal clk_7_mmcm         : std_logic;

signal main_clk           : std_logic;
signal sdram_clk          : std_logic;
signal main_locked        : std_logic;
signal pll_clkfb          : std_logic;
signal pll_clkfb_pll      : std_logic;
signal sdram_out_clk_pll  : std_logic;
signal sdram_locked       : std_logic;

begin

   i_clk_main : MMCME2_ADV
      generic map (
         BANDWIDTH            => "OPTIMIZED",
         CLKOUT4_CASCADE      => FALSE,
         COMPENSATION         => "ZHOLD",
         STARTUP_WAIT         => FALSE,
         CLKIN1_PERIOD        => 10.0,       -- INPUT @ 100 MHz
         REF_JITTER1          => 0.010,
         DIVCLK_DIVIDE        => 5,
         CLKFBOUT_MULT_F      => 35.000,     -- 700 MHz
         CLKFBOUT_PHASE       => 0.000,
         CLKFBOUT_USE_FINE_PS => FALSE,
         CLKOUT0_DIVIDE_F     => 6.250,      -- 112 MHz
         CLKOUT0_PHASE        => 0.000,
         CLKOUT0_DUTY_CYCLE   => 0.500,
         CLKOUT0_USE_FINE_PS  => FALSE,
         CLKOUT1_DIVIDE       => 25,         -- 28 MHz
         CLKOUT1_PHASE        => 0.000,
         CLKOUT1_DUTY_CYCLE   => 0.500,
         CLKOUT1_USE_FINE_PS  => FALSE,
         CLKOUT2_DIVIDE       => 25,         -- 28 MHz, 180 degrees
         CLKOUT2_PHASE        => 180.000,
         CLKOUT2_DUTY_CYCLE   => 0.500,
         CLKOUT2_USE_FINE_PS  => FALSE,
         CLKOUT3_DIVIDE       => 50,         -- 14 MHz
         CLKOUT3_PHASE        => 0.000,
         CLKOUT3_DUTY_CYCLE   => 0.500,
         CLKOUT3_USE_FINE_PS  => FALSE,
         CLKOUT4_DIVIDE       => 100,        -- 7 MHz
         CLKOUT4_PHASE        => 0.000,
         CLKOUT4_DUTY_CYCLE   => 0.500,
         CLKOUT4_USE_FINE_PS  => FALSE
      )
      port map (
         -- Output clocks
         CLKFBOUT            => clkfb_mmcm,
         CLKOUT0             => sdram_clk_mmcm,
         CLKOUT1             => main_clk_mmcm,
         CLKOUT2             => main_clk_n_mmcm,
         CLKOUT3             => clk_14_mmcm,
         CLKOUT4             => clk_7_mmcm,
         -- Input clock control
         CLKFBIN             => clkfb,
         CLKIN1              => sys_clk_i,
         CLKIN2              => '0',
         -- Tied to always select the primary input clock
         CLKINSEL            => '1',
         -- Ports for dynamic reconfiguration
         DADDR               => (others => '0'),
         DCLK                => '0',
         DEN                 => '0',
         DI                  => (others => '0'),
         DO                  => open,
         DRDY                => open,
         DWE                 => '0',
         -- Ports for dynamic phase shift
         PSCLK               => '0',
         PSEN                => '0',
         PSINCDEC            => '0',
         PSDONE              => open,
         -- Other control and status signals
         LOCKED              => main_locked,
         CLKINSTOPPED        => open,
         CLKFBSTOPPED        => open,
         PWRDWN              => '0',
         RST                 => '0'
      ); -- i_clk_main

   -------------------------------------------------------------------------------------
   -- Output buffering
   -------------------------------------------------------------------------------------

   clkfb_bufg : BUFG
      port map (
         I => clkfb_mmcm,
         O => clkfb
      );

   sdram_clk_bufg : BUFG
      port map (
         I => sdram_clk_mmcm,
         O => sdram_clk
      );

   main_clk_bufg : BUFG
      port map (
         I => main_clk_mmcm,
         O => main_clk
      );

   main_clk_n_bufg : BUFG
      port map (
         I => main_clk_n_mmcm,
         O => main_clk_n_o
      );

   clk_14_bufg : BUFG
      port map (
         I => clk_14_mmcm,
         O => clk_14_o
      );

   clk_7_bufg : BUFG
      port map (
         I => clk_7_mmcm,
         O => clk_7_o
      );

   main_clk_o  <= main_clk;
   sdram_clk_o <= sdram_clk;

   -------------------------------------------------------------------------------------
   -- SDRAM clock pin: 112 MHz, 56.25 degrees later than sdram_clk
   -------------------------------------------------------------------------------------

   -- The feedback runs through a BUFG, so the output BUFG is in phase with the input clock
   -- (plus CLKOUT0_PHASE). Vivado times the I/O paths with this relation (CORE.xdc).
   i_pll_sdram : PLLE2_BASE
      generic map (
         BANDWIDTH          => "OPTIMIZED",
         CLKIN1_PERIOD      => 8.929,         -- INPUT @ 112 MHz
         REF_JITTER1        => 0.010,
         DIVCLK_DIVIDE      => 1,
         CLKFBOUT_MULT      => 8,             -- 896 MHz
         CLKFBOUT_PHASE     => 0.000,
         CLKOUT0_DIVIDE     => 8,             -- 112 MHz
         CLKOUT0_PHASE      => 56.250,        -- 1.40 ns
         CLKOUT0_DUTY_CYCLE => 0.500,
         STARTUP_WAIT       => "FALSE"
      )
      port map (
         CLKIN1   => sdram_clk,
         CLKFBIN  => pll_clkfb,
         CLKFBOUT => pll_clkfb_pll,
         CLKOUT0  => sdram_out_clk_pll,
         CLKOUT1  => open,
         CLKOUT2  => open,
         CLKOUT3  => open,
         CLKOUT4  => open,
         CLKOUT5  => open,
         LOCKED   => sdram_locked,
         PWRDWN   => '0',
         RST      => not main_locked
      ); -- i_pll_sdram

   pll_clkfb_bufg : BUFG
      port map (
         I => pll_clkfb_pll,
         O => pll_clkfb
      );

   sdram_out_clk_bufg : BUFG
      port map (
         I => sdram_out_clk_pll,
         O => sdram_out_clk_o
      );

   -------------------------------------
   -- Reset generation
   -------------------------------------

   i_xpm_cdc_async_rst_main : xpm_cdc_async_rst
      generic map (
         RST_ACTIVE_HIGH => 1,
         DEST_SYNC_FF    => 6
      )
      port map (
         src_arst  => not main_locked,   -- 1-bit input: Source reset signal.
         dest_clk  => main_clk,          -- 1-bit input: Destination clock.
         dest_arst => main_rst_o         -- 1-bit output: src_rst synchronized to the destination clock domain.
      );

   i_xpm_cdc_async_rst_sdram : xpm_cdc_async_rst
      generic map (
         RST_ACTIVE_HIGH => 1,
         DEST_SYNC_FF    => 6
      )
      port map (
         src_arst  => not (main_locked and sdram_locked),
         dest_clk  => sdram_clk,
         dest_arst => sdram_rst_o
      );

end architecture rtl;
