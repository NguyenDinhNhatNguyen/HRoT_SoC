# sim/run_bv.do -- Boot_Verifier and the SYSCSR release gate. Run from sim/:
#   vsim -c -do run_bv.do
if {[file exists work]} {vdel -all -lib work}
vlib work

vlog -sv ../rtl/periph/SYSCSR.v ../rtl/periph/Boot_Verifier.v
vlog -sv ../dv/tb/soc/Boot_Verifier_tb.sv

vsim -voptargs="+acc" work.Boot_Verifier_tb
run -all
if {[batch_mode]} {quit -f}
