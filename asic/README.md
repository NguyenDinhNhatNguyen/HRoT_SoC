# asic/

Điểm xuất phát cho luồng ASIC (Genus, Innovus) của Phát (P-20, P-21).

| File | Nội dung |
| --- | --- |
| `SoC_Top.sdc` | Khung SDC cho `SoC_Top`: một clock `clk`, false path cho các đầu vào bất đồng bộ, `set_output_delay` cho đầu ra |

File này chưa có chu kỳ clock và độ trễ I/O, vì chúng phụ thuộc PDK mà Phát chọn. Đặt hai biến `CLK_PERIOD_NS` và `IO_DELAY_NS` trước khi `source`, nếu thiếu thì SDC báo lỗi. Cổng lấy từ `rtl/top/SoC_Top.v`. Các đầu vào được coi là bất đồng bộ theo ràng buộc FPGA (`fpga/intel/de2/constraints.sdc`), cần kiểm lại khi có vòng pad của ASIC, nhất là `reset_system` (top FPGA đồng bộ nó trước khi vào `SoC_Top`).

Số đo FPGA để so sánh nằm ở `docs/project/PPA_FPGA.md`.
