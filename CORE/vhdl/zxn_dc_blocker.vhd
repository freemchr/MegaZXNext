----------------------------------------------------------------------------------
-- MegaZXNext: ZX Next core for the MEGA65
--
-- Converts the ZX Next's 12-bit unsigned audio into 16-bit signed PCM and
-- removes the DC offset (the ZX Next mixer output is not centered around zero).
--
-- First order high pass: dc += (x - dc) / 2^10, y = x - dc
-- The DC estimate is updated every 512 clock cycles (28 MHz / 512 = 54.7 kHz),
-- which results in a cut-off frequency of approx. 8.5 Hz.
--
-- MEGA65 port done by Chris Freeman in 2026 and licensed under GPL v3
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity zxn_dc_blocker is
   port (
      clk_i    : in  std_logic;
      audio_i  : in  std_logic_vector(11 downto 0);   -- unsigned
      audio_o  : out signed(15 downto 0)              -- signed PCM
   );
end entity zxn_dc_blocker;

architecture synthesis of zxn_dc_blocker is

   constant C_SHIFT : natural := 10;

   signal x      : signed(16 downto 0) := (others => '0');                   -- input scaled to 0 .. 32760
   signal dc     : signed(16 + C_SHIFT downto 0) := (others => '0');         -- DC estimate with fractional bits
   signal y      : signed(17 downto 0) := (others => '0');
   signal div    : unsigned(8 downto 0) := (others => '0');

begin

   process (clk_i)
   begin
      if rising_edge(clk_i) then
         x   <= signed("00" & audio_i & "000");
         div <= div + 1;

         if div = 0 then
            dc <= dc + resize(x, dc'length) - shift_right(dc, C_SHIFT);
         end if;

         y <= resize(x, 18) - resize(shift_right(dc, C_SHIFT), 18);

         -- saturate to 16 bits
         if y > 32767 then
            audio_o <= to_signed(32767, 16);
         elsif y < -32768 then
            audio_o <= to_signed(-32768, 16);
         else
            audio_o <= resize(y, 16);
         end if;
      end if;
   end process;

end architecture synthesis;
