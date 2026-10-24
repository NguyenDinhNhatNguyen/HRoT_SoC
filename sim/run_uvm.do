# sim/run_uvm.do  -- chạy từ thư mục sim/
#   vsim -c -do run_uvm.do
#   vsim -c -do "set TEST axi4_lite_full_test; set SEED 7; do run_uvm.do"
# Test có sẵn: base_test | axi4_lite_wstrb_test | axi4_lite_rand_test | axi4_lite_full_test
# DUT SHA-256 that (P-08): set DUT sha256; TEST = sha256_kat_test | sha256_ctl_test | sha256_rand_test
#   | sha256_full_test | sha256_alias_test   (vd: vsim -c -do "set DUT sha256; set TEST sha256_full_test; do run_uvm.do")
# Tùy chọn: TEST, SEED, VERB (UVM_LOW/MEDIUM/HIGH), PLUSARGS (vd "+NUM_TRANS=500 +SLAVE_MAX_DELAY=6")
# UVM: mặc định dùng bản UVM tích hợp sẵn của Questa.
#      Nếu vlog báo không tìm thấy uvm_pkg: set UVM_LIB <tên thư viện UVM của Questa> (xem `vmap -l`
#      hoặc modelsim.ini; thường là mtiUvm) rồi chạy lại. Không đoán tên khi chưa kiểm tra.
#      Nếu muốn dùng bản ngoài: đặt UVM_HOME (và UVM_DPI = đường dẫn uvm_dpi, không đuôi).
if {![info exists TEST]}     {set TEST base_test}
if {![info exists SEED]}     {set SEED 1}
if {![info exists VERB]}     {set VERB UVM_MEDIUM}
if {![info exists PLUSARGS]} {set PLUSARGS {}}
if {![info exists DUT]}      {set DUT slave_model}
set DV ../dv

if {[file exists work]} {vdel -all -lib work}
vlib work
vmap work work

set UVM_FLAGS {}
set DPI_FLAGS {}
set LIB_FLAGS {}
if {[info exists UVM_LIB]} {
  lappend UVM_FLAGS -L $UVM_LIB
  lappend LIB_FLAGS -L $UVM_LIB
}
if {[info exists env(UVM_HOME)]} {
  vlog -sv -work work +incdir+$env(UVM_HOME)/src $env(UVM_HOME)/src/uvm_pkg.sv
  lappend UVM_FLAGS +incdir+$env(UVM_HOME)/src
  if {[info exists env(UVM_DPI)]} {lappend DPI_FLAGS -sv_lib $env(UVM_DPI)}
}

# 1) Interface -> 2) Package UVM -> 3) Slave mô hình + top
vlog -sv -work work {*}$UVM_FLAGS $DV/agents/axi4_lite_if.sv
vlog -sv -work work {*}$UVM_FLAGS +incdir+$DV/agents +incdir+$DV/env +incdir+$DV/tests \
     $DV/hrot_dv_pkg.sv
if {$DUT eq "sha256"} {
  vlog -sv -work work ../rtl/bus/AXI4_Lite_Slave_Template.v ../rtl/crypto/SHA256_Core.v \
       ../rtl/crypto/SHA256_Wrapper.v
  vlog -sv -work work {*}$UVM_FLAGS $DV/tb/tb_sha256_top.sv
  set TOP tb_sha256_top
} else {
  vlog -sv -work work {*}$UVM_FLAGS $DV/tb/axi4_lite_slave_model.sv $DV/tb/tb_top.sv
  set TOP tb_top
}

# 4) Chạy
vsim -voptargs=+acc -t 1ps -sv_seed $SEED {*}$LIB_FLAGS {*}$DPI_FLAGS work.$TOP \
     +UVM_TESTNAME=$TEST +UVM_VERBOSITY=$VERB {*}$PLUSARGS

if {[batch_mode]} {log -r /*} else {add wave -r /*}
run -all
if {[batch_mode]} {quit -f}
