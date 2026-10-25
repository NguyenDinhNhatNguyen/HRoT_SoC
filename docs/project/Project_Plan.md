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
| I-03 | 08/11 | Địa chỉ golden hash trong Boot ROM (cổng đọc dữ liệu) + đổi `linker.ld` đặt `.rodata` vào đó | Cả hai |
| I-04 | 15/11 | Target CMake `app_firmware.hex` + bước sinh golden hash (băm cả 4 KB ROM App) | Phát |
| I-05 | — | SHA-256: 66 chu kỳ START→DONE, offset trống OKAY/0, ngoài slave DECERR (đã chốt, RTL khớp từ 25/10) | Nguyên |
| I-06 | — | UART `BAUD_DIV` mặc định 26 = 115200 baud @ 50 MHz (đã chốt) | Nguyên |
| I-07 | — | Chỉ commit trên `main`, chạy trong WSL, mô phỏng Questa, `make test` PASS trước khi push (đã chốt). Tới khi xong P-22: các mục còn lại PASS, chạy `make test < /dev/null` | Cả hai |

## 5. Mốc

| Mốc | Ngày | Nội dung |
| --- | --- | --- |
| M1 | 01/11 | Phát chốt cổng ngắt lõi (I-01), TIMER0 + WDT xong. ✅ Xong 25/10 (TIMER0, WDT xong, I-01 đã chốt), còn P-09 để nối ngắt vào lõi |
| M2 | 22/11 | **RTL FREEZE** — toàn SoC biên dịch sạch Questa/Quartus/Vivado, `make test` PASS, 50 MHz |
| M3 | 29/11 | Demo secure boot trên DE2 (LED + log UART) |
| M4 | 06/12 | Báo cáo PPA FPGA + functional coverage |
| M5 | 13/12 | PPA ASIC (Genus/Innovus) + so sánh FPGA–ASIC |
| M6 | 20/12 | GitHub + tài liệu hoàn chỉnh |
| M7 | 27/12 | Báo cáo + slide + bảo vệ thử |

## 6. Tình trạng tới 25/10 (cuối Tuần 7)

**Đã xong**
- Nguyên: workspace + testbench SV, Forwarding/Hazard, AXI4-Lite master/slave/interconnect (WSTRB, DECERR, SLVERR), SHA-256 đầy đủ (đúng vector NIST), Dual-Port ROM + cách ly Boot ROM/ROM App, SoC_Top + test secure boot đầu–cuối, cầu AXI→APB, SYSCSR (thay Reset Controller), UART0, GPIO0, bộ nhớ đồng bộ, luồng Quartus/Vivado, VP SystemC chạy HAL thật, Makefile gốc. Ngày 25/10 thêm: TIMER0 kiểu CLINT, WDT, sửa alias SHA-256, cấu trúc lại repo, comment và log test tiếng Anh.
- Phát: lõi 5 tầng + hazard, test ISA 41 CHECK phủ đủ 37 lệnh RV32I tính toán, nhảy, load/store (có/không stall), load/store byte/half (`data_wstrb`), 11 TB đơn vị tự kiểm tra, khung UVM AXI4-Lite (có reset giữa giao dịch), HAL SHA-256 + test plan, toolchain CMake + linker + crt0, UVM SHA-256 ngẫu nhiên + corner case trên DUT thật (P-08, 25/10).

**Kết quả đo**
- Mô phỏng (Questa, 25/10): `RISCV_Core_tb` 44/44, chương trình ISA PASS (có/không stall), hazard 0 lỗi, APB 42/42 (thêm TIMER/WDT), `SoC_Top_tb` PASS (firmware thử băm "abc" bằng SHA phần cứng, đọc ROM App qua cổng B, kiểm SLVERR/DECERR, UART, GPIO rồi nhả App, **chưa băm image App, chưa có kịch bản image bị sửa trên RTL**), HAL 9.692 test host PASS, VP image đúng/sai PASS, `sha256_alias_test` PASS. 11 TB đơn vị và UVM PASS trên Verilator nhưng đang FAIL trên Questa do lỗi script (xem `Project_Status.md` mục 4).
- DE2 (EP2C35, 25/10): 7.885 LE (24%), 3.694 thanh ghi, 135 Kbit M4K (28%), Fmax 55,17 MHz, đạt 50 MHz. Trước khi thêm TIMER/WDT là 7.453 LE, 54,9 MHz.
- Artix-7 xc7a35t (thử, 25/10): 3.360 LUT (16%), 1 BRAM, WNS +2,891 ns @ 50 MHz, đạt. Trước đó là 3.125 LUT, WNS +3,174 ns.

**Còn thiếu hoặc trễ**
- Ngắt trong lõi (Zicsr, irq): PLIC/TIMER cần để dùng ngắt (vẫn chạy được bằng polling). `timer0_irq` đã có phía SoC, chờ P-09 để nối vào lõi.
- PLIC-lite, Mailbox, bus ngoại vi của thế giới App, Boot Guard/Zeroization, Secure DMA, tường lửa AXI.
- Firmware secure boot thật (`fw/secure_boot/main.c` vẫn là mẫu, `SoC_Top_tb` đang chạy firmware thử viết tay `dv/sw/mkhex.py`). Golden hash đang nằm trong RAM ghi được.
- Đổ board (chân DE2 đã đối chiếu xong 25/10, N-18: 52/52 chân khớp DE2 User Manual v1.3).

## 7. Lịch Tuần 8 → 16

| Tuần | Nguyên | Phát |
| --- | --- | --- |
| **8** (26/10–01/11) — Nền tảng + TIMER/WDT | ~~TIMER0 kiểu CLINT~~, ~~WDT~~, ~~cập nhật `SoC_Memory_Map.md`~~, ~~đối chiếu chân DE2 (N-18)~~ (xong 25/10). ~~VP băm cả 4 KB ROM App (N-33)~~, ~~header địa chỉ firmware `soc_map.h` (I-02, N-34)~~ (xong 25/10). **Kéo lên từ Tuần 9:** cổng đọc dữ liệu Boot ROM (N-21), Boot Guard + Zeroization (N-20), PLIC-lite (N-19) | Zicsr + trap máy (`mtvec`, `mepc`, `mcause`, `mstatus.MIE`, `mie`/`mip`, `ecall`/`mret`) + cổng `irq_timer`/`irq_ext` (I-01, **chặn nối ngắt TIMER/PLIC**), ~~UVM sequence ngẫu nhiên cho SHA-256 (P-08)~~ (xong 25/10), sửa 2 lỗi script Questa (P-22, đã sửa 25/10, chờ chạy trên Questa), dọn `dv/tb` sang `dv/env`, `dv/agents`, driver UART/GPIO trong `fw/hal` dùng `soc_map.h`, ~~cập nhật `Project_Status.md` (P-12)~~ (xong 24/10) |
| **9** (02–08/11) — Ngắt + Boot Guard | Hoàn tất N-19, N-20, N-21 (nối `irq_ext` khi có I-01), VP thêm mô hình UART0, TIMER0, WDT cho firmware (N-32), `SoC_Top_tb` băm cả image App và thêm kịch bản image bị sửa trên RTL (N-35). ~~Báo lỗi bus AXI qua `SYSCSR.BUS_ERR` (N-36)~~ (xong 25/10) | Firmware secure boot thật (HAL + log UART + golden trong Boot ROM + LOCK khi sai), chạy VP rồi RTL, đổi `linker.ld` đặt `.rodata` vào Boot ROM (I-03), test assembly ngắt timer/external |
| **10** (09–15/11) — DMA, tường lửa, thế giới App | Secure DMA (ROM App → SHA theo block) + bus Secure 2 master (arbiter) + tường lửa AXI ở cổng DMA, bus APB của App (UART1, GPIO1, TIMER1) + Mailbox 2 chiều | Firmware dùng DMA, firmware App demo (Mailbox, LED, UART) + target CMake `app_firmware.hex` + bước sinh golden hash băm cả 4 KB (I-04), UVM agent APB + scoreboard SHA (golden model DPI từ `sha256_ref.c`) |
| **11** (16–22/11) — Tích hợp, **RTL FREEZE 22/11** | Regression toàn SoC, đạt 50 MHz trên DE2 và Xilinx, cập nhật VP theo RTL, đóng băng RTL | Test firmware toàn SoC (boot đúng/sai, ngắt, DMA), regression UVM |
| **12** (23–29/11) — Đổ board | Nạp DE2 qua USB-Blaster, demo secure boot bằng LED + log UART, chốt kit Xilinx, gán chân, nạp | Covergroup + thu coverage, sửa lỗi phát sinh khi chạy board |
| **13** (30/11–06/12) — PPA FPGA + coverage | Báo cáo PPA (Fmax, LE/LUT, FF, M4K/BRAM, công suất) cho Quartus và Vivado, SDC bàn giao ASIC | Báo cáo functional coverage, Synthesis mức cổng (Genus) |
| **14** (07–13/12) — ASIC + sơ đồ | Sơ đồ khối hệ thống, VP, testbed FPGA, tài liệu chạy VP/FPGA | Innovus, so sánh PPA FPGA–ASIC |
| **15** (14–20/12) — GitHub + tài liệu | Cả hai: README, cấu trúc thư mục, hướng dẫn build/sim/FPGA/VP, dọn RTL | |
| **16** (21–27/12) — Báo cáo + bảo vệ thử | Cả hai: báo cáo tổng kết, slide (4 luồng: RTL/HRoT, VP, DV/coverage, PD/PPA), tập phản biện với thầy | |

## 8. Rủi ro và cách xử lý

Cập nhật 25/10/2026, 15 rủi ro. Cột "Phụ trách" là người xử lý, việc của Phát ở đây là **đề xuất**, Phát xác nhận lại.

| # | Rủi ro | Mức | Hướng xử lý | Phụ trách | Trạng thái |
| --- | --- | --- | --- | --- | --- |
| R1 | `make test` không PASS được trên Questa 10.2c (timeout UVM lệch đơn vị, `run_unit.do` dừng sau `ALU_tb`), nên quy ước I-07 đang không thực hiện được | Cao | Sửa `base_test.svh` (tính timeout theo `ns` cố định hoặc so với `$time` trong cùng package) và bỏ `-onfinish stop` hay thay bằng `onbreak {resume}` trong `run_unit.do`, kiểm tra lại trên Questa. Tạm thời chạy `make test < /dev/null` và chấp nhận 5 mục FAIL đã biết | Phát (P-22) | Đã sửa 25/10 (watchdog trong package, mỗi TB đơn vị một `vsim`, stdin `/dev/null`), chờ `make test` trên Questa |
| R2 | Fmax DE2 chỉ dư khoảng 9% (54,69 MHz, 8.011 LE, đo 25/10 sau N-36), cách ngưỡng 52 MHz khoảng 5%. Đường găng lần đo 55,17 MHz: lõi App, `ID_EX.Rs1_EX` → forwarding → so sánh nhánh → `PC` (slack 1,875 ns), `fpga/reports/` chưa có báo cáo của lần đo 54,69 MHz | Trung bình | Lõi: nếu Fmax tụt dưới 52 MHz thì tách đường quyết định nhánh (đăng ký kết quả so sánh, chấp nhận thêm 1 chu kỳ phạt khi nhảy) hoặc tính sẵn đích nhảy ở ID. Uncore: mỗi khối mới phải giữ slack ≥ 2 ns, đo lại DE2 sau mỗi khối | Phát (lõi), Nguyên (đo, uncore) | Đang theo dõi |
| R3 | Ngắt phụ thuộc cổng `irq_timer`/`irq_ext` của lõi (I-01, hạn 01/11), mốc M1 có thể trễ | Trung bình | Phía SoC đã có `timer0_irq`, PLIC-lite làm và test độc lập trước (N-19). Nếu I-01 trễ, firmware dùng polling, demo không bị chặn | Phát (I-01), Nguyên | Đang làm |
| R4 | Golden hash nằm trong RAM ghi được, chưa đúng mô hình Root of Trust | Cao | Kéo N-21 (cổng đọc dữ liệu Boot ROM) lên Tuần 8, Phát đổi `linker.ld` theo I-03 ở Tuần 9 | Nguyên, Phát | Kéo lên Tuần 8 |
| R5 | VP băm theo độ dài image, còn I-04 chốt băm cả 4 KB ROM App, hai bên ra golden khác nhau | Trung bình | VP băm đủ 4 KB (N-33, diff 3 dòng đã có) | Nguyên | Đã xong 25/10 (N-33, commit `a946e2a`) |
| R6 | Firmware secure boot (P-13) phải chạy trên VP trước RTL nhưng VP chưa có UART, TIMER, WDT | Trung bình | Thêm mô hình UART0 (in log ra console), TIMER0, WDT vào VP ở Tuần 9 (N-32) | Nguyên | Đã lên lịch |
| R6b | Firmware không biết khi bus Master trả SLVERR/DECERR vì `AXI4_Lite_Master` bỏ qua BRESP/RRESP | Trung bình | Thêm `SYSCSR.BUS_ERR` và `BUS_ERR_ADDR` (N-36). Access fault qua trap làm sau P-09 | Nguyên | Đã xong 25/10 |
| R7 | Secure boot mức RTL mới kiểm image đúng, firmware thử chỉ băm "abc" | Trung bình | `SoC_Top_tb` băm cả 4 KB ROM App bằng SHA phần cứng, so với golden do `mkhex.py` tính bằng `hashlib`, chạy thêm lần với image bị sửa và kiểm App bị giữ reset (N-35) | Nguyên | Đã lên lịch |
| R8 | Bộ nhớ đọc ở cạnh xuống không hợp với SRAM macro ASIC (Tuần 13–14) | Trung bình | Nguyên thêm tham số chọn bộ nhớ đồng bộ cạnh lên cho bản ASIC, Phát thêm tín hiệu chờ (`ready`) ở IF/MEM để lõi chịu được 1 chu kỳ trễ. Chốt cách làm trước Tuần 12 | Nguyên, Phát | Đề xuất |
| R9 | Xuống dòng lẫn LF và CRLF giữa hai máy, diff dễ bị nhiễu | Thấp | Thêm `* text=auto eol=lf` vào `.gitattributes` và `git add --renormalize .` trong một commit riêng, làm lúc cả hai đã push hết | Nguyên | Chờ thời điểm |
| R10 | WSL của Phát chưa có `make`, `gcc`, toolchain RISC-V | Trung bình | Cài `build-essential`, `python3`, `gcc-riscv64-unknown-elf`, SystemC trước 01/11 | Phát | Đã xong 25/10: `build-essential`, `cmake`, `gcc-riscv64-unknown-elf` 14.2 (có multilib `rv32i/ilp32`), SystemC 2.3.4 build từ mã nguồn ở `/usr/local/systemc-2.3.4`. `make fw`, `make vp`, HAL host test PASS. Còn QuestaSim |
| R11 | Comment trong `fw/linker.ld` còn ghi `0x4000_0000` là Reset Controller và chờ Nguyên xác nhận RAM | Thấp | Nguyên xác nhận: RAM `0x1000_0000` 4 KB đúng với `SoC_Top`, `0x4000_0000` nay là SYSCSR. Phát sửa comment khi đổi `linker.ld` cho I-03 | Phát | Đã sửa 25/10 (comment `linker.ld` ghi SYSCSR, RAM `0x1000_0000` 4 KB đã chốt) |
| R12 | Bảng chân DE2 đối chiếu theo manual v1.3, Terasic đã có bản 1.6 | Thấp | Xem lại bảng chân trong bản 1.6 trước khi nạp board (Tuần 12) | Nguyên | Đã lên lịch |
| R13 | Quartus II 13.0sp1 chỉ hỗ trợ một phần SystemVerilog | Thấp | RTL tổng hợp giữ Verilog-2001, SystemVerilog chỉ dùng trong testbench | Cả hai | Đang áp dụng |
| R14 | Kit Xilinx chưa chốt | Thấp | Luồng Vivado đã chạy với Artix-7, khi chốt chỉ đổi part và gán chân | Nguyên | Đang theo dõi |

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
