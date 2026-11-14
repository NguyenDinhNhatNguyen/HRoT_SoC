# config.tcl - PDK paths shared by Innovus and Tempus for ASIC_Top (P-21).
# Layout of the Lab PDK: <PDK_DIR>/lib/*.lib, <PDK_DIR>/lef/*.lef. The paths and the corner
# choices follow the flow of RV32i-SoC (pnr/scripts/config.tcl, run on this server in Oct-Nov 2026).
# Only paths live in the repo. Libraries, LEF and GDS stay on the server and are never committed.

if {[info exists ::env(PDK_DIR)] && $::env(PDK_DIR) ne ""} {
    set PDK_DIR $::env(PDK_DIR)
} else {
    set PDK_DIR $::env(HOME)/PDK_GPDK45
}

set LIB_DIR   $PDK_DIR/lib
set LIB_SLOW  slow_vdd1v0_basiccells.lib   ;# Setup corner (1.0 V, 125 C), same file as asic/genus/config.tcl
set LIB_FAST  fast_vdd1v0_basicCells.lib   ;# Hold corner. The capital C is real (RV32i-SoC HT-01)
set TECH_LEF  $PDK_DIR/lef/gsclib045_tech.lef
set CELL_LEF  $PDK_DIR/lef/gsclib045_macro.lef
set GDS_MAP   $PDK_DIR/streamOut.map

# SRAM macro of the school: 80 x 100 um, 1 read/write port. Only one corner (typical) exists, so
# both analysis views read the same file, and paths through a macro are a little optimistic.
set SRAM_CELL      sram_2k_macro
set SRAM_LEF       $PDK_DIR/lef/sram_2k_macro.lef
set SRAM_LIB_SLOW  $PDK_DIR/lib/sram_2k_macro.lib
set SRAM_LIB_FAST  $PDK_DIR/lib/sram_2k_macro.lib

# BUFX2 is a double-height cell and the floorplan has single-height rows only. CLKBUFX2 breaks the
# pin spacing rule (Lab 04 of the school). Both are banned before any optimization.
set DONT_USE_CELLS {BUFX2 CLKBUFX2}
set CTS_BUFFERS    {CLKBUFX3 CLKBUFX4 CLKBUFX8 CLKBUFX12 CLKBUFX16}
set CTS_INVERTERS  {CLKINVX3 CLKINVX4 CLKINVX8 CLKINVX12 CLKINVX16}

set PWR_NET   VDD
set GND_NET   VSS
set CORE_SITE CoreSite

if {![file exists $LIB_DIR/$LIB_FAST]} {
    puts "WARNING: cannot find $LIB_DIR/$LIB_FAST, using $LIB_SLOW for the hold corner"
    puts "         Hold results are then meaningless and must not go into a report"
    set LIB_FAST $LIB_SLOW
}
if {$GDS_MAP ne "" && ![file exists $GDS_MAP]} { set GDS_MAP {} }
foreach f [list $LIB_DIR/$LIB_SLOW $TECH_LEF $CELL_LEF $SRAM_LEF $SRAM_LIB_SLOW] {
    if {![file exists $f]} { puts "WARNING: cannot find $f, set PDK_DIR or edit asic/pnr/config.tcl" }
}
