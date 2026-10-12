-- Minimal behavioral models of the Xilinx primitives used by sdram_zxn.vhd (simulation only)
library ieee;
use ieee.std_logic_1164.all;

package vcomponents is
   component ODDR is
      generic (DDR_CLK_EDGE : string := "OPPOSITE_EDGE");
      port (Q : out std_logic; C, CE, D1, D2, R, S : in std_logic);
   end component ODDR;
   component BUFGMUX_CTRL is
      port (O : out std_logic; I0 : in std_logic; I1 : in std_logic; S : in std_logic);
   end component BUFGMUX_CTRL;
end package vcomponents;

library ieee;
use ieee.std_logic_1164.all;

entity ODDR is
   generic (DDR_CLK_EDGE : string := "OPPOSITE_EDGE");
   port (Q : out std_logic; C, CE, D1, D2, R, S : in std_logic);
end entity ODDR;

architecture sim of ODDR is
begin
   -- D1 during the high phase of C, D2 during the low phase
   Q <= D1 when C = '1' else D2;
end architecture sim;

-- BUFGMUX_CTRL (simulation model): glitch-free in hardware, a plain mux here
library ieee;
use ieee.std_logic_1164.all;

entity BUFGMUX_CTRL is
   port (
      O  : out std_logic;
      I0 : in  std_logic;
      I1 : in  std_logic;
      S  : in  std_logic
   );
end entity BUFGMUX_CTRL;

architecture sim of BUFGMUX_CTRL is
begin
   O <= I1 when S = '1' else I0;
end architecture sim;
