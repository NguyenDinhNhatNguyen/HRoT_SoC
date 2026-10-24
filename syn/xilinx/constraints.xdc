# Timing cho kit Xilinx (Vivado). Clock board 50 MHz - doi chu ky neu kit dung clock khac.
create_clock -period 20.000 -name clk -waveform {0.000 10.000} [get_ports clk]

# Chan bat dong bo da duoc dong bo trong RTL
set_false_path -from [get_ports {btn_rst sw[*] sw_boot[*] uart_rx}]
set_false_path -to   [get_ports {led[*] led_app uart_tx}]

# Gan chan: dien khi chot kit, vi du
# set_property -dict {PACKAGE_PIN W5 IOSTANDARD LVCMOS33} [get_ports clk]
