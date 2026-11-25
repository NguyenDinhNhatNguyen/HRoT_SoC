# DE10 (Cyclone V) timing constraints for Quartus TimeQuest, ports of Xilinx_Top
# 50 MHz on clk
create_clock -name clk50 -period 20.000 [get_ports clk]
derive_clock_uncertainty

# Asynchronous inputs are synchronized in RTL
set_false_path -from [get_ports {btn_rst sw[*] sw_boot[*] uart_rx}]
# LEDs and UART TX have no board-level timing requirement
set_false_path -to   [get_ports {led[*] led_app uart_tx}]
