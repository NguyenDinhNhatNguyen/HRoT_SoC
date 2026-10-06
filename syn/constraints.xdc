# Clock 50MHz (Chu kỳ 20ns, Duty Cycle 50%)
create_clock -period 20.000 -name clk -waveform {0.000 10.000} [get_ports clk]

# Bỏ qua kiểm tra critical path cho tín hiệu reset để Vivado tập trung tối ưu luồng dữ liệu
set_false_path -from [get_ports reset_system]