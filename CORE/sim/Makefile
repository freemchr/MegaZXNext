# Simulations with GHDL
#
#    make            run all testbenches
#    make sdram      sdram_zxn.vhd (SDRAM controller)
#    make sd         sd_image.vhd (SD card image: virtual SD card + physical card access)
#    make speed      CPU speed changes: ZX Next + sdram_zxn + SDRAM model, test boot ROM
#    make speed_bram the same with bram_zxn (R3: 1 MB of block RAM)
#    make boot       the ZX Next from reset with an ideal memory (not part of make)
#    make GHDL=...   use a specific GHDL binary
#
# sdram_model.vhd and sdram_model_ram.vhd: SDRAM simulation model by MJoergen
# (https://github.com/MJoergen/SDRAM, MIT license)

GHDL      ?= ghdl
STD       := --std=08 -fsynopsys -frelaxed
WORK      := build

SDRAM_SRCS := ../vhdl/sdram_zxn.vhd sdram_model_ram.vhd sdram_model.vhd tb_sdram_zxn.vhd
SD_SRCS    := ../ZXNext_MiSTer/rtl/serial/spi_master.vhd $(WORK)/sd_spi_sim.vhd \
              ../vhdl/sd_card_zxn.vhd ../vhdl/sd_image.vhd tb_sd_image.vhd

.PHONY: sim sdram sd speed speed_bram boot clean
sim: sdram sd speed speed_bram

sdram:
	mkdir -p $(WORK)
	$(GHDL) -a $(STD) --workdir=$(WORK) --work=unisim unisim_sim.vhd
	$(GHDL) -a $(STD) --workdir=$(WORK) -P$(WORK) $(SDRAM_SRCS)
	$(GHDL) -e $(STD) --workdir=$(WORK) -P$(WORK) tb_sdram_zxn
	$(GHDL) -r $(STD) --workdir=$(WORK) -P$(WORK) tb_sdram_zxn --assert-level=error

# M2M's sd_controller (sd_spi.vhd) counts byte_counter (integer range 0 to 512) below zero while it
# waits for a read token. The hardware wraps and never looks at the value there, but GHDL stops
# with a bound check failure: the simulation uses a copy with a wider range.
sd:
	mkdir -p $(WORK)
	sed 's/byte_counter : integer range 0 to 512/byte_counter : integer range -65536 to 512/' \
	   ../../M2M/QNICE/vhdl/sd_spi.vhd > $(WORK)/sd_spi_sim.vhd
	grep -q 'range -65536 to 512' $(WORK)/sd_spi_sim.vhd
	$(GHDL) -a $(STD) --workdir=$(WORK) --work=zxnext ../vhdl/zxnext/bram_xilinx.vhd
	$(GHDL) -a $(STD) --workdir=$(WORK) -P$(WORK) $(SD_SRCS)
	$(GHDL) -e $(STD) --workdir=$(WORK) -P$(WORK) tb_sd_image
	$(GHDL) -r $(STD) --workdir=$(WORK) -P$(WORK) tb_sd_image --assert-level=error

# The ZX Next from reset with an ideal memory (zxnext_top_m65 and all ZX Next RTL of CORE-R6.xpr)
ZXNEXT_SRCS = $(shell python3 -c "import re;s=open('../CORE-R6.xpr').read();print(' '.join(p.replace('\$$PPRDIR','..') for p,b in re.findall(r'<File Path=\"([^\"]+)\">(.*?)</File>',s,re.S) if 'Val=\"zxnext\"' in b and p.endswith('.vhd')))")
# fifop.vhd uses to_unsigned(-1, n) (all ones), which GHDL rejects at run time: simulation copy
boot:
	mkdir -p $(WORK)
	sed 's/std_logic_vector(to_unsigned(-1,stored.length-1))/(stored\x27length-2 downto 0 => \x271\x27)/' \
	   ../ZXNext_MiSTer/rtl/serial/fifop.vhd > $(WORK)/fifop_sim.vhd
	grep -q "downto 0 => '1')" $(WORK)/fifop_sim.vhd
	$(GHDL) -a $(STD) --workdir=$(WORK) --work=unisim unisim_sim.vhd
	$(GHDL) -i $(STD) --workdir=$(WORK) --work=zxnext $(filter-out %/fifop.vhd,$(ZXNEXT_SRCS)) $(WORK)/fifop_sim.vhd
	$(GHDL) -m $(STD) --workdir=$(WORK) -P$(WORK) --work=zxnext zxnext_top_m65
	$(GHDL) -a $(STD) --workdir=$(WORK) -P$(WORK) tb_zxnext_boot.vhd
	$(GHDL) -e $(STD) --workdir=$(WORK) -P$(WORK) tb_zxnext_boot
	$(GHDL) -r $(STD) --workdir=$(WORK) -P$(WORK) tb_zxnext_boot --assert-level=error --ieee-asserts=disable

# The ZX Next with sdram_zxn and the SDRAM model, the boot ROM replaced by the test program of
# mk_cpu_speed_rom.py (lowers the CPU speed at different phases; no opcode fetch may get lost)
speed:
	mkdir -p $(WORK)
	sed 's/std_logic_vector(to_unsigned(-1,stored.length-1))/(stored\x27length-2 downto 0 => \x271\x27)/' \
	   ../ZXNext_MiSTer/rtl/serial/fifop.vhd > $(WORK)/fifop_sim.vhd
	grep -q "downto 0 => '1')" $(WORK)/fifop_sim.vhd
	python3 mk_cpu_speed_rom.py $(WORK)/bootrom_cpu_speed.vhd
	$(GHDL) -a $(STD) --workdir=$(WORK) --work=unisim unisim_sim.vhd
	$(GHDL) -i $(STD) --workdir=$(WORK) --work=zxnext $(filter-out %/fifop.vhd %/bootrom.vhd,$(ZXNEXT_SRCS)) \
	   $(WORK)/fifop_sim.vhd $(WORK)/bootrom_cpu_speed.vhd
	$(GHDL) -m $(STD) --workdir=$(WORK) -P$(WORK) --work=zxnext zxnext_top_m65
	$(GHDL) -a $(STD) --workdir=$(WORK) -P$(WORK) ../vhdl/sdram_zxn.vhd ../vhdl/bram_zxn.vhd sdram_model_ram.vhd sdram_model.vhd tb_cpu_speed.vhd
	$(GHDL) -e $(STD) --workdir=$(WORK) -P$(WORK) tb_cpu_speed
	$(GHDL) -r $(STD) --workdir=$(WORK) -P$(WORK) tb_cpu_speed --assert-level=error --ieee-asserts=disable

# The same with bram_zxn: run after "make speed" (uses its build)
speed_bram: speed
	$(GHDL) -r $(STD) --workdir=$(WORK) -P$(WORK) tb_cpu_speed -gG_BRAM=true --assert-level=error --ieee-asserts=disable

clean:
	rm -rf $(WORK) *.cf *.ghw
