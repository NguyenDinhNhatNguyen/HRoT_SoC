# HRoT_SoC entry points. Run inside WSL (Ubuntu) from the repo root:
#   make test        full regression (core, IP, SoC, VP) on QuestaSim, prints PASS/FAIL per check
#   make cov         code and functional coverage of the core, SHA-256 and APB tests (sim/cov.sh, P-19)
#   make sim-unit    the 11 core unit testbenches (sim/run_unit.do)
#   make sim-core    core simulation (sim/run_rtl.do), TB=RISCV_Core_prog_tb | RISCV_Core_tb | RISCV_Core_hazard_tb
#   make sim-uvm     UVM AXI4-Lite (sim/run_uvm.do), TEST=axi4_lite_full_test SEED=1
#   make sim-soc     whole-SoC simulation (sim/run_soc.do)
#   make sim-ip      APB peripheral testbench (sim/run_ip.do)
#   make sim-ram     SRAM macro wrappers of the ASIC build against a reference array (sim/run_ram.do, P-21)
#   make sim-bv      Boot_Verifier and the SYSCSR release gate (sim/run_bv.do)
#   make vp          SystemC virtual platform (sim/run_vp.sh)
#   make fw          build the Master firmware (CMake + riscv64-unknown-elf)
#   make de2         synthesis + P&R for the DE2 (Quartus II 13.0sp1)
#   make xilinx      synthesis + P&R for a Xilinx part (Vivado 2025.2), PART=...
#   make kv260       synthesis + P&R for the Kria KV260 (Vivado 2025.2), clock from the PS
#   make asic-yosys  trend numbers for SoC_Top with Yosys + NanGate45 in docker (asic/run_yosys.sh)
#   make asic-genus  Genus synthesis of ASIC_Top with GPDK45, school server only (asic/genus/synth.tcl)
#   make asic-genus-sweep  period sweep 20 12 10 8 7 6 ns plus a run without clock gating (asic/genus/sweep.sh)
#   make asic-genus-save  copy the text reports of asic-genus, the sweep and asic-gls into asic/reports
#   make asic-lec    Conformal LEC of ASIC_Top, RTL against the Genus netlist, school server only
#   make asic-gls    Xcelium gate-level simulation of the netlist with ASIC_Top_tb, school server only
#   make asic-macro-info  size, pins and area of the school SRAM macro (asic/macro_info.sh)
#   make asic-innovus  Innovus on ASIC_Top (floorplan to route) after asic-genus, school server only
#   make asic-sta    Tempus STA of ASIC_Top, SPEF=<file> NETLIST=<file> SDC=<file> for after route
#   make asic-lec-save, asic-pnr-save, asic-sta-save  copy only the text reports into asic/reports
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

# FPGA builds load the test firmware (dv/sw/mkhex.py, UART at 115200 baud / 50 MHz) by default.
# For the real firmware (make fw first): make de2 BOOT_HEX=fw/build/firmware_imem.hex ...
HEX_DIR  := build/hex
BOOT_HEX ?= $(HEX_DIR)/boot.hex
RAM_HEX  ?= $(HEX_DIR)/zero.hex
APP_HEX  ?= $(HEX_DIR)/app.hex
winpath   = $(shell wslpath -m $(abspath $(1)))

.PHONY: test cov sim-unit sim-core sim-uvm sim-soc sim-ip sim-ram vp fw hex de2 xilinx asic-yosys asic-genus asic-genus-sweep asic-genus-save asic-lec asic-lec-save asic-gls asic-macro-info asic-innovus asic-sta asic-pnr-save asic-sta-save clean

test:
	bash sim/regress.sh

cov:
	QUESTA=$(QUESTA) bash sim/cov.sh

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

sim-ram:
	cd sim && $(QUESTA) -c -do run_ram.do

sim-bv:
	cd sim && $(QUESTA) -c -do run_bv.do

vp:
	cd sim && bash run_vp.sh

fw:
	cmake -S fw -B fw/build && cmake --build fw/build

hex:
	mkdir -p $(HEX_DIR)
	python3 dv/sw/mkhex.py $(HEX_DIR) --baud-div 26
	echo 00000000 > $(HEX_DIR)/zero.hex

de2: hex
	cd fpga/intel/de2 && $(QUARTUS) -t build.tcl $(call winpath,$(BOOT_HEX)) $(call winpath,$(RAM_HEX)) $(call winpath,$(APP_HEX))

xilinx: hex
	cd fpga/xilinx/artix7 && cmd.exe /c "$(VIVADO) -mode batch -nojournal -nolog -source build.tcl -tclargs $(PART) $(call winpath,$(BOOT_HEX)) $(call winpath,$(RAM_HEX)) $(call winpath,$(APP_HEX))"

asic-yosys:
	bash asic/run_yosys.sh

# School server only (Genus + GPDK45). PERIOD=20 CG=1 are the defaults, see asic/genus/synth.tcl.
# The netlist, SDF and logs stay in asic/out_genus and asic/run_genus, both ignored by git.
asic-genus:
	rm -f asic/out_genus/ASIC_Top_netlist.v
	mkdir -p asic/run_genus
	cd asic/run_genus && rm -f genus.log* genus.cmd* && genus -batch -files ../genus/synth.tcl -log genus.log
	@test -f asic/out_genus/ASIC_Top_netlist.v || { echo "ERROR: Genus produced no netlist, see asic/run_genus/genus.log"; exit 1; }
	@cat asic/out_genus/reports/summary.txt

# One Genus run per period, results in asic/out_sweep (ignored by git). PERIODS="10 9 8" changes the list
asic-genus-sweep:
	bash asic/genus/sweep.sh

asic-gls:
	bash asic/gls/run.sh

asic-macro-info:
	bash asic/macro_info.sh

# Only .rpt, .txt and .md reports are copied, never the netlist, SDF or anything built from the PDK
asic-genus-save:
	bash asic/genus/save.sh

# The next targets are drafts (P-20, P-21): the scripts follow the RV32i-SoC flow that ran on the
# server, but they have not run on HRoT_SoC yet. Results stay in asic/out_* and asic/run_*, ignored by git.
asic-lec:
	bash asic/lec/run_lec.sh

# Innovus needs the SRAM wrappers first: it rejects black boxes and the assign statements they leave
asic-innovus:
	@test -f asic/out_genus/ASIC_Top_netlist.v || { echo "ERROR: no netlist yet, run make asic-genus first"; exit 1; }
	rm -f asic/out_innovus/ASIC_Top_pnr.v
	mkdir -p asic/run_innovus
	cd asic/run_innovus && rm -f innovus.log* innovus.cmd* && innovus -batch -files ../pnr/run_all.tcl -log innovus.log
	@test -f asic/out_innovus/ASIC_Top_pnr.v || { echo "ERROR: Innovus stopped midway, see asic/run_innovus/innovus.log"; exit 1; }
	@cat asic/out_innovus/reports/pd_checks.rpt asic/out_innovus/reports/slack_summary.txt 2>/dev/null || true
	@grep -i violations asic/out_innovus/reports/drc.rpt 2>/dev/null || true

# STA stage: pre (Genus netlist) or spef (SPEF=<absolute path>, Tempus runs inside asic/run_sta)
asic-sta:
	@command -v tempus > /dev/null || { echo "ERROR: tempus not found, this target runs on the school server"; exit 1; }
	@stage=$$( [ -n "$(SPEF)" ] && echo spef || echo pre ); \
	  rm -f asic/out_sta/$$stage/summary.txt; mkdir -p asic/run_sta; \
	  ( cd asic/run_sta && rm -f tempus.log* tempus.cmd* tempus.out && \
	    tempus -nowin -files ../sta/sta.tcl -log tempus.log < /dev/null > tempus.out 2>&1 ) || true; \
	  test -f asic/out_sta/$$stage/summary.txt || { echo "ERROR: Tempus wrote no summary, see asic/run_sta/tempus.log and tempus.out"; exit 1; }; \
	  cat asic/out_sta/$$stage/summary.txt

# Copy only text reports into asic/reports, never netlists, SPEF, SDF or GDS
asic-lec-save:
	bash asic/save_reports.sh asic/out_lec/reports asic/reports/lec
	cp asic/out_lec/lec.txt asic/reports/lec/
	@git status --short asic/reports/lec

asic-pnr-save:
	bash asic/save_reports.sh asic/out_innovus/reports asic/reports/innovus
	@git status --short asic/reports/innovus | head -20

asic-sta-save:
	bash asic/save_reports.sh asic/out_sta asic/reports/sta
	@git status --short asic/reports/sta

kv260: hex
	cd fpga/xilinx/kv260 && cmd.exe /c "$(VIVADO) -mode batch -nojournal -nolog -source build_kv260.tcl -tclargs xck26-sfvc784-2LV-c $(call winpath,$(BOOT_HEX)) $(call winpath,$(RAM_HEX)) $(call winpath,$(APP_HEX))"

clean:
	rm -rf build fw/build fpga/intel/de2/build fpga/xilinx/artix7/build fpga/xilinx/kv260/build vp/build sim/work sim/transcript sim/*.wlf sim/*.hex sim/labels.vh
