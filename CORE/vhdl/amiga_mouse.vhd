----------------------------------------------------------------------------------
-- MegaZXNext: ZX Next core for the MEGA65
--
-- Amiga mouse in a MEGA65 joystick port, for the ZX Next's Kempston mouse.
--
-- An Amiga mouse sends two quadrature signals per axis on the joystick lines:
--    pin 1 (up)    V    pin 3 (left)  VQ     vertical axis
--    pin 2 (down)  H    pin 4 (right) HQ     horizontal axis
--    pin 6 (fire)  left button
--    pin 9 (POT X) right button, pin 5 (POT Y) middle button
--
-- The pins come straight from the board (not through M2M's joystick debouncer, which needs a
-- line to be stable for 1 ms and would lose fast movement). They are synchronised and glitch
-- filtered (1 us at 28 MHz).
--
-- Detection: a joystick never closes up and down (or left and right) at the same time, a moving
-- Amiga mouse does. The first time that happens, active_o goes high and stays high until reset.
-- Until then the port is treated as a joystick (main.vhd).
--
-- count_x_o/count_y_o count every quadrature step (x: right = up, y: up = up, both wrap); the
-- ZX Next's DPI setting selects which 8 bits it sees (main.vhd). The right and middle buttons
-- pull the POT lines to ground: a button counts as pressed while its POT value differs by more
-- than 64 from the value it had when the mouse was detected.
--
-- MEGA65 port done by Chris Freeman in 2026 and licensed under GPL v3
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity amiga_mouse is
   generic (
      G_FILTER    : natural := 28;           -- glitch filter in clock cycles (1 us at 28 MHz)
      G_X_INVERT  : boolean := false;        -- swap the direction of an axis
      G_Y_INVERT  : boolean := false
   );
   port (
      clk_i       : in  std_logic;
      reset_i     : in  std_logic;

      -- joystick port pins, asynchronous, low active
      up_n_i      : in  std_logic;
      down_n_i    : in  std_logic;
      left_n_i    : in  std_logic;
      right_n_i   : in  std_logic;
      fire_n_i    : in  std_logic;
      pot_x_i     : in  std_logic_vector(7 downto 0);   -- clk_i domain
      pot_y_i     : in  std_logic_vector(7 downto 0);

      active_o    : out std_logic;                      -- an Amiga mouse was detected
      count_x_o   : out unsigned(10 downto 0);
      count_y_o   : out unsigned(10 downto 0);
      buttons_o   : out std_logic_vector(2 downto 0)    -- middle, right, left (1 = pressed)
   );
end entity amiga_mouse;

architecture synthesis of amiga_mouse is

   -- pin order in the vectors: 4 = fire, 3 = up (V), 2 = down (H), 1 = left (VQ), 0 = right (HQ)
   signal pins_meta  : std_logic_vector(4 downto 0) := (others => '1');
   signal pins_sync  : std_logic_vector(4 downto 0) := (others => '1');
   signal pins       : std_logic_vector(4 downto 0) := (others => '1');   -- filtered

   attribute ASYNC_REG : string;
   attribute ASYNC_REG of pins_meta : signal is "TRUE";
   attribute ASYNC_REG of pins_sync : signal is "TRUE";

   type filter_t is array (4 downto 0) of natural range 0 to G_FILTER;
   signal filter     : filter_t := (others => 0);

   signal active     : std_logic := '0';
   signal last_x     : std_logic_vector(1 downto 0) := "11";
   signal last_y     : std_logic_vector(1 downto 0) := "11";
   signal count_x    : unsigned(10 downto 0) := (others => '0');
   signal count_y    : unsigned(10 downto 0) := (others => '0');
   signal idle_x     : unsigned(7 downto 0) := (others => '0');
   signal idle_y     : unsigned(7 downto 0) := (others => '0');

   -- One quadrature step: +1, -1 or 0 (no change or an invalid jump of two steps)
   function step(last, now : std_logic_vector(1 downto 0); invert : boolean) return integer is
      variable s : integer := 0;
   begin
      case last & now is
         when "0001" | "0111" | "1110" | "1000" => s := 1;
         when "0010" | "1011" | "1101" | "0100" => s := -1;
         when others                            => s := 0;
      end case;
      if invert then
         return -s;
      end if;
      return s;
   end function step;

   function pressed(pot, idle : unsigned(7 downto 0)) return std_logic is
   begin
      if abs(to_integer(pot) - to_integer(idle)) > 64 then
         return '1';
      end if;
      return '0';
   end function pressed;

begin

   process (clk_i)
      variable now_x : std_logic_vector(1 downto 0);
      variable now_y : std_logic_vector(1 downto 0);
   begin
      if rising_edge(clk_i) then
         pins_meta <= fire_n_i & up_n_i & down_n_i & left_n_i & right_n_i;
         pins_sync <= pins_meta;

         -- glitch filter: a pin changes after G_FILTER cycles at its new level
         for i in 4 downto 0 loop
            if pins_sync(i) = pins(i) then
               filter(i) <= 0;
            elsif filter(i) = G_FILTER then
               pins(i)   <= pins_sync(i);
               filter(i) <= 0;
            else
               filter(i) <= filter(i) + 1;
            end if;
         end loop;

         -- quadrature decoding: x = HQ (right) and H (down), y = V (up) and VQ (left), in the order
         -- that counts right and up (checked on an R6 with an Amiga mouse)
         now_x  := pins(0) & pins(2);
         now_y  := pins(3) & pins(1);
         last_x <= now_x;
         last_y <= now_y;
         count_x <= count_x + to_unsigned(step(last_x, now_x, G_X_INVERT) mod 2048, 11);
         count_y <= count_y + to_unsigned(step(last_y, now_y, G_Y_INVERT) mod 2048, 11);

         -- detection: up and down, or left and right, at the same time
         if active = '0' and ((pins(3) = '0' and pins(2) = '0') or (pins(1) = '0' and pins(0) = '0')) then
            active <= '1';
            idle_x <= unsigned(pot_x_i);
            idle_y <= unsigned(pot_y_i);
         end if;

         if reset_i = '1' then
            active  <= '0';
            count_x <= (others => '0');
            count_y <= (others => '0');
         end if;
      end if;
   end process;

   active_o     <= active;
   count_x_o    <= count_x;
   count_y_o    <= count_y;
   buttons_o(0) <= active and not pins(4);
   buttons_o(1) <= active and pressed(unsigned(pot_x_i), idle_x);
   buttons_o(2) <= active and pressed(unsigned(pot_y_i), idle_y);

end architecture synthesis;
