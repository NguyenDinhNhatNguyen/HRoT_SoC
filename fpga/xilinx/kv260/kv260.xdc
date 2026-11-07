# Kria KV260 (K26 SOM + KV260 carrier card).
# The 50 MHz clock comes from the PS (pl_clk0, kv260_bd.tcl), its constraint comes with the PS IP.
# Asynchronous input is synchronized in RTL, outputs go to LEDs and a UART
set_false_path -from [get_ports uart_rx]
set_false_path -to   [get_ports {led[*] led_app uart_tx}]

# Pin assignments: not set yet. AMD publishes no carrier card XDC. UG1089 points to the carrier card
# schematic, so take PACKAGE_PIN and IOSTANDARD from there (PMOD CC J2 or another header) and
# check the IO voltage of the bank before connecting any external module. Example of the form:
# set_property -dict {PACKAGE_PIN <pin> IOSTANDARD LVCMOS33} [get_ports uart_tx]
