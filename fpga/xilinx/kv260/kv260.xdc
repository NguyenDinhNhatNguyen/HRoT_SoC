# Kria KV260 (K26 SOM + KV260 carrier card).
# The 50 MHz clock comes from the PS (pl_clk0, kv260_bd.tcl), its constraint comes with the PS IP.
# Asynchronous input is synchronized in RTL, outputs go to LEDs and a UART
set_false_path -from [get_ports uart_rx]
set_false_path -to   [get_ports {led[*] led_app uart_tx}]

# Pins: the 8 PMOD pins HDA11 to HDA18 (3.3 V bank), taken from AMD's own constraints for the KV260
# https://github.com/Xilinx/kria-vitis-platforms  kv260/platforms/kv260_bist/xdc/pin.xdc
# The HDA names are the carrier card nets. Pmod pin numbers (cross-checked from AMD's Kria-PYNQ base.xdc
# and the third-party ikwzm/Kv260-Pmod-gpio-emio XDC, not the schematic): pin1..4 = HDA11..HDA14,
# pin7..10 = HDA15..HDA18, see README.md for the table
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
