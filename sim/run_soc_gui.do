# sim/run_soc_gui.do -- the whole-SoC test with a ready wave window, for screenshots in the reports. Run from sim/ in the GUI:
#   vsim -do run_soc_gui.do                                           good image: App is released, LED 0x5A
#   vsim -do "set PLUSARGS +TAMPER; do run_soc_gui.do"                tampered image: App is locked, RAM is cleared, LED 0xEE
# Same compile and test as run_soc.do (dv/tb/soc/SoC_Top_tb.sv, test firmware of dv/sw/mkhex.py). Only the wave window differs.
if {![file exists boot.hex]} {exec python ../dv/sw/mkhex.py .}
if {![info exists PLUSARGS]} {set PLUSARGS {}}

if {[file exists work]} {vdel -all -lib work}
vlib work

vlog -sv ../rtl/core/*.v
vlog -sv ../rtl/bus/*.v ../rtl/periph/*.v ../rtl/mem/*.v ../rtl/crypto/*.v
vlog -sv ../dv/models/sram_macro_model.v
vlog -sv ../rtl/top/RISCV_Core.v ../rtl/top/SoC_Top.v
vlog -sv +incdir+. ../dv/tb/soc/SoC_Top_tb.sv

vsim -voptargs="+acc" work.soc_tb {*}$PLUSARGS

add wave -divider {Reset and release of the App Core}
add wave /soc_tb/clk
add wave /soc_tb/rst
add wave /soc_tb/dut/sys_rst
add wave /soc_tb/dut/syscsr/app_run
add wave /soc_tb/dut/app_core_reset_n
add wave -divider {Hardware verdict}
add wave /soc_tb/dut/bv_verified
add wave -radix unsigned /soc_tb/dut/boot_verifier/st
add wave -divider {Boot Guard}
add wave /soc_tb/dut/syscsr/lock_q
add wave /soc_tb/dut/syscsr/zero_done
add wave -divider {Result}
add wave -radix hexadecimal /soc_tb/led
run -all
catch {wave zoom full}
