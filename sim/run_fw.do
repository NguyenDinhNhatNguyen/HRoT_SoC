# sim/run_fw.do -- whole-SoC testbenches of Phat's firmware and core (dv/tb/SoC_*_tb.sv). Run from sim/:
#   vsim -c -do "set TB SoC_Fw_tb; do run_fw.do"                         Secure Boot firmware (P-13), good image
#   vsim -c -do "set TB SoC_Fw_tb; set PLUSARGS +TAMPER; do run_fw.do"   Secure Boot firmware, tampered image
#   vsim -c -do "set TB SoC_Irq_tb; do run_fw.do"                        interrupts on both cores (P-14)
#   vsim -c -do "set TB SoC_App_tb; do run_fw.do"                        firmware of both cores (P-16), add
#                                                                        "set PLUSARGS +TAMPER" for a tampered App ROM
# SoC_Fw_tb and SoC_App_tb need the firmware first: make fw (fw/build/firmware_imem.hex, firmware_dmem.hex,
# app_firmware.hex). SoC_App_tb takes the golden hash from firmware_imem.hex, as built.
# app.hex comes from dv/sw/mkhex.py, fw_golden.hex from fw/tools/golden.py app.hex,
# SoC_Irq_tb's own programs from dv/tests/asm/soc_irq_*.hex.
if {![info exists TB]} {set TB SoC_Fw_tb}
if {![info exists PLUSARGS]} {set PLUSARGS {}}
if {![file exists app.hex]} {exec python ../dv/sw/mkhex.py .}
exec python ../fw/tools/golden.py app.hex fw_golden.hex

if {[file exists work]} {vdel -all -lib work}
vlib work

vlog -sv ../rtl/core/*.v
vlog -sv ../rtl/bus/*.v ../rtl/periph/*.v ../rtl/mem/*.v ../rtl/crypto/*.v
vlog -sv ../rtl/top/RISCV_Core.v ../rtl/top/SoC_Top.v
vlog -sv ../dv/tb/$TB.sv

vsim -voptargs="+acc" work.$TB {*}$PLUSARGS
if {[batch_mode]} {log -r /*} else {add wave -position insertpoint sim:/$TB/dut/*}
run -all
if {[batch_mode]} {quit -f}
