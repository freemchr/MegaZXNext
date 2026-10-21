----------------------------------------------------------------------------------
-- MegaZXNext: ZX Next core for the MEGA65
--
-- Testbench for amiga_mouse.vhd: joystick use is not taken for a mouse, short glitches are
-- ignored, quadrature steps are counted in both directions on both axes (also at 2 us per step),
-- the buttons and the reset.
--
-- MEGA65 port done by Chris Freeman in 2026 and licensed under GPL v3
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_amiga_mouse is
end entity tb_amiga_mouse;

architecture sim of tb_amiga_mouse is

   constant C_CLK   : time := 35.714 ns;          -- 28 MHz

   signal clk       : std_logic := '0';
   signal reset     : std_logic := '1';
   signal up_n      : std_logic := '1';
   signal down_n    : std_logic := '1';
   signal left_n    : std_logic := '1';
   signal right_n   : std_logic := '1';
   signal fire_n    : std_logic := '1';
   signal pot_x     : std_logic_vector(7 downto 0) := x"FF";
   signal pot_y     : std_logic_vector(7 downto 0) := x"FF";
   signal active    : std_logic;
   signal count_x   : unsigned(10 downto 0);
   signal count_y   : unsigned(10 downto 0);
   signal buttons   : std_logic_vector(2 downto 0);
   signal done      : boolean := false;

   -- quadrature state per axis: 0..3 = (a,b) = 11, 10, 00, 01 (each step changes one line)
   signal x_state   : integer := 0;
   signal y_state   : integer := 0;

   type ab_t is array (0 to 3) of std_logic_vector(1 downto 0);
   constant C_AB    : ab_t := ("11", "10", "00", "01");

begin

   clk <= not clk after C_CLK / 2 when not done;

   dut : entity work.amiga_mouse
      port map (
         clk_i     => clk,
         reset_i   => reset,
         up_n_i    => up_n,
         down_n_i  => down_n,
         left_n_i  => left_n,
         right_n_i => right_n,
         fire_n_i  => fire_n,
         pot_x_i   => pot_x,
         pot_y_i   => pot_y,
         active_o  => active,
         count_x_o => count_x,
         count_y_o => count_y,
         buttons_o => buttons
      );

   process
      -- x: a = HQ (right), b = H (down); y: a = V (up), b = VQ (left)
      procedure set_lines is
      begin
         right_n <= C_AB(x_state mod 4)(1);
         down_n  <= C_AB(x_state mod 4)(0);
         up_n    <= C_AB(y_state mod 4)(1);
         left_n  <= C_AB(y_state mod 4)(0);
      end procedure;

      -- n steps on one axis (dir = +1 / -1), each held for t
      procedure move(axis : character; n : integer; dir : integer; t : time) is
      begin
         for i in 1 to n loop
            if axis = 'x' then
               x_state <= (x_state + dir + 4) mod 4;
            else
               y_state <= (y_state + dir + 4) mod 4;
            end if;
            wait for 0 ns;
            set_lines;
            wait for t;
         end loop;
      end procedure;

      variable x0, y0 : unsigned(10 downto 0);
   begin
      wait for 200 ns;
      reset <= '0';
      wait for 2 us;

      -- 1. A joystick: single directions, diagonals, fire. Never a mouse.
      up_n <= '0'; wait for 5 us; left_n <= '0'; wait for 5 us;
      up_n <= '1'; left_n <= '1'; down_n <= '0'; right_n <= '0'; wait for 5 us;
      down_n <= '1'; right_n <= '1'; fire_n <= '0'; wait for 5 us; fire_n <= '1'; wait for 5 us;
      assert active = '0' report "1: joystick taken for a mouse" severity error;
      assert buttons = "000" report "1: buttons without a mouse" severity error;

      -- 2. A glitch of 0.5 us with up and down low: ignored
      up_n <= '0'; down_n <= '0'; wait for 500 ns; up_n <= '1'; down_n <= '1'; wait for 5 us;
      assert active = '0' report "2: glitch detected as a mouse" severity error;

      -- 3. The mouse moves: x right 2 steps (H goes low), then y 2 steps (V goes low), detection when up and down
      --    are both low. x_state 0 = 11, y_state 0 = 11.
      move('x', 2, 1, 20 us);                 -- x: 10, 00 -> H (down) = 0 (and HQ)
      move('y', 2, 1, 20 us);                 -- y: 10, 00 -> V (up) = 0: detected
      assert active = '1' report "3: mouse not detected" severity error;
      x0 := count_x; y0 := count_y;

      -- 4. Counting: x +40 at 20 us/step, -15 at 2 us/step; y -30 at 2 us/step, +10 at 20 us
      move('x', 40,  1, 20 us);
      move('x', 15, -1,  2 us);
      move('y', 30, -1,  2 us);
      move('y', 10,  1, 20 us);
      wait for 5 us;
      assert count_x = x0 + 25 report "4: x count " & integer'image(to_integer(count_x - x0)) & ", expected 25" severity error;
      assert count_y = y0 - 20 report "4: y count " & integer'image(to_integer(y0 - count_y)) & ", expected -20" severity error;

      -- 5. An invalid jump (both lines at once) is not counted
      x0 := count_x;
      x_state <= (x_state + 2) mod 4; wait for 0 ns; set_lines; wait for 20 us;
      assert count_x = x0 report "5: invalid jump counted" severity error;

      -- 6. Buttons: left = fire, right = POT X, middle = POT Y (far from the idle value FF)
      fire_n <= '0'; wait for 5 us;
      assert buttons = "001" report "6: left button" severity error;
      fire_n <= '1'; pot_x <= x"20"; wait for 2 us;
      assert buttons = "010" report "6: right button" severity error;
      pot_x <= x"F0"; pot_y <= x"10"; wait for 1 us;
      assert buttons = "100" report "6: middle button (or right still pressed)" severity error;
      pot_y <= x"FF"; wait for 1 us;
      assert buttons = "000" report "6: buttons released" severity error;

      -- 7. Reset forgets the mouse (unplugged: all lines high, else it is detected again)
      up_n <= '1'; down_n <= '1'; left_n <= '1'; right_n <= '1'; wait for 2 us;
      reset <= '1'; wait for 200 ns; reset <= '0'; wait for 1 us;
      assert active = '0' and count_x = 0 and count_y = 0 report "7: reset" severity error;

      report "tb_amiga_mouse: done" severity note;
      done <= true;
      wait;
   end process;

end architecture sim;
