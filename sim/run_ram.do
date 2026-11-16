# sim/run_ram.do -- SRAM macro wrappers (RAM_Macro_Core, RAM_Macro_Axi) against a reference array. Run from sim/:
#   vsim -c -do run_ram.do
# The macro itself is the home model dv/models/sram_macro_model.v (on the server the real macro replaces it).
if {[file exists work]} {vdel -all -lib work}
vlib work

vlog -sv ../rtl/mem/RAM_Macro_Core.v ../rtl/mem/RAM_Macro_Axi.v ../rtl/bus/AXI4_Lite_Slave_Template.v
vlog -sv ../dv/models/sram_macro_model.v
vlog -sv ../dv/tb/mem/RAM_Macro_tb.sv

vsim -voptargs="+acc" work.RAM_Macro_tb
run -all
if {[batch_mode]} {quit -f}
