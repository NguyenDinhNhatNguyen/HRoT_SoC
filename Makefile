# HRoT_SoC entry points. Run inside WSL (Ubuntu) from the repo root:
#   make test        full regression (core, IP, SoC, VP) on QuestaSim, prints PASS/FAIL per check
#   make sim-unit    the 11 core unit testbenches (sim/run_unit.do)
#   make sim-core    core simulation (sim/run_rtl.do), TB=RISCV_Core_prog_tb | RISCV_Core_tb | RISCV_Core_hazard_tb
#   make sim-uvm     UVM AXI4-Lite (sim/run_uvm.do), TEST=axi4_lite_full_test SEED=1
#   make sim-soc     whole-SoC simulation (sim/run_soc.do)
#   make sim-ip      APB peripheral testbench (sim/run_ip.do)
#   make vp          SystemC virtual platform (sim/run_vp.sh)
#   make fw          build the Master firmware (CMake + riscv64-unknown-elf)
#   make de2         synthesis + P&R for the DE2 (Quartus II 13.0sp1)
#   make xilinx      synthesis + P&R for a Xilinx part (Vivado 2025.2), PART=...
#   make clean       remove build output
# Windows tools are called through WSL interop by absolute path, so PATH doesn't matter.
# Simulation uses QuestaSim only, never ModelSim.

QUESTA  ?= /mnt/c/questasim64_10.2c/win64/vsim.exe
QUARTUS ?= /mnt/c/altera/13.0sp1/quartus/bin64/quartus_sh.exe
VIVADO  ?= D:\AMDDesignTools\2025.2\Vivado\bin\vivado.bat
PART    ?= xc7a35tcpg236-1
TB      ?= RISCV_Core_prog_tb
TEST    ?= axi4_lite_full_test
SEED    ?= 1

# FPGA builds load the test firmware (dv/sw/mkhex.py, UART at 115200 baud / 50 MHz) until the real
# firmware is ready. Override with: make de2 BOOT_HEX=fw/build/firmware_imem.hex ...
HEX_DIR  := build/hex
BOOT_HEX ?= $(HEX_DIR)/boot.hex
RAM_HEX  ?= $(HEX_DIR)/zero.hex
APP_HEX  ?= $(HEX_DIR)/app.hex
winpath   = $(shell wslpath -m $(abspath $(1)))

.PHONY: test sim-unit sim-core sim-uvm sim-soc sim-ip vp fw hex de2 xilinx clean

test:
	bash sim/regress.sh

sim-unit:
	cd sim && $(QUESTA) -c -do run_unit.do

sim-core:
	cd sim && $(QUESTA) -c -do "set TB $(TB); do run_rtl.do"

sim-uvm:
	cd sim && $(QUESTA) -c -do "set TEST $(TEST); set SEED $(SEED); do run_uvm.do"

sim-soc:
	python3 dv/sw/mkhex.py sim
	cd sim && $(QUESTA) -c -do run_soc.do

sim-ip:
	cd sim && $(QUESTA) -c -do run_ip.do

vp:
	cd sim && bash run_vp.sh

fw:
	cmake -S fw -B fw/build && cmake --build fw/build

hex:
	mkdir -p $(HEX_DIR)
	python3 dv/sw/mkhex.py $(HEX_DIR) --baud-div 26
	echo 00000000 > $(HEX_DIR)/zero.hex

de2: hex
	cd fpga/intel_de2 && $(QUARTUS) -t build.tcl $(call winpath,$(BOOT_HEX)) $(call winpath,$(RAM_HEX)) $(call winpath,$(APP_HEX))

xilinx: hex
	cd fpga/xilinx && cmd.exe /c "$(VIVADO) -mode batch -nojournal -nolog -source build.tcl -tclargs $(PART) $(call winpath,$(BOOT_HEX)) $(call winpath,$(RAM_HEX)) $(call winpath,$(APP_HEX))"

clean:
	rm -rf build fw/build fpga/intel_de2/build fpga/xilinx/build vp/build sim/work sim/transcript sim/*.wlf sim/*.hex sim/labels.vh
