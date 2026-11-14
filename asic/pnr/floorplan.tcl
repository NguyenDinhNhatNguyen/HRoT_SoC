# floorplan.tcl - floorplan, SRAM macro placement, pin plan and power plan of ASIC_Top (P-21).
# Called by run_all.tcl after init_design and globalNetConnect. Needs try_cmd (from run_all.tcl)
# and the variables of config.tcl.
# Adapted from RV32i-SoC pnr/scripts/soc_floorplan.tcl (Innovus 21.1, GPDK45, ran in Nov 2026).
# NOT RUN on HRoT_SoC yet: the SRAM wrappers do not exist, so the macro count and the core size
# are open. Macros are found by cell name, so the instance names of the wrappers do not matter.
#
# Layout: half of the macros in one row at the bottom edge, the rest at the top edge, logic in
# the middle band. Signal pins on the left (inputs) and right (outputs) edges.
#
# Environment:
#   CORE_W, CORE_H  fixed core size in um. Without them: floorPlan -r 1.0 UTIL (UTIL below)

set UTIL     0.60       ;# Used only without CORE_W and CORE_H. Macro area counts in it
set IO_GAP   15.0       ;# Core to die edge, room for the power ring
set MAC_W    80.0       ;# sram_2k_macro, 80 x 100 um (RV32i-SoC HT-01, docs/macro_notes.md)
set MAC_H    100.0
set HALO     5.0
set MAC_GAP  [expr {2 * $HALO}]
set BLK_RING_H Metal6   ;# Ring layers around each macro, from the macro VDD/VSS pin layers
set BLK_RING_V Metal5   ;# (RV32i-SoC run), the log line below prints the real ones

# Where the signal pins sit in the R0 view of the macro, from the average y of their shapes
proc macro_pin_side {cell_name} {
    set cell [dbGet -p head.libCells.name $cell_name]
    if {$cell eq "" || $cell eq "0x0"} { return unknown }
    set h [dbGet $cell.size_y]
    set ys {}
    foreach r [dbGet $cell.terms.pins.allShapes.shapes.rect] {
        lassign $r x0 y0 x1 y1
        lappend ys [expr {($y0 + $y1) / 2.0}]
    }
    if {[llength $ys] == 0} { return unknown }
    set avg [expr {[tcl::mathop::+ {*}$ys] / [llength $ys]}]
    if {$avg < $h / 3.0} { return bottom }
    if {$avg > 2.0 * $h / 3.0} { return top }
    return side
}
# Pins must face the logic band. Default for pins on the top edge: bottom row R0, top row MX
set BOT_ORIENT R0
set TOP_ORIENT MX
if {[catch {macro_pin_side $SRAM_CELL} pin_side]} { set pin_side unknown }
switch -- $pin_side {
    bottom { set BOT_ORIENT MX ; set TOP_ORIENT R0 }
    top    { set BOT_ORIENT R0 ; set TOP_ORIENT MX }
}
puts "PD-02: macro signal pins on the $pin_side edge, bottom row $BOT_ORIENT, top row $TOP_ORIENT"
set mac_cell [dbGet -p head.libCells.name $SRAM_CELL]
if {$mac_cell ne "" && $mac_cell ne "0x0" &&
    ![catch {dbGet $mac_cell.pgTerms.pins.allShapes.layer.name} pg]} {
    puts "PD-02: macro VDD/VSS pin layers [lsort -unique $pg], ring layers $BLK_RING_H/$BLK_RING_V"
}

# Floorplan
if {[info exists ::env(CORE_W)] && [info exists ::env(CORE_H)]} {
    floorPlan -site $CORE_SITE -s $::env(CORE_W) $::env(CORE_H) $IO_GAP $IO_GAP $IO_GAP $IO_GAP
} else {
    floorPlan -site $CORE_SITE -r 1.0 $UTIL $IO_GAP $IO_GAP $IO_GAP $IO_GAP
}

# Macro placement
set macros [lsort [dbGet [dbGet -p2 top.insts.cell.name $SRAM_CELL].name]]
set n_mac [llength $macros]
puts "PD-02: $n_mac macro of type $SRAM_CELL"
if {$n_mac == 0} {
    puts "WARNING: no $SRAM_CELL in the netlist, the memories are still black boxes or the wrappers are not in it"
} else {
    lassign [lindex [dbGet top.fPlan.coreBox] 0] cx0 cy0 cx1 cy1
    set n_bot [expr {($n_mac + 1) / 2}]
    set bot [lrange $macros 0 [expr {$n_bot - 1}]]
    set top [lrange $macros $n_bot end]
    set row_w [expr {$n_bot * $MAC_W + ($n_bot - 1) * $MAC_GAP + 2 * $HALO}]
    if {$row_w > ($cx1 - $cx0)} {
        puts "WARNING: a row of $n_bot macros is $row_w um wide, the core is [expr {$cx1 - $cx0}] um. Make the core bigger"
    }
    proc place_row {insts y orient} {
        upvar cx0 cx0 HALO HALO MAC_W MAC_W MAC_GAP MAC_GAP
        set x [expr {$cx0 + $HALO}]
        foreach m $insts {
            placeInstance $m $x $y $orient -fixed
            set x [expr {$x + $MAC_W + $MAC_GAP}]
        }
    }
    place_row $bot [expr {$cy0 + $HALO}]          $BOT_ORIENT
    place_row $top [expr {$cy1 - $HALO - $MAC_H}] $TOP_ORIENT
    foreach m $macros { try_cmd {addHaloToBlock $HALO $HALO $HALO $HALO $m} }
    try_cmd {cutRow}            ;# Remove standard cell rows under the macros and halos
}

# Pin plan, ports of asic/ASIC_Top.v. Left edge 0: inputs. Right edge 2: outputs
editPin -pin {clk rst_pad_n uart0_rx uart1_rx gpio0_i* gpio1_i* boot_strap*} \
        -edge 0 -spreadType CENTER -spacing 4 -layer 3
editPin -pin {app_running uart0_tx uart1_tx gpio0_o* gpio1_o*} \
        -edge 2 -spreadType CENTER -spacing 4 -layer 3

# Power plan
addRing -nets [list $PWR_NET $GND_NET] -type core_rings -follow core \
        -layer {top Metal8 bottom Metal8 left Metal7 right Metal7} \
        -width 2.0 -spacing 1.0 -offset 1.5
if {$n_mac > 0} {
    try_cmd {addRing -nets [list $PWR_NET $GND_NET] -type block_rings -around each_block \
             -layer [list top $BLK_RING_H bottom $BLK_RING_H left $BLK_RING_V right $BLK_RING_V] \
             -width 1.0 -spacing 0.5 -offset 1.0}
}
addStripe -nets [list $PWR_NET $GND_NET] -layer Metal8 -direction vertical \
          -width 1.5 -spacing 1.0 -set_to_set_distance 30.0 -start_offset 10.0
addStripe -nets [list $PWR_NET $GND_NET] -layer Metal7 -direction horizontal \
          -width 1.5 -spacing 1.0 -set_to_set_distance 30.0 -start_offset 10.0
if {$n_mac > 0} {
    try_cmd {sroute -connect {blockPin} -nets [list $PWR_NET $GND_NET] -blockPinTarget {nearestTarget}}
}
sroute -connect {corePin} -layerChangeRange {Metal1 Metal8} -nets [list $PWR_NET $GND_NET]
# run_all.tcl runs verifyGeometry right after this file
