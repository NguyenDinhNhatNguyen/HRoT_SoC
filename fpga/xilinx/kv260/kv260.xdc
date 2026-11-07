# Kria KV260 (K26 SOM + KV260 carrier card).
# The 50 MHz clock comes from the PS (pl_clk0, kv260_bd.tcl), its constraint comes with the PS IP.
# Asynchronous input is synchronized in RTL, outputs go to LEDs and a UART
set_false_path -from [get_ports uart_rx]
set_false_path -to   [get_ports {led[*] led_app uart_tx}]

# Pins: the 8 PMOD pins HDA11 to HDA18 (3.3 V bank), taken from AMD's own constraints for the KV260
# https://github.com/Xilinx/kria-vitis-platforms  kv260/platforms/kv260_bist/xdc/pin.xdc
# The HDA names are the carrier card nets. J2 pin numbers are from AMD's carrier card schematic XTP682
# (rev 1.0 and rev 2.0, sheet 17): J2.1 HDA11, J2.2 HDA15, J2.3 HDA12, J2.4 HDA16, J2.5 HDA13, J2.6 HDA17,
# J2.7 HDA14, J2.8 HDA18, J2.9 and J2.10 GND, J2.11 and J2.12 3.3 V. See README.md for the table
set_property PACKAGE_PIN H12 [get_ports uart_tx]
set_property PACKAGE_PIN E10 [get_ports uart_rx]
set_property PACKAGE_PIN D10 [get_ports led_app]
set_property PACKAGE_PIN C11 [get_ports {led[0]}]
set_property PACKAGE_PIN B10 [get_ports {led[1]}]
set_property PACKAGE_PIN E12 [get_ports {led[2]}]
set_property PACKAGE_PIN D11 [get_ports {led[3]}]
set_property PACKAGE_PIN B11 [get_ports {led[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {uart_tx uart_rx led_app led[*]}]
set_property SLEW SLOW [get_ports {uart_tx led_app led[*]}]
set_property DRIVE 4 [get_ports {uart_tx led_app led[*]}]
