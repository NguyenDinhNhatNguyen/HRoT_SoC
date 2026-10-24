# ============================================================================
# sim/run_ip.do -- APB peripheral testbench (SYSCSR, GPIO, UART, TIMER, WDT). Run from sim/:
#   vsim -c -do run_ip.do
# ============================================================================
if {[file exists work]} {vdel -all -lib work}
vlib work

vlog -sv ../rtl/periph/*.v
vlog -sv ../dv/tb/soc/APB_Periph_tb.sv

vsim -voptargs="+acc" work.APB_Periph_tb
run -all
if {[batch_mode]} {quit -f}
