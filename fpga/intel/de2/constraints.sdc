# DE2 (Cyclone II) timing constraints for Quartus TimeQuest
# 50 MHz on CLOCK_50
create_clock -name clk50 -period 20.000 [get_ports CLOCK_50]
derive_clock_uncertainty

# Asynchronous inputs (keys, switches, UART RX) are synchronized in RTL
set_false_path -from [get_ports {KEY[*] SW[*] UART_RXD}]
# LEDs and UART TX have no board-level timing requirement
set_false_path -to   [get_ports {LEDR[*] LEDG[*] UART_TXD}]
