----------------------------------------------------------------------------------
-- ZX Spectrum Next for MEGA65 (MegaZXNext)
--
-- Xilinx replacement for ZXNext_MiSTer/rtl/mister/bram.vhd
--
-- The MiSTer version wraps Altera altsyncram / altdpram primitives. This file
-- provides the very same entities (same names, same ports, same behavior) as
-- plain inferable VHDL, so that Vivado maps them to Block RAM (dpram) and to
-- distributed LUT RAM (mlab).
--
-- Behavior that is kept from the Altera originals:
--    dpram : true dual port, both ports synchronous (address registered),
--            unregistered outputs, read-during-write on the same port returns
--            the NEW data ("write first"), optional clock enable and chip
--            select per port (outputs read all ones when not selected).
--    mlab  : registered write, asynchronous (combinatorial) read.
--
-- Compiled into library "zxnext" together with the rest of the ZX Next RTL.
--
-- MEGA65 port done by Chris Freeman in 2026 and licensed under GPL v3
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity dpram is
   generic (
      addr_width_a  : integer := 8;
      data_width_a  : integer := 8;
      addr_width_b  : integer := 8;
      data_width_b  : integer := 8;
      mem_init_file : string  := " "   -- ignored: Altera .mif files are not supported by Vivado
   );
   port (
      clock0      : in  std_logic;
      clock1      : in  std_logic;
      address_a   : in  std_logic_vector(addr_width_a-1 downto 0);
      data_a      : in  std_logic_vector(data_width_a-1 downto 0) := (others => '0');
      enable_a    : in  std_logic := '1';
      wren_a      : in  std_logic := '0';
      q_a         : out std_logic_vector(data_width_a-1 downto 0);
      cs_a        : in  std_logic := '1';
      address_b   : in  std_logic_vector(addr_width_b-1 downto 0) := (others => '0');
      data_b      : in  std_logic_vector(data_width_b-1 downto 0) := (others => '0');
      enable_b    : in  std_logic := '1';
      wren_b      : in  std_logic := '0';
      q_b         : out std_logic_vector(data_width_b-1 downto 0);
      cs_b        : in  std_logic := '1'
   );
end entity dpram;

architecture rtl of dpram is

   type mem_t is array (0 to 2**addr_width_a - 1) of std_logic_vector(data_width_a-1 downto 0);
   shared variable mem : mem_t := (others => (others => '0'));

   signal q0 : std_logic_vector(data_width_a-1 downto 0);
   signal q1 : std_logic_vector(data_width_b-1 downto 0);

begin

   assert addr_width_a = addr_width_b and data_width_a = data_width_b
      report "dpram: mixed port widths are not supported by the Xilinx replacement"
      severity failure;

   q_a <= q0 when cs_a = '1' else (others => '1');
   q_b <= q1 when cs_b = '1' else (others => '1');

   port_a : process (clock0)
   begin
      if rising_edge(clock0) then
         if enable_a = '1' then
            if wren_a = '1' and cs_a = '1' then
               mem(to_integer(unsigned(address_a))) := data_a;
            end if;
            q0 <= mem(to_integer(unsigned(address_a)));
         end if;
      end if;
   end process port_a;

   port_b : process (clock1)
   begin
      if rising_edge(clock1) then
         if enable_b = '1' then
            if wren_b = '1' and cs_b = '1' then
               mem(to_integer(unsigned(address_b))) := data_b;
            end if;
            q1 <= mem(to_integer(unsigned(address_b)));
         end if;
      end if;
   end process port_b;

end architecture rtl;

----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity mlab is
   generic (
      addr_width  : integer := 8;
      data_width  : integer := 8
   );
   port (
      clk       : in  std_logic;
      rdaddress : in  std_logic_vector(addr_width-1 downto 0);
      q         : out std_logic_vector(data_width-1 downto 0);
      wraddress : in  std_logic_vector(addr_width-1 downto 0);
      data      : in  std_logic_vector(data_width-1 downto 0);
      wren      : in  std_logic
   );
end entity mlab;

architecture rtl of mlab is

   type mem_t is array (0 to 2**addr_width - 1) of std_logic_vector(data_width-1 downto 0);
   signal mem : mem_t := (others => (others => '0'));

   attribute ram_style : string;
   attribute ram_style of mem : signal is "distributed";

begin

   process (clk)
   begin
      if rising_edge(clk) then
         if wren = '1' then
            mem(to_integer(unsigned(wraddress))) <= data;
         end if;
      end if;
   end process;

   q <= mem(to_integer(unsigned(rdaddress)));

end architecture rtl;

----------------------------------------------------------------------------------
-- Joystick-to-key mapping RAM of membrane_stick.vhd
-- Initialized with the contents of rtl/mister/keyjoy_sdpram_64_6.mif
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity keyjoy_sdpram_64_6 is
   port (
      DPRA : in  std_logic_vector(5 downto 0);
      DPO  : out std_logic_vector(5 downto 0);
      CLK  : in  std_logic;
      WE   : in  std_logic;
      A    : in  std_logic_vector(5 downto 0);
      D    : in  std_logic_vector(5 downto 0)
   );
end entity keyjoy_sdpram_64_6;

architecture rtl of keyjoy_sdpram_64_6 is

   type mem_t is array (0 to 63) of std_logic_vector(5 downto 0);

   -- sinclair / cursor mappings (identical for both halves)
   constant C_INIT_HALF : mem_t := (
       0 => "100011",  1 => "100100",  2 => "100010",  3 => "100001",
       4 => "100000",  5 => "011001",  6 => "011000",  7 => "011010",
       8 => "011011",  9 => "011100", 10 => "100010", 11 => "011100",
      12 => "100100", 13 => "100011", 14 => "100000", 15 => "111111",
      others => "000111"
   );

   function init_mem return mem_t is
      variable m : mem_t;
   begin
      for i in 0 to 31 loop
         m(i)      := C_INIT_HALF(i);
         m(i + 32) := C_INIT_HALF(i);
      end loop;
      return m;
   end function init_mem;

   -- In the Altera original this is a dpram with registered read address
   signal mem : mem_t := init_mem;
   signal q   : std_logic_vector(5 downto 0);

begin

   process (CLK)
   begin
      if rising_edge(CLK) then
         if WE = '1' then
            mem(to_integer(unsigned(A))) <= D;
         end if;
         q <= mem(to_integer(unsigned(DPRA)));
      end if;
   end process;

   DPO <= q;

end architecture rtl;

----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

entity sdpram_128_8 is
   port (
      DPRA : in  std_logic_vector(6 downto 0);
      DPO  : out std_logic_vector(7 downto 0);
      CLK  : in  std_logic;
      WE   : in  std_logic;
      A    : in  std_logic_vector(6 downto 0);
      D    : in  std_logic_vector(7 downto 0)
   );
end entity sdpram_128_8;

architecture rtl of sdpram_128_8 is
begin
   ram : entity work.mlab
      generic map (addr_width => 7, data_width => 8)
      port map (clk => CLK, rdaddress => DPRA, q => DPO, wraddress => A, data => D, wren => WE);
end architecture rtl;

----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

entity spram_320_9 is
   port (
      CLK  : in  std_logic;
      WE   : in  std_logic;
      SPO  : out std_logic_vector(8 downto 0);
      A    : in  std_logic_vector(8 downto 0);
      D    : in  std_logic_vector(8 downto 0)
   );
end entity spram_320_9;

architecture rtl of spram_320_9 is
begin
   ram : entity work.mlab
      generic map (addr_width => 9, data_width => 9)
      port map (clk => CLK, rdaddress => A, q => SPO, wraddress => A, data => D, wren => WE);
end architecture rtl;

----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

entity sdpbram_16k_8 is
   port (
      WEA    : in  std_logic_vector(0 downto 0);      -- as declared by the component in sprites.vhd
      ADDRA  : in  std_logic_vector(13 downto 0);
      DINA   : in  std_logic_vector(7 downto 0);
      CLKA   : in  std_logic;
      ENB    : in  std_logic;
      ADDRB  : in  std_logic_vector(13 downto 0);
      DOUTB  : out std_logic_vector(7 downto 0);
      CLKB   : in  std_logic
   );
end entity sdpbram_16k_8;

architecture rtl of sdpbram_16k_8 is
begin
   -- ENB is not connected in the MiSTer original either
   ram : entity work.dpram
      generic map (addr_width_a => 14, data_width_a => 8, addr_width_b => 14, data_width_b => 8)
      port map (
         clock0    => CLKA,
         clock1    => CLKB,
         address_a => ADDRA,
         data_a    => DINA,
         wren_a    => WEA(0),
         q_a       => open,
         address_b => ADDRB,
         q_b       => DOUTB
      );
end architecture rtl;

----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

entity sdpram_16_9 is
   port (
      DPRA : in  std_logic_vector(3 downto 0);
      DPO  : out std_logic_vector(8 downto 0);
      CLK  : in  std_logic;
      WE   : in  std_logic;
      A    : in  std_logic_vector(3 downto 0);
      D    : in  std_logic_vector(8 downto 0)
   );
end entity sdpram_16_9;

architecture rtl of sdpram_16_9 is
begin
   ram : entity work.mlab
      generic map (addr_width => 4, data_width => 9)
      port map (clk => CLK, rdaddress => DPRA, q => DPO, wraddress => A, data => D, wren => WE);
end architecture rtl;

----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

entity sdpram_64_9 is
   port (
      DPRA  : in  std_logic_vector(5 downto 0);
      CLK   : in  std_logic;
      WE    : in  std_logic;
      DPO   : out std_logic_vector(8 downto 0);
      A     : in  std_logic_vector(5 downto 0);
      D     : in  std_logic_vector(8 downto 0)
   );
end entity sdpram_64_9;

architecture rtl of sdpram_64_9 is
begin
   ram : entity work.mlab
      generic map (addr_width => 6, data_width => 9)
      port map (clk => CLK, rdaddress => DPRA, q => DPO, wraddress => A, data => D, wren => WE);
end architecture rtl;

----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

entity tdpram is
   generic (
      addr_width_g : integer := 8;
      data_width_g : integer := 8
   );
   port (
      clk_a_i  : in  std_logic;
      we_a_i   : in  std_logic;
      addr_a_i : in  std_logic_vector(addr_width_g-1 downto 0);
      data_a_i : in  std_logic_vector(data_width_g-1 downto 0);
      data_a_o : out std_logic_vector(data_width_g-1 downto 0);
      clk_b_i  : in  std_logic;
      we_b_i   : in  std_logic;
      addr_b_i : in  std_logic_vector(addr_width_g-1 downto 0);
      data_b_i : in  std_logic_vector(data_width_g-1 downto 0);
      data_b_o : out std_logic_vector(data_width_g-1 downto 0)
   );
end entity tdpram;

architecture rtl of tdpram is
begin
   ram : entity work.dpram
      generic map (
         addr_width_a => addr_width_g, data_width_a => data_width_g,
         addr_width_b => addr_width_g, data_width_b => data_width_g
      )
      port map (
         clock0    => clk_a_i,
         clock1    => clk_b_i,
         address_a => addr_a_i,
         data_a    => data_a_i,
         wren_a    => we_a_i,
         q_a       => data_a_o,
         address_b => addr_b_i,
         data_b    => data_b_i,
         wren_b    => we_b_i,
         q_b       => data_b_o
      );
end architecture rtl;

----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

entity dpram2 is
   generic (
      addr_width_g : integer := 8;
      data_width_g : integer := 8;
      init_file_g  : string  := " "
   );
   port (
      clk_a_i  : in  std_logic;
      we_i     : in  std_logic;
      addr_a_i : in  std_logic_vector(addr_width_g-1 downto 0);
      data_a_i : in  std_logic_vector(data_width_g-1 downto 0);
      data_a_o : out std_logic_vector(data_width_g-1 downto 0);
      clk_b_i  : in  std_logic;
      addr_b_i : in  std_logic_vector(addr_width_g-1 downto 0);
      data_b_o : out std_logic_vector(data_width_g-1 downto 0)
   );
end entity dpram2;

architecture rtl of dpram2 is
begin
   ram : entity work.dpram
      generic map (
         addr_width_a => addr_width_g, data_width_a => data_width_g,
         addr_width_b => addr_width_g, data_width_b => data_width_g,
         mem_init_file => init_file_g
      )
      port map (
         clock0    => clk_a_i,
         clock1    => clk_b_i,
         address_a => addr_a_i,
         data_a    => data_a_i,
         wren_a    => we_i,
         q_a       => data_a_o,
         address_b => addr_b_i,
         q_b       => data_b_o
      );
end architecture rtl;
