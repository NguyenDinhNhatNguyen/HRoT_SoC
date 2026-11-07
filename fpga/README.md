# fpga/

Cùng một RTL trong `rtl/`, mỗi hãng chỉ khác top bọc chân và constraints. Hai công cụ dùng thư mục `build/` riêng nên chạy song song không đụng nhau.

| Thư mục | Nội dung | Lệnh |
| --- | --- | --- |
| `intel/de2/` | `DE2_Top.v`, `constraints.sdc`, `de2_pins.tcl`, `build.tcl` — Terasic DE2 (Cyclone II EP2C35F672C6), Quartus II 13.0sp1 | `make de2` |
| `xilinx/artix7/` | `Xilinx_Top.v`, `constraints.xdc`, `build.tcl` — Artix-7 xc7a35t chạy thử luồng Vivado (không có board), Vivado 2025.2 | `make xilinx PART=<part>` |
| `xilinx/kv260/` | `KV260_Top.v`, `kv260_bd.tcl`, `kv260.xdc`, `build_kv260.tcl`, `firmware/` — Kria KV260 (xck26-sfvc784-2LV-c), clock từ PS, chân PMOD theo XDC của AMD, ra `kv260.bit`. Xem `xilinx/kv260/README.md` | `make kv260` |
| `reports/` | Báo cáo đã lưu: `de2_fit_summary.txt`, `de2_fmax.txt`, `de2_power_summary.txt`, `artix7_*.rpt` (kèm `artix7_power.rpt`), `kv260_*.rpt` (kèm `kv260_power.rpt`) | chép tay từ `<hãng>/<kit>/build/` |

Mặc định cả hai bản nạp firmware thử từ `dv/sw/mkhex.py` (UART 115200 baud @ 50 MHz). Muốn nạp firmware thật:
`make de2 BOOT_HEX=fw/build/firmware_imem.hex RAM_HEX=fw/build/firmware_dmem.hex APP_HEX=...`.

Trên DE2, GPIO0 là `LEDR[7:0]` và `SW[7:0]`, GPIO1 của thế giới App là `LEDG[8:1]` và `SW[13:8]`, `LEDG0` sáng khi App được nhả. UART1 chưa có chân (DE2 chỉ có một cổng RS-232). Trên Artix-7 (không có board), UART1 và GPIO1 không nối chân. Trên KV260 chỉ có 8 chân Pmod, nên UART0 và 5 LED dùng chân đó, GPIO1 và UART1 không nối.

Số đo mới nhất (07/11/2026): DE2 10.982 LE, 54,07 MHz. Artix-7 WNS +3,228 ns. KV260 WNS +5,517 ns ở 50,000 MHz. Bảng đầy đủ, kèm công suất ước tính, ở `docs/project/PPA_FPGA.md`, lịch sử các lần đo ở `docs/project/FPGA_Results.md`. Sơ đồ testbed: `docs/diagrams/png/21_fpga_testbed.png`.

`de2_pins.tcl` đã được đối chiếu ngày 25/10/2026 (N-18): 52/52 chân khớp bảng chân trong DE2 User Manual v1.3. Terasic đã có bản manual 1.6, nên xem lại bảng chân trong bản đó trước khi nạp board.

Mỗi hãng một thư mục, bên trong mỗi kit một thư mục con. Thêm kit mới: tạo `<hãng>/<kit>/` với top bọc chân, file ràng buộc và `build.tcl` (lấy `$root` là `../../..`), rồi thêm một target vào `Makefile`.
