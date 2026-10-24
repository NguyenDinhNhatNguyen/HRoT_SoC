# ============================================================================
# sim/run_soc.do -- mo phong toan SoC (2 loi + uncore), chay tu thu muc sim/
#   vsim -c -do run_soc.do
# Sinh firmware thu truoc: python ../dv/tests/mkhex.py .   (tao boot.hex, app.hex, labels.vh)
# ============================================================================
if {![file exists boot.hex]} {exec python ../dv/tests/mkhex.py .}

if {[file exists work]} {vdel -all -lib work}
vlib work

vlog -sv ../rtl/core/*.v
vlog -sv ../rtl/uncore/*.v
vlog -sv ../rtl/top/RISCV_Core.v ../rtl/top/SoC_Top.v
vlog -sv +incdir+. ../dv/tb/SoC_Top_tb.sv

vsim -voptargs="+acc" work.soc_tb
if {[batch_mode]} {log -r /*} else {add wave -position insertpoint sim:/soc_tb/dut/*}
run -all
if {[batch_mode]} {quit -f}
