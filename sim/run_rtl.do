
vdel -all -lib work
vlib work

vlog -sv ../rtl/core/*.v
vlog -sv ../rtl/uncore/*.v
vlog -sv ../rtl/top/RISCV_Core.v

vlog -sv ../dv/tb/RISCV_Core_tb.sv

vsim -voptargs="+acc" work.RISCV_Core_tb
add wave -position insertpoint sim:/RISCV_Core_tb/dut/*
run 5000ns