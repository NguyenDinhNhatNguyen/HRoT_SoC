# sim/run_rtl.do -- RISC-V core on its own (no uncore). Run from sim/:
#   vsim -c -do run_rtl.do                               (default: RISCV_Core_prog_tb)
#   vsim -c -do "set TB RISCV_Core_tb; do run_rtl.do"
# Testbenches: RISCV_Core_prog_tb (runs dv/tests/asm/core_isa_test.hex) | RISCV_Core_tb | RISCV_Core_hazard_tb
if {![info exists TB]} {set TB RISCV_Core_prog_tb}

if {[file exists work]} {vdel -all -lib work}
vlib work

vlog -sv ../rtl/core/*.v
vlog -sv ../rtl/top/RISCV_Core.v
vlog -sv ../dv/tb/$TB.sv

vsim -voptargs="+acc" work.$TB
if {[batch_mode]} {log -r /*} else {add wave -position insertpoint sim:/$TB/dut/*}
run -all
if {[batch_mode]} {quit -f}
