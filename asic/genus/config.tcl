# config.tcl - PDK paths for the Genus flow on the school server (P-20).
# Lab folder layout: <PDK_DIR>/lib/*.lib and <PDK_DIR>/lef/gsclib045_*.lef (GPDK45, gsclib045).
# Point the PDK_DIR environment variable at the Lab PDK_GPDK45 folder, or keep the default below.
# Only paths live in the repo. The libraries stay on the server and are never committed.

if {[info exists ::env(PDK_DIR)] && $::env(PDK_DIR) ne ""} {
    set PDK_DIR $::env(PDK_DIR)
} else {
    set PDK_DIR $::env(HOME)/PDK_GPDK45
}

set LIB_DIR  $PDK_DIR/lib
# Setup corner (1.0 V, 125 C)
set LIB_SLOW slow_vdd1v0_basiccells.lib

# SRAM macro of the school (P-21), read only when SRAM=1 (see synth.tcl). One corner only (typical)
set SRAM_LIB sram_2k_macro.lib

# Double-height cells of gsclib045 (SITE CoreSiteDouble). The floorplan has only single-height
# rows, so they are banned in Genus and the netlist stays usable for Innovus (P-21)
set DONT_USE_CELLS {BUFX2 CLKBUFX2}

if {[info exists ::env(SRAM)] && $::env(SRAM) == 1 && ![file exists $LIB_DIR/$SRAM_LIB]} {
    puts "ERROR: SRAM=1 but cannot find $LIB_DIR/$SRAM_LIB"
    quit
}
if {![file exists $LIB_DIR/$LIB_SLOW]} {
    puts "ERROR: cannot find $LIB_DIR/$LIB_SLOW, set PDK_DIR to the Lab PDK_GPDK45 folder"
    quit
}
