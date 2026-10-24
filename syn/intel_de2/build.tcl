# Build Quartus II 13.0sp1 cho DE2, chay tu thu muc syn/intel_de2:
#   quartus_sh -t build.tcl [boot_hex] [ram_hex] [app_hex]
# Ket qua: build/ (project, .sof, bao cao) - khong commit thu muc nay.
load_package flow

set here     [file normalize [file dirname [info script]]]
set root     [file normalize "$here/../.."]
set boot_hex [expr {[llength $argv] > 0 ? [lindex $argv 0] : "$root/fw/build/firmware_imem.hex"}]
set ram_hex  [expr {[llength $argv] > 1 ? [lindex $argv 1] : "$root/fw/build/firmware_dmem.hex"}]
set app_hex  [expr {[llength $argv] > 2 ? [lindex $argv 2] : "$root/fw/build/app_firmware.hex"}]

file mkdir "$here/build"
cd "$here/build"
project_new hrot_de2 -overwrite

set_global_assignment -name FAMILY "Cyclone II"
set_global_assignment -name DEVICE EP2C35F672C6
set_global_assignment -name TOP_LEVEL_ENTITY DE2_Top
set_global_assignment -name VERILOG_INPUT_VERSION VERILOG_2001
set_global_assignment -name PROJECT_OUTPUT_DIRECTORY output_files

# RTL dung chung (rtl/core, rtl/uncore, rtl/top) + top boc chan cua board
foreach f [concat [glob $root/rtl/core/*.v] [glob $root/rtl/uncore/*.v] \
                  [list $root/rtl/top/RISCV_Core.v $root/rtl/top/SoC_Top.v $here/DE2_Top.v]] {
    set_global_assignment -name VERILOG_FILE $f
}
set_global_assignment -name SDC_FILE $here/constraints.sdc
source $here/de2_pins.tcl

foreach {name val} [list BOOT_HEX $boot_hex RAM_HEX $ram_hex APP_HEX $app_hex] {
    if {$val ne ""} { set_parameter -name $name $val }
}

set_global_assignment -name RESERVE_ALL_UNUSED_PINS "AS INPUT TRI-STATED"
set_global_assignment -name STRATIX_DEVICE_IO_STANDARD "3.3-V LVTTL"

execute_flow -compile
project_close
