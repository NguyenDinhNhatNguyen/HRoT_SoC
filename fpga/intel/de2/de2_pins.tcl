# DE2 (EP2C35F672C6) pin assignments for DE2_Top's ports.
# Check against Terasic's DE2_pin_assignments.csv / DE2 User Manual before programming a board.
set_location_assignment PIN_N2  -to CLOCK_50
set_location_assignment PIN_G26 -to KEY[0]
set_location_assignment PIN_N23 -to KEY[1]
set_location_assignment PIN_P23 -to KEY[2]
set_location_assignment PIN_W26 -to KEY[3]

set sw_pins {N25 N26 P25 AE14 AF14 AD13 AC13 C13 B13 A13 N1 P1 P2 T7 U3 U4 V1 V2}
for {set i 0} {$i < 18} {incr i} { set_location_assignment PIN_[lindex $sw_pins $i] -to SW[$i] }

set ledr_pins {AE23 AF23 AB21 AC22 AD22 AD23 AD21 AC21 AA14 Y13 AA13 AC14 AD15 AE15 AF13 AE13 AE12 AD12}
for {set i 0} {$i < 18} {incr i} { set_location_assignment PIN_[lindex $ledr_pins $i] -to LEDR[$i] }

set ledg_pins {AE22 AF22 W19 V18 U18 U17 AA20 Y18 Y12}
for {set i 0} {$i < 9} {incr i} { set_location_assignment PIN_[lindex $ledg_pins $i] -to LEDG[$i] }

set_location_assignment PIN_C25 -to UART_RXD
set_location_assignment PIN_B25 -to UART_TXD
