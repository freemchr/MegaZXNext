# Simulation of the SDRAM controller (sdram_zxn.vhd) with GHDL
#
#    make            run the testbench
#    make GHDL=...   use a specific GHDL binary
#
# sdram_model.vhd and sdram_model_ram.vhd: SDRAM simulation model by MJoergen
# (https://github.com/MJoergen/SDRAM, MIT license)

GHDL      ?= ghdl
STD       := --std=08 -fsynopsys -frelaxed
WORK      := build

SRCS      := ../vhdl/sdram_zxn.vhd sdram_model_ram.vhd sdram_model.vhd tb_sdram_zxn.vhd

.PHONY: sim clean
sim:
	mkdir -p $(WORK)
	$(GHDL) -a $(STD) --workdir=$(WORK) --work=unisim unisim_sim.vhd
	$(GHDL) -a $(STD) --workdir=$(WORK) -P$(WORK) $(SRCS)
	$(GHDL) -e $(STD) --workdir=$(WORK) -P$(WORK) tb_sdram_zxn
	$(GHDL) -r $(STD) --workdir=$(WORK) -P$(WORK) tb_sdram_zxn --assert-level=error

clean:
	rm -rf $(WORK) *.cf *.ghw
