# Starting SDC for the ASIC flow (Genus, Innovus) on SoC_Top. This is a skeleton, the target clock
# period and the I/O delays depend on the PDK and are decided by P-20 and P-21 (Phat).
# Set these two variables before sourcing the file, for example in the tool script:
#   set CLK_PERIOD_NS <target period in ns>
#   set IO_DELAY_NS   <input and output delay in ns>
foreach v {CLK_PERIOD_NS IO_DELAY_NS} {
    if {![info exists $v]} { error "Set $v before sourcing asic/SoC_Top.sdc" }
}

# Single clock domain, ports from rtl/top/SoC_Top.v
create_clock -name clk -period $CLK_PERIOD_NS [get_ports clk]

# The FPGA constraints treat these inputs as asynchronous and synchronized in RTL
# (fpga/intel/de2/constraints.sdc, fpga/xilinx/artix7/constraints.xdc). Check that this still
# holds for the ASIC pad ring, reset_system included (the FPGA tops synchronize it before SoC_Top)
set async_in [get_ports {reset_system uart0_rx uart1_rx gpio0_i[*] gpio1_i[*] boot_strap[*]}]
set_false_path -from $async_in

# Outputs go to LEDs and UART lines with no board-level timing requirement in the FPGA flow.
# Keep them constrained here until the pad timing is known
set sync_out [get_ports {app_running uart0_tx uart1_tx gpio0_o[*] gpio1_o[*]}]
set_output_delay $IO_DELAY_NS -clock clk $sync_out
