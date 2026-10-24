# sim/run_rtl.do  -- mô phỏng lõi RISC-V (không cần uncore), chạy từ thư mục sim/
#   vsim -c -do run_rtl.do                               (mặc định: RISCV_Core_prog_tb)
#   vsim -c -do "set TB RISCV_Core_tb; do run_rtl.do"
# TB có sẵn: RISCV_Core_prog_tb (chạy dv/tests/asm/core_isa_test.hex) | RISCV_Core_tb
if {![info exists TB]} {set TB RISCV_Core_prog_tb}

if {[file exists work]} {vdel -all -lib work}
vlib work

vlog -sv ../rtl/core/*.v
vlog -sv ../rtl/top/RISCV_Core.v
vlog -sv ../dv/tb/$TB.sv

vsim -voptargs="+acc" work.$TB
if {[batch_mode]} {log -r /*} else {add wave -position insertpoint sim:/$TB/dut/*}
run -all
if {[batch_mode]} {quit -f}
