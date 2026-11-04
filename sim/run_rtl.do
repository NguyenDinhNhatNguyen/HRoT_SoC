# sim/run_rtl.do -- RISC-V core on its own (no uncore). Run from sim/:
#   vsim -c -do run_rtl.do                               (default: RISCV_Core_prog_tb)
#   vsim -c -do "set TB RISCV_Core_tb; do run_rtl.do"
# Testbenches: RISCV_Core_prog_tb (runs dv/tests/asm/core_isa_test.hex and core_trap_test.hex) | RISCV_Core_tb | RISCV_Core_hazard_tb
# COV <file.ucdb> (P-19, used by sim/cov.sh): code coverage on the core, the covergroups of
# RISCV_Core_prog_tb (+define+HROT_COV), and the coverage database saved to that file at the end
if {![info exists TB]} {set TB RISCV_Core_prog_tb}
set COV_RTL {}
set COV_DV  {}
set COV_SIM {}
if {[info exists COV]} {
  set COV_RTL {+cover=sbcef}
  set COV_DV  {+define+HROT_COV}
  set COV_SIM {-coverage}
}

if {[file exists work]} {vdel -all -lib work}
vlib work

vlog -sv {*}$COV_RTL ../rtl/core/*.v
vlog -sv {*}$COV_RTL ../rtl/top/RISCV_Core.v
vlog -sv {*}$COV_DV ../dv/tb/$TB.sv

vsim -voptargs="+acc" {*}$COV_SIM work.$TB
if {[info exists COV]} {coverage save -onexit $COV}
if {[batch_mode]} {log -r /*} else {add wave -position insertpoint sim:/$TB/dut/*}
run -all
if {[batch_mode]} {quit -f}
