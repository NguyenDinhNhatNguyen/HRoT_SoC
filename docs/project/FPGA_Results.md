# Kết quả tổng hợp FPGA qua các phiên bản

> Lập 26/10/2026 (Phát), đủ số đo tới 27/10 (`9f9e66a` + P-13, P-14). Thư mục `fpga/reports/` chỉ giữ báo cáo của lần đo cuối mà Nguyên commit, mỗi lần đo lại sẽ ghi đè. File này giữ lại số của mọi lần đo để so sánh. Các tài liệu khác (`Project_Plan.md`, `Project_Status.md`, sheet) chỉ ghi số mới nhất và trỏ về đây.

## Thiết bị, công cụ, ràng buộc

| | DE2 (Intel) | Artix-7 (Xilinx, kit thử) |
| --- | --- | --- |
| Thiết bị | Cyclone II `EP2C35F672C6` (33.216 LE, 483.840 bit M4K, 475 chân) | `xc7a35tcpg236-1` (20.800 LUT, 41.600 FF, 50 tile BRAM) |
| Công cụ | Quartus II 64-bit 13.0.1 Build 232 SP1 Web Edition | Vivado 2025.2 (win64) Build 6299465 |
| Clock | `clk50`, 50 MHz (chu kỳ 20 ns) | `clk`, 50 MHz (chu kỳ 20 ns) |
| Lệnh | `make de2` | `make xilinx PART=xc7a35tcpg236-1` |
| Top | `fpga/intel_de2/DE2_Top.v` | `fpga/xilinx/Xilinx_Top.v` |

## DE2 (Cyclone II)

| Ngày | Commit | Thay đổi so với lần trước | LE | Thanh ghi | Bộ nhớ (bit) | Chân | Fmax | Setup slack | Người đo |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 24/10 | `ad42ec7` | Bộ nhớ đồng bộ cạnh xuống (M4K), luồng FPGA DE2 | 7.453 (22%) | 3.487 | 135.168 (28%) | 52 | 54,9 MHz | +1,79 ns | Nguyên |
| 25/10 | `0be826d` | Thêm TIMER0, WDT | 7.885 (24%) | 3.694 | 135.168 (28%) | 52 | 55,17 MHz | +1,875 ns | Nguyên |
| 25/10 | `d2315b2` | Thêm `SYSCSR.BUS_ERR`, `BUS_ERR_ADDR` (N-36) | 8.011 | — | — | — | 54,69 MHz | +1,71 ns | Nguyên |
| 26/10 | `d912cdc` + bản thử P-23 | Thêm PLIC-lite, Mailbox, Boot Guard, cổng dữ liệu Boot ROM, Secure DMA + tường lửa, bus APB thế giới App. Lõi đổi reset đồng bộ ở `IF_ID_Reg`, `ID_EX_Reg` (chưa commit lúc đo) | 9.358 (28%) | 4.390 | 135.168 (28%) | 52 | 53,02 MHz | +1,14 ns | Nguyên |
| 26/10 | `9f9e66a` | Lõi thêm Zicsr và trap máy, cổng `irq_timer`/`irq_ext` (P-09, chưa nối trong `SoC_Top`), P-23 đã commit | 10.270 (31%) | 4.840 | 135.168 (28%) | 52 | 53,73 MHz | +1,389 ns (hold +0,391 ns) | Phát |
| 27/10 | `9f9e66a` + P-13, P-14 (chưa commit) | Nối 4 dây ngắt vào hai lõi trong `SoC_Top` (P-14). Boot ROM vẫn là firmware thử của `mkhex.py` (target `make hex`) | 10.509 (32%) | 4.842 | 135.168 (28%) | 52 | 54,21 MHz | +1,554 ns (hold +0,391 ns) | Phát |

Ô "—" là số chưa có trong báo cáo đã lưu. Setup slack của các dòng Nguyên đo tính từ Fmax (slack = 20 ns − 1000/Fmax), riêng dòng 25/10 lấy từ ghi chú review.

Thay đổi qua từng bước:

| Bước | LE | Thanh ghi | Fmax |
| --- | --- | --- | --- |
| 24/10 → 25/10 (TIMER0, WDT) | +432 | +207 | +0,27 MHz |
| 25/10 → 25/10 (N-36) | +126 | — | −0,48 MHz |
| 25/10 → 26/10 (khối Tuần 8–10 của Nguyên) | +1.347 | — | −1,67 MHz |
| 26/10 → `9f9e66a` (P-09 trên cả hai lõi) | +912 | +450 | +0,71 MHz |
| `9f9e66a` → 27/10 (nối dây ngắt) | +239 | +2 | +0,48 MHz |

## Artix-7 (xc7a35t)

| Ngày | Commit | Thay đổi so với lần trước | LUT | FF | BRAM tile | IOB | WNS | WHS | Fmax ước tính | Người đo |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 24/10 | `ad42ec7` | Luồng Vivado đầu tiên | 3.125 (15,02%) | 2.665 (6,41%) | 1 (2%) | 25 | +3,174 ns | +0,022 ns | 59,4 MHz | Nguyên |
| 25/10 | `0be826d` | Thêm TIMER0, WDT | 3.360 (16,15%) | 2.872 (6,90%) | 1 (2%) | 25 | +2,891 ns | +0,076 ns | 58,4 MHz | Nguyên |
| 26/10 | `d912cdc` + bản thử P-23 | Khối Tuần 8–10 của Nguyên, lõi reset đồng bộ ở `IF_ID_Reg`, `ID_EX_Reg` | 5.530 (26,59%) | 4.092 (9,84%) | 2,5 (5%) | 25 | +3,519 ns | +0,034 ns | 60,7 MHz | Nguyên |
| 26/10 | `9f9e66a` | P-09 | chưa đo | | | | | | | |

Fmax ước tính = 1000 / (20 − WNS) MHz. Vivado không in Fmax trực tiếp. DSP dùng 0 ở mọi lần đo.

Bản `9f9e66a` chưa đo trên Artix-7 vì máy Phát chưa cài Vivado (`D:\AMDDesignTools` chỉ có thư mục `xic`). Nguyên đo khi chạy `make xilinx` lần tới thì thêm dòng vào bảng.

## Đường găng (DE2)

| Lần đo | Đường găng | Slack |
| --- | --- | --- |
| 25/10 (`0be826d`) | Trong lõi App: `ID_EX.Rs1_EX` → forwarding → so sánh nhánh → PC | +1,875 ns |
| 26/10 (`d912cdc` + P-23) | Trong lõi: `Rd_WB` → forwarding ở ID → `RD2_EX`. Không có đường nào của uncore trong top | +1,14 ns |
| 26/10 (`9f9e66a`) | Trong lõi Master: `MEM_WB_Reg.Rd_WB` → forwarding ở ID → `ID_EX_Reg.RD1_EX` (cùng loại đường với lần trước). P-09 không làm đường găng dài thêm | +1,389 ns |
| 27/10 (`9f9e66a` + P-13, P-14) | Trong lõi Master: `EX_MEM_Reg.Rd_MEM` → forwarding ở ID → `ID_EX_Reg.RD1_EX` (cùng loại đường). Nối dây ngắt không tạo đường găng mới | +1,554 ns |

Ngưỡng theo dõi (R2 trong `Project_Plan.md`): DE2 còn dư khoảng 7% so với 50 MHz. Nếu Fmax xuống dưới 52 MHz thì tách đường forwarding / quyết định nhánh trong lõi. Mỗi khối uncore mới nên giữ slack từ 2 ns trở lên.

## Ghi chú về các lần đo

- Bộ nhớ DE2 (135.168 bit M4K) không đổi qua các lần đo từ 24/10.
- Ở lần `9f9e66a`, Quartus báo `irq_timer`/`irq_ext` của hai lõi chưa nối nên tự nối GND. Từ lần 27/10 dây ngắt đã nối (P-14), logic ngắt trong `CSR_Unit` không còn bị rút gọn nên LE tăng 239, Quartus không còn cảnh báo cổng hở.
- Báo cáo gốc của lần `9f9e66a` nằm ở `fpga/intel_de2/build/output_files/` trên máy Phát (thư mục build, không commit). Báo cáo trong `fpga/reports/` vẫn là của lần đo 26/10 của Nguyên.

## Cách thêm một lần đo

1. Chạy `make de2` (máy Phát: `make de2 QUARTUS=/mnt/d/altera/13.0sp1/quartus/bin64/quartus_sh.exe`) hoặc `make xilinx`.
2. Lấy số từ `fpga/intel_de2/build/output_files/hrot_de2.fit.summary` (LE, thanh ghi, bộ nhớ, chân) và `hrot_de2.sta.rpt` (mục "Slow Model Fmax Summary", "Slow Model Setup: 'clk50'"), hoặc từ `artix7_utilization.rpt`, `artix7_timing_summary.rpt` của Vivado.
3. Thêm một dòng vào bảng, ghi commit đã đo (nếu đo trên thay đổi chưa commit thì ghi rõ), người đo, và đường găng nếu đổi.
