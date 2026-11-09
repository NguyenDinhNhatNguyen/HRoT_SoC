# SDC for ASIC_Top (asic/ASIC_Top.v), the chip-level wrapper with the reset synchronizer.
# Same variables as asic/SoC_Top.sdc, set them before sourcing this file:
#   set CLK_PERIOD_NS <target period in ns>    (proposed start: 20, the 50 MHz of the FPGA builds)
#   set IO_DELAY_NS   <input and output delay> (proposed start: 4, about 20 % of the period)
# Final values come from the PD flow on the school server (P-20, P-21), see asic/README.md.
foreach v {CLK_PERIOD_NS IO_DELAY_NS} {
    if {![info exists $v]} { error "Set $v before sourcing asic/ASIC_Top.sdc" }
}

create_clock -name clk -period $CLK_PERIOD_NS [get_ports clk]

# rst_pad_n only drives the asynchronous set of the two synchronizer flops. Its release reaches the
# design through those flops, so the internal reset_system is a normal synchronous path that STA
# times (unlike the false path on reset_system in asic/SoC_Top.sdc, where no synchronizer exists)
set_false_path -from [get_ports rst_pad_n]

# UART RX and GPIO in pass through two-flop synchronizers inside SoC_Top. boot_strap is only latched
# while in reset and must be stable before the release
set async_in [get_ports {uart0_rx uart1_rx gpio0_i[*] gpio1_i[*] boot_strap[*]}]
set_false_path -from $async_in

set sync_out [get_ports {app_running uart0_tx uart1_tx gpio0_o[*] gpio1_o[*]}]
set_output_delay $IO_DELAY_NS -clock clk $sync_out
