# Build Vivado (non-project), chay tu thu muc syn/xilinx:
#   vivado -mode batch -source build.tcl -tclargs <part> [boot_hex] [ram_hex] [app_hex]
# Chua chot kit: chi chay tong hop + P&R de lay bao cao (khong ghi bitstream neu chua gan chan).
set here [file normalize [file dirname [info script]]]
set root [file normalize "$here/../.."]
set part     [expr {[llength $argv] > 0 ? [lindex $argv 0] : "xc7a35tcpg236-1"}]
set boot_hex [expr {[llength $argv] > 1 ? [lindex $argv 1] : "$root/fw/build/firmware_imem.hex"}]
set ram_hex  [expr {[llength $argv] > 2 ? [lindex $argv 2] : "$root/fw/build/firmware_dmem.hex"}]
set app_hex  [expr {[llength $argv] > 3 ? [lindex $argv 3] : "$root/fw/build/app_firmware.hex"}]

file mkdir "$here/build"
cd "$here/build"

read_verilog [concat [glob $root/rtl/core/*.v] [glob $root/rtl/uncore/*.v] \
                     [list $root/rtl/top/RISCV_Core.v $root/rtl/top/SoC_Top.v $here/Xilinx_Top.v]]
read_xdc $here/constraints.xdc

synth_design -top Xilinx_Top -part $part \
    -generic BOOT_HEX=\"$boot_hex\" -generic RAM_HEX=\"$ram_hex\" -generic APP_HEX=\"$app_hex\"
opt_design
place_design
route_design

report_utilization    -file utilization.rpt
report_timing_summary -file timing_summary.rpt
