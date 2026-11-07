# Timing for the Xilinx kit (Vivado). Assumes a 50 MHz board clock, change the period if the kit differs.
create_clock -period 20.000 -name clk -waveform {0.000 10.000} [get_ports clk]

# Asynchronous inputs are synchronized in RTL
set_false_path -from [get_ports {btn_rst sw[*] sw_boot[*] uart_rx}]
set_false_path -to   [get_ports {led[*] led_app uart_tx}]

# Pin assignments go here once the kit is chosen, for example
# set_property -dict {PACKAGE_PIN W5 IOSTANDARD LVCMOS33} [get_ports clk]
