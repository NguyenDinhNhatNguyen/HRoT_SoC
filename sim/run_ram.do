# sim/run_ram.do -- SRAM macro wrappers (RAM_Macro_Core, RAM_Macro_Axi). Run from sim/:
#   vsim -c -do run_ram.do                                   wrappers against a reference array (RAM_Macro_tb)
#   vsim -c -do "set TB RAM_Core_ISA_tb; do run_ram.do"      the core runs core_isa_test on RAM_Macro_Core
# The macro itself is the home model dv/models/sram_macro_model.v (on the server the real macro replaces it).
if {![info exists TB]} {set TB RAM_Macro_tb}
if {[file exists work]} {vdel -all -lib work}
vlib work

vlog -sv ../rtl/mem/RAM_Macro_Core.v ../rtl/mem/RAM_Macro_Axi.v ../rtl/bus/AXI4_Lite_Slave_Template.v
vlog -sv ../dv/models/sram_macro_model.v
vlog -sv ../rtl/core/*.v ../rtl/top/RISCV_Core.v
vlog -sv ../dv/tb/mem/$TB.sv

vsim -voptargs="+acc" work.$TB
run -all
if {[batch_mode]} {quit -f}
