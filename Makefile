# HRoT_SoC - tram dieu khien chung. CHAY TRONG WSL (Ubuntu), tai thu muc goc repo:
#   make test        regression toan bo (lop, IP, SoC, VP) bang QuestaSim -> PASS/FAIL
#   make sim-unit    11 testbench don vi cua loi (sim/run_unit.do)
#   make sim-core    mo phong loi (sim/run_rtl.do), TB=RISCV_Core_prog_tb | RISCV_Core_tb | RISCV_Core_hazard_tb
#   make sim-uvm     UVM AXI4-Lite (sim/run_uvm.do), TEST=axi4_lite_full_test SEED=1
#   make sim-soc     mo phong toan SoC (sim/run_soc.do)
#   make sim-ip      testbench ngoai vi APB (sim/run_ip.do)
#   make vp          Virtual Platform SystemC (sim/run_vp.sh)
#   make fw          build firmware Master (CMake + riscv64-unknown-elf)
#   make de2         tong hop + P&R cho DE2 (Quartus II 13.0sp1)
#   make xilinx      tong hop + P&R cho kit Xilinx (Vivado 2025.2), PART=...
#   make clean       xoa thu muc build
# Cong cu Windows goi qua WSL interop bang duong dan tuyet doi (khong phu thuoc PATH):
# mo phong chi dung QuestaSim, khong dung ModelSim.

QUESTA  ?= /mnt/c/questasim64_10.2c/win64/vsim.exe
QUARTUS ?= /mnt/c/altera/13.0sp1/quartus/bin64/quartus_sh.exe
VIVADO  ?= D:\AMDDesignTools\2025.2\Vivado\bin\vivado.bat
PART    ?= xc7a35tcpg236-1
TB      ?= RISCV_Core_prog_tb
TEST    ?= axi4_lite_full_test
SEED    ?= 1

# Firmware nap vao FPGA: mac dinh dung firmware thu (dv/sw/mkhex.py, UART 115200 @ 50 MHz)
# cho toi khi co firmware that; doi bang: make de2 BOOT_HEX=fw/build/firmware_imem.hex ...
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
