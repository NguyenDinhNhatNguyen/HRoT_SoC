# HRoT_SoC - tram dieu khien chung (chay trong Git Bash hoac WSL)
#   make fw          build firmware Master (CMake + riscv64-unknown-elf, chay trong WSL)
#   make sim-core    mo phong loi (Questa, sim/run_rtl.do)
#   make sim-soc     mo phong toan SoC (Questa, sim/run_soc.do)
#   make sim-ip      testbench ngoai vi APB
#   make vp          Virtual Platform SystemC (WSL)
#   make de2         tong hop + P&R cho DE2 (Quartus II 13.0sp1)
#   make xilinx      tong hop + P&R cho kit Xilinx (Vivado), PART=...
#   make clean       xoa thu muc build
# Duong dan cong cu dat qua bien moi truong, khong phu thuoc PATH (tranh xung dot Questa/ModelSim/Vivado).

QUARTUS ?= /c/altera/13.0sp1/quartus/bin64/quartus_sh.exe
VIVADO  ?= vivado
VSIM    ?= vsim
WSL     ?= wsl.exe -d Ubuntu --
PART    ?= xc7a35tcpg236-1

.PHONY: fw sim-core sim-soc sim-ip vp de2 xilinx clean

fw:
	$(WSL) bash -c "cmake -S fw -B fw/build && cmake --build fw/build"

sim-core:
	cd sim && $(VSIM) -c -do run_rtl.do

sim-soc:
	cd sim && $(VSIM) -c -do run_soc.do

sim-ip:
	cd sim && $(VSIM) -c -do run_ip.do

vp:
	$(WSL) bash -c "cd sim && bash run_vp.sh"

de2:
	cd syn/intel_de2 && $(QUARTUS) -t build.tcl

xilinx:
	cd syn/xilinx && $(VIVADO) -mode batch -source build.tcl -tclargs $(PART)

clean:
	rm -rf fw/build syn/intel_de2/build syn/xilinx/build vp/build sim/work sim/transcript sim/*.wlf
