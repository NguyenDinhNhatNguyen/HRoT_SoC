# Plan Đồ án 2 — HRoT SoC

> Chuyển từ Google Doc "Plan Đồ án 2", tab "Kế hoạch chuẩn (hợp nhất)" và "Tổng quan Đồ án 2" (bản 24/10/2026), đã đối chiếu với repo (`main` `bb8288a`) và [Google Sheet tiến độ](https://docs.google.com/spreadsheets/d/13jJj9UP1Cxr8ZNFqzQnNTaiulD2_HaKOWAONfCnZnU4/edit). Hạn và trạng thái từng việc theo sheet; khi file này lệch sheet thì theo sheet. Các chỗ đã chỉnh so với Google Doc ghi ở mục 9.

## 1. Đề tài

- **Tên:** Thiết kế SoC đa lõi bất đối xứng (AMP) RISC-V tích hợp cách ly vật lý và khởi động bảo mật (Hardware Root of Trust & Secure Boot).
- **Thời gian:** 07/09/2026 – 27/12/2026 (16 tuần, mỗi tuần thứ Hai → Chủ nhật). **RTL FREEZE: 22/11/2026** (cuối Tuần 11, theo yêu cầu thầy hướng dẫn).
- **Mục tiêu chứng minh trên FPGA:** lõi ứng dụng chỉ được chạy khi firmware của nó được phần cứng xác thực bằng SHA-256, và lõi ứng dụng không thể chạm vào thế giới Secure.
- **Quy ước làm việc (I-07):** chỉ commit trên `main`, mọi lệnh chạy trong WSL tại thư mục gốc repo, mô phỏng bằng QuestaSim 10.2c, `make test` PASS trước khi push.

## 2. Kiến trúc đã chốt

- **Kiến trúc tham chiếu:** SoC RISC-V hai lõi kiểu công nghiệp — lõi boot/điều khiển (vai trò như Ibex) nắm quyền khởi động, lõi ứng dụng (vai trò như CVA6) bị giữ reset tới khi image được xác thực. Rút gọn cho đồ án và thêm cách ly vật lý.
- **Hai lõi RV32I 5 tầng tự viết:** Master (Secure) chạy từ Boot ROM 4 KB riêng + RAM 4 KB; App chạy từ ROM App (cổng A của Dual-Port ROM) + RAM riêng, bị giữ reset tới khi Master cho phép.
- **Cách ly vật lý:** mỗi thế giới có bus và bộ nhớ riêng; chỉ nối nhau qua cổng B chỉ đọc của ROM App (Master đọc để băm) và Mailbox (Tuần 10).
- **Bus Secure:** AXI4-Lite (RAM, SHA-256, ROM App cổng B, default slave DECERR) + cầu AXI→APB ra bus ngoại vi (SYSCSR, UART0, GPIO0, TIMER0, WDT, PLIC-lite, Mailbox).
- **Bảo mật phần cứng:** SHA-256 tăng tốc (66 chu kỳ/block); Boot Guard + Zeroization (băm sai → khóa App tới khi bật lại nguồn, xóa RAM App); Secure DMA nạp ROM App vào SHA; tường lửa AXI ở cổng master DMA; golden hash nằm trong Boot ROM.
- **Bộ nhớ** đọc/ghi đồng bộ ở cạnh xuống: suy ra M4K/BRAM mà lõi không phải sửa (đường đọc còn nửa chu kỳ).
- **RTL tổng hợp viết Verilog-2001** (Quartus 13 chỉ hỗ trợ một phần SystemVerilog), không dùng IP/primitive riêng hãng; SystemVerilog chỉ dùng trong testbench.
- **FPGA:** DE2 (Cyclone II EP2C35F672C6) bằng Quartus II 13.0sp1; kit Xilinx (chưa chốt, đang thử Artix-7 xc7a35t) bằng Vivado 2025.2. Cùng RTL, chỉ khác top bọc chân và constraints (`syn/intel_de2`, `syn/xilinx`).

### Bản đồ địa chỉ thế giới Secure

Chi tiết thanh ghi: `doc/SoC_Memory_Map.md` (Nguyên giữ).

| Địa chỉ | Khối |
|---|---|
| `0x0000_0000` 4 KB | Boot ROM (`firmware_imem.hex`) |
| `0x1000_0000` 4 KB | RAM Master (`firmware_dmem.hex`) |
| `0x4000_0000` | Bus APB: SYSCSR `+0x0000`, UART0 `+0x1000`, GPIO0 `+0x2000`, TIMER0 `+0x3000`, WDT `+0x4000`, PLIC `+0x5000`, Mailbox `+0x6000` |
| `0x5000_0000` | SHA-256 |
| `0x6000_0000` 4 KB | ROM App cổng B (chỉ đọc, ghi → `SLVERR`) |
| còn lại | default slave → `DECERR` |

## 3. Kịch bản Secure Boot

1. Bấm reset: chỉ Master chạy từ Boot ROM; SYSCSR giữ App Core trong reset.
2. Master băm **toàn bộ 4 KB** ROM App qua cổng B (bằng CPU, sau này bằng Secure DMA) với lõi SHA-256 phần cứng.
3. So kết quả với golden hash lưu trong Boot ROM.
4. Khớp: ghi `SYSCSR.APP_CTRL = 1`, App Core bắt đầu chạy. Sai: Boot Guard khóa App tới khi bật lại nguồn và xóa RAM App (Zeroization).
5. Trạng thái báo qua LED (LEDG0 = App đang chạy) và log qua UART (115200 baud @ 50 MHz) lên máy tính.

## 4. Phân công và giao diện

- **Nguyên — System Architect & PPA:** `rtl/uncore` + `SoC_Top` (bus AXI/APB, ngoại vi, bộ nhớ, SHA-256, Boot Guard, DMA, tường lửa), testbench IP/SoC, VP, Quartus/Vivado, PPA FPGA, sơ đồ kiến trúc hệ thống.
- **Phát — Core RTL, Firmware, DV, PD:** `rtl/core` (lõi, Zicsr, ngắt), firmware + HAL + driver, UVM + coverage, ASIC Genus/Innovus.

| ID | Hạn | Nội dung | Chủ trì |
|---|---|---|---|
| I-01 | 01/11 | Cổng ngắt của lõi: tên + mức tích cực (đề xuất `irq_timer`, `irq_ext` mức cao → `mip.MTIP`/`mip.MEIP`) | Phát |
| I-02 | 01/11 | Header địa chỉ firmware theo `doc/SoC_Memory_Map.md`; đổi map phải báo trước | Nguyên |
| I-03 | 08/11 | Địa chỉ golden hash trong Boot ROM (cổng đọc dữ liệu) + đổi `linker.ld` đặt `.rodata` vào đó | Cả hai |
| I-04 | 15/11 | Target CMake `app_firmware.hex` + bước sinh golden hash (băm cả 4 KB ROM App) | Phát |
| I-05 | — | SHA-256: 66 chu kỳ START→DONE; offset trống OKAY/0; ngoài slave DECERR (đã chốt) | Nguyên |
| I-06 | — | UART `BAUD_DIV` mặc định 26 = 115200 baud @ 50 MHz (đã chốt) | Nguyên |
| I-07 | — | Chỉ commit trên `main`, chạy trong WSL, mô phỏng Questa, `make test` PASS trước khi push (đã chốt) | Cả hai |

## 5. Mốc

| Mốc | Ngày | Nội dung |
|---|---|---|
| M1 | 01/11 | Phát chốt cổng ngắt lõi (I-01); TIMER0 + WDT xong |
| M2 | 22/11 | **RTL FREEZE** — toàn SoC biên dịch sạch Questa/Quartus/Vivado, `make test` PASS, 50 MHz |
| M3 | 29/11 | Demo secure boot trên DE2 (LED + log UART) |
| M4 | 06/12 | Báo cáo PPA FPGA + functional coverage |
| M5 | 13/12 | PPA ASIC (Genus/Innovus) + so sánh FPGA–ASIC |
| M6 | 20/12 | GitHub + tài liệu hoàn chỉnh |
| M7 | 27/12 | Báo cáo + slide + bảo vệ thử |

## 6. Tình trạng tới 24/10 (cuối Tuần 7)

**Đã xong**
- Nguyên: workspace + testbench SV; Forwarding/Hazard; AXI4-Lite master/slave/interconnect (WSTRB, DECERR, SLVERR); SHA-256 đầy đủ (đúng vector NIST); Dual-Port ROM + cách ly Boot ROM/ROM App; SoC_Top + test secure boot đầu–cuối; cầu AXI→APB, SYSCSR (thay Reset Controller), UART0, GPIO0; bộ nhớ đồng bộ; luồng Quartus/Vivado; VP SystemC chạy HAL thật; Makefile gốc.
- Phát: lõi 5 tầng + hazard; test ISA 40 CHECK (có/không stall); load/store byte/half (`data_wstrb`); 11 TB đơn vị tự kiểm tra; khung UVM AXI4-Lite (có reset giữa giao dịch); HAL SHA-256 + test plan; toolchain CMake + linker + crt0.

**Kết quả đo**
- Mô phỏng: 11 TB đơn vị FAIL = 0; `RISCV_Core_tb` 44/44; chương trình ISA PASS (có/không stall); hazard 0 lỗi; APB 28/28; `SoC_Top_tb` PASS (firmware thử băm "abc" bằng SHA phần cứng, đọc ROM App qua cổng B, kiểm SLVERR/DECERR, UART, GPIO rồi nhả App — **chưa băm image App, chưa có kịch bản image bị sửa trên RTL**); SHA-256 đúng vector NIST; HAL 9.692 test host PASS; UVM 15/15 PASS; VP image đúng/sai PASS.
- DE2 (EP2C35): 7.453 LE (22%), 3.487 thanh ghi, 135 Kbit M4K (28%), Fmax 54,9 MHz — đạt 50 MHz.
- Artix-7 xc7a35t (thử): 3.125 LUT (15%), 2.665 FF, WNS +3,174 ns @ 50 MHz — đạt.

**Còn thiếu hoặc trễ**
- Ngắt trong lõi (Zicsr, irq) — PLIC/TIMER cần để dùng ngắt (vẫn chạy được bằng polling).
- TIMER, WDT, PLIC-lite, Mailbox, bus ngoại vi của thế giới App; Boot Guard/Zeroization, Secure DMA, tường lửa AXI.
- Firmware secure boot thật (`fw/secure_boot/main.c` vẫn là mẫu; `SoC_Top_tb` đang chạy firmware thử viết tay `dv/tests/mkhex.py`); golden hash đang nằm trong RAM ghi được.
- UVM sequence ngẫu nhiên cho SHA-256 (P-08, Tuần 7 gốc); chưa đổ board.

## 7. Lịch Tuần 8 → 16

| Tuần | Nguyên | Phát |
|---|---|---|
| **8** (26/10–01/11) — Nền tảng + TIMER/WDT | TIMER0 kiểu CLINT (`mtime`/`mtimecmp` → `irq_timer`); WDT (hết giờ → reset qua SYSCSR, ghi RST_CAUSE); cập nhật `SoC_Memory_Map.md`; đối chiếu chân DE2 với file Terasic; header địa chỉ firmware (I-02) | Zicsr + trap máy (`mtvec`, `mepc`, `mcause`, `mstatus.MIE`, `mie`/`mip`, `ecall`/`mret`) + cổng `irq_timer`/`irq_ext` (I-01, **chặn TIMER/PLIC**); UVM sequence ngẫu nhiên cho SHA-256 (P-08, chuyển từ Tuần 7); dọn `dv/tb` sang `dv/env`, `dv/agents`; driver UART/GPIO trong `fw/hal`; cập nhật `Project_Status.md` |
| **9** (02–08/11) — Ngắt + Boot Guard | PLIC-lite 8 nguồn → `irq_ext`; Boot Guard + Zeroization (thanh ghi LOCK trong SYSCSR, FSM xóa RAM App); cổng đọc dữ liệu chỉ-đọc cho Boot ROM | Firmware secure boot thật (HAL + log UART + golden trong Boot ROM + LOCK khi sai), chạy VP rồi RTL; đổi `linker.ld` đặt `.rodata` vào Boot ROM (I-03); test assembly ngắt timer/external |
| **10** (09–15/11) — DMA, tường lửa, thế giới App | Secure DMA (ROM App → SHA theo block) + bus Secure 2 master (arbiter) + tường lửa AXI ở cổng DMA; bus APB của App (UART1, GPIO1, TIMER1) + Mailbox 2 chiều | Firmware dùng DMA; firmware App demo (Mailbox, LED, UART) + target CMake `app_firmware.hex` + bước sinh golden hash băm cả 4 KB (I-04); UVM agent APB + scoreboard SHA (golden model DPI từ `sha256_ref.c`) |
| **11** (16–22/11) — Tích hợp, **RTL FREEZE 22/11** | Regression toàn SoC; đạt 50 MHz trên DE2 và Xilinx; cập nhật VP theo RTL; đóng băng RTL | Test firmware toàn SoC (boot đúng/sai, ngắt, DMA); regression UVM |
| **12** (23–29/11) — Đổ board | Nạp DE2 qua USB-Blaster, demo secure boot bằng LED + log UART; chốt kit Xilinx, gán chân, nạp | Covergroup + thu coverage; sửa lỗi phát sinh khi chạy board |
| **13** (30/11–06/12) — PPA FPGA + coverage | Báo cáo PPA (Fmax, LE/LUT, FF, M4K/BRAM, công suất) cho Quartus và Vivado; SDC bàn giao ASIC | Báo cáo functional coverage; Synthesis mức cổng (Genus) |
| **14** (07–13/12) — ASIC + sơ đồ | Sơ đồ khối hệ thống, VP, testbed FPGA; tài liệu chạy VP/FPGA | Innovus, so sánh PPA FPGA–ASIC |
| **15** (14–20/12) — GitHub + tài liệu | Cả hai: README, cấu trúc thư mục, hướng dẫn build/sim/FPGA/VP, dọn RTL | |
| **16** (21–27/12) — Báo cáo + bảo vệ thử | Cả hai: báo cáo tổng kết, slide (4 luồng: RTL/HRoT, VP, DV/coverage, PD/PPA), tập phản biện với thầy | |

## 8. Rủi ro và cách xử lý

- **Fmax DE2 chỉ dư khoảng 10%** (54,9 MHz): đo lại sau mỗi khối mới; nếu thiếu thì chèn thanh ghi ở đường bus/SHA hoặc hạ xuống 40 MHz.
- **Ngắt phụ thuộc lõi (Phát):** nếu trễ, PLIC/TIMER vẫn dùng bằng polling, demo không bị chặn.
- **Golden hash trong RAM ghi được:** chuyển vào Boot ROM ở Tuần 9 (N-21, I-03).
- **VP đang băm theo độ dài image**, còn I-04 chốt băm cả 4 KB ROM App: thống nhất trước khi làm firmware thật (Tuần 9–10).
- **Bộ nhớ đọc ở cạnh xuống không hợp với SRAM macro ASIC** (Tuần 13–14): chuẩn bị phương án — dùng flip-flop cho bộ nhớ nhỏ, hoặc thêm 1 chu kỳ chờ ở IF/MEM trong bản ASIC.
- **Quartus II 13.0sp1 chỉ hỗ trợ một phần SystemVerilog:** RTL tổng hợp giữ Verilog-2001.
- **Kit Xilinx chưa chốt:** luồng Vivado đã chạy với Artix-7, khi chốt chỉ đổi part và gán chân.
- **Máy WSL của Phát** chưa có `make`, `gcc`, toolchain RISC-V: cần cài trước khi chạy `make test` / `make fw`.

## 9. Các điểm đã chỉnh so với Google Doc (24/10)

1. **I-02 (header địa chỉ firmware):** tab "Tổng quan" mục 8 ghi Phát giữ; sheet ghi Nguyên chủ trì → theo sheet.
2. **Cách tạo file hex:** các ghi chú "Đề xuất 24/10" ghi `od -tx4` ra `fw/build/secure_boot.hex`; repo dùng CMake + `objcopy --verilog-data-width=4` ra `firmware_imem.hex` / `firmware_dmem.hex` → theo repo.
3. **Bộ nhớ:** ghi chú Tuần 8/11 ở tab gốc nói ROM đọc tổ hợp (distributed ROM) và "cần Phát thêm stall ở IF nếu chuyển BRAM"; repo đã chuyển sang đọc đồng bộ cạnh xuống (`ad42ec7`), lõi không phải sửa → bỏ việc thêm stall.
4. **"Đề xuất 24/10 (chưa merge)" và "Còn chờ Phát P1–P3"** ở tab gốc và tab Review đã lỗi thời: các đề xuất đã vào `main` (`459f4fe`…`bb8288a`), P1–P3 xong ở commit `33c0d1e`.
5. **Lịch Tuần 8:** bổ sung P-08 (UVM SHA ngẫu nhiên, trễ từ Tuần 7) và việc cập nhật tài liệu; Tuần 9 bổ sung đổi `linker.ld` (I-03); Tuần 10 bổ sung target `app_firmware.hex` + sinh golden hash (I-04) — các việc này có trong sheet nhưng thiếu trong lịch.
6. **Mốc M1 (01/11)** có trong sheet nhưng thiếu ở mục "Mốc chính" → bổ sung.
7. **Kết quả đo:** bổ sung TB đơn vị, HAL, UVM; WNS Artix-7 ghi chính xác +3,174 ns theo `pd/reports/fpga/artix7_timing_summary.rpt`.
8. **SoC_Top_tb:** tab gốc (Tuần 9) và tab Review ghi "hash đúng → nhả reset App; hash sai → App giữ reset"; thực tế firmware thử trong `dv/tests/mkhex.py` chỉ băm chuỗi "abc" rồi luôn nhả App. Kịch bản đúng/sai trên ảnh App hiện chỉ có ở VP → đưa vào việc test firmware toàn SoC (Tuần 11).
9. **Thay đổi phạm vi so với kế hoạch gốc (giữ theo bản hợp nhất):** việc "bơm dữ liệu nhiễu vào UVM khi chạy Full SoC" (Tuần 10 gốc) được thay bằng UVM agent APB + scoreboard SHA; code Application cho App Core chuyển từ Tuần 12 lên Tuần 10.

**Chưa sửa, cần nhóm xem lại trong sheet:** P-07 (sơ đồ datapath) đang ghi "Xong" nhưng chưa có ngày xong, commit, và repo chưa có file sơ đồ trong `doc/`; N-09 ghi WNS "+3,07 ns" (báo cáo là +3,174 ns); N-20 (Boot Guard) để trống cột Hạn và ghi "08/11" vào cột Ngày xong dù trạng thái "Chưa làm".
