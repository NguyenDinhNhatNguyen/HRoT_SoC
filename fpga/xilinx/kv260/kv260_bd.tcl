# Block design with only the Zynq UltraScale+ PS of the K26 SOM. The K26 PL has no clock of its own,
# so the SoC runs on pl_clk0 (50 MHz) and pl_resetn0 from the PS. Sourced by build_kv260.tcl inside
# an in-memory project, after create_project. Creates kv260_ps and its wrapper kv260_ps_wrapper.
set bd_dir [lindex $argv 4]
create_bd_design -dir $bd_dir kv260_ps
set ipdef [lindex [lsort [get_ipdefs -all xilinx.com:ip:zynq_ultra_ps_e:*]] end]
create_bd_cell -type ip -vlnv $ipdef ps
# PL0 from the IOPLL gives 49.9995 MHz, the RPLL default only 48.484 MHz, which would put the UART baud 3% off.
# M_AXI_GP2 off because nothing in the PL talks to the PS
set_property -dict [list CONFIG.PSU__CRL_APB__PL0_REF_CTRL__SRCSEL {IOPLL} CONFIG.PSU__CRL_APB__PL0_REF_CTRL__FREQMHZ {50} CONFIG.PSU__USE__M_AXI_GP2 {0}] [get_bd_cells ps]
make_bd_pins_external [get_bd_pins ps/pl_clk0] [get_bd_pins ps/pl_resetn0]
set_property name pl_clk0 [get_bd_ports pl_clk0_0]
set_property name pl_resetn0 [get_bd_ports pl_resetn0_0]
validate_bd_design
save_bd_design
generate_target all [get_files kv260_ps.bd]
set wrapper [make_wrapper -files [get_files kv260_ps.bd] -top]
add_files -norecurse $wrapper
