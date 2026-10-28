# Trạng thái dự án — HRoT SoC

> Cập nhật: 26/10/2026 (Nguyên làm xong phần RTL của mình tới RTL freeze). Tiến độ chi tiết theo từng việc nằm ở [Google Sheet "HRoT_SoC — Tiến độ Đồ án 2"](https://docs.google.com/spreadsheets/d/13jJj9UP1Cxr8ZNFqzQnNTaiulD2_HaKOWAONfCnZnU4/edit) (tab Tổng hợp, Tiến độ, Mốc & Giao diện). Sheet là nguồn chính thức, khi lệch thì theo sheet. File này tóm tắt trạng thái kỹ thuật, sửa mỗi khi xong một mốc hoặc chốt một quyết định.

## 1. Tổng quan

- Toàn dự án 45/61 việc (74%): Nguyên 31/36, Phát 14/23. Ngày 26/10 Phát làm xong P-09, P-10, P-11, P-23. Ngày 26/10 Nguyên làm xong N-19…N-25, N-27, N-32 và N-35. Ngày 25/10 thêm 6 việc phát sinh (N-32…N-36, P-22), danh sách rủi ro và hướng xử lý ở `Project_Plan.md` mục 8. RTL FREEZE: **22/11/2026** (mốc M2).
- SoC biên dịch và chạy được: Master boot từ Boot ROM riêng, băm cả 4 KB ROM App bằng CPU và bằng Secure DMA (qua tường lửa), so với golden hash đọc từ Boot ROM, rồi nhả App qua SYSCSR, hoặc khóa App bằng Boot Guard và xóa RAM App khi hash sai. Bus APB Secure có SYSCSR, UART0, GPIO0, TIMER0, WDT, PLIC-lite, Mailbox và Secure DMA. Thế giới App có bus APB riêng với UART1, GPIO1, TIMER1 và Mailbox. `SoC_Top_tb` chạy cả ảnh đúng lẫn ảnh bị sửa trên RTL (firmware thử `dv/sw/mkhex.py`). Dây ngắt của hai lõi đã nối vào cổng `irq_timer`/`irq_ext` của lõi (P-14, 27/10, I-01), `SoC_Irq_tb` kiểm ngắt timer, PLIC và Mailbox trên cả hai lõi.
- FPGA (26/10, đo với lõi đã đổi reset đồng bộ ở `IF_ID_Reg` và `ID_EX_Reg`, xem mục 4): DE2 9.358 LE (28%), 4.390 thanh ghi, 135 Kbit M4K, Fmax 53,02 MHz. Artix-7 xc7a35t 5.530 LUT (27%), 4.092 FF, WNS +3,519 ns @ 50 MHz. Đường găng DE2 nằm trong lõi (`Rd_WB` → forwarding ở ID → `RD2_EX`, slack +1,14 ns), không có đường nào của uncore trong top. Báo cáo ở `fpga/reports/`. Lần đo mới nhất (DE2, 27/10, có P-09 và dây ngắt đã nối ở P-14): 10.509 LE (32%), Fmax 54,21 MHz. Số của mọi lần đo: [FPGA_Results.md](FPGA_Results.md).
- Firmware Secure Boot thật có từ 27/10 (P-13): `fw/secure_boot/secure_boot.c` băm cả 4 KB ROM App bằng Secure DMA (`SWAP` + `PAD`, từ 29/10, P-15, trước đó bằng HAL), so golden ở `0xFE0` trong Boot ROM, nhả App hoặc khóa bằng Boot Guard, log qua UART0, kết quả ra LED GPIO0. Chạy trên VP (`vp_sim --fw`) và trên RTL (`SoC_Fw_tb`). `SoC_Top_tb` vẫn dùng firmware thử viết tay (`dv/sw/mkhex.py`).

Kết quả kiểm tra gần nhất trên Questa (`make test`, 26/10, toàn bộ PASS):

| Nhóm | Kết quả |
| --- | --- |
| Lõi: 11 TB đơn vị, chương trình ISA, `RISCV_Core_tb`, hazard | PASS (11 TB đơn vị và UVM chạy được trên Questa sau khi Phát sửa P-22) |
| UVM AXI4-Lite (full, reset giữa giao dịch) và UVM SHA-256 (full, có reset) | PASS |
| HAL SHA-256 trên host | PASS |
| Ngoại vi APB (SYSCSR gồm BUS_ERR và Boot Guard, GPIO, UART, TIMER, WDT, PLIC-lite, Mailbox) | PASS, 79/79 check |
| SoC secure boot, ảnh đúng | PASS: hash của CPU và của DMA (SWAP bật và tắt) khớp golden trong Boot ROM, PLIC và tường lửa đúng, App chạy |
| SoC secure boot, ảnh bị sửa 1 bit (`+TAMPER`) | PASS: Boot Guard khóa App kể cả khi firmware cố nhả lại, RAM App về 0, không có yêu cầu DMA nào ra ngoài cửa sổ cho phép |
| VP (ảnh đúng và ảnh bị sửa) | PASS (UART log, WDT, Boot Guard, DMA, tường lửa) |
| `sha256_alias_test` (chạy riêng) | PASS |

Trên Verilator (Phát chạy, 23–25/10): UVM AXI4-Lite 15/15 PASS. UVM SHA-256 trên DUT thật: KAT, CTL (khoảng 960 check), RAND 40 message × 3 seed (khoảng 4.300–4.900 check), FULL, reset giữa message × 3, tất cả PASS, 0 lỗi.

Ngày 26/10 (Phát chạy bằng iverilog và Verilator, **chưa chạy trên Questa**): sau P-09, P-10, P-11, P-23 thì 11 TB đơn vị, `RISCV_Core_tb`, hazard, chương trình `core_isa_test` và `core_trap_test` (có và không `bus_stall`), `SoC_Top_tb` (ảnh đúng và `+TAMPER`), UVM 9 test, `drv_host_test` 49/0, HAL 9.692/0, `make fw`, `make vp` đều PASS.

## 2. Phần của Phát

| ID | Việc | Hạn | Trạng thái |
| --- | --- | --- | --- |
| P-01…P-06 | Lõi 5 tầng, hazard + test ISA, khung UVM, HAL + test plan, toolchain, load/store byte/half | ≤ 25/10 | ✅ Xong |
| P-07 | Sơ đồ khối datapath 5 tầng trong `docs/` | 13/09 | ✅ Vẽ từ Tuần 1, đưa vào repo 25/10: `docs/spec/Core_Datapath.md` + hình, có bảng đối chiếu RTL và 5 điểm nên sửa khi vẽ lại cho báo cáo (commit `fb0b577`) |
| P-08 | UVM sequence ngẫu nhiên cho SHA-256 (corner case) | 25/10 | ✅ Xong 25/10 (commit `bb59f25`). `sha256_alias_test` PASS sau khi Nguyên sửa RTL 25/10 |
| **P-09** | Zicsr + trap máy + cổng `irq_timer`/`irq_ext` | 01/11 | ✅ Xong 26/10 (commit `9f9e66a`): `Sys_Decoder`, `CSR_Unit`, `Pipe_Reg`, cổng `irq_timer`/`irq_ext` theo I-01 (xem `Dev_Guide.md` mục 2). Test `core_trap_test` (CSR, ECALL, EBREAK, lệnh không hợp lệ, MRET, ngắt timer/external) PASS có và không `bus_stall`, bắt được 9/9 lỗi cài thử. **Còn: Nguyên nối dây ngắt trong `SoC_Top.v` theo comment `TODO(P-09)` (R16)**. Access fault qua `data_err` (mcause 5/7) để sau P-09 như ghi chú trên sheet |
| P-10 | Dọn `dv/tb` sang `dv/env`, `dv/agents` | 01/11 | ✅ Xong 26/10 (commit `9f9e66a`): `tb_top.sv`, `tb_sha256_top.sv` sang `dv/env/`, `axi4_lite_slave_model.sv` sang `dv/agents/`, sửa `sim/run_uvm.do`. `dv/tb/` chỉ còn TB trực tiếp |
| P-11 | Driver UART/GPIO theo `SoC_Memory_Map.md` | 01/11 | ✅ Xong 26/10 (commit `9f9e66a`): `fw/hal/uart.h`, `gpio.h` (một driver cho cả UART0/GPIO0 và UART1/GPIO1), thư viện `hal_drivers` trong CMake, test host `drv_host_test` 49/0 chạy trong `make -C fw/hal/test test` |
| P-12 | Cập nhật tài liệu này + `Dev_Guide.md`, thêm test của Phát vào `make test` | 01/11 | ✅ Xong (làm 24/10, vào `main` cùng commit P-08 `bb59f25`), sheet đã cập nhật 25/10 |
| P-23 | Sửa lỗi Quartus 10200 ở `IF_ID_Reg.v` và `ID_EX_Reg.v`: đổi `always @(posedge clk or posedge rst)` thành `always @(posedge clk)` (mục 4, R15) | 01/11 | ✅ Xong 26/10 (commit `9f9e66a`). Chạy lại iverilog: TB đơn vị, lõi, SoC (ảnh đúng và `+TAMPER`) PASS. `make de2` trên máy Phát 26/10 (bản có cả P-09): biên dịch sạch, không còn lỗi 10200, DE2 10.270 LE (31%), 4.840 thanh ghi, Fmax 53,73 MHz, đường găng vẫn trong lõi (`Rd_WB` → forwarding ở ID → `RD1_EX`, slack +1,39 ns) |
| P-22 | Sửa 2 lỗi script trên Questa 10.2c (mục 4) | 01/11 | ✅ Xong: Phát sửa 25/10 (commit `fb0b577`), Nguyên chạy `make test` trên Questa 26/10, 11 TB đơn vị và 4 test UVM PASS |
| P-13 | Firmware secure boot thật (HAL + UART + golden + LOCK), chạy VP rồi RTL | 08/11 | ✅ Xong 27/10 (`c739654`): `fw/secure_boot/secure_boot.c` theo đúng ghi chú (BUS_ERR → log, giữ App, xóa bit0. Golden băm đủ 4 KB ROM App). `linker.ld` đặt `.rodata` vào Boot ROM, golden ở `0xFE0` (I-03). Firmware build `-Os` (3,5/4 KB ROM). Test: `sb_host_test` 30/0 (8 nhánh, gồm lỗi bus, SHA hỏng, LOCK không xong), VP `--fw` ảnh đúng và bị sửa PASS, `SoC_Fw_tb` ảnh đúng và `+TAMPER` PASS |
| P-14 | Test assembly ngắt timer/external | 08/11 | ✅ Xong 27/10 (`c739654`): nối 4 dây ngắt trong `SoC_Top.v` (Phát làm, đã báo Nguyên). `SoC_Irq_tb` + `soc_irq_master.S`, `soc_irq_app.S`: TIMER0, GPIO0 qua PLIC, MEI trước MTI, Mailbox hai chiều, TIMER1. Master 5 ngắt, App 2 ngắt, PASS. Tháo từng dây hoặc đảo ưu tiên đều làm test FAIL |
| P-15 | FW dùng Secure DMA | 15/11 | ✅ Xong 29/10: driver `fw/hal/dma.c` (`dma_sha256`: kiểm DMA và SHA rảnh, chạy với `PAD`, polling có giới hạn và nghỉ giữa các lần đọc, xóa `DONE`, báo lỗi tường lửa, lỗi bus, timeout). Secure Boot băm ROM App bằng DMA `SWAP = 1`, khớp golden ở `0xFE0`. CPU không còn đọc ROM App, firmware còn 3.320/4.064 byte. Test: `sb_host_test` 63/0 (thêm tường lửa, DMA không xong, DMA hoặc SHA đang bận, bắt 10/10 lỗi cài thử), VP `--fw` PASS, `SoC_Fw_tb` ảnh đúng và `+TAMPER` PASS (DMA chạy 1 lần, 17.026 chu kỳ, CPU tự băm mất 34.143) |
| P-16, P-17 | FW App + `app_firmware.hex` + sinh golden hash · UVM agent APB + scoreboard SHA (DPI) | 15/11 | Chưa làm |
| P-18…P-21 | Test toàn SoC + regression UVM · coverage · Genus · Innovus + so sánh PPA | 22/11 → 13/12 | Chưa làm |

## 3. Giao diện Nguyên ↔ Phát

| ID | Nội dung | Hạn | Trạng thái |
| --- | --- | --- | --- |
| I-01 | Cổng ngắt của lõi: `irq_timer`, `irq_ext`: đầu vào mức cao, đồng bộ `clk`, giữ mức tới khi nguồn tự xóa (TIMER0: ghi `mtimecmp`, PLIC: claim/complete), lõi không bắt cạnh → `mip.MTIP` (bit 7) / `mip.MEIP` (bit 11), ưu tiên MEI > MTI. Dự trữ cho sau P-09: `data_err` mức cao cùng chu kỳ với `resp_valid` (nối `err_valid` của `AXI4_Lite_Master`) → access fault `mcause` 5 (load) / 7 (store), `mtval` = địa chỉ | 01/11 | ✅ **Đã chốt 25/10** (Phát). Lõi có cổng từ P-09 (26/10, commit `9f9e66a`), nối trong `SoC_Top` từ 27/10 (P-14) |
| I-02 | Header địa chỉ firmware theo `SoC_Memory_Map.md`, đổi map phải báo trước | 01/11 | Nguyên |
| I-03 | Địa chỉ golden hash trong Boot ROM (cổng đọc dữ liệu) + đổi `linker.ld` đặt `.rodata` vào đó | 08/11 | ✅ Xong 27/10: `.rodata` trong Boot ROM, golden ở `0xFE0` (32 byte cuối ROM, `SB_GOLDEN_ADDR`) |
| I-04 | Target CMake `app_firmware.hex` + bước sinh golden hash (băm **cả 4 KB** ROM App) | 15/11 | Phát |
| I-05 | SHA-256: 66 chu kỳ START→DONE, offset trống OKAY/0, ngoài slave DECERR | — | ✅ Đã chốt, RTL đã khớp từ 25/10 |
| I-06 | UART `BAUD_DIV` mặc định 26 = 115200 baud @ 50 MHz | — | ✅ Đã chốt |
| I-07 | Chỉ commit trên `main`, chạy trong WSL, mô phỏng Questa, `make test` PASS trước khi push | — | ✅ Đã chốt |

Các lỗi SoC/uncore liệt kê ở bản trước (SoC không compile, Master fetch ROM App, ROM đọc đồng bộ, `bus_stall` trễ, thiếu WSTRB, SHA chưa băm, Reset Controller treo, VP thiếu `sc_main`…) **đều đã được Nguyên sửa** trong các commit `459f4fe`…`bb8288a`.

## 4. Điểm cần lưu ý

- **Việc của Nguyên:** N-33 (VP băm cả 4 KB ROM App), N-34 (`fw/hal/soc_map.h`), N-36 (`SYSCSR.BUS_ERR`) xong 25/10. Ngày 26/10 xong N-19 (PLIC-lite), N-20 (Boot Guard + Zeroization), N-21 (cổng đọc dữ liệu Boot ROM ở `0x0000_0000`), N-22 (Secure DMA + một master AXI dùng chung cho CPU và DMA), N-23 (tường lửa DMA), N-24 (bus APB thế giới App với UART1, GPIO1, TIMER1), N-25 (Mailbox), N-27 và N-32 (VP có Boot ROM, UART0, TIMER0, WDT, Boot Guard, DMA), N-35 (`SoC_Top_tb` băm image App, thêm ảnh bị sửa). N-26 (đóng băng RTL 22/11): phần của Phát (P-09, P-23) xong 26/10, còn nối dây ngắt trong `SoC_Top`. N-18 xong: 52/52 chân trong `fpga/intel_de2/de2_pins.tcl` khớp bảng chân của DE2 User Manual v1.3.
- **Lỗi Quartus 13 trong lõi (Nguyên phát hiện 26/10, Phát sửa cùng ngày ở commit `9f9e66a`, P-23):** commit `fb0b577` gộp `if (rst || flush)` vào khối `always @(posedge clk or posedge rst)` của `IF_ID_Reg.v` và `ID_EX_Reg.v`. Quartus báo lỗi 10200 ("cannot match operand(s) in the condition to the corresponding edges") nên `make de2` không chạy được. Đề xuất đổi hai khối đó sang `always @(posedge clk)`, reset đồng bộ, hợp với `sys_rst` đồng bộ của SoC. Nguyên đã thử: `make test` PASS, Quartus và Vivado build được, số đo ở trên là của bản này.
- **Thứ tự byte của golden hash (I-04):** CPU chép từng từ vào SHA-256 nên thông điệp là các byte big-endian của từng từ. Secure DMA có bit `SWAP`: bật thì đảo byte từng từ, digest bằng `sha256sum` của file `.bin` (little-endian), cũng là kết quả của HAL và VP. Golden của firmware thật là `sha256sum` của `.bin`, băm bằng DMA với `SWAP = 1` (firmware làm vậy từ 29/10, P-15). `dv/sw/mkhex.py` giữ cả hai golden trong Boot ROM để test.
- **DMA và SHA-256:** khi DMA `BUSY` thì nó giữ SHA-256, firmware chờ `DONE` rồi mới đọc kết quả hoặc dùng SHA. Từ 29/10 `dma_sha256` làm đúng vậy, khi DMA không xong thì không đụng SHA nữa và giữ App trong reset (P-15).
- **Cấu trúc repo đổi từ 25/10:** `doc/` thành `docs/` (chia `spec`, `verification`, `guides`, `project`), `rtl/uncore/` tách thành `rtl/bus`, `rtl/periph`, `rtl/mem`, `rtl/crypto`, `syn/` thành `fpga/` (thêm `fpga/reports`), `mkhex.py` sang `dv/sw/`. Phải `git pull` trước khi sửa tiếp.
- **Lỗi RTL SHA-256 (P-08 phát hiện), đã sửa 25/10:** `SHA256_Wrapper` chỉ giải mã `addr[7:0]` trong khi `SoC_Top` cấp cửa sổ 64 KB, nên offset ≥ `0x100` bị alias vào thanh ghi thật. Wrapper giờ giải mã `addr[15:8] == 0`, `sha256_alias_test` PASS trên Questa (chạy với `+TEST_TIMEOUT_US=100000000`, xem mục dưới).
- **Ba lỗi khi chạy trên Questa 10.2c (Nguyên phát hiện 25/10, trên Verilator không gặp). Lỗi 1 và 2 Phát sửa 25/10, Nguyên chạy lại trên Questa 26/10 PASS (P-22):**
  1. Timeout UVM tính bằng `time'(real'(tmo_us) * 1us)` trong `dv/tests/base_test.svh` ra 1,6 µs thay vì 1600 µs, do lệch timescale giữa package và `uvm_pkg`. 4 test UVM trong `make test` chết vì `PH_TIMEOUT`.
  2. `vsim -onfinish stop` trong `sim/run_unit.do` làm macro dừng sau `ALU_tb` ở chế độ `-c`, chỉ 1/11 TB chạy. Chạy `make test` trong terminal thì Questa đứng chờ ở dấu nhắc `VSIM(paused)>` và cả regression bị treo. Tạm thời chạy `make test < /dev/null`.
     Cách sửa (25/10): `base_test.svh` bỏ `uvm_top.set_timeout()` (đối số bị đọc theo đơn vị thời gian của `uvm_pkg`, trên Questa là 1 ps theo `-t 1ps`) và dùng watchdog `#(timeout_us * 1us)` ngay trong package của test nên luôn đúng đơn vị. `regress.sh` chạy mỗi TB đơn vị bằng một tiến trình `vsim` riêng (`set UNIT <tb>`, cùng kiểu với `run_rtl.do`) và mọi lệnh `vsim` đọc stdin từ `/dev/null` nên không còn treo ở `VSIM(paused)>`.
  3. (Đã sửa, phía Nguyên) `sim/run_vp.sh` trước đây chỉ tìm thư viện ở `$SYSTEMC_HOME/lib-linux64`, nên link lỗi khi `SYSTEMC_HOME` trỏ tới bản 2.3.4 (thư viện nằm trong `lib/`). Script giờ thử cả hai.
- **Comment và chuỗi in ra của testbench viết bằng tiếng Anh** từ 25/10. File của Nguyên đã đổi, file của Phát đổi hết ngày 25/10 (commit `fb0b577`).
- **VP băm cả 4 KB ROM App** theo I-04 từ 25/10 (N-33, commit `a946e2a`).
- **Bộ nhớ đọc ở cạnh xuống** chạy tốt trên FPGA nhưng không hợp với SRAM macro khi làm ASIC (P-20/P-21). Cần phương án: thêm 1 tầng chờ ở IF/MEM, hoặc dùng flip-flop cho bộ nhớ nhỏ.
- **Golden hash đặt được trong Boot ROM từ 26/10 (N-21):** lệnh `lw` đọc được ROM ở `0x0000_0000` qua cổng B (chỉ đọc, ghi trả `SLVERR`). Từ 27/10 `linker.ld` đặt `.rodata` trong ROM và chừa `0xFE0`–`0xFFF` cho golden (P-13, I-03). Golden lúc này do TB (`fw/tools/golden.py`) hoặc VP ghi vào, bước tự sinh lúc build là I-04 (P-16).
- **Xuống dòng:** `.gitattributes` ép LF cho `*.sh`, `Makefile`, `*.tcl`. Nên thêm `* text=auto eol=lf` để file `.v/.sv/.c/.md` không bị đổi qua lại LF↔CRLF giữa hai máy.
- **WSL của Phát** đã cài `make`, `gcc`, `cmake`, toolchain RISC-V và SystemC 2.3.4 (25/10), chạy được `make fw`, `make vp` và test HAL. Chưa có QuestaSim, nên các lần chạy `make test` trên Questa do Nguyên làm.

## 5. Lỗ hổng so với lộ trình Tuần 16

- Kiểm chứng secure boot mức SoC với firmware thật (P-13, P-18): `SoC_Top_tb` kiểm cả ảnh đúng lẫn ảnh bị sửa nhưng bằng firmware thử viết tay. Từ 27/10 firmware C thật chạy trên RTL (`SoC_Fw_tb`), kịch bản lõi SHA hỏng mới kiểm trên host (`sb_host_test`).
- Hạ tầng coverage (P-19): covergroup, `+cover`, `vcover merge`, báo cáo. Monitor UVM cần ghi thời điểm và thứ tự AW–W.
- GLS (P-20): `RISCV_Core_prog_tb` dùng lại được (bọc phần dump thanh ghi bằng `ifndef GLS`), `RISCV_Core_tb` chỉ chạy RTL.
