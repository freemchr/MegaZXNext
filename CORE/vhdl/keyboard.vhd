---------------------------------------------------------------------------------------------------------
-- ZX Spectrum Next for MEGA65 (MegaZXNext)
--
-- MEGA65 keyboard to ZX Next membrane matrix
--
-- Runs in the clock domain of the core.
--
-- M2M provides kb_key_num_i, which runs through the key numbers 0 to 79 with a frequency of 1 kHz,
-- and kb_key_pressed_n_i, which is debounced and low active.
--
-- The ZX Next membrane is an 8 x 7 matrix. Columns 0-4 are the classic ZX Spectrum keys; columns 5
-- and 6 contain the extra keys of the ZX Next keyboard (see ZXNext_MiSTer/rtl/input/membrane/membrane.vhd):
--
--       col  0    1    2    3    4     5          6
--       row ------------------------------------------
--        0 | CAPS Z    X    C    V   EXTEND      UP
--        1 | A    S    D    F    G  CAPS LOCK   GRAPH
--        2 | Q    W    E    R    T  TRUE VID   INV VID
--        3 | 1    2    3    4    5   BREAK      EDIT
--        4 | 0    9    8    7    6     ;          "
--        5 | P    O    I    U    Y     ,          .
--        6 | RET  L    K    J    H   DELETE     RIGHT
--        7 | SPC  SYM  M    N    B    LEFT      DOWN
--
-- MEGA65 key            ZX Next
-- -------------------------------------------------------
-- Left/Right Shift      CAPS SHIFT
-- Ctrl, MEGA            SYMBOL SHIFT
-- Alt                   EXTEND MODE
-- Caps Lock             CAPS LOCK
-- No Scroll             GRAPH
-- Tab                   TRUE VIDEO
-- Clr/Home              INV VIDEO
-- Esc, Run/Stop         BREAK
-- <- (left of 1)        EDIT
-- Inst/Del              DELETE
-- Cursor keys           Cursor keys
-- ; , .                 ; , .
-- : + - * / = @ £ ^     SYMBOL SHIFT + Z K J B V L 2 X H
--
-- F3                    50 Hz / 60 Hz toggle     (ZX Next F3)
-- F9                    Multiface NMI            (ZX Next F9)
-- F11                   DivMMC NMI (drive btn)   (ZX Next F10)
-- F13                   Cycle CPU speed          (ZX Next F8)
--
-- MEGA65 port done by Chris Freeman in 2026 and licensed under GPL v3
---------------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity keyboard is
   port (
      clk_main_i           : in  std_logic;               -- core clock

      -- Interface to the MEGA65 keyboard
      key_num_i            : in  integer range 0 to 79;   -- cycles through all MEGA65 keys
      key_pressed_n_i      : in  std_logic;               -- low active: debounced feedback: is kb_key_num_i pressed right now?

      -- ZX Next membrane: row selected by the membrane scanner, low active columns
      membrane_row_i       : in  std_logic_vector(2 downto 0);
      membrane_col_o       : out std_logic_vector(6 downto 0);

      -- ZX Next special function keys F1 .. F10, high active
      fn_keys_o            : out std_logic_vector(10 downto 1)
   );
end entity keyboard;

architecture beh of keyboard is

-- MEGA65 key codes that kb_key_num_i is using while
-- kb_key_pressed_n_i is signalling (low active) which key is pressed
constant m65_ins_del       : integer := 0;
constant m65_return        : integer := 1;
constant m65_horz_crsr     : integer := 2;   -- means cursor right in C64 terminology
constant m65_f7            : integer := 3;
constant m65_f1            : integer := 4;
constant m65_f3            : integer := 5;
constant m65_f5            : integer := 6;
constant m65_vert_crsr     : integer := 7;   -- means cursor down in C64 terminology
constant m65_3             : integer := 8;
constant m65_w             : integer := 9;
constant m65_a             : integer := 10;
constant m65_4             : integer := 11;
constant m65_z             : integer := 12;
constant m65_s             : integer := 13;
constant m65_e             : integer := 14;
constant m65_left_shift    : integer := 15;
constant m65_5             : integer := 16;
constant m65_r             : integer := 17;
constant m65_d             : integer := 18;
constant m65_6             : integer := 19;
constant m65_c             : integer := 20;
constant m65_f             : integer := 21;
constant m65_t             : integer := 22;
constant m65_x             : integer := 23;
constant m65_7             : integer := 24;
constant m65_y             : integer := 25;
constant m65_g             : integer := 26;
constant m65_8             : integer := 27;
constant m65_b             : integer := 28;
constant m65_h             : integer := 29;
constant m65_u             : integer := 30;
constant m65_v             : integer := 31;
constant m65_9             : integer := 32;
constant m65_i             : integer := 33;
constant m65_j             : integer := 34;
constant m65_0             : integer := 35;
constant m65_m             : integer := 36;
constant m65_k             : integer := 37;
constant m65_o             : integer := 38;
constant m65_n             : integer := 39;
constant m65_plus          : integer := 40;
constant m65_p             : integer := 41;
constant m65_l             : integer := 42;
constant m65_minus         : integer := 43;
constant m65_dot           : integer := 44;
constant m65_colon         : integer := 45;
constant m65_at            : integer := 46;
constant m65_comma         : integer := 47;
constant m65_gbp           : integer := 48;
constant m65_asterisk      : integer := 49;
constant m65_semicolon     : integer := 50;
constant m65_clr_home      : integer := 51;
constant m65_right_shift   : integer := 52;
constant m65_equal         : integer := 53;
constant m65_arrow_up      : integer := 54;  -- symbol, not cursor
constant m65_slash         : integer := 55;
constant m65_1             : integer := 56;
constant m65_arrow_left    : integer := 57;  -- symbol, not cursor
constant m65_ctrl          : integer := 58;
constant m65_2             : integer := 59;
constant m65_space         : integer := 60;
constant m65_mega          : integer := 61;
constant m65_q             : integer := 62;
constant m65_run_stop      : integer := 63;
constant m65_no_scrl       : integer := 64;
constant m65_tab           : integer := 65;
constant m65_alt           : integer := 66;
constant m65_help          : integer := 67;
constant m65_f9            : integer := 68;
constant m65_f11           : integer := 69;
constant m65_f13           : integer := 70;
constant m65_esc           : integer := 71;
constant m65_capslock      : integer := 72;
constant m65_up_crsr       : integer := 73;  -- cursor up
constant m65_left_crsr     : integer := 74;  -- cursor left
constant m65_restore       : integer := 75;

signal key_pressed_n : std_logic_vector(79 downto 0) := (others => '1');

type matrix_t is array (0 to 7) of std_logic_vector(6 downto 0);
signal matrix        : matrix_t;             -- low active

begin

   keyboard_state : process(clk_main_i)
   begin
      if rising_edge(clk_main_i) then
         key_pressed_n(key_num_i) <= key_pressed_n_i;
      end if;
   end process keyboard_state;

   -- Build the ZX Next matrix (low active) from the MEGA65 key states (low active)
   build_matrix : process(all)
      variable k      : std_logic_vector(79 downto 0);   -- high active
      variable m      : matrix_t;                        -- high active
      variable symbol : std_logic;
   begin
      k := not key_pressed_n;
      m := (others => (others => '0'));

      -- symbols that need SYMBOL SHIFT + key on the ZX Spectrum
      symbol := k(m65_colon) or k(m65_plus) or k(m65_minus) or k(m65_asterisk) or k(m65_slash) or
                k(m65_equal) or k(m65_at)   or k(m65_gbp)   or k(m65_arrow_up);

      -- row 0: CAPS Z X C V | EXTEND UP
      m(0)(0) := k(m65_left_shift) or k(m65_right_shift);
      m(0)(1) := k(m65_z) or k(m65_colon);
      m(0)(2) := k(m65_x) or k(m65_gbp);
      m(0)(3) := k(m65_c);
      m(0)(4) := k(m65_v) or k(m65_slash);
      m(0)(5) := k(m65_alt);
      m(0)(6) := k(m65_up_crsr);

      -- row 1: A S D F G | CAPS LOCK GRAPH
      m(1)(0) := k(m65_a);
      m(1)(1) := k(m65_s);
      m(1)(2) := k(m65_d);
      m(1)(3) := k(m65_f);
      m(1)(4) := k(m65_g);
      m(1)(5) := k(m65_capslock);
      m(1)(6) := k(m65_no_scrl);

      -- row 2: Q W E R T | TRUE VIDEO INV VIDEO
      m(2)(0) := k(m65_q);
      m(2)(1) := k(m65_w);
      m(2)(2) := k(m65_e);
      m(2)(3) := k(m65_r);
      m(2)(4) := k(m65_t);
      m(2)(5) := k(m65_tab);
      m(2)(6) := k(m65_clr_home);

      -- row 3: 1 2 3 4 5 | BREAK EDIT
      m(3)(0) := k(m65_1);
      m(3)(1) := k(m65_2) or k(m65_at);
      m(3)(2) := k(m65_3);
      m(3)(3) := k(m65_4);
      m(3)(4) := k(m65_5);
      m(3)(5) := k(m65_esc) or k(m65_run_stop);
      m(3)(6) := k(m65_arrow_left);

      -- row 4: 0 9 8 7 6 | ; "
      m(4)(0) := k(m65_0);
      m(4)(1) := k(m65_9);
      m(4)(2) := k(m65_8);
      m(4)(3) := k(m65_7);
      m(4)(4) := k(m65_6);
      m(4)(5) := k(m65_semicolon);
      m(4)(6) := '0';

      -- row 5: P O I U Y | , .
      m(5)(0) := k(m65_p);
      m(5)(1) := k(m65_o);
      m(5)(2) := k(m65_i);
      m(5)(3) := k(m65_u);
      m(5)(4) := k(m65_y);
      m(5)(5) := k(m65_comma);
      m(5)(6) := k(m65_dot);

      -- row 6: ENTER L K J H | DELETE RIGHT
      m(6)(0) := k(m65_return);
      m(6)(1) := k(m65_l) or k(m65_equal);
      m(6)(2) := k(m65_k) or k(m65_plus);
      m(6)(3) := k(m65_j) or k(m65_minus);
      m(6)(4) := k(m65_h) or k(m65_arrow_up);
      m(6)(5) := k(m65_ins_del);
      m(6)(6) := k(m65_horz_crsr);

      -- row 7: SPACE SYM M N B | LEFT DOWN
      m(7)(0) := k(m65_space);
      m(7)(1) := k(m65_ctrl) or k(m65_mega) or symbol;
      m(7)(2) := k(m65_m);
      m(7)(3) := k(m65_n);
      m(7)(4) := k(m65_b) or k(m65_asterisk);
      m(7)(5) := k(m65_left_crsr);
      m(7)(6) := k(m65_vert_crsr);

      for r in 0 to 7 loop
         matrix(r) <= not m(r);
      end loop;
   end process build_matrix;

   membrane_col_o <= matrix(to_integer(unsigned(membrane_row_i)));

   -- ZX Next special keys (high active)
   fn_keys_o(1)  <= '0';                              -- hard reset: use the MEGA65 reset button
   fn_keys_o(2)  <= '0';
   fn_keys_o(3)  <= not key_pressed_n(m65_f3);        -- 50 Hz / 60 Hz
   fn_keys_o(4)  <= '0';                              -- soft reset: use the MEGA65 reset button
   fn_keys_o(5)  <= '0';
   fn_keys_o(6)  <= '0';
   fn_keys_o(7)  <= '0';
   fn_keys_o(8)  <= not key_pressed_n(m65_f13);       -- cpu speed
   fn_keys_o(9)  <= not key_pressed_n(m65_f9);        -- multiface nmi
   fn_keys_o(10) <= not key_pressed_n(m65_f11);       -- divmmc nmi

end architecture beh;
