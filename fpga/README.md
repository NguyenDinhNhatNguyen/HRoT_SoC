# fpga/

Cùng một RTL trong `rtl/`, mỗi hãng chỉ khác top bọc chân và constraints. Hai công cụ dùng thư mục `build/` riêng nên chạy song song không đụng nhau.

| Thư mục | Nội dung | Lệnh |
| --- | --- | --- |
| `intel_de2/` | `DE2_Top.v`, `constraints.sdc`, `de2_pins.tcl`, `build.tcl` — Terasic DE2 (Cyclone II EP2C35F672C6), Quartus II 13.0sp1 | `make de2` |
| `xilinx/` | `Xilinx_Top.v`, `constraints.xdc`, `build.tcl` — kit chưa chốt (đang thử Artix-7 xc7a35t), Vivado 2025.2 | `make xilinx PART=<part>` |
| `reports/` | Báo cáo đã lưu: `de2_fit_summary.txt`, `de2_fmax.txt`, `artix7_utilization.rpt`, `artix7_timing_summary.rpt` | chép tay từ `*/build/` |

Mặc định cả hai bản nạp firmware thử từ `dv/sw/mkhex.py` (UART 115200 baud @ 50 MHz). Muốn nạp firmware thật:
`make de2 BOOT_HEX=fw/build/firmware_imem.hex RAM_HEX=fw/build/firmware_dmem.hex APP_HEX=...`.

`de2_pins.tcl` đã được đối chiếu ngày 25/10/2026 (N-18): 52/52 chân khớp bảng chân trong DE2 User Manual v1.3. Terasic đã có bản manual 1.6, nên xem lại bảng chân trong bản đó trước khi nạp board.
