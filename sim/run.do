
if {[file exists work]} {vdel -all}
vlib work
vmap work work

vlog -sv -work work ../rtl/uncore/*.v
# Đợi code của Phát và file Top, bỏ comment các dòng dưới
# vlog -sv -work work ../rtl/core/*.v
# vlog -sv -work work ../rtl/top/*.v
# vlog -sv -work work tb_soc.sv

# Thoát script nếu có lỗi biên dịch (giúp dễ debug)
if {[eval {catch {vlog -sv -work work ../rtl/uncore/*.v}}]} {
    quit -sim
}