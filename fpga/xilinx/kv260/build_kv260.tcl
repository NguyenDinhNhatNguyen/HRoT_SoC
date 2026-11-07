# Vivado build for the Kria KV260, run from fpga/xilinx/kv260 (or `make kv260`):
#   vivado -mode batch -source build_kv260.tcl -tclargs <part> [boot_hex] [ram_hex] [app_hex]
# Runs synthesis, place and route, the reports and the bitstream (kv260.bit).
set here [file normalize [file dirname [info script]]]
set root [file normalize "$here/../../.."]
set part     [expr {[llength $argv] > 0 ? [lindex $argv 0] : "xck26-sfvc784-2LV-c"}]
set boot_hex [expr {[llength $argv] > 1 ? [lindex $argv 1] : "$root/fw/build/firmware_imem.hex"}]
set ram_hex  [expr {[llength $argv] > 2 ? [lindex $argv 2] : "$root/fw/build/firmware_dmem.hex"}]
set app_hex  [expr {[llength $argv] > 3 ? [lindex $argv 3] : "$root/fw/build/app_firmware.hex"}]

file mkdir "$here/build"
cd "$here/build"

create_project -in_memory -part $part
set_property target_language Verilog [current_project]
# kv260_bd.tcl reads the build directory from argv index 4
set argv [list $part $boot_hex $ram_hex $app_hex "$here/build"]
source $here/kv260_bd.tcl

read_verilog [concat [glob $root/rtl/{core,bus,periph,mem,crypto}/*.v] \
                     [list $root/rtl/top/RISCV_Core.v $root/rtl/top/SoC_Top.v $here/KV260_Top.v]]
read_xdc $here/kv260.xdc

synth_design -top KV260_Top -part $part \
    -generic BOOT_HEX=\"$boot_hex\" -generic RAM_HEX=\"$ram_hex\" -generic APP_HEX=\"$app_hex\"
opt_design
place_design
route_design

report_utilization    -file utilization.rpt
report_timing_summary -file timing_summary.rpt
write_bitstream -force kv260.bit
