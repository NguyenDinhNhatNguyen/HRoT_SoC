# ============================================================================
# sim/run_soc.do -- whole SoC (both cores + bus + peripherals). Run from sim/:
#   vsim -c -do run_soc.do
# Needs the test firmware first: python3 ../dv/sw/mkhex.py .   (writes boot.hex, app.hex, labels.vh)
#   set PLUSARGS +TAMPER   runs the tampered-image case (Boot Guard must lock the App out)
# ============================================================================
if {![file exists boot.hex]} {exec python ../dv/sw/mkhex.py .}
if {![info exists PLUSARGS]} {set PLUSARGS {}}

if {[file exists work]} {vdel -all -lib work}
vlib work

vlog -sv ../rtl/core/*.v
vlog -sv ../rtl/bus/*.v ../rtl/periph/*.v ../rtl/mem/*.v ../rtl/crypto/*.v
vlog -sv ../rtl/top/RISCV_Core.v ../rtl/top/SoC_Top.v
vlog -sv +incdir+. ../dv/tb/soc/SoC_Top_tb.sv

vsim -voptargs="+acc" work.soc_tb {*}$PLUSARGS
if {[batch_mode]} {log -r /*} else {add wave -position insertpoint sim:/soc_tb/dut/*}
run -all
if {[batch_mode]} {quit -f}
