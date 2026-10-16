----------------------------------------------------------------------------------
-- MiSTer2MEGA65 Framework
--
-- MEGA65 main file that contains the whole machine
--
-- MegaZXNext: ZX Next core for the MEGA65
-- based on ZXNext_MISTer by the MiSTer development team
--
-- MiSTer2MEGA65 done by sy2002 and MJoergen in 2022 and licensed under GPL v3
-- MEGA65 port done by Chris Freeman in 2026 and licensed under GPL v3
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.globals.all;
use work.types_pkg.all;
use work.video_modes_pkg.all;

library xpm;
use xpm.vcomponents.all;

entity MEGA65_Core is
generic (
   G_BOARD : string                                         -- Which platform are we running on.
);
port (
   --------------------------------------------------------------------------------------------------------
   -- QNICE Clock Domain
   --------------------------------------------------------------------------------------------------------

   -- Get QNICE clock from the framework: for the vdrives as well as for RAMs and ROMs
   qnice_clk_i             : in  std_logic;
   qnice_rst_i             : in  std_logic;

   -- Video and audio mode control
   qnice_dvi_o             : out std_logic;              -- 0=HDMI (with sound), 1=DVI (no sound)
   qnice_video_mode_o      : out video_mode_type;        -- Defined in video_modes_pkg.vhd
   qnice_osm_cfg_scaling_o : out std_logic_vector(8 downto 0);
   qnice_scandoubler_o     : out std_logic;              -- 0 = no scandoubler, 1 = scandoubler
   qnice_audio_mute_o      : out std_logic;
   qnice_audio_filter_o    : out std_logic;
   qnice_zoom_crop_o       : out std_logic;
   qnice_ascal_mode_o      : out std_logic_vector(1 downto 0);
   qnice_ascal_polyphase_o : out std_logic;
   qnice_ascal_triplebuf_o : out std_logic;
   qnice_retro15kHz_o      : out std_logic;              -- 0 = normal frequency, 1 = retro 15 kHz frequency
   qnice_csync_o           : out std_logic;              -- 0 = normal HS/VS, 1 = Composite Sync  

   -- Flip joystick ports
   qnice_flip_joyports_o   : out std_logic;

   -- On-Screen-Menu selections
   qnice_osm_control_i     : in  std_logic_vector(255 downto 0);

   -- QNICE general purpose register
   qnice_gp_reg_i          : in  std_logic_vector(255 downto 0);

   -- Core-specific devices
   qnice_dev_id_i          : in  std_logic_vector(15 downto 0);
   qnice_dev_addr_i        : in  std_logic_vector(27 downto 0);
   qnice_dev_data_i        : in  std_logic_vector(15 downto 0);
   qnice_dev_data_o        : out std_logic_vector(15 downto 0);
   qnice_dev_ce_i          : in  std_logic;
   qnice_dev_we_i          : in  std_logic;
   qnice_dev_wait_o        : out std_logic;

   --------------------------------------------------------------------------------------------------------
   -- HyperRAM Clock Domain
   --------------------------------------------------------------------------------------------------------

   hr_clk_i                : in  std_logic;
   hr_rst_i                : in  std_logic;
   hr_core_write_o         : out std_logic;
   hr_core_read_o          : out std_logic;
   hr_core_address_o       : out std_logic_vector(31 downto 0);
   hr_core_writedata_o     : out std_logic_vector(15 downto 0);
   hr_core_byteenable_o    : out std_logic_vector( 1 downto 0);
   hr_core_burstcount_o    : out std_logic_vector( 7 downto 0);
   hr_core_readdata_i      : in  std_logic_vector(15 downto 0);
   hr_core_readdatavalid_i : in  std_logic;
   hr_core_waitrequest_i   : in  std_logic;
   hr_high_i               : in  std_logic;  -- Core is too fast
   hr_low_i                : in  std_logic;  -- Core is too slow

   --------------------------------------------------------------------------------------------------------
   -- Video Clock Domain
   --------------------------------------------------------------------------------------------------------

   video_clk_o             : out std_logic;
   video_rst_o             : out std_logic;
   video_ce_o              : out std_logic;
   video_ce_ovl_o          : out std_logic;
   video_red_o             : out std_logic_vector(7 downto 0);
   video_green_o           : out std_logic_vector(7 downto 0);
   video_blue_o            : out std_logic_vector(7 downto 0);
   video_vs_o              : out std_logic;
   video_hs_o              : out std_logic;
   video_hblank_o          : out std_logic;
   video_vblank_o          : out std_logic;

   --------------------------------------------------------------------------------------------------------
   -- Core Clock Domain
   --------------------------------------------------------------------------------------------------------

   clk_i                   : in  std_logic;              -- 100 MHz clock

   -- Share clock and reset with the framework
   main_clk_o              : out std_logic;              -- CORE's 28 MHz clock
   main_rst_o              : out std_logic;              -- CORE's reset, synchronized

   -- M2M's reset manager provides 2 signals:
   --    m2m:   Reset the whole machine: Core and Framework
   --    core:  Only reset the core
   main_reset_m2m_i        : in  std_logic;
   main_reset_core_i       : in  std_logic;

   main_pause_core_i       : in  std_logic;

   -- On-Screen-Menu selections
   main_osm_control_i      : in  std_logic_vector(255 downto 0);

   -- QNICE general purpose register converted to main clock domain
   main_qnice_gp_reg_i     : in  std_logic_vector(255 downto 0);

   -- Audio output (Signed PCM)
   main_audio_left_o       : out signed(15 downto 0);
   main_audio_right_o      : out signed(15 downto 0);

   -- M2M Keyboard interface (incl. power led and drive led)
   main_kb_key_num_i       : in  integer range 0 to 79;  -- cycles through all MEGA65 keys
   main_kb_key_pressed_n_i : in  std_logic;              -- low active: debounced feedback: is kb_key_num_i pressed right now?
   main_power_led_o        : out std_logic;
   main_power_led_col_o    : out std_logic_vector(23 downto 0);
   main_drive_led_o        : out std_logic;
   main_drive_led_col_o    : out std_logic_vector(23 downto 0);

   -- Joysticks and paddles input
   main_joy_1_up_n_i       : in  std_logic;
   main_joy_1_down_n_i     : in  std_logic;
   main_joy_1_left_n_i     : in  std_logic;
   main_joy_1_right_n_i    : in  std_logic;
   main_joy_1_fire_n_i     : in  std_logic;
   main_joy_1_up_n_o       : out std_logic;
   main_joy_1_down_n_o     : out std_logic;
   main_joy_1_left_n_o     : out std_logic;
   main_joy_1_right_n_o    : out std_logic;
   main_joy_1_fire_n_o     : out std_logic;
   main_joy_2_up_n_i       : in  std_logic;
   main_joy_2_down_n_i     : in  std_logic;
   main_joy_2_left_n_i     : in  std_logic;
   main_joy_2_right_n_i    : in  std_logic;
   main_joy_2_fire_n_i     : in  std_logic;
   main_joy_2_up_n_o       : out std_logic;
   main_joy_2_down_n_o     : out std_logic;
   main_joy_2_left_n_o     : out std_logic;
   main_joy_2_right_n_o    : out std_logic;
   main_joy_2_fire_n_o     : out std_logic;

   main_pot1_x_i           : in  std_logic_vector(7 downto 0);
   main_pot1_y_i           : in  std_logic_vector(7 downto 0);
   main_pot2_x_i           : in  std_logic_vector(7 downto 0);
   main_pot2_y_i           : in  std_logic_vector(7 downto 0);
   main_rtc_i              : in  std_logic_vector(64 downto 0);

   -- CBM-488/IEC serial port
   iec_reset_n_o           : out std_logic;
   iec_atn_n_o             : out std_logic;
   iec_clk_en_o            : out std_logic;
   iec_clk_n_i             : in  std_logic;
   iec_clk_n_o             : out std_logic;
   iec_data_en_o           : out std_logic;
   iec_data_n_i            : in  std_logic;
   iec_data_n_o            : out std_logic;
   iec_srq_en_o            : out std_logic;
   iec_srq_n_i             : in  std_logic;
   iec_srq_n_o             : out std_logic;

   -- C64 Expansion Port (aka Cartridge Port)
   cart_en_o               : out std_logic;  -- Enable port, active high
   cart_phi2_o             : out std_logic;
   cart_dotclock_o         : out std_logic;
   cart_dma_i              : in  std_logic;
   cart_reset_oe_o         : out std_logic;
   cart_reset_i            : in  std_logic;
   cart_reset_o            : out std_logic;
   cart_game_oe_o          : out std_logic;
   cart_game_i             : in  std_logic;
   cart_game_o             : out std_logic;
   cart_exrom_oe_o         : out std_logic;
   cart_exrom_i            : in  std_logic;
   cart_exrom_o            : out std_logic;
   cart_nmi_oe_o           : out std_logic;
   cart_nmi_i              : in  std_logic;
   cart_nmi_o              : out std_logic;
   cart_irq_oe_o           : out std_logic;
   cart_irq_i              : in  std_logic;
   cart_irq_o              : out std_logic;
   cart_roml_oe_o          : out std_logic;
   cart_roml_i             : in  std_logic;
   cart_roml_o             : out std_logic;
   cart_romh_oe_o          : out std_logic;
   cart_romh_i             : in  std_logic;
   cart_romh_o             : out std_logic;
   cart_ctrl_oe_o          : out std_logic; -- 0 : tristate (i.e. input), 1 : output
   cart_ba_i               : in  std_logic;
   cart_rw_i               : in  std_logic;
   cart_io1_i              : in  std_logic;
   cart_io2_i              : in  std_logic;
   cart_ba_o               : out std_logic;
   cart_rw_o               : out std_logic;
   cart_io1_o              : out std_logic;
   cart_io2_o              : out std_logic;
   cart_addr_oe_o          : out std_logic; -- 0 : tristate (i.e. input), 1 : output
   cart_a_i                : in  unsigned(15 downto 0);
   cart_a_o                : out unsigned(15 downto 0);
   cart_data_oe_o          : out std_logic; -- 0 : tristate (i.e. input), 1 : output
   cart_d_i                : in  unsigned( 7 downto 0);
   cart_d_o                : out unsigned( 7 downto 0);

   --------------------------------------------------------------------------------------------------------
   -- ZX Next specific board I/O (R4, R5, R6)
   --------------------------------------------------------------------------------------------------------

   -- SD card slots. The framework (QNICE) drives them, except the slot that holds the ZX Next's
   -- SD card image while the image is mounted: then the core drives that slot (see below).
   -- MISO and card detect go from the pins to the framework directly (top level file).
   -- Slot at the back of the machine (external micro SD)
   sd_reset_o              : out std_logic;              -- = SPI chip select (low active)
   sd_clk_o                : out std_logic;
   sd_mosi_o               : out std_logic;
   sd_miso_i               : in  std_logic := '1';
   -- Slot in the bottom tray (internal)
   sd2_reset_o             : out std_logic;
   sd2_clk_o               : out std_logic;
   sd2_mosi_o              : out std_logic;
   sd2_miso_i              : in  std_logic := '1';
   -- The framework's outputs for both slots
   fw_sd_reset_i           : in  std_logic := '1';
   fw_sd_clk_i             : in  std_logic := '0';
   fw_sd_mosi_i            : in  std_logic := '1';
   fw_sd2_reset_i          : in  std_logic := '1';
   fw_sd2_clk_i            : in  std_logic := '0';
   fw_sd2_mosi_i           : in  std_logic := '1';

   -- SDRAM - 32M x 16 bit, 3.3V VCC. U44 = IS42S16320F-6BL
   -- The tri-state buffers for DQ are inferred in the top level file
   sdram_clk_o             : out std_logic;
   sdram_cke_o             : out std_logic;
   sdram_ras_n_o           : out std_logic;
   sdram_cas_n_o           : out std_logic;
   sdram_we_n_o            : out std_logic;
   sdram_cs_n_o            : out std_logic;
   sdram_ba_o              : out std_logic_vector(1 downto 0);
   sdram_a_o               : out std_logic_vector(12 downto 0);
   sdram_dqml_o            : out std_logic;
   sdram_dqmh_o            : out std_logic;
   sdram_dq_out_o          : out std_logic_vector(15 downto 0);
   sdram_dq_oe_n_o         : out std_logic_vector(15 downto 0);
   sdram_dq_in_i           : in  std_logic_vector(15 downto 0) := (others => '0')
);
end entity MEGA65_Core;


architecture synthesis of MEGA65_Core is

---------------------------------------------------------------------------------------------
-- Clocks and active high reset signals for each clock domain
---------------------------------------------------------------------------------------------

signal main_clk               : std_logic;               -- Core main clock: 28 MHz
signal main_clk_n             : std_logic;               -- 28 MHz, 180 degrees
signal clk_14                 : std_logic;
signal clk_7                  : std_logic;
signal main_rst               : std_logic;
signal sdram_clk              : std_logic;               -- 112 MHz
signal sdram_out_clk          : std_logic;               -- 112 MHz, 56.25 degrees late (SDRAM clock pin)
signal sdram_rst              : std_logic;

---------------------------------------------------------------------------------------------
-- main_clk (MiSTer core's clock)
---------------------------------------------------------------------------------------------

-- Options menu items: the numbers are the line numbers of the items in OPTM_ITEMS (config.vhd)
constant C_MENU_HDMI_16_9_50     : natural := 5;
constant C_MENU_HDMI_16_9_60     : natural := 6;
constant C_MENU_HDMI_4_3_50      : natural := 7;
constant C_MENU_HDMI_5_4_50      : natural := 8;
constant C_MENU_HDMI_640_60      : natural := 9;
constant C_MENU_HDMI_720_5994    : natural := 10;
constant C_MENU_SVGA_800_60      : natural := 11;
constant C_MENU_VGA_STD          : natural := 17;
constant C_MENU_VGA_15KHZHSVS    : natural := 18;
constant C_MENU_VGA_15KHZCS      : natural := 19;
constant C_MENU_FLIP_JOYS        : natural := 23;
constant C_MENU_CRT_EMULATION    : natural := 24;
constant C_MENU_IMPROVE_AUDIO    : natural := 25;
constant C_MENU_RESET            : natural := 26;

signal main_scandoubler       : std_logic;
signal main_sd_active         : std_logic;

-- SD card image (see sd_image.vhd), from the QNICE registers below
signal main_img_cfg           : std_logic_vector(43 downto 0);
signal main_img_enable        : std_logic;
signal main_img_slot          : std_logic;               -- 1 = back slot, 0 = bottom tray
signal main_img_size          : std_logic_vector(31 downto 0);
signal main_img_ext_count     : std_logic_vector(9 downto 0);
signal main_img_ext_addr      : std_logic_vector(8 downto 0);
signal main_img_ext_data      : std_logic_vector(63 downto 0);
signal main_img_err_cnt       : std_logic_vector(15 downto 0);
signal main_own_back          : std_logic;
signal main_own_tray          : std_logic;

-- Physical SD card, driven by the core
signal main_sd_cs_n           : std_logic;
signal main_sd_sclk           : std_logic;
signal main_sd_mosi           : std_logic;
signal main_sd_miso           : std_logic;

---------------------------------------------------------------------------------------------
-- qnice_clk
---------------------------------------------------------------------------------------------

-- Device C_DEV_ZXN_IMG (globals.vhd): where the ZX Next's SD card image is (set by zxn_mount.asm)
--    0x0002 / 0x0003   size of the image in sectors: low / high word
--    0x0004            slot: 1 = back slot, 0 = bottom tray (M2M$CSR_SD_ACTIVE semantics)
--    0x0005            1 = mounted: the core takes the slot and the ZX Next leaves reset.
--                      Write this last; nothing else may change while it is 1.
--    0x0006            (read only) number of sectors that failed three times
--    0x0007            number of extents (1 .. 512)
--    0x0010 / 0x0011   extent: first virtual sector, low / high word
--    0x0012 / 0x0013   extent: first physical sector, low / high word
--    0x0014            write: store the extent (0x0010 .. 0x0013) as table entry n (0 .. 511)
-- Extents are the pieces of the image file on the card, sorted by virtual sector, the first one
-- starting at virtual sector 0 (see sd_image.vhd).
signal qnice_img_size         : std_logic_vector(31 downto 0) := (others => '0');
signal qnice_img_ext_count    : std_logic_vector(9 downto 0) := (others => '0');
signal qnice_img_ext_stage    : std_logic_vector(63 downto 0) := (others => '0');   -- physical & virtual

-- Extent table: written by QNICE, read by sd_image.vhd. A dual-clock RAM (the CDC); QNICE only
-- writes it while the image is not mounted, so the core never reads an entry that is changing.
type img_ext_ram_t is array (0 to 511) of std_logic_vector(63 downto 0);
signal img_ext_ram            : img_ext_ram_t;
signal qnice_img_slot         : std_logic := '0';
signal qnice_img_enable       : std_logic := '0';
signal qnice_img_err_cnt      : std_logic_vector(15 downto 0);

begin

   -- The ZX Next's RAM lives in the SDRAM and the core drives the SD card slot that holds its image:
   -- only the R4, R5 and R6 board top files (M2M/vhdl/top_mega65-r4/5/6.vhd) wire them to the core.
   -- R3 has no SDRAM.
   assert G_BOARD /= "MEGA65_R3"
      report "MegaZXNext needs a MEGA65 R4, R5 or R6: R3 has no SDRAM"
      severity failure;

   hr_core_write_o      <= '0';
   hr_core_read_o       <= '0';
   hr_core_address_o    <= (others => '0');
   hr_core_writedata_o  <= (others => '0');
   hr_core_byteenable_o <= (others => '0');
   hr_core_burstcount_o <= (others => '0');

   -- Tristate all expansion port drivers that we can directly control
   cart_ctrl_oe_o       <= '0';
   cart_addr_oe_o       <= '0';
   cart_data_oe_o       <= '0';

   -- Due to a bug in the R5/R6 boards, the cartridge port needs to be enabled for joystick port 2 to work
   cart_en_o            <= '1';

   cart_reset_oe_o      <= '0';
   cart_game_oe_o       <= '0';
   cart_exrom_oe_o      <= '0';
   cart_nmi_oe_o        <= '0';
   cart_irq_oe_o        <= '0';
   cart_roml_oe_o       <= '0';
   cart_romh_oe_o       <= '0';

   -- Default values for all signals
   cart_phi2_o          <= '0';
   cart_reset_o         <= '1';
   cart_dotclock_o      <= '0';
   cart_game_o          <= '1';
   cart_exrom_o         <= '1';
   cart_nmi_o           <= '1';
   cart_irq_o           <= '1';
   cart_roml_o          <= '0';
   cart_romh_o          <= '0';
   cart_ba_o            <= '0';
   cart_rw_o            <= '0';
   cart_io1_o           <= '0';
   cart_io2_o           <= '0';
   cart_a_o             <= (others => '0');
   cart_d_o             <= (others => '0');

   iec_reset_n_o        <= '1';
   iec_atn_n_o          <= '1';
   iec_clk_en_o         <= '0';
   iec_clk_n_o          <= '1';
   iec_data_en_o        <= '0';
   iec_data_n_o         <= '1';
   iec_srq_en_o         <= '0';
   iec_srq_n_o          <= '1';

   main_joy_1_up_n_o    <= '1';
   main_joy_1_down_n_o  <= '1';
   main_joy_1_left_n_o  <= '1';
   main_joy_1_right_n_o <= '1';
   main_joy_1_fire_n_o  <= '1';
   main_joy_2_up_n_o    <= '1';
   main_joy_2_down_n_o  <= '1';
   main_joy_2_left_n_o  <= '1';
   main_joy_2_right_n_o <= '1';
   main_joy_2_fire_n_o  <= '1';

   -- MMCME2_ADV clock generator: 28 MHz, 28 MHz @ 180 deg, 14 MHz, 7 MHz, 112 MHz
   clk_gen : entity work.clk
      port map (
         sys_clk_i         => clk_i,           -- expects 100 MHz
         main_clk_o        => main_clk,
         main_clk_n_o      => main_clk_n,
         clk_14_o          => clk_14,
         clk_7_o           => clk_7,
         sdram_clk_o       => sdram_clk,
         sdram_out_clk_o   => sdram_out_clk,
         main_rst_o        => main_rst,
         sdram_rst_o       => sdram_rst
      ); -- clk_gen

   main_clk_o  <= main_clk;
   main_rst_o  <= main_rst;
   video_clk_o <= main_clk;
   video_rst_o <= main_rst;

   ---------------------------------------------------------------------------------------------
   -- main_clk (MiSTer core's clock)
   ---------------------------------------------------------------------------------------------

   -- MEGA65's power led: By default, it is on and glows green when the MEGA65 is powered on.
   -- We switch it to blue when a long reset is detected and as long as the user keeps pressing the preset button
   main_power_led_o     <= '1';
   main_power_led_col_o <= x"0000FF" when main_reset_m2m_i else x"00FF00";

   -- Drive led: SD card activity of the ZX Next
   main_drive_led_o     <= main_sd_active;
   main_drive_led_col_o <= x"FFFF00";

   -- VGA: the scandoubler is on unless one of the retro 15 kHz modes is selected
   main_scandoubler     <= not (main_osm_control_i(C_MENU_VGA_15KHZHSVS) or main_osm_control_i(C_MENU_VGA_15KHZCS));

   -- main.vhd contains the actual MiSTer core
   i_main : entity work.main
      port map (
         clk_main_i           => main_clk,
         clk_main_n_i         => main_clk_n,
         clk_14_i             => clk_14,
         clk_7_i              => clk_7,
         clk_sdram_i          => sdram_clk,
         clk_sdram_out_i      => sdram_out_clk,
         rst_sdram_i          => sdram_rst,

         reset_soft_i         => main_reset_core_i,
         reset_hard_i         => main_reset_m2m_i,
         menu_reset_i         => main_osm_control_i(C_MENU_RESET),
         pause_i              => main_pause_core_i,

         clk_main_speed_i     => CORE_CLK_SPEED,

         cpu_speed_sw_i       => '0',

         -- Video output: 14 MHz pixel clock, synchronized to main_clk (28 MHz)
         video_ce_o           => video_ce_o,
         video_ce_ovl_o       => video_ce_ovl_o,
         video_red_o          => video_red_o,
         video_green_o        => video_green_o,
         video_blue_o         => video_blue_o,
         video_vs_o           => video_vs_o,
         video_hs_o           => video_hs_o,
         video_hblank_o       => video_hblank_o,
         video_vblank_o       => video_vblank_o,
         video_scandoubler_i  => main_scandoubler,

         -- audio output (pcm format, signed values)
         audio_left_o         => main_audio_left_o,
         audio_right_o        => main_audio_right_o,

         -- M2M Keyboard interface
         kb_key_num_i         => main_kb_key_num_i,
         kb_key_pressed_n_i   => main_kb_key_pressed_n_i,

         -- MEGA65 joysticks and paddles/mouse/potentiometers
         joy_1_up_n_i         => main_joy_1_up_n_i,
         joy_1_down_n_i       => main_joy_1_down_n_i,
         joy_1_left_n_i       => main_joy_1_left_n_i,
         joy_1_right_n_i      => main_joy_1_right_n_i,
         joy_1_fire_n_i       => main_joy_1_fire_n_i,

         joy_2_up_n_i         => main_joy_2_up_n_i,
         joy_2_down_n_i       => main_joy_2_down_n_i,
         joy_2_left_n_i       => main_joy_2_left_n_i,
         joy_2_right_n_i      => main_joy_2_right_n_i,
         joy_2_fire_n_i       => main_joy_2_fire_n_i,

         pot1_x_i             => main_pot1_x_i,
         pot1_y_i             => main_pot1_y_i,
         pot2_x_i             => main_pot2_x_i,
         pot2_y_i             => main_pot2_y_i,

         rtc_i                => main_rtc_i,

         img_enable_i         => main_img_enable,
         img_size_i           => main_img_size,
         img_ext_count_i      => main_img_ext_count,
         img_ext_addr_o       => main_img_ext_addr,
         img_ext_data_i       => main_img_ext_data,
         img_err_cnt_o        => main_img_err_cnt,

         sd_cs_n_o            => main_sd_cs_n,
         sd_sclk_o            => main_sd_sclk,
         sd_mosi_o            => main_sd_mosi,
         sd_miso_i            => main_sd_miso,
         sd_active_o          => main_sd_active,

         sdram_clk_o          => sdram_clk_o,
         sdram_cke_o          => sdram_cke_o,
         sdram_cs_n_o         => sdram_cs_n_o,
         sdram_ras_n_o        => sdram_ras_n_o,
         sdram_cas_n_o        => sdram_cas_n_o,
         sdram_we_n_o         => sdram_we_n_o,
         sdram_ba_o           => sdram_ba_o,
         sdram_a_o            => sdram_a_o,
         sdram_dqml_o         => sdram_dqml_o,
         sdram_dqmh_o         => sdram_dqmh_o,
         sdram_dq_out_o       => sdram_dq_out_o,
         sdram_dq_oe_n_o      => sdram_dq_oe_n_o,
         sdram_dq_in_i        => sdram_dq_in_i
      ); -- i_main

   ---------------------------------------------------------------------------------------------
   -- SD card slots
   --
   -- The ZX Next's SD card is an image file on the MEGA65's SD card. The QNICE Shell finds it at
   -- startup (m2m-rom.asm) and passes its position through the C_DEV_ZXN_IMG registers. From
   -- then on the core drives the slot that holds the image; QNICE does not use the card any more.
   ---------------------------------------------------------------------------------------------

   i_cdc_img_cfg : entity work.cdc_stable
      generic map (
         G_DATA_SIZE => 44
      )
      port map (
         src_clk_i   => qnice_clk_i,
         src_data_i  => qnice_img_enable & qnice_img_slot & qnice_img_ext_count & qnice_img_size,
         dst_clk_i   => main_clk,
         dst_data_o  => main_img_cfg
      ); -- i_cdc_img_cfg

   main_img_enable    <= main_img_cfg(43);
   main_img_slot      <= main_img_cfg(42);
   main_img_ext_count <= main_img_cfg(41 downto 32);
   main_img_size      <= main_img_cfg(31 downto 0);

   main_img_ext_read_proc : process (main_clk)
   begin
      if rising_edge(main_clk) then
         main_img_ext_data <= img_ext_ram(to_integer(unsigned(main_img_ext_addr)));
      end if;
   end process main_img_ext_read_proc;

   main_own_back <= main_img_enable and main_img_slot;
   main_own_tray <= main_img_enable and not main_img_slot;

   sd_reset_o    <= main_sd_cs_n when main_own_back = '1' else fw_sd_reset_i;
   sd_clk_o      <= main_sd_sclk when main_own_back = '1' else fw_sd_clk_i;
   sd_mosi_o     <= main_sd_mosi when main_own_back = '1' else fw_sd_mosi_i;
   sd2_reset_o   <= main_sd_cs_n when main_own_tray = '1' else fw_sd2_reset_i;
   sd2_clk_o     <= main_sd_sclk when main_own_tray = '1' else fw_sd2_clk_i;
   sd2_mosi_o    <= main_sd_mosi when main_own_tray = '1' else fw_sd2_mosi_i;
   main_sd_miso  <= sd_miso_i when main_img_slot = '1' else sd2_miso_i;

   ---------------------------------------------------------------------------------------------
   -- Audio and video settings (QNICE clock domain)
   ---------------------------------------------------------------------------------------------

   -- Due to a discussion on the MEGA65 discord (https://discord.com/channels/719326990221574164/794775503818588200/1039457688020586507)
   -- we decided to choose a naming convention for the PAL modes that might be more intuitive for the end users than it is
   -- for the programmers: "4:3" means "meant to be run on a 4:3 monitor", "5:4 on a 5:4 monitor".
   qnice_video_mode_o <= C_VIDEO_SVGA_800_60   when qnice_osm_control_i(C_MENU_SVGA_800_60)    = '1' else
                         C_VIDEO_HDMI_720_5994 when qnice_osm_control_i(C_MENU_HDMI_720_5994)  = '1' else
                         C_VIDEO_HDMI_640_60   when qnice_osm_control_i(C_MENU_HDMI_640_60)    = '1' else
                         C_VIDEO_HDMI_5_4_50   when qnice_osm_control_i(C_MENU_HDMI_5_4_50)    = '1' else
                         C_VIDEO_HDMI_4_3_50   when qnice_osm_control_i(C_MENU_HDMI_4_3_50)    = '1' else
                         C_VIDEO_HDMI_16_9_60  when qnice_osm_control_i(C_MENU_HDMI_16_9_60)   = '1' else
                         C_VIDEO_HDMI_16_9_50;

   -- Use On-Screen-Menu selections to configure several audio and video settings
   qnice_dvi_o                <= '0';                                         -- 0=HDMI (with sound), 1=DVI (no sound)
   qnice_audio_mute_o         <= '0';                                         -- audio is not muted
   qnice_audio_filter_o       <= qnice_osm_control_i(C_MENU_IMPROVE_AUDIO);   -- 0 = raw audio, 1 = use filters from globals.vhd
   qnice_zoom_crop_o          <= '0';   -- no zoom/crop: M2M's crop.vhd is made for the C64 picture

   -- VGA: "Standard VGA" (31 kHz, scandoubler on), "Retro 15 kHz with HSync and VSync", "Retro 15 kHz with CSync"
   qnice_scandoubler_o        <= not (qnice_osm_control_i(C_MENU_VGA_15KHZHSVS) or qnice_osm_control_i(C_MENU_VGA_15KHZCS));
   qnice_retro15kHz_o         <= qnice_osm_control_i(C_MENU_VGA_15KHZHSVS) or qnice_osm_control_i(C_MENU_VGA_15KHZCS);
   qnice_csync_o              <= qnice_osm_control_i(C_MENU_VGA_15KHZCS);
   qnice_osm_cfg_scaling_o    <= (others => '1');

   -- ascal filters that are applied while processing the input
   -- 00 : Nearest Neighbour
   -- 01 : Bilinear
   -- 10 : Sharp Bilinear
   -- 11 : Bicubic
   qnice_ascal_mode_o         <= "00";

   -- If polyphase is '1' then the ascal filter mode is ignored and polyphase filters are used instead
   qnice_ascal_polyphase_o    <= qnice_osm_control_i(C_MENU_CRT_EMULATION);

   -- ascal triple-buffering
   qnice_ascal_triplebuf_o    <= '0';

   -- Flip joystick ports (i.e. the joystick in port 2 is used as joystick 1 and vice versa)
   qnice_flip_joyports_o      <= qnice_osm_control_i(C_MENU_FLIP_JOYS);

   ---------------------------------------------------------------------------------------------
   -- Core specific device handling (QNICE clock domain)
   ---------------------------------------------------------------------------------------------

   -- C_DEV_ZXN_IMG: the ZX Next's SD card image (see the register map above)
   qnice_img_regs_proc : process (qnice_clk_i)
   begin
      if rising_edge(qnice_clk_i) then
         if qnice_dev_ce_i = '1' and qnice_dev_we_i = '1' and qnice_dev_id_i = C_DEV_ZXN_IMG then
            case to_integer(unsigned(qnice_dev_addr_i(11 downto 0))) is
               when 2      => qnice_img_size(15 downto 0)          <= qnice_dev_data_i;
               when 3      => qnice_img_size(31 downto 16)         <= qnice_dev_data_i;
               when 4      => qnice_img_slot                       <= qnice_dev_data_i(0);
               when 5      => qnice_img_enable                     <= qnice_dev_data_i(0);
               when 7      => qnice_img_ext_count                  <= qnice_dev_data_i(9 downto 0);
               when 16#10# => qnice_img_ext_stage(15 downto 0)     <= qnice_dev_data_i;
               when 16#11# => qnice_img_ext_stage(31 downto 16)    <= qnice_dev_data_i;
               when 16#12# => qnice_img_ext_stage(47 downto 32)    <= qnice_dev_data_i;
               when 16#13# => qnice_img_ext_stage(63 downto 48)    <= qnice_dev_data_i;
               when 16#14# => img_ext_ram(to_integer(unsigned(qnice_dev_data_i(8 downto 0)))) <= qnice_img_ext_stage;
               when others => null;
            end case;
         end if;
         if qnice_rst_i = '1' then
            qnice_img_enable <= '0';
         end if;
      end if;
   end process qnice_img_regs_proc;

   i_cdc_img_err_cnt : entity work.cdc_stable
      generic map (
         G_DATA_SIZE => 16
      )
      port map (
         src_clk_i   => main_clk,
         src_data_i  => main_img_err_cnt,
         dst_clk_i   => qnice_clk_i,
         dst_data_o  => qnice_img_err_cnt
      ); -- i_cdc_img_err_cnt

   qnice_img_read_proc : process (all)
   begin
      qnice_dev_data_o <= x"EEEE";
      if qnice_dev_id_i = C_DEV_ZXN_IMG then
         case to_integer(unsigned(qnice_dev_addr_i(11 downto 0))) is
            when 2      => qnice_dev_data_o <= qnice_img_size(15 downto 0);
            when 3      => qnice_dev_data_o <= qnice_img_size(31 downto 16);
            when 4      => qnice_dev_data_o <= x"000" & "000" & qnice_img_slot;
            when 5      => qnice_dev_data_o <= x"000" & "000" & qnice_img_enable;
            when 6      => qnice_dev_data_o <= qnice_img_err_cnt;
            when 7      => qnice_dev_data_o <= "000000" & qnice_img_ext_count;
            when others => null;
         end case;
      end if;
   end process qnice_img_read_proc;

   qnice_dev_wait_o     <= '0';

end architecture synthesis;
