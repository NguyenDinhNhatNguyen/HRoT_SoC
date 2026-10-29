# Plan Đồ án 2 — HRoT SoC

> Chuyển từ Google Doc "Plan Đồ án 2", tab "Kế hoạch chuẩn (hợp nhất)" và "Tổng quan Đồ án 2" (bản 24/10/2026, cập nhật tình trạng, lịch và rủi ro 25/10/2026), đã đối chiếu với repo (`main` sau `bb59f25`) và [Google Sheet tiến độ](https://docs.google.com/spreadsheets/d/13jJj9UP1Cxr8ZNFqzQnNTaiulD2_HaKOWAONfCnZnU4/edit). Hạn và trạng thái từng việc theo sheet, khi file này lệch sheet thì theo sheet. Các chỗ đã chỉnh so với Google Doc ghi ở mục 9.

## 1. Đề tài

- **Tên:** Thiết kế SoC đa lõi bất đối xứng (AMP) RISC-V tích hợp cách ly vật lý và khởi động bảo mật (Hardware Root of Trust & Secure Boot).
- **Thời gian:** 07/09/2026 – 27/12/2026 (16 tuần, mỗi tuần thứ Hai → Chủ nhật). **RTL FREEZE: 22/11/2026** (cuối Tuần 11, theo yêu cầu thầy hướng dẫn).
- **Mục tiêu chứng minh trên FPGA:** lõi ứng dụng chỉ được chạy khi firmware của nó được phần cứng xác thực bằng SHA-256, và lõi ứng dụng không thể chạm vào thế giới Secure.
- **Quy ước làm việc (I-07):** chỉ commit trên `main`, mọi lệnh chạy trong WSL tại thư mục gốc repo, mô phỏng bằng QuestaSim 10.2c, `make test` PASS trước khi push.

## 2. Kiến trúc đã chốt

- **Kiến trúc tham chiếu:** SoC RISC-V hai lõi kiểu công nghiệp — lõi boot/điều khiển (vai trò như Ibex) nắm quyền khởi động, lõi ứng dụng (vai trò như CVA6) bị giữ reset tới khi image được xác thực. Rút gọn cho đồ án và thêm cách ly vật lý.
- **Hai lõi RV32I 5 tầng tự viết:** Master (Secure) chạy từ Boot ROM 4 KB riêng + RAM 4 KB, App chạy từ ROM App (cổng A của Dual-Port ROM) + RAM riêng, bị giữ reset tới khi Master cho phép.
- **Cách ly vật lý:** mỗi thế giới có bus và bộ nhớ riêng, chỉ nối nhau qua cổng B chỉ đọc của ROM App (Master đọc để băm) và Mailbox (Tuần 10).
- **Bus Secure:** AXI4-Lite (RAM, SHA-256, ROM App cổng B, default slave DECERR) + cầu AXI→APB ra bus ngoại vi (SYSCSR, UART0, GPIO0, TIMER0, WDT, PLIC-lite, Mailbox).
- **Bảo mật phần cứng:** SHA-256 tăng tốc (66 chu kỳ/block), Boot Guard + Zeroization (băm sai → khóa App tới khi bật lại nguồn, xóa RAM App), Secure DMA nạp ROM App vào SHA, tường lửa AXI ở cổng master DMA, golden hash nằm trong Boot ROM.
- **Bộ nhớ** đọc/ghi đồng bộ ở cạnh xuống: suy ra M4K/BRAM mà lõi không phải sửa (đường đọc còn nửa chu kỳ).
- **RTL tổng hợp viết Verilog-2001** (Quartus 13 chỉ hỗ trợ một phần SystemVerilog), không dùng IP/primitive riêng hãng. SystemVerilog chỉ dùng trong testbench.
- **FPGA:** DE2 (Cyclone II EP2C35F672C6) bằng Quartus II 13.0sp1, kit Xilinx (chưa chốt, đang thử Artix-7 xc7a35t) bằng Vivado 2025.2. Cùng RTL, chỉ khác top bọc chân và constraints (`fpga/intel_de2`, `fpga/xilinx`).

### Bản đồ địa chỉ thế giới Secure

Chi tiết thanh ghi: `docs/spec/SoC_Memory_Map.md` (Nguyên giữ).

| Địa chỉ | Khối |
| --- | --- |
| `0x0000_0000` 4 KB | Boot ROM (`firmware_imem.hex`) |
| `0x1000_0000` 4 KB | RAM Master (`firmware_dmem.hex`) |
| `0x4000_0000` | Bus APB: SYSCSR `+0x0000`, UART0 `+0x1000`, GPIO0 `+0x2000`, TIMER0 `+0x3000`, WDT `+0x4000`, PLIC `+0x5000`, Mailbox `+0x6000` |
| `0x5000_0000` | SHA-256 |
| `0x6000_0000` 4 KB | ROM App cổng B (chỉ đọc, ghi → `SLVERR`) |
| còn lại | default slave → `DECERR` |

## 3. Kịch bản Secure Boot

1. Bấm reset: chỉ Master chạy từ Boot ROM, SYSCSR giữ App Core trong reset.
2. Master băm **toàn bộ 4 KB** ROM App qua cổng B (bằng CPU, sau này bằng Secure DMA) với lõi SHA-256 phần cứng.
3. So kết quả với golden hash lưu trong Boot ROM.
4. Khớp: ghi `SYSCSR.APP_CTRL = 1`, App Core bắt đầu chạy. Sai thì Boot Guard khóa App tới khi bật lại nguồn và xóa RAM App (Zeroization).
5. Trạng thái báo qua LED (LEDG0 = App đang chạy) và log qua UART (115200 baud @ 50 MHz) lên máy tính.

## 4. Phân công và giao diện

- **Nguyên — System Architect & PPA:** `rtl/{bus,periph,mem,crypto}` + `SoC_Top` (bus AXI/APB, ngoại vi, bộ nhớ, SHA-256, Boot Guard, DMA, tường lửa), testbench IP/SoC, VP, Quartus/Vivado, PPA FPGA, sơ đồ kiến trúc hệ thống.
- **Phát — Core RTL, Firmware, DV, PD:** `rtl/core` (lõi, Zicsr, ngắt), firmware + HAL + driver, UVM + coverage, ASIC Genus/Innovus.

| ID | Hạn | Nội dung | Chủ trì |
| --- | --- | --- | --- |
| I-01 | 01/11 | Cổng ngắt của lõi (đã chốt 25/10): `irq_timer`, `irq_ext`: đầu vào mức cao, đồng bộ `clk`, giữ mức tới khi nguồn tự xóa (TIMER0: ghi `mtimecmp`, PLIC: claim/complete), lõi không bắt cạnh → `mip.MTIP` (bit 7) / `mip.MEIP` (bit 11), ưu tiên MEI > MTI. Dự trữ cho sau P-09: `data_err` mức cao cùng chu kỳ với `resp_valid` (nối `err_valid` của `AXI4_Lite_Master`) → access fault `mcause` 5 (load) / 7 (store), `mtval` = địa chỉ | Phát |
| I-02 | 01/11 | Header địa chỉ firmware `fw/hal/soc_map.h` theo `docs/spec/SoC_Memory_Map.md` (việc N-34), đổi map phải báo trước | Nguyên |
| I-03 | 08/11 | Địa chỉ golden hash trong Boot ROM (cổng đọc dữ liệu) + đổi `linker.ld` đặt `.rodata` vào đó. Xong 27/10: golden ở `0xFE0` | Cả hai |
| I-04 | 15/11 | Target CMake `app_firmware.hex` + bước sinh golden hash (băm cả 4 KB ROM App). Xong 29/10 (P-16) | Phát |
| I-05 | — | SHA-256: 66 chu kỳ START→DONE, offset trống OKAY/0, ngoài slave DECERR (đã chốt, RTL khớp từ 25/10) | Nguyên |
| I-06 | — | UART `BAUD_DIV` mặc định 26 = 115200 baud @ 50 MHz (đã chốt) | Nguyên |
| I-07 | — | Chỉ commit trên `main`, chạy trong WSL, mô phỏng Questa, `make test` PASS trước khi push (đã chốt). P-22 xong 26/10, `regress.sh` tự cho mọi `vsim` đọc stdin từ `/dev/null` | Cả hai |

## 5. Mốc

| Mốc | Ngày | Nội dung |
| --- | --- | --- |
| M1 | 01/11 | Phát chốt cổng ngắt lõi (I-01), TIMER0 + WDT xong. ✅ Xong 25/10 (TIMER0, WDT xong, I-01 đã chốt). P-09 xong 26/10, còn Nguyên nối dây ngắt trong `SoC_Top` |
| M2 | 22/11 | **RTL FREEZE** — toàn SoC biên dịch sạch Questa/Quartus/Vivado, `make test` PASS, 50 MHz |
| M3 | 29/11 | Demo secure boot trên DE2 (LED + log UART) |
| M4 | 06/12 | Báo cáo PPA FPGA + functional coverage |
| M5 | 13/12 | PPA ASIC (Genus/Innovus) + so sánh FPGA–ASIC |
| M6 | 20/12 | GitHub + tài liệu hoàn chỉnh |
| M7 | 27/12 | Báo cáo + slide + bảo vệ thử |

## 6. Tình trạng tới 26/10

**Đã xong**
- Nguyên: workspace + testbench SV, Forwarding/Hazard, AXI4-Lite master/slave/interconnect (WSTRB, DECERR, SLVERR), SHA-256 đầy đủ (đúng vector NIST), Dual-Port ROM + cách ly Boot ROM/ROM App, SoC_Top + test secure boot đầu–cuối, cầu AXI→APB, SYSCSR (thay Reset Controller), UART0, GPIO0, bộ nhớ đồng bộ, luồng Quartus/Vivado, VP SystemC chạy HAL thật, Makefile gốc. Ngày 25/10 thêm: TIMER0 kiểu CLINT, WDT, sửa alias SHA-256, cấu trúc lại repo, comment và log test tiếng Anh, `SYSCSR.BUS_ERR`. Ngày 26/10 thêm: PLIC-lite, Mailbox, Boot Guard + Zeroization, cổng đọc dữ liệu Boot ROM, Secure DMA với một master AXI dùng chung và tường lửa, bus APB thế giới App (UART1, GPIO1, TIMER1), VP có UART0, TIMER0, WDT, Boot Guard và DMA, `SoC_Top_tb` băm cả image App và chạy thêm ảnh bị sửa.
- Phát: lõi 5 tầng + hazard, test ISA 41 CHECK phủ đủ 37 lệnh RV32I tính toán, nhảy, load/store (có/không stall), load/store byte/half (`data_wstrb`), 11 TB đơn vị tự kiểm tra, khung UVM AXI4-Lite (có reset giữa giao dịch), HAL SHA-256 + test plan, toolchain CMake + linker + crt0, UVM SHA-256 ngẫu nhiên + corner case trên DUT thật (P-08, 25/10).

**Kết quả đo**
- Mô phỏng (Questa, 26/10, `make test` toàn bộ PASS): 11 TB đơn vị, chương trình ISA, `RISCV_Core_tb`, hazard, UVM AXI4-Lite và SHA-256, HAL 9.692 test host, APB 79/79 (thêm Boot Guard, PLIC-lite, Mailbox), `SoC_Top_tb` PASS ở hai kịch bản (ảnh đúng: CPU và DMA hash cả 4 KB ROM App khớp golden trong Boot ROM, ảnh bị sửa: Boot Guard khóa App và RAM App về 0), VP PASS ở hai kịch bản.
- DE2 (EP2C35, 26/10): 9.358 LE (28%), 4.390 thanh ghi, 135 Kbit M4K (28%), Fmax 53,02 MHz, đạt 50 MHz. Số này đo với lõi đã đổi reset đồng bộ (rủi ro R15). Lần đo 25/10 trước khi thêm DMA, PLIC, Mailbox và bus App: 8.011 LE, 54,69 MHz.
- Artix-7 xc7a35t (thử, 26/10): 5.530 LUT (27%), 4.092 FF, 2,5 BRAM, WNS +3,519 ns @ 50 MHz, đạt. Lần đo 25/10: 3.360 LUT, WNS +2,891 ns.
- Lần đo mới nhất (DE2, `9f9e66a` + P-13, P-14 với dây ngắt đã nối, Phát đo 27/10): 10.509 LE (32%), 4.842 thanh ghi, Fmax 54,21 MHz. Artix-7 chưa đo lại. Số của mọi lần đo: [FPGA_Results.md](FPGA_Results.md).

**Còn thiếu hoặc trễ**
- Ngắt trong lõi (Zicsr, irq): PLIC/TIMER cần để dùng ngắt (vẫn chạy được bằng polling). Lõi đã có cổng `irq_timer`/`irq_ext` (P-09, 26/10), còn nối `timer0_irq`, `plic_irq` trong `SoC_Top`.
- Phần RTL Nguyên giao đã có đủ. Còn thiếu việc đóng băng RTL (N-26) và nối dây ngắt vào lõi (P-09 đã xong 26/10).
- Firmware secure boot thật: đã hoàn thành 27/10 (P-13), chạy trên VP và RTL. Băm bằng Secure DMA từ 29/10 (P-15). Firmware App demo và bước tự sinh golden lúc build xong 29/10 (I-04, P-16).
- Đổ board (chân DE2 đã đối chiếu xong 25/10, N-18: 52/52 chân khớp DE2 User Manual v1.3).

## 7. Lịch Tuần 8 → 16

| Tuần | Nguyên | Phát |
| --- | --- | --- |
| **8** (26/10–01/11) — Nền tảng + TIMER/WDT | TIMER0 kiểu CLINT, WDT, cập nhật `SoC_Memory_Map.md`, đối chiếu chân DE2 (N-18): đã hoàn thành 25/10. VP băm cả 4 KB ROM App (N-33), header địa chỉ firmware `soc_map.h` (I-02, N-34): đã hoàn thành 25/10. **Kéo lên từ Tuần 9:** cổng đọc dữ liệu Boot ROM (N-21), Boot Guard + Zeroization (N-20), PLIC-lite (N-19), cả ba đã xong 26/10 | Zicsr + trap máy (`mtvec`, `mepc`, `mcause`, `mstatus.MIE`, `mie`/`mip`, `ecall`/`mret`) + cổng `irq_timer`/`irq_ext` (I-01, **chặn nối ngắt TIMER/PLIC**), UVM sequence ngẫu nhiên cho SHA-256 (P-08, đã hoàn thành 25/10), sửa 2 lỗi script Questa (P-22, đã sửa 25/10, chờ chạy trên Questa), dọn `dv/tb` sang `dv/env`, `dv/agents`, driver UART/GPIO trong `fw/hal` dùng `soc_map.h`, cập nhật `Project_Status.md` (P-12, đã hoàn thành 24/10) |
| **9** (02–08/11) — Ngắt + Boot Guard | Hoàn tất N-19, N-20, N-21 (nối `irq_ext` khi có I-01), VP thêm mô hình UART0, TIMER0, WDT cho firmware (N-32), `SoC_Top_tb` băm cả image App và thêm kịch bản image bị sửa trên RTL (N-35). **N-19, N-20, N-21, N-32 và N-35 đã xong 26/10, chỉ còn nối `irq_ext` vào lõi (chờ P-09).** Báo lỗi bus AXI qua `SYSCSR.BUS_ERR` (N-36, đã hoàn thành 25/10) | Firmware secure boot thật (HAL + log UART + golden trong Boot ROM + LOCK khi sai), chạy VP rồi RTL, đổi `linker.ld` đặt `.rodata` vào Boot ROM (I-03), test assembly ngắt timer/external |
| **10** (09–15/11) — DMA, tường lửa, thế giới App | Secure DMA (ROM App → SHA theo block) + bus Secure 2 master (arbiter) + tường lửa AXI ở cổng DMA, bus APB của App (UART1, GPIO1, TIMER1) + Mailbox 2 chiều. **Đã xong 26/10 (N-22…N-25)** | Firmware dùng DMA, firmware App demo (Mailbox, LED, UART) + target CMake `app_firmware.hex` + bước sinh golden hash băm cả 4 KB (I-04), UVM agent APB + scoreboard SHA (golden model DPI từ `sha256_ref.c`) |
| **11** (16–22/11) — Tích hợp, **RTL FREEZE 22/11** | Regression toàn SoC, đạt 50 MHz trên DE2 và Xilinx, cập nhật VP theo RTL, đóng băng RTL. **Regression, 50 MHz (DE2 53,02 MHz, Artix-7 WNS +3,5 ns) và VP đã xong 26/10, còn đóng băng RTL 22/11. P-09 và P-23 (R15) của Phát xong 26/10, còn nối dây ngắt trong `SoC_Top`** | Test firmware toàn SoC (boot đúng/sai, ngắt, DMA), regression UVM |
| **12** (23–29/11) — Đổ board | Nạp DE2 qua USB-Blaster, demo secure boot bằng LED + log UART, chốt kit Xilinx, gán chân, nạp | Covergroup + thu coverage, sửa lỗi phát sinh khi chạy board |
| **13** (30/11–06/12) — PPA FPGA + coverage | Báo cáo PPA (Fmax, LE/LUT, FF, M4K/BRAM, công suất) cho Quartus và Vivado, SDC bàn giao ASIC | Báo cáo functional coverage, Synthesis mức cổng (Genus) |
| **14** (07–13/12) — ASIC + sơ đồ | Sơ đồ khối hệ thống, VP, testbed FPGA, tài liệu chạy VP/FPGA | Innovus, so sánh PPA FPGA–ASIC |
| **15** (14–20/12) — GitHub + tài liệu | Cả hai: README, cấu trúc thư mục, hướng dẫn build/sim/FPGA/VP, dọn RTL | |
| **16** (21–27/12) — Báo cáo + bảo vệ thử | Cả hai: báo cáo tổng kết, slide (4 luồng: RTL/HRoT, VP, DV/coverage, PD/PPA), tập phản biện với thầy | |

## 8. Rủi ro và cách xử lý

Cập nhật 26/10/2026, 19 rủi ro, việc sửa R15 là P-23. Cột "Phụ trách" là người xử lý, việc của Phát ở đây là **đề xuất**, Phát xác nhận lại.

| # | Rủi ro | Mức | Hướng xử lý | Phụ trách | Trạng thái |
| --- | --- | --- | --- | --- | --- |
| R1 | `make test` không PASS được trên Questa 10.2c (timeout UVM lệch đơn vị, `run_unit.do` dừng sau `ALU_tb`), nên quy ước I-07 đang không thực hiện được | Cao | Sửa `base_test.svh` (tính timeout theo `ns` cố định hoặc so với `$time` trong cùng package) và bỏ `-onfinish stop` hay thay bằng `onbreak {resume}` trong `run_unit.do`, kiểm tra lại trên Questa. Tạm thời chạy `make test < /dev/null` và chấp nhận 5 mục FAIL đã biết | Phát (P-22) | Đã xong: Phát sửa 25/10 (`fb0b577`), Nguyên chạy `make test` trên Questa 26/10 PASS (P-22) |
| R2 | Fmax DE2 chỉ dư khoảng 6% (53,02 MHz, 9.358 LE, đo 26/10), cách ngưỡng 52 MHz khoảng 2%. Đường găng nằm trong lõi: `Rd_WB` → forwarding ở ID → `RD2_EX` (slack +1,14 ns), không có đường nào của uncore trong top. Lần đo 25/10 thì đường găng là `Rs1_EX` → so sánh nhánh → `PC` | Trung bình | Lõi: nếu Fmax tụt dưới 52 MHz thì đăng ký kết quả forwarding/so sánh nhánh (thêm 1 chu kỳ phạt khi nhảy) hoặc tính sẵn đích nhảy ở ID. Uncore: giữ slack ≥ 2 ns, đo lại DE2 sau mỗi khối | Phát (lõi), Nguyên (đo, uncore) | Đang theo dõi, sát ngưỡng |
| R3 | Ngắt phụ thuộc cổng `irq_timer`/`irq_ext` của lõi (I-01 đã chốt 25/10), mốc M1 có thể trễ vì P-09 chưa xong | Trung bình | Phía SoC đã đủ dây ngắt cho cả hai lõi và `master_data_err`, PLIC-lite đã làm và test. Khi P-09 xong, nối theo các comment `TODO(P-09)`. Nếu trễ, firmware dùng polling, demo không bị chặn | Phát (P-09), Nguyên (nối) | Đã xong 27/10: dây ngắt nối trong `SoC_Top` (P-14), `SoC_Irq_tb` PASS |
| R4 | Golden hash nằm trong RAM ghi được, chưa đúng mô hình Root of Trust | Cao | Cổng đọc dữ liệu Boot ROM (N-21) đã có ở `0x0000_0000`. Còn Phát đổi `linker.ld` đặt `.rodata` và golden trong ROM (I-03) | Nguyên, Phát | Đã xong 27/10: `.rodata` và golden trong Boot ROM (P-13, I-03) |
| R5 | VP băm theo độ dài image, còn I-04 chốt băm cả 4 KB ROM App, hai bên ra golden khác nhau | Trung bình | VP băm đủ 4 KB (N-33, diff 3 dòng đã có) | Nguyên | Đã xong 25/10 (N-33, commit `a946e2a`) |
| R6 | Firmware secure boot (P-13) phải chạy trên VP trước RTL nhưng VP chưa có UART, TIMER, WDT | Trung bình | VP có UART0 (in log), TIMER0, WDT, Boot ROM, Boot Guard và Secure DMA (N-27, N-32) | Nguyên | Đã xong 26/10 |
| R6b | Firmware không biết khi bus Master trả SLVERR/DECERR vì `AXI4_Lite_Master` bỏ qua BRESP/RRESP | Trung bình | Thêm `SYSCSR.BUS_ERR` và `BUS_ERR_ADDR` (N-36). Access fault qua trap làm sau P-09 | Nguyên | Đã xong 25/10 |
| R7 | Secure boot mức RTL mới kiểm image đúng, firmware thử chỉ băm "abc" | Trung bình | `SoC_Top_tb` băm cả 4 KB ROM App bằng CPU và bằng DMA, so với golden trong Boot ROM do `mkhex.py` tính bằng `hashlib`, chạy thêm ảnh bị sửa và kiểm App bị khóa, RAM App về 0 (N-35) | Nguyên | Đã xong 26/10 |
| R8 | Bộ nhớ đọc ở cạnh xuống không hợp với SRAM macro ASIC (Tuần 13–14) | Trung bình | Nguyên thêm tham số chọn bộ nhớ đồng bộ cạnh lên cho bản ASIC, Phát thêm tín hiệu chờ (`ready`) ở IF/MEM để lõi chịu được 1 chu kỳ trễ. Chốt cách làm trước Tuần 12 | Nguyên, Phát | Đề xuất |
| R9 | Xuống dòng lẫn LF và CRLF giữa hai máy, diff dễ bị nhiễu | Thấp | Thêm `* text=auto eol=lf` vào `.gitattributes` và `git add --renormalize .` trong một commit riêng, làm lúc cả hai đã push hết | Nguyên | Chờ thời điểm |
| R10 | WSL của Phát chưa có `make`, `gcc`, toolchain RISC-V | Trung bình | Cài `build-essential`, `python3`, `gcc-riscv64-unknown-elf`, SystemC trước 01/11 | Phát | Đã xong 25/10: `build-essential`, `cmake`, `gcc-riscv64-unknown-elf` 14.2 (có multilib `rv32i/ilp32`), SystemC 2.3.4 build từ mã nguồn ở `/usr/local/systemc-2.3.4`. `make fw`, `make vp`, HAL host test PASS. Còn QuestaSim |
| R11 | Comment trong `fw/linker.ld` còn ghi `0x4000_0000` là Reset Controller và chờ Nguyên xác nhận RAM | Thấp | Nguyên xác nhận: RAM `0x1000_0000` 4 KB đúng với `SoC_Top`, `0x4000_0000` nay là SYSCSR. Phát sửa comment khi đổi `linker.ld` cho I-03 | Phát | Đã sửa 25/10 (comment `linker.ld` ghi SYSCSR, RAM `0x1000_0000` 4 KB đã chốt) |
| R12 | Bảng chân DE2 đối chiếu theo manual v1.3, Terasic đã có bản 1.6 | Thấp | Xem lại bảng chân trong bản 1.6 trước khi nạp board (Tuần 12) | Nguyên | Đã lên lịch |
| R13 | Quartus II 13.0sp1 chỉ hỗ trợ một phần SystemVerilog | Thấp | RTL tổng hợp giữ Verilog-2001, SystemVerilog chỉ dùng trong testbench | Cả hai | Đang áp dụng |
| R14 | Kit Xilinx chưa chốt | Thấp | Luồng Vivado đã chạy với Artix-7, khi chốt chỉ đổi part và gán chân | Nguyên | Đang theo dõi |
| R15 | `make de2` lỗi Quartus 10200 ở `IF_ID_Reg.v` và `ID_EX_Reg.v` sau commit `fb0b577` (gộp `rst \|\| flush` vào khối `always @(posedge clk or posedge rst)`), nên luồng Quartus của cả nhóm đang hỏng | Cao | Đổi hai khối sang `always @(posedge clk)` (reset đồng bộ, hợp với `sys_rst` đồng bộ của SoC), mỗi file một dòng. Nguyên đã thử: `make test` PASS, Quartus và Vivado build được | Phát (`rtl/core`) | Đã sửa 26/10 (P-23, commit `9f9e66a`). Nguyên đã thử bản này trên Quartus và Vivado. Phát chạy lại `make de2` 26/10 (Quartus 13.0sp1 ở `D:\altera`, `QUARTUS=/mnt/d/altera/13.0sp1/quartus/bin64/quartus_sh.exe`) trên bản có cả P-09: biên dịch sạch, không còn lỗi 10200, 10.270 LE, Fmax 53,73 MHz |
| R16 | Dây ngắt hai lõi chưa nối vì lõi chưa có cổng: `timer0_irq`, `plic_irq`, `timer1_irq`, `app_irq_ext`, `master_data_err` | Trung bình | Khi P-09 xong, thêm cổng vào `RISCV_Core` và nối theo comment `TODO(P-09)` trong `SoC_Top.v`, mỗi dây một dòng, rồi viết test ngắt (P-14) | Phát (P-09), Nguyên (nối, test) | Đã nối 27/10 (P-14): `timer0_irq`, `plic_irq`, `app_irq_timer`, `app_irq_ext`. Còn `master_data_err` (access fault, để sau P-09) |
| R17 | CPU và DMA cùng dùng SHA-256, ghi chồng lên nhau sẽ cho hash sai | Thấp | DMA giữ SHA-256 khi `BUSY`, firmware chờ `DONE` rồi mới đọc hash hoặc dùng SHA. Đã ghi trong `SoC_Memory_Map.md` và `soc_map.h` | Phát (P-15) | Đã xử lý 29/10: `dma_sha256` kiểm SHA rảnh trước khi chạy, chờ `DONE`, timeout thì không đụng SHA |
| R18 | Thứ tự byte của golden hash: HAL và VP băm theo byte bộ nhớ (little-endian), còn CPU chép từng từ cho thông điệp big-endian | Trung bình | Golden của firmware thật là `sha256sum` của `.bin`, băm bằng DMA với `SWAP = 1` (khớp HAL, VP và `sha256sum`). `mkhex.py` giữ hai golden để test cả hai kiểu | Phát (P-13, P-16), Nguyên | Đã thống nhất, ghi trong mục 4 của `Project_Status.md`. Firmware băm bằng DMA `SWAP = 1` từ 29/10 (P-15) |

## 9. Các điểm đã chỉnh so với Google Doc (24/10)

1. **I-02 (header địa chỉ firmware):** tab "Tổng quan" mục 8 ghi Phát giữ, sheet ghi Nguyên chủ trì → theo sheet.
2. **Cách tạo file hex:** các ghi chú "Đề xuất 24/10" ghi `od -tx4` ra `fw/build/secure_boot.hex`, còn repo dùng CMake + `objcopy --verilog-data-width=4` ra `firmware_imem.hex` / `firmware_dmem.hex` → theo repo.
3. **Bộ nhớ:** ghi chú Tuần 8/11 ở tab gốc nói ROM đọc tổ hợp (distributed ROM) và "cần Phát thêm stall ở IF nếu chuyển BRAM". Repo đã chuyển sang đọc đồng bộ cạnh xuống (`ad42ec7`), lõi không phải sửa → bỏ việc thêm stall.
4. **"Đề xuất 24/10 (chưa merge)" và "Còn chờ Phát P1–P3"** ở tab gốc và tab Review đã lỗi thời. Các đề xuất đã vào `main` (`459f4fe`…`bb8288a`), P1–P3 xong ở commit `33c0d1e`.
5. **Lịch Tuần 8:** bổ sung P-08 (UVM SHA ngẫu nhiên, trễ từ Tuần 7) và việc cập nhật tài liệu. Tuần 9 bổ sung đổi `linker.ld` (I-03), Tuần 10 bổ sung target `app_firmware.hex` + sinh golden hash (I-04). Các việc này có trong sheet nhưng thiếu trong lịch.
6. **Mốc M1 (01/11)** có trong sheet nhưng thiếu ở mục "Mốc chính" → bổ sung.
7. **Kết quả đo:** bổ sung TB đơn vị, HAL, UVM. WNS Artix-7 ngày 24/10 ghi chính xác +3,174 ns theo báo cáo khi đó (báo cáo trong `fpga/reports/` đã thay bằng bản 25/10: +2,891 ns).
8. **SoC_Top_tb:** tab gốc (Tuần 9) và tab Review ghi "hash đúng → nhả reset App, hash sai → App giữ reset", thực tế firmware thử trong `dv/sw/mkhex.py` chỉ băm chuỗi "abc" rồi luôn nhả App. Kịch bản đúng/sai trên ảnh App hiện chỉ có ở VP → đưa vào việc test firmware toàn SoC (Tuần 11).
9. **Thay đổi phạm vi so với kế hoạch gốc (giữ theo bản hợp nhất):** việc "bơm dữ liệu nhiễu vào UVM khi chạy Full SoC" (Tuần 10 gốc) được thay bằng UVM agent APB + scoreboard SHA, còn code Application cho App Core chuyển từ Tuần 12 lên Tuần 10.

**Đã sửa trong sheet 25/10:** N-09 ghi lại WNS +3,17 ns (đo 24/10), N-20 đưa hạn 08/11 về đúng cột Hạn và sửa công thức cảnh báo bị lỗi `#REF!`, N-18 đánh dấu xong. **Phát đã xác nhận 25/10:** P-07 thêm sơ đồ datapath vào `docs/spec/Core_Datapath.md` (ngày xong 25/10), P-12 sheet đổi sang Xong.
