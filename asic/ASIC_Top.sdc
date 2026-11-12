# SDC for ASIC_Top (asic/ASIC_Top.v), the chip-level wrapper with the reset synchronizer.
# Ratios and values follow Lab 01 of the school Genus flow (GPDK45).
# Shared by Genus, Innovus and Tempus, so it only uses commands all three accept.
# Set the clock period before sourcing this file:
#   set CLK_PERIOD_NS <target period in ns>    (proposed start: 20, the 50 MHz of the FPGA builds)
# asic/genus/synth.tcl sets it from PERIOD. The I/O delays follow the period (24 % in, 20 % out).
# Final period comes from the PD flow on the school server (P-20, P-21), see asic/README.md.
if {![info exists CLK_PERIOD_NS]} {
    error "Set CLK_PERIOD_NS before sourcing asic/ASIC_Top.sdc"
}

# 1. Clock: one clock domain, 50 % duty cycle
create_clock -name clk -period $CLK_PERIOD_NS -waveform [list 0 [expr {$CLK_PERIOD_NS / 2.0}]] \
    [get_ports clk]

# 2. Clock uncertainty and transition before CTS (Lab 01 values).
# Setup 0.15 ns covers jitter and part of the skew, hold 0.08 ns covers skew
set_clock_uncertainty -setup 0.15 [get_clocks clk]
set_clock_uncertainty -hold  0.08 [get_clocks clk]
set_clock_transition 0.08 [get_clocks clk]

# 3. Input delays, 24 % of the period for max and 0.3 ns for min (Lab 01 ratio).
# UART RX and GPIO in are asynchronous to clk and go into two-flop synchronizers inside SoC_Top.
# They still get an input delay so the path to the first synchronizer flop is constrained and no
# endpoint is left unconstrained
set in_ports [get_ports {uart0_rx uart1_rx gpio0_i[*] gpio1_i[*]}]
set_input_delay -clock clk -max [expr {0.24 * $CLK_PERIOD_NS}] $in_ports
set_input_delay -clock clk -min 0.3 $in_ports

# 4. Output delays, 20 % of the period for max and 0.2 ns for min (Lab 01 ratio)
set out_ports [get_ports {app_running uart0_tx uart1_tx gpio0_o[*] gpio1_o[*]}]
set_output_delay -clock clk -max [expr {0.20 * $CLK_PERIOD_NS}] $out_ports
set_output_delay -clock clk -min 0.2 $out_ports

# 5. Input slew and output load. No library cell is named, so the file works with any library
set_input_transition 0.1 [get_ports {rst_pad_n uart0_rx uart1_rx gpio0_i[*] gpio1_i[*] boot_strap[*]}]
set_load -pin_load 0.05 $out_ports

# 6. Asynchronous reset. rst_pad_n only drives the asynchronous set of the two synchronizer flops,
# so this false path covers exactly the pin to the synchronizer. The release from the synchronizer
# (reset_system of SoC_Top) to the reset pin of every other flop is NOT a false path: STA checks
# recovery and removal on it.
# boot_strap is only latched while in reset (SYSCSR) and must be stable before the release, so it
# is a false path too. Both get an input delay so the timing check reports no input without one
set_false_path -from [get_ports {rst_pad_n boot_strap[*]}]
set_input_delay -clock clk 0.0 [get_ports {rst_pad_n boot_strap[*]}]

# 7. Design rules. Without them Genus leaves a high fanout net on one small flop: the Yosys run
# showed an internal reset flop with fanout 893 and a 1.43 ns slew. With a limit Genus buffers every
# high fanout net (synth.tcl also sets ideal_seq_async_pins false for the reset pins)
set_max_transition 0.5 [current_design]
set_max_fanout     32  [current_design]
