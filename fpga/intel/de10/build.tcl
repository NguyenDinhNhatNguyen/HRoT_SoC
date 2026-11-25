# Quartus II 13.0sp1 PPA build for the Cyclone V DE10 boards, run from fpga/intel/de10:
#   quartus_sh -t build.tcl <standard|nano> [boot_hex] [ram_hex] [app_hex]
# No pin assignments (the Fitter places the pins), so the result shows fit and timing only, not a
# bitstream for the board. Output goes to build/<board>/, which is not committed.
load_package flow

set here     [file normalize [file dirname [info script]]]
set root     [file normalize "$here/../../.."]
set board    [lindex $argv 0]
# shortcut: part numbers not yet checked against the Terasic manual or the chip, check before pin assignment
array set parts {standard 5CSXFC6D6F31C6 nano 5CSEBA6U23I7}
if {![info exists parts($board)]} { puts "ERROR: board must be standard or nano"; exit 1 }
set boot_hex [expr {[llength $argv] > 1 ? [lindex $argv 1] : "$root/fw/build/firmware_imem.hex"}]
set ram_hex  [expr {[llength $argv] > 2 ? [lindex $argv 2] : "$root/fw/build/firmware_dmem.hex"}]
set app_hex  [expr {[llength $argv] > 3 ? [lindex $argv 3] : "$root/fw/build/app_firmware.hex"}]

file mkdir "$here/build/$board"
cd "$here/build/$board"
project_new hrot_de10 -overwrite

set_global_assignment -name FAMILY "Cyclone V"
set_global_assignment -name DEVICE $parts($board)
# The generic board wrapper is plain Verilog, shared with the Artix-7 build
set_global_assignment -name TOP_LEVEL_ENTITY Xilinx_Top
set_global_assignment -name VERILOG_INPUT_VERSION VERILOG_2001
set_global_assignment -name PROJECT_OUTPUT_DIRECTORY output_files

foreach f [concat [glob $root/rtl/{core,bus,periph,mem,crypto}/*.v] \
                  [list $root/rtl/top/RISCV_Core.v $root/rtl/top/SoC_Top.v $root/fpga/xilinx/artix7/Xilinx_Top.v]] {
    # Data_Memory comes from this folder, see the note in that file
    if {[file tail $f] eq "Data_Memory.v"} { set f $here/Data_Memory.v }
    set_global_assignment -name VERILOG_FILE $f
}
set_global_assignment -name SDC_FILE $here/constraints.sdc

foreach {name val} [list BOOT_HEX $boot_hex RAM_HEX $ram_hex APP_HEX $app_hex] {
    if {$val ne ""} { set_parameter -name $name $val }
}

execute_flow -compile
# Power estimate with the default toggle rates (not a measurement), written to output_files/hrot_de10.pow.rpt
execute_module -tool pow
project_close
