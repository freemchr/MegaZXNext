----------------------------------------------------------------------------------
-- ZX Spectrum Next for MEGA65 (MegaZXNext)
--
-- Wrapper for the MiSTer core that runs exclusively in the core's clock domain
--
-- Contains the ZX Next (zxnext_top_m65), the SDRAM controller for the ZX Next's
-- 2 MB of RAM, the ZX Next's SD card (an image file on the MEGA65's SD card, sd_image.vhd),
-- the DS1307 RTC emulation and the conversion of audio, video, keyboard and joysticks
-- between the ZX Next and the M2M framework.
--
-- MiSTer2MEGA65 done by sy2002 and MJoergen in 2022 and licensed under GPL v3
-- MEGA65 port done by Chris Freeman in 2026 and licensed under GPL v3
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.video_modes_pkg.all;

library zxnext;

entity main is
   port (
      clk_main_i              : in  std_logic;              -- 28 MHz
      clk_main_n_i            : in  std_logic;              -- 28 MHz, 180 degrees
      clk_14_i                : in  std_logic;              -- 14 MHz
      clk_7_i                 : in  std_logic;              --  7 MHz
      clk_sdram_i             : in  std_logic;              -- 112 MHz
      rst_sdram_i             : in  std_logic;              -- synchronous to clk_sdram_i

      reset_soft_i            : in  std_logic;
      reset_hard_i            : in  std_logic;
      pause_i                 : in  std_logic;

      -- MiSTer core main clock speed:
      -- Make sure you pass very exact numbers here, because they are used for avoiding clock drift at derived clocks
      clk_main_speed_i        : in  natural;

      -- Core configuration (from the options menu, main clock domain)
      cpu_speed_sw_i          : in  std_logic;              -- pulse: cycle through the CPU speeds

      -- Video output
      video_ce_o              : out std_logic;
      video_ce_ovl_o          : out std_logic;
      video_red_o             : out std_logic_vector(7 downto 0);
      video_green_o           : out std_logic_vector(7 downto 0);
      video_blue_o            : out std_logic_vector(7 downto 0);
      video_vs_o              : out std_logic;
      video_hs_o              : out std_logic;
      video_hblank_o          : out std_logic;
      video_vblank_o          : out std_logic;
      video_scandoubler_i     : in  std_logic;              -- VGA: 0 = native 15 kHz, 1 = 31 kHz

      -- Audio output (Signed PCM)
      audio_left_o            : out signed(15 downto 0);
      audio_right_o           : out signed(15 downto 0);

      -- M2M Keyboard interface
      kb_key_num_i            : in  integer range 0 to 79;    -- cycles through all MEGA65 keys
      kb_key_pressed_n_i      : in  std_logic;                -- low active: debounced feedback: is kb_key_num_i pressed right now?

      -- MEGA65 joysticks and paddles/mouse/potentiometers
      joy_1_up_n_i            : in  std_logic;
      joy_1_down_n_i          : in  std_logic;
      joy_1_left_n_i          : in  std_logic;
      joy_1_right_n_i         : in  std_logic;
      joy_1_fire_n_i          : in  std_logic;

      joy_2_up_n_i            : in  std_logic;
      joy_2_down_n_i          : in  std_logic;
      joy_2_left_n_i          : in  std_logic;
      joy_2_right_n_i         : in  std_logic;
      joy_2_fire_n_i          : in  std_logic;

      pot1_x_i                : in  std_logic_vector(7 downto 0);
      pot1_y_i                : in  std_logic_vector(7 downto 0);
      pot2_x_i                : in  std_logic_vector(7 downto 0);
      pot2_y_i                : in  std_logic_vector(7 downto 0);

      -- MEGA65 real time clock (MiSTer format)
      rtc_i                   : in  std_logic_vector(64 downto 0);

      -- The ZX Next's SD card: an image file on the MEGA65's SD card (see sd_image.vhd). The image
      -- is located by the QNICE Shell; the ZX Next is held in reset until it is mounted.
      img_enable_i            : in  std_logic;              -- 1 = mounted: the core owns the card
      img_size_i              : in  std_logic_vector(31 downto 0);   -- in sectors
      img_ext_count_i         : in  std_logic_vector(9 downto 0);    -- number of extents
      img_ext_addr_o          : out std_logic_vector(8 downto 0);    -- extent table (in mega65.vhd)
      img_ext_data_i          : in  std_logic_vector(63 downto 0);
      img_err_cnt_o           : out std_logic_vector(15 downto 0);

      -- Debug: activity counters and status, latched every 2**22 cycles (about 150 ms), 10 words
      dbg_o                   : out std_logic_vector(159 downto 0);
      -- Debug: SPI sniffer on SD0: ring buffer of the last 1024 events: command bytes from the ZX
      -- Next (MOSI /= 0xFF) with the byte the card returned, the 16 exchanges after each of them
      -- (responses), and changes of CS0.
      --    bits 7..0 MISO byte, 15..8 MOSI byte, 16 event is a CS0 change, 17 new CS0 value,
      --    31..18 0, 47..32 time since the previous event in units of 256 cycles (saturating)
      --    count: bits 9..0 next entry to be written (= oldest entry), bit 10 0
      dbg_trace_addr_i        : in  std_logic_vector(9 downto 0);
      dbg_trace_data_o        : out std_logic_vector(47 downto 0);
      dbg_trace_count_o       : out std_logic_vector(10 downto 0);

      -- Physical SD card (mega65.vhd connects the slot that holds the image)
      sd_cs_n_o               : out std_logic;
      sd_sclk_o               : out std_logic;
      sd_mosi_o               : out std_logic;
      sd_miso_i               : in  std_logic;
      sd_active_o             : out std_logic;              -- for the drive led

      -- SDRAM (tri-state buffers are in the top level file)
      sdram_clk_o             : out std_logic;
      sdram_cke_o             : out std_logic;
      sdram_cs_n_o            : out std_logic;
      sdram_ras_n_o           : out std_logic;
      sdram_cas_n_o           : out std_logic;
      sdram_we_n_o            : out std_logic;
      sdram_ba_o              : out std_logic_vector(1 downto 0);
      sdram_a_o               : out std_logic_vector(12 downto 0);
      sdram_dqml_o            : out std_logic;
      sdram_dqmh_o            : out std_logic;
      sdram_dq_out_o          : out std_logic_vector(15 downto 0);
      sdram_dq_oe_n_o         : out std_logic_vector(15 downto 0);
      sdram_dq_in_i           : in  std_logic_vector(15 downto 0)
   );
end entity main;

architecture synthesis of main is

   component rtc is
      generic (
         CLOCK_RATE : integer
      );
      port (
         clk        : in  std_logic;
         reset      : in  std_logic;
         RTC        : in  std_logic_vector(64 downto 0);
         scl_i      : in  std_logic;
         sda_i      : in  std_logic;
         sda_o      : out std_logic
      );
   end component rtc;

   -- MiSTer's "MiSTer" machine id: tells the ZX Next firmware that there is no flash, no
   -- bootstrap option and no Raspberry Pi
   constant C_MACHINE_ID      : unsigned(7 downto 0) := X"DA";
   constant C_BOARD_ISSUE     : unsigned(3 downto 0) := X"0";

   signal reset_core          : std_logic;
   signal hw_reset_cnt        : unsigned(15 downto 0) := (others => '0');
   signal hw_reset            : std_logic := '0';

   -- ZX Next memory ports
   signal ram_a_addr          : std_logic_vector(20 downto 0);
   signal ram_a_req           : std_logic;
   signal ram_a_rd_n          : std_logic;
   signal ram_a_wr_data       : std_logic_vector(7 downto 0);
   signal ram_a_rd_data       : std_logic_vector(7 downto 0);
   signal ram_a_wait          : std_logic;
   signal ram_b_addr          : std_logic_vector(20 downto 0);
   signal ram_b_req           : std_logic;
   signal ram_b_rd_data       : std_logic_vector(7 downto 0);

   -- keyboard
   signal membrane_row        : std_logic_vector(2 downto 0);
   signal membrane_col        : std_logic_vector(6 downto 0);
   signal fn_keys             : std_logic_vector(10 downto 1);

   -- joysticks: active high  MODE X Z Y START A C B U D L R
   signal joy_left            : std_logic_vector(11 downto 0);
   signal joy_right           : std_logic_vector(11 downto 0);

   -- audio
   signal audio_l_u           : std_logic_vector(11 downto 0);
   signal audio_r_u           : std_logic_vector(11 downto 0);

   -- video (CLK_14 domain)
   signal rgb                 : std_logic_vector(8 downto 0);
   signal rgb_vs_n            : std_logic;
   signal rgb_hs_n            : std_logic;
   signal rgb_vb_n            : std_logic;
   signal rgb_hb_n            : std_logic;
   signal clk14_toggle        : std_logic := '0';

   -- video (main clock domain)
   signal v_rgb               : std_logic_vector(8 downto 0);
   signal v_vs_n              : std_logic;
   signal v_hs_n              : std_logic;
   signal v_vb_n              : std_logic;
   signal v_hb_n              : std_logic;
   signal v_toggle            : std_logic := '0';
   signal v_toggle_d          : std_logic := '0';
   signal video_ce            : std_logic := '0';

   -- RTC (I2C)
   signal i2c_scl             : std_logic;
   signal i2c_sda_to_rtc      : std_logic;
   signal i2c_sda_from_rtc    : std_logic;

   -- The ZX Next's SPI bus (SD0 = the image, SD1 = no card)
   signal sd_cs0_n            : std_logic;
   signal sd_cs1_n            : std_logic;
   signal sd_sclk             : std_logic;
   signal sd_mosi             : std_logic;
   signal sd_miso             : std_logic;
   signal img_miso            : std_logic;
   signal img_cpu_wait        : std_logic;
   signal img_active          : std_logic;
   signal cpu_wait            : std_logic;
   signal sd_sclk_d           : std_logic := '0';

   -- Debug counters (see dbg_o)
   signal dbg_period          : unsigned(21 downto 0) := (others => '0');
   signal dbg_spi             : unsigned(15 downto 0) := (others => '0');
   signal dbg_sectors         : unsigned(15 downto 0) := (others => '0');
   signal dbg_ram_a           : unsigned(15 downto 0) := (others => '0');
   signal dbg_vs              : unsigned(15 downto 0) := (others => '0');
   signal dbg_wait            : unsigned(31 downto 0) := (others => '0');
   signal dbg_ram_wait        : unsigned(31 downto 0) := (others => '0');
   signal dbg_latches         : unsigned(15 downto 0) := (others => '0');
   signal dbg_ram_a_req_d     : std_logic := '0';
   signal dbg_vs_d            : std_logic := '1';
   signal dbg_ack_d           : std_logic := '0';
   signal dbg_sclk_d          : std_logic := '0';
   signal dbg_hold            : std_logic_vector(159 downto 0) := (others => '0');
   type dbg_trace_t is array (0 to 1023) of std_logic_vector(47 downto 0);
   signal dbg_trace           : dbg_trace_t;
   signal dbg_trace_ptr       : unsigned(9 downto 0) := (others => '0');
   signal dbg_trace_delta     : unsigned(23 downto 0) := (others => '0');
   signal dbg_spi_sclk_d      : std_logic := '0';
   signal dbg_spi_cs_d        : std_logic := '1';
   signal dbg_spi_bits        : unsigned(2 downto 0) := (others => '0');
   signal dbg_spi_mosi        : std_logic_vector(7 downto 0) := (others => '1');
   signal dbg_spi_miso        : std_logic_vector(7 downto 0) := (others => '1');
   signal dbg_spi_follow      : unsigned(4 downto 0) := (others => '0');
   signal sd_act_cnt          : unsigned(21 downto 0) := (others => '0');

   -- first order DC blocker for the unsigned ZX Next audio
   function expand3(c : std_logic_vector(2 downto 0)) return std_logic_vector is
   begin
      return c & c & c(2 downto 1);
   end function expand3;

begin

   ---------------------------------------------------------------------------------------------
   -- Resets
   ---------------------------------------------------------------------------------------------

   -- Short press of the MEGA65 reset button: ZX Next soft reset
   -- Long press of the MEGA65 reset button:  ZX Next hard reset (reloads the firmware from SD card)
   -- Until the SD card image is mounted, the ZX Next is held in a hard reset: it boots from it.
   reset_core <= reset_soft_i or reset_hard_i or not img_enable_i;

   hard_reset_proc : process (clk_main_i)
   begin
      if rising_edge(clk_main_i) then
         if hw_reset_cnt /= 0 then
            hw_reset_cnt <= hw_reset_cnt - 1;
         end if;
         if reset_hard_i = '1' or img_enable_i = '0' then
            hw_reset_cnt <= (others => '1');
         end if;
         hw_reset <= '1' when hw_reset_cnt /= 0 else '0';
      end if;
   end process hard_reset_proc;

   ---------------------------------------------------------------------------------------------
   -- ZX Spectrum Next
   ---------------------------------------------------------------------------------------------

   i_zxnext_top : entity zxnext.zxnext_top_m65
      port map (
         g_machine_id      => C_MACHINE_ID,
         g_board_issue     => C_BOARD_ISSUE,

         CLK_28            => clk_main_i,
         CLK_28_n          => clk_main_n_i,
         CLK_14            => clk_14_i,
         CLK_7             => clk_7_i,

         HW_RESET          => hw_reset,
         SW_RESET          => reset_core,

         CPU_SPEED         => open,
         CPU_SPEED_SW      => cpu_speed_sw_i,
         CPU_WAIT          => cpu_wait,

         RAM_A_ADDR        => ram_a_addr,
         RAM_A_REQ         => ram_a_req,
         RAM_A_RD_n        => ram_a_rd_n,
         RAM_A_DI          => ram_a_rd_data,
         RAM_A_DO          => ram_a_wr_data,

         RAM_B_ADDR        => ram_b_addr,
         RAM_B_REQ         => ram_b_req,
         RAM_B_DI          => ram_b_rd_data,

         membrane_row_o    => membrane_row,
         membrane_col_i    => membrane_col,
         fn_keys_i         => fn_keys,

         sd_cs0_n_o        => sd_cs0_n,
         sd_cs1_n_o        => sd_cs1_n,
         sd_sclk_o         => sd_sclk,
         sd_mosi_o         => sd_mosi,
         sd_miso_i         => sd_miso,

         joy_left          => joy_left,
         joy_right         => joy_right,

         audio_L           => audio_l_u,
         audio_R           => audio_r_u,

         ear_port_i        => '1',
         mic_port_o        => open,

         RGB               => rgb,
         RGB_VS_n          => rgb_vs_n,
         RGB_HS_n          => rgb_hs_n,
         RGB_VB_n          => rgb_vb_n,
         RGB_HB_n          => rgb_hb_n,
         RGB_NTSC          => open,
         center            => '0',

         i2c_scl_o         => i2c_scl,
         i2c_sda_o         => i2c_sda_to_rtc,
         i2c_sda_i         => i2c_sda_from_rtc,

         uart_rx_i         => '1',
         uart_tx_o         => open,
         esp_reset_o       => open
      ); -- i_zxnext_top

   ---------------------------------------------------------------------------------------------
   -- SDRAM: 2 MB of ZX Next memory
   ---------------------------------------------------------------------------------------------

   i_sdram : entity work.sdram_zxn
      port map (
         clk_i           => clk_sdram_i,
         rst_i           => rst_sdram_i,
         clk_28_i        => clk_main_i,

         ram_a_addr_i    => ram_a_addr,
         ram_a_req_i     => ram_a_req,
         ram_a_rd_n_i    => ram_a_rd_n,
         ram_a_di_i      => ram_a_wr_data,
         ram_a_do_o      => ram_a_rd_data,
         ram_a_wait_o    => ram_a_wait,

         ram_b_addr_i    => ram_b_addr,
         ram_b_req_i     => ram_b_req,
         ram_b_do_o      => ram_b_rd_data,

         sdram_clk_o     => sdram_clk_o,
         sdram_cke_o     => sdram_cke_o,
         sdram_cs_n_o    => sdram_cs_n_o,
         sdram_ras_n_o   => sdram_ras_n_o,
         sdram_cas_n_o   => sdram_cas_n_o,
         sdram_we_n_o    => sdram_we_n_o,
         sdram_ba_o      => sdram_ba_o,
         sdram_a_o       => sdram_a_o,
         sdram_dqml_o    => sdram_dqml_o,
         sdram_dqmh_o    => sdram_dqmh_o,
         sdram_dq_out_o  => sdram_dq_out_o,
         sdram_dq_oe_n_o => sdram_dq_oe_n_o,
         sdram_dq_in_i   => sdram_dq_in_i
      ); -- i_sdram

   ---------------------------------------------------------------------------------------------
   -- Real time clock: DS1307 emulation on the ZX Next's I2C bus
   ---------------------------------------------------------------------------------------------

   i_rtc : rtc
      generic map (
         CLOCK_RATE => 28_000_000
      )
      port map (
         clk        => clk_main_i,
         reset      => reset_core,
         RTC        => rtc_i,
         scl_i      => i2c_scl,
         sda_i      => i2c_sda_to_rtc,
         sda_o      => i2c_sda_from_rtc
      ); -- i_rtc

   ---------------------------------------------------------------------------------------------
   -- Keyboard
   ---------------------------------------------------------------------------------------------

   i_keyboard : entity work.keyboard
      port map (
         clk_main_i           => clk_main_i,
         key_num_i            => kb_key_num_i,
         key_pressed_n_i      => kb_key_pressed_n_i,
         membrane_row_i       => membrane_row,
         membrane_col_o       => membrane_col,
         fn_keys_o            => fn_keys
      ); -- i_keyboard

   ---------------------------------------------------------------------------------------------
   -- Joysticks: MEGA65 port 1 = ZX Next left joystick, port 2 = right joystick.
   -- The MEGA65's (single) fire button is fire button 1 ("B"), which is the Kempston fire.
   ---------------------------------------------------------------------------------------------

   joy_left  <= "0000000" & (not joy_1_fire_n_i) & (not joy_1_up_n_i) & (not joy_1_down_n_i) &
                            (not joy_1_left_n_i) & (not joy_1_right_n_i);
   joy_right <= "0000000" & (not joy_2_fire_n_i) & (not joy_2_up_n_i) & (not joy_2_down_n_i) &
                            (not joy_2_left_n_i) & (not joy_2_right_n_i);

   ---------------------------------------------------------------------------------------------
   -- Video: RGB333 @ 14 MHz pixel clock, re-timed into the 28 MHz main clock domain.
   -- CLK_14 and CLK_28 are phase aligned (same MMCM), so this is a synchronous transfer.
   ---------------------------------------------------------------------------------------------

   clk14_toggle_proc : process (clk_14_i)
   begin
      if rising_edge(clk_14_i) then
         clk14_toggle <= not clk14_toggle;
      end if;
   end process clk14_toggle_proc;

   video_proc : process (clk_main_i)
   begin
      if rising_edge(clk_main_i) then
         -- stage 1: sample the CLK_14 domain
         v_rgb      <= rgb;
         v_vs_n     <= rgb_vs_n;
         v_hs_n     <= rgb_hs_n;
         v_vb_n     <= rgb_vb_n;
         v_hb_n     <= rgb_hb_n;
         v_toggle   <= clk14_toggle;
         v_toggle_d <= v_toggle;

         -- stage 2: output with a clock enable in the first 28 MHz cycle of each 14 MHz pixel
         video_ce       <= v_toggle xor v_toggle_d;
         video_red_o    <= expand3(v_rgb(8 downto 6));
         video_green_o  <= expand3(v_rgb(5 downto 3));
         video_blue_o   <= expand3(v_rgb(2 downto 0));
         video_vs_o     <= not v_vs_n;
         video_hs_o     <= not v_hs_n;
         video_vblank_o <= not v_vb_n;
         video_hblank_o <= not v_hb_n;
      end if;
   end process video_proc;

   video_ce_o <= video_ce;

   -- The OSM overlay of the analog (VGA) output runs at the post-scandoubler pixel clock:
   -- 28 MHz with the scandoubler on, 14 MHz with the scandoubler off (retro 15 kHz)
   video_ce_ovl_o <= '1' when video_scandoubler_i = '1' else video_ce;

   ---------------------------------------------------------------------------------------------
   -- Audio: 12-bit unsigned -> 16-bit signed with a DC blocker
   ---------------------------------------------------------------------------------------------

   i_dc_blocker_l : entity work.zxn_dc_blocker
      port map (
         clk_i   => clk_main_i,
         audio_i => audio_l_u,
         audio_o => audio_left_o
      );

   i_dc_blocker_r : entity work.zxn_dc_blocker
      port map (
         clk_i   => clk_main_i,
         audio_i => audio_r_u,
         audio_o => audio_right_o
      );

   ---------------------------------------------------------------------------------------------
   -- SD card: SD0 is the image on the MEGA65's SD card, SD1 has no card (as on MiSTer without
   -- a second image)
   ---------------------------------------------------------------------------------------------

   i_sd_image : entity work.sd_image
      generic map (
         G_CLK_HZ       => 28_000_000
      )
      port map (
         clk_i          => clk_main_i,
         reset_i        => reset_core,
         enable_i       => img_enable_i,
         size_i         => img_size_i,
         ext_count_i    => img_ext_count_i,
         ext_addr_o     => img_ext_addr_o,
         ext_data_i     => img_ext_data_i,
         ss_i           => sd_cs0_n,
         sck_i          => sd_sclk,
         mosi_i         => sd_mosi,
         miso_o         => img_miso,
         sd_cs_n_o      => sd_cs_n_o,
         sd_sclk_o      => sd_sclk_o,
         sd_mosi_o      => sd_mosi_o,
         sd_miso_i      => sd_miso_i,
         cpu_wait_o     => img_cpu_wait,
         active_o       => img_active,
         err_cnt_o      => img_err_cnt_o
      ); -- i_sd_image

   sd_miso  <= img_miso when sd_cs0_n = '0' else '1';

   -- Debug: count activity over a period of 2**22 cycles, then latch it for QNICE
   --    word 0: SPI clock edges with SD0 selected      word 1: sectors served (sd_ack pulses)
   --    word 2: CPU memory requests to the SDRAM       word 3: vertical syncs
   --    word 4: cycles with the CPU waiting (/64)       word 5: cycles with ram_a_wait (/64)
   --    word 6: status: 0 img_enable, 1 reset_core, 2 hw_reset, 3 cpu_wait, 4 ram_a_wait,
   --            5 img_cpu_wait, 6 sd_cs0_n, 7 sd_cs1_n, 8 img_active
   --    word 7: number of latches (proves that the counters run)
   --    word 8, 9: CPU memory address of the last SDRAM request (low, high)
   dbg_proc : process (clk_main_i)
   begin
      if rising_edge(clk_main_i) then
         dbg_period      <= dbg_period + 1;
         dbg_ram_a_req_d <= ram_a_req;
         dbg_vs_d        <= rgb_vs_n;
         dbg_ack_d       <= img_active;
         dbg_sclk_d      <= sd_sclk;
         if sd_cs0_n = '0' and sd_sclk /= dbg_sclk_d then dbg_spi <= dbg_spi + 1; end if;
         if img_active = '1' and dbg_ack_d = '0' then dbg_sectors <= dbg_sectors + 1; end if;
         if ram_a_req /= dbg_ram_a_req_d then dbg_ram_a <= dbg_ram_a + 1; end if;
         if rgb_vs_n = '0' and dbg_vs_d = '1' then dbg_vs <= dbg_vs + 1; end if;
         if cpu_wait = '1' then dbg_wait <= dbg_wait + 1; end if;
         if ram_a_wait = '1' then dbg_ram_wait <= dbg_ram_wait + 1; end if;
         if dbg_period = 0 then
            dbg_hold <= "00000000000" & ram_a_addr &
                        std_logic_vector(dbg_latches) &
                        "0000000" & img_active & sd_cs1_n & sd_cs0_n & img_cpu_wait & ram_a_wait &
                        cpu_wait & hw_reset & reset_core & img_enable_i &
                        std_logic_vector(dbg_ram_wait(21 downto 6)) & std_logic_vector(dbg_wait(21 downto 6)) &
                        std_logic_vector(dbg_vs) & std_logic_vector(dbg_ram_a) &
                        std_logic_vector(dbg_sectors) & std_logic_vector(dbg_spi);
            dbg_latches  <= dbg_latches + 1;
            dbg_spi      <= (others => '0');
            dbg_sectors  <= (others => '0');
            dbg_ram_a    <= (others => '0');
            dbg_vs       <= (others => '0');
            dbg_wait     <= (others => '0');
            dbg_ram_wait <= (others => '0');
         end if;
      end if;
   end process dbg_proc;

   dbg_o <= dbg_hold;

   dbg_trace_proc : process (clk_main_i)
      variable v_mosi : std_logic_vector(7 downto 0);
      variable v_miso : std_logic_vector(7 downto 0);
      variable v_rec  : boolean;
      variable v_cs   : std_logic;
   begin
      if rising_edge(clk_main_i) then
         dbg_spi_sclk_d <= sd_sclk;
         dbg_spi_cs_d   <= sd_cs0_n;
         if dbg_trace_delta /= x"FFFFFF" then
            dbg_trace_delta <= dbg_trace_delta + 1;
         end if;

         v_rec  := false;
         v_cs   := '0';
         v_mosi := dbg_spi_mosi;
         v_miso := dbg_spi_miso;
         if sd_cs0_n /= dbg_spi_cs_d then
            dbg_spi_bits <= (others => '0');
            v_rec := true;
            v_cs  := '1';
         elsif sd_cs0_n = '0' and sd_sclk = '1' and dbg_spi_sclk_d = '0' then
            -- SPI mode 0: both lines are valid at the rising edge of SCK
            v_mosi := dbg_spi_mosi(6 downto 0) & sd_mosi;
            v_miso := dbg_spi_miso(6 downto 0) & sd_miso;
            dbg_spi_mosi <= v_mosi;
            dbg_spi_miso <= v_miso;
            dbg_spi_bits <= dbg_spi_bits + 1;
            if dbg_spi_bits = 7 then
               if v_mosi /= x"FF" then
                  v_rec := true;
                  dbg_spi_follow <= to_unsigned(16, 5);
               elsif dbg_spi_follow /= 0 then
                  v_rec := true;
                  dbg_spi_follow <= dbg_spi_follow - 1;
               end if;
            end if;
         end if;

         if v_rec then
            dbg_trace(to_integer(dbg_trace_ptr)) <=
               std_logic_vector(dbg_trace_delta(23 downto 8)) & "00000000000000" & sd_cs0_n & v_cs &
               v_mosi & v_miso;
            dbg_trace_ptr   <= dbg_trace_ptr + 1;
            dbg_trace_delta <= (others => '0');
         end if;
         dbg_trace_data_o <= dbg_trace(to_integer(unsigned(dbg_trace_addr_i)));
      end if;
   end process dbg_trace_proc;

   dbg_trace_count_o <= '0' & std_logic_vector(dbg_trace_ptr);
   cpu_wait <= ram_a_wait or img_cpu_wait;

   -- SD card activity (drive led): stays on for ~150 ms after the last clock edge
   sd_activity_proc : process (clk_main_i)
   begin
      if rising_edge(clk_main_i) then
         sd_sclk_d <= sd_sclk;
         if sd_act_cnt /= 0 then
            sd_act_cnt <= sd_act_cnt - 1;
         end if;
         if (sd_cs0_n = '0' and sd_sclk /= sd_sclk_d) or img_active = '1' then
            sd_act_cnt <= (others => '1');
         end if;
      end if;
   end process sd_activity_proc;

   sd_active_o <= '1' when sd_act_cnt /= 0 else '0';

end architecture synthesis;
