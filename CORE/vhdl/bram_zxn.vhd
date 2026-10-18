----------------------------------------------------------------------------------
-- MegaZXNext: ZX Next core for the MEGA65
--
-- 1 MB of ZX Next RAM in the FPGA's block RAM, for the MEGA65 R3 / R3A (no SDRAM).
--
-- The ZX Next was designed for an asynchronous SRAM (zxnext.vhd: "memory
-- transactions complete after one cycle, data read is registered a cycle later
-- but is available asap"). Block RAM clocked by CLK_28 behaves the same way:
--
--    * Port A (CPU / DMA): ram_a_req_i = '1' means "memory request on the next
--      rising edge of CLK_28". On that edge the byte is written or read; the
--      read data is valid a few ns later and held until the next request. No
--      wait states are needed (ram_a_wait_o = '0').
--    * Port B (Layer 2): Layer 2 changes its address on a rising edge of CLK_28
--      and latches the data 4 cycles later, so port B simply reads every cycle.
--
-- 1 MB is the memory of an unexpanded ZX Next: 0x000000 - 0x0FFFFF of the 2 MB
-- map. Addresses from 0x100000 up do not exist: they read as 0xFF and writes are
-- ignored. NextZXOS finds the RAM size with its own RAM test and then reports
-- 768K (tested on an R6 with the upper 1 MB of the SDRAM hidden the same way).
-- A mirror of the lower 1 MB would pass that test and corrupt memory later.
--
-- 1 MB = 256 RAMB36 (of 365 on the XC7A200T).
--
-- MEGA65 port done by Chris Freeman in 2026 and licensed under GPL v3
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity bram_zxn is
   port (
      clk_i          : in  std_logic;                        -- ZX Next 28 MHz clock (CLK_28)

      -- ZX Next port A: CPU / DMA (byte addresses)
      ram_a_addr_i   : in  std_logic_vector(20 downto 0);
      ram_a_req_i    : in  std_logic;                        -- '1' = access on this rising edge
      ram_a_rd_n_i   : in  std_logic;                        -- '0' = read, '1' = write
      ram_a_di_i     : in  std_logic_vector(7 downto 0);     -- data to be written
      ram_a_do_o     : out std_logic_vector(7 downto 0);     -- data read
      ram_a_wait_o   : out std_logic;

      -- ZX Next port B: Layer 2 video fetch (read only)
      ram_b_addr_i   : in  std_logic_vector(20 downto 0);
      ram_b_do_o     : out std_logic_vector(7 downto 0)
   );
end entity bram_zxn;

architecture synthesis of bram_zxn is

   type ram_t is array (0 to 2**20 - 1) of std_logic_vector(7 downto 0);
   signal ram : ram_t := (others => (others => '0'));

   signal a_do   : std_logic_vector(7 downto 0) := (others => '0');
   signal a_high : std_logic := '0';                         -- last port A access was above 1 MB
   signal b_do   : std_logic_vector(7 downto 0) := (others => '0');
   signal b_high : std_logic := '0';

begin

   ram_a_wait_o <= '0';

   p_ram : process (clk_i)
   begin
      if rising_edge(clk_i) then
         if ram_a_req_i = '1' then
            if ram_a_rd_n_i = '1' and ram_a_addr_i(20) = '0' then
               ram(to_integer(unsigned(ram_a_addr_i(19 downto 0)))) <= ram_a_di_i;
            end if;
            a_do   <= ram(to_integer(unsigned(ram_a_addr_i(19 downto 0))));
            a_high <= ram_a_addr_i(20);
         end if;

         b_do   <= ram(to_integer(unsigned(ram_b_addr_i(19 downto 0))));
         b_high <= ram_b_addr_i(20);
      end if;
   end process p_ram;

   ram_a_do_o <= x"FF" when a_high = '1' else a_do;
   ram_b_do_o <= x"FF" when b_high = '1' else b_do;

end architecture synthesis;
