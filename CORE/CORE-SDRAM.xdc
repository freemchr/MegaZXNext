## MegaZXNext: ZX Next core for the MEGA65
##
## SDRAM constraints (R4, R5 and R6 only: the R3 has no SDRAM, its ZX Next RAM is block RAM,
## see bram_zxn.vhd). Used by CORE-R4/R5/R6.xpr together with CORE.xdc.
##
## MEGA65 port done by Chris Freeman in 2026 and licensed under GPL v3

## SDRAM port A <-> CPU: 2 cycles of sdram_clk in both directions. Valid because sdram_zxn only
## samples ram_a_*_i and only changes ram_a_wait/ram_a_do on the sdram_clk edges that coincide
## with an edge of CLK_28 (see the sdram_zxn.vhd header).
set_multicycle_path -from [get_clocks sdram_clk] -to [get_clocks {cpu_clk_div cpu_clk_28}] -start -setup 2
set_multicycle_path -from [get_clocks sdram_clk] -to [get_clocks {cpu_clk_div cpu_clk_28}] -start -hold 1
set_multicycle_path -from [get_clocks {cpu_clk_div cpu_clk_28}] -to [get_clocks sdram_clk] -setup 2
set_multicycle_path -from [get_clocks {cpu_clk_div cpu_clk_28}] -to [get_clocks sdram_clk] -hold 1

## The same for the port A signals that come from main_clk (rising and falling edge) logic.
## Only the port A registers: port B (Layer 2) samples its main_clk inputs on every edge.
## last_data: its clock enable sees ram_a_req_i only through the request queue branch, which is
## evaluated on even edges only (its data comes from registers).
set sdram_port_a [get_cells -hierarchical -filter {NAME =~ CORE/i_main/gen_sdram.i_sdram/* && (NAME =~ */a_req_e_reg* || NAME =~ */a_addr_r_reg* || NAME =~ */a_rd_n_r_reg* || NAME =~ */a_di_r_reg* || NAME =~ */a_fetch_r_reg* || NAME =~ */a_queued_reg* || NAME =~ */a_q_addr_reg* || NAME =~ */a_q_rd_n_reg* || NAME =~ */a_q_di_reg* || NAME =~ */ram_a_wait_reg* || NAME =~ */ram_a_do_reg* || NAME =~ */a_wait_o_reg* || NAME =~ */a_do_o_reg* || NAME =~ */last_data_reg*)}]
set_multicycle_path -from [get_clocks {main_clk main_clk_n}] -to $sdram_port_a -setup 2
set_multicycle_path -from [get_clocks {main_clk main_clk_n}] -to $sdram_port_a -hold 1

## SDRAM I/O: the I/O registers are packed into the IOBs (see sdram_zxn.vhd), which gives
## deterministic timing. Same settings as MJoergen's SDRAM controller for the MEGA65.
set_property -dict {PULLUP FALSE SLEW FAST DRIVE 16} [get_ports {sdram_*}]
set_property IOB TRUE [get_cells -hierarchical -filter {NAME =~ CORE/i_main/gen_sdram.i_sdram/* && (NAME =~ */cmd_reg* || NAME =~ */sd_a_reg* || NAME =~ */sd_ba_reg* || NAME =~ */sd_dqm?_reg || NAME =~ */dq_out_reg* || NAME =~ */dq_oe_n_reg* || NAME =~ */data_reg_reg*)}]

## SDRAM I/O timing (IS42S16320F-6, CL3): the SDRAM clock pin is the inverted sdram_out_clk (a PLL
## copy of sdram_clk, 56.25 degrees late, see clk.vhd), so the SDRAM samples commands and launches
## read data in the middle of our cycle + 1.4 ns. Delays: tAC <= 5.4 ns, tOH >= 2.5 ns,
## tIS >= 1.5 ns, tIH >= 0.8 ns, plus ~0.2 ns PCB per direction (estimated; the clock trace adds to
## the read path, so the 0.4 ns on input max and the 0 on input min are on the safe side).
## Read data is sampled CL+1 cycles after the READ command: 1.5 sdram_clk cycles after the SDRAM
## clock edge that launches it (multicycle 2, default hold). Without the 1.4 ns the read hold
## slack was -0.9 ns.
create_generated_clock -name sdram_out_clk [get_pins CORE/clk_gen/i_pll_sdram/CLKOUT0]
create_generated_clock -name sdram_pin_clk -source [get_pins CORE/i_main/gen_sdram.i_sdram/i_oddr_clk/C] \
   -multiply_by 1 -invert [get_ports sdram_clk_o]
set sdram_outs [get_ports {sdram_cke_o sdram_ras_n_o sdram_cas_n_o sdram_we_n_o sdram_cs_n_o sdram_ba_o[*] sdram_a_o[*] sdram_dqml_o sdram_dqmh_o sdram_dq_io[*]}]
set_input_delay  -clock sdram_pin_clk -max 5.8 [get_ports {sdram_dq_io[*]}]
set_input_delay  -clock sdram_pin_clk -min 2.5 [get_ports {sdram_dq_io[*]}]
set_output_delay -clock sdram_pin_clk -max 1.7  $sdram_outs
set_output_delay -clock sdram_pin_clk -min -0.8 $sdram_outs
set_multicycle_path -setup 2 -from [get_clocks sdram_pin_clk] -to [get_clocks sdram_clk]
