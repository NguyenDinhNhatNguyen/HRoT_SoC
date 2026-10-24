# Timing cho DE2 (Cyclone II) - Quartus TimeQuest
# Clock 50 MHz tren chan CLOCK_50
create_clock -name clk50 -period 20.000 [get_ports CLOCK_50]
derive_clock_uncertainty

# Chan bat dong bo (nut, switch, UART RX) da duoc dong bo trong RTL
set_false_path -from [get_ports {KEY[*] SW[*] UART_RXD}]
# LED va UART TX khong co yeu cau timing voi board
set_false_path -to   [get_ports {LEDR[*] LEDG[*] UART_TXD}]
