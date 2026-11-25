# sim/run_imem.do -- shared instruction memory of the two-world design (dv/tb/mem/IMEM_tb.sv). Run from sim/:
#   vsim -c -do run_imem.do
if {[file exists work]} {vdel -all -lib work}
vlib work

vlog -sv ../rtl/mem/IMEM.v
vlog -sv ../dv/tb/mem/IMEM_tb.sv

vsim -voptargs="+acc" work.IMEM_tb
run -all
if {[batch_mode]} {quit -f}
