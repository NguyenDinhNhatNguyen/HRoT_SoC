# Báo cáo PPA FPGA (N-30)

> Đo ngày 07/11/2026 (Nguyên) trên cùng một RTL, `VERIFY_GATE = 1`, firmware thử của `dv/sw/mkhex.py`, clock 50 MHz. Lịch sử các lần đo và đường găng ở `FPGA_Results.md`. Báo cáo gốc ở `fpga/reports/`.

## Tóm tắt

| | DE2 (Cyclone II) | Artix-7 (kit thử) | Kria KV260 | DE10-Standard (Cyclone V) | DE10-Nano (Cyclone V) |
| --- | --- | --- | --- | --- | --- |
| Thiết bị | `EP2C35F672C6` | `xc7a35tcpg236-1` | `xck26-sfvc784-2LV-c` | `5CSXFC6D6F31C6` | `5CSEBA6U23I7` |
| Công cụ | Quartus II 13.0sp1 | Vivado 2025.2 | Vivado 2025.2 | Quartus II 13.0sp1 | Quartus II 13.0sp1 |
| Clock | 50 MHz | 50 MHz | 50,000 MHz (PL0 từ IOPLL của PS) | 50 MHz | 50 MHz |
| Tốc độ | Fmax 54,07 MHz, slack setup +1,505 ns (tính từ Fmax) | WNS +3,228 ns, Fmax ước tính 59,6 MHz | WNS +5,517 ns, Fmax ước tính 69,0 MHz | Fmax 62,74 MHz, slack setup +2,531 ns | Fmax 58,76 MHz, slack setup +1,838 ns |
| Hold | +0,391 ns (đo 27/10) | WHS +0,018 ns | WHS +0,011 ns | +0,216 ns | +0,265 ns |
| Logic | 10.982 LE (33%) | 6.137 LUT (29,50%) | 6.045 LUT (5,16%) | 4.643 ALM (11%) | 4.674 ALM (11%) |
| Thanh ghi | 4.925 (15%) | 4.401 FF (10,58%) | 4.365 FF (1,86%) | 5.148 | 5.190 |
| Bộ nhớ | 135.168 bit M4K (28%) | 2,5 tile BRAM (5%) | 2,5 tile BRAM (1,74%) | 135.360 bit block RAM (2%) | 135.360 bit block RAM (2%) |
| DSP hoặc nhân nhúng | 0 / 70 nhân 9 bit | 0 | 0 | 0 / 112 DSP | 0 / 112 DSP |
| Chân dùng | 52 | 25 | 8 (Pmod) | 25, chưa gán | 25, chưa gán |
| Công suất tổng (ước tính) | 271,18 mW | 0,118 W | 2,542 W (có PS) | 473,40 mW | 474,09 mW |

Fmax ước tính của Vivado = 1000 / (20 − WNS) MHz, Vivado không in Fmax trực tiếp. Slack DE2 = 20 ns − 1000 / Fmax.

DE10 đo ngày 25/11/2026. Hai bản dùng `fpga/intel/de10/Data_Memory.v` thay cho `rtl/mem/Data_Memory.v`, vì Quartus 13.0sp1 dựng bản chung bằng flip-flop trên Cyclone V nên thiết kế không vừa chip. Bản thay đã so với bản gốc ở mức khối (10.180 lần đọc, 0 sai khác), chưa mô phỏng cả SoC. Timing model của chip là Preliminary, chân chưa gán, mã chip chưa đối chiếu với board. Fmax và slack lấy ở model Slow chậm nhất (Standard 85 °C, Nano 100 °C). Logic đếm bằng ALM nên không so trực tiếp với LE của DE2.

## Công suất ước tính

Đây là ước tính với toggle rate mặc định, không phải số đo, độ tin cậy do chính công cụ báo là thấp. Chỉ dùng để so sánh các thiết kế với nhau, không dùng làm công suất thực của chip.

| Kit | Động | Tĩnh | Khác | Ghi chú |
| --- | --- | --- | --- | --- |
| DE2 | 146,53 mW | 80,46 mW | I/O 44,19 mW | PowerPlay, vectorless, toggle mặc định 12,5%. Nhiệt độ môi trường 25 °C, nhiệt độ mối nối tính ra 26,6 °C. Độ tin cậy "Low" |
| Artix-7 | 0,047 W | 0,070 W | | Vivado `report_power`. Toàn bộ phần động nằm trong `soc`. Độ tin cậy "Low" (I/O thiếu thông tin hoạt động, nút nội bộ "Medium") |
| KV260 | 2,220 W | 0,322 W | | PS8 chiếm 2,208 W. Phần PL của `soc` chỉ 0,011 W (lõi Master 0,003 W, SHA-256 0,003 W, lõi App 0,001 W). Độ tin cậy "Low" |
| DE10-Standard | 52,06 mW | 410,07 mW | I/O 11,28 mW | PowerPlay, toggle mặc định. Timing và power model Preliminary, Quartus báo chưa tính công suất HPS. Độ tin cậy "Low" |
| DE10-Nano | 52,04 mW | 410,80 mW | I/O 11,25 mW | Như DE10-Standard |

Tổng công suất của KV260 do bộ xử lý PS (Zynq UltraScale+) quyết định và không phụ thuộc vào SoC của đồ án. Khi so với ASIC chỉ nên lấy phần `soc` (0,011 W trên KV260, 0,047 W động trên Artix-7). Hai con số này cách nhau vì hai họ FPGA khác nhau về điện áp, công nghệ và cách công cụ ước tính, không so trực tiếp với nhau được.

## Cách đo lại

| Bước | Lệnh | Lấy số ở đâu |
| --- | --- | --- |
| DE2 | `make de2` | `fpga/intel/de2/build/output_files/hrot_de2.fit.summary` (LE, thanh ghi, bộ nhớ, chân), `hrot_de2.sta.rpt` (Fmax), `hrot_de2.pow.rpt` (công suất) |
| Artix-7 | `make xilinx` | `fpga/xilinx/artix7/build/utilization.rpt`, `timing_summary.rpt`, `power.rpt` |
| KV260 | `make kv260` | `fpga/xilinx/kv260/build/utilization.rpt`, `timing_summary.rpt`, `power.rpt` |
| DE10 | trong `fpga/intel/de10`: `quartus_sh -t build.tcl <standard hoặc nano> <boot.hex> <zero.hex> <app.hex>` sau `make hex` | `fpga/intel/de10/build/<bản>/output_files/hrot_de10.fit.summary`, `hrot_de10.sta.rpt`, `hrot_de10.pow.summary` |

Kiểm nhanh sau mỗi lần đo DE2: bộ nhớ phải còn 135.168 bit và `RISCV_Core:master_core` phải có trong `hrot_de2.map.rpt`. Lần đo 07/11 đạt cả hai.

Virtex-7 chưa đo: máy hiện tại không có chip Virtex-7 trong Vivado. Khi có license, chạy `build.tcl` của Artix-7 với `-tclargs <mã chip>`.

Ảnh chụp giao diện của cả năm cấu hình ở `docs/diagrams/gui/`.

## SDC bàn giao ASIC

Khung SDC nằm ở `asic/SoC_Top.sdc`. Chu kỳ clock ASIC và độ trễ I/O do Phát (P-20, P-21) đặt theo PDK, file báo lỗi nếu chưa đặt hai biến `CLK_PERIOD_NS` và `IO_DELAY_NS`. Từ 09/11 có thêm top cấp chip `asic/ASIC_Top.v` (bộ đồng bộ reset) và `asic/ASIC_Top.sdc`. Từ 12/11 `ASIC_Top.sdc` chỉ cần `CLK_PERIOD_NS`, độ trễ vào ra lấy 24% và 20% chu kỳ. Số Genus đầu tiên (12/11, 20 tới 8 ns) ghi ở `asic/README.md`.

## Chưa làm được

- Công suất đo thật trên board chưa có. Cần kit và đồng hồ đo dòng, chưa thuộc phạm vi hiện tại.
- Số công suất của DE2 chưa so với bảng tính của Altera (EPE).
