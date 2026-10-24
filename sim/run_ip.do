# ============================================================================
# sim/run_ip.do -- testbench tung IP uncore (APB: SYSCSR, GPIO, UART), chay tu thu muc sim/
#   vsim -c -do run_ip.do
# ============================================================================
if {[file exists work]} {vdel -all -lib work}
vlib work

vlog -sv ../rtl/periph/*.v
vlog -sv ../dv/tb/soc/APB_Periph_tb.sv

vsim -voptargs="+acc" work.APB_Periph_tb
run -all
if {[batch_mode]} {quit -f}
