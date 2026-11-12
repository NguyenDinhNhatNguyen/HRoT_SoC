# asic/

Điểm xuất phát cho luồng ASIC (Genus, Innovus) của Phát (P-20, P-21).

| File | Nội dung |
| --- | --- |
| `SoC_Top.sdc` | Khung SDC cho `SoC_Top`: một clock `clk`, false path cho các đầu vào bất đồng bộ, `set_output_delay` cho đầu ra |
| `ASIC_Top.v`, `ASIC_Top.sdc` | Top cấp chip bọc `SoC_Top` (Phát, 09/11): bộ đồng bộ reset bật bất đồng bộ, nhả đồng bộ 2 flop từ chân `rst_pad_n`, như `DE2_Top` làm trên FPGA. SDC đi kèm tính giờ `reset_system` bên trong (đã qua bộ đồng bộ), từ 12/11 theo tỉ lệ của Lab 01 và chỉ cần biến `CLK_PERIOD_NS`. Test: `dv/tb/ASIC_Top_tb.sv` (`set TB ASIC_Top_tb; do run_fw.do`), nằm trong `make test` từ 11/11 |
| `run_yosys.sh`, `yosys/` | Chạy thử Yosys + NanGate45 cho `SoC_Top` trong docker để lấy số sơ bộ (`make asic-yosys`). Bộ nhớ là black box (`yosys/mem_bb.v`) |
| `genus/` | Luồng Genus cho `ASIC_Top` với GPDK45, chỉ chạy trên server trường (`make asic-genus`, Phát, 12/11). Xem mục "Chạy Genus trên server trường" |

File này chưa có chu kỳ clock và độ trễ I/O, vì chúng phụ thuộc PDK mà Phát chọn. Giá trị đề xuất để bắt đầu (Phát, 09/11): `CLK_PERIOD_NS = 20` (50 MHz như bản FPGA, Yosys cho đường flop sang flop 4,0 ns nên còn dư nhiều) và `IO_DELAY_NS = 4` (khoảng 20% chu kỳ). Hai số này chốt lại khi chạy Genus với GPDK45 trên server trường. Đặt hai biến `CLK_PERIOD_NS` và `IO_DELAY_NS` trước khi `source`, nếu thiếu thì SDC báo lỗi. Cổng lấy từ `rtl/top/SoC_Top.v`. Từ 12/11 `ASIC_Top.sdc` không dùng `IO_DELAY_NS` nữa: độ trễ vào ra theo tỉ lệ chu kỳ của Lab 01 (xem mục "Chạy Genus trên server trường"). Các đầu vào được coi là bất đồng bộ theo ràng buộc FPGA (`fpga/intel/de2/constraints.sdc`), cần kiểm lại khi có vòng pad của ASIC, nhất là `reset_system` (top FPGA đồng bộ nó trước khi vào `SoC_Top`).

Số đo FPGA để so sánh nằm ở `docs/project/PPA_FPGA.md`.

## Quy tắc khi chạy luồng ASIC

Repo này công khai, nên file của PDK GPDK45 và mọi file dựng từ nó (`.gds`, `.spef`, netlist) không bao giờ được lên repo.

| Quy tắc | Chi tiết |
| --- | --- |
| Chỉ commit report văn bản | Report timing, diện tích, DRC dạng `.rpt` hoặc `.txt` |
| Không commit file dựng từ PDK | Thư viện cell (`.lib`, `.lef`, `.tf`, `.captbl`), netlist, `.spef`, `.sdf`, `.gds`, `.def`. `.gitignore` chặn các đuôi này trong toàn repo, cùng thư mục `PDK_GPDK45/` (từ 12/11). Không dùng `git add -f` |
| Thư viện GPDK45 chỉ ở server trường | Không chép về máy cá nhân hay repo. Đường dẫn đặt bằng biến `PDK_DIR` (mặc định `~/PDK_GPDK45`) |
| Genus, Innovus, Tempus chỉ chạy trên server trường | Docker `hpretl/iic-osic-tools` trên máy Nguyên là bộ công cụ mã nguồn mở (Yosys, OpenROAD, OpenSTA), không có các công cụ Cadence |
| Số từ Yosys với NanGate45 chỉ là sơ bộ | Ghi rõ là Yosys, thư viện mở, không dùng thay số Genus trong báo cáo chính thức |

## Số sơ bộ Yosys + NanGate45 (07/11/2026)

Chạy bằng `make asic-yosys` trong WSL, cần container `hpretl/iic-osic-tools` đang chạy (Yosys 0.70, OpenSTA 3.1.0). Thư viện NanGate45 đặt ở `~/eda/designs/nangate45/` (kiểm sha256, không chép vào repo). Kết quả văn bản nằm ở `asic/out_yosys/` (bị `.gitignore`).

| Chỉ số | Giá trị |
| --- | --- |
| Số cell (gồm flip-flop và 4 black box) | 41.060 |
| Diện tích logic (không gồm bộ nhớ) | 72.012 µm² |
| Flip-flop | 7.004 (`DFF_X1` 6.386, `DFFR_X1` 618) |
| Bộ nhớ (black box) | 4 khối 4 KB, tổng 16 KB, không có diện tích |
| Đường flop sang flop chậm nhất | 4,022 ns chu kỳ tối thiểu, F_max 249 MHz (clock 20 ns, slack +15,978 ns) |
| Vào sang flop, flop ra | 0,114 ns, 3,739 ns |

Hai lần chạy liên tiếp cho cùng diện tích và số flop.

Đường chậm nhất bắt đầu từ một flop reset nội bộ có fanout 893 và độ dốc 1,43 ns, nghĩa là cây reset chưa được buffer. Genus và Innovus sẽ buffer cây này (`ASIC_Top.sdc` có `set_max_fanout` cho việc đó), nên F_max thật có thể cao hơn. Đường reset thuộc loại recovery cũng đo ra slack +17,505 ns, không vi phạm.

Giới hạn, chỉ là xu hướng:

- NanGate45 là thư viện mở, không phải GPDK45, và Yosys khác Genus.
- Bộ nhớ là black box: không có diện tích bộ nhớ, đường đi qua bộ nhớ không được tính giờ, `Data_Memory` mất 32 cổng AND của `MemRead`. Diện tích ASIC thật phải cộng macro SRAM.
- SDC tối thiểu: độ trễ I/O bằng 0, không có `set_max_transition` hay `set_max_fanout`, không đặt dây, clock lý tưởng.
- 7.004 flip-flop nhiều hơn 4.925 thanh ghi của Quartus trên DE2. Phần lớn là file thanh ghi: một `Register_File` ra 1.024 flip-flop trong Yosys (đo riêng, `$_DFFE_PP_`), hai lõi là 2.048. Quartus đưa file thanh ghi vào M4K, nên bộ nhớ DE2 là 135.168 bit = 131.072 bit của 4 bộ nhớ cộng 4.096 bit (2 lõi, mỗi lõi 2 bản cho 2 cổng đọc). Chênh 7.004 − 4.925 = 2.079. Phần 31 flip-flop còn lại là do so khác điều kiện (Phát kiểm 09/11): Quartus tổng hợp `DE2_Top`, nơi `gpio1_i[7:6]` nối 0 và `uart1_rx` nối 1 nên các flop đồng bộ và flop phía sau thành hằng rồi bị bỏ, còn số Yosys ở trên là `SoC_Top` để chân tự do. Tổng hợp `DE2_Top` bằng Yosys cho 6.921 flip-flop, trừ 2.048 của file thanh ghi còn 4.873, ít hơn Quartus 52 (khoảng 1%), do hai công cụ gộp và nhân bản thanh ghi khác nhau.
- Yosys báo `check` không có vòng tổ hợp, không có chân nhiều driver hay chân không driver (0 vấn đề), không suy ra latch, và chỉ một cảnh báo: bộ nhớ `W` của SHA-256 (16 × 32 bit) thành thanh ghi.
- Không kiểm tương đương netlist với RTL. Tên flip-flop mất sau tổng hợp nên so sánh tự động không khớp được, và netlist cần mô hình hành vi của cell NanGate45 để mô phỏng. Việc này để cho LEC (Conformal) trên server trường.

## Macro SRAM của trường

Chân của `sram_2k_macro`: `CLK`, `CEN`, `WEN`, `A[9:0]`, `D[31:0]`, `Q[31:0]`. Một cổng địa chỉ, nghĩa là bộ nhớ một cổng đọc ghi (1RW) sâu 1.024 từ 32 bit (4 KB). 16 KB là 4 macro.

| Bộ nhớ của `SoC_Top` | Cổng cần | Ghép với macro |
| --- | --- | --- |
| `master_ram`, `app_ram` (`Data_Memory`) | 1 cổng đọc ghi, có `wstrb` | Vừa một macro, cần wrapper cho byte enable (macro không có chân tương ứng) |
| `boot_rom`, `app_rom` (`Dual_Port_ROM`) | 2 cổng đọc cùng lúc (A: lấy lệnh, B: AXI và Boot_Verifier) | Một macro chỉ có một cổng nên cần hai macro chứa cùng nội dung, hoặc chia thời gian truy cập (đổi thiết kế) |

Chưa biết diện tích, thời gian truy cập và lớp kim loại chắn của macro: các số này nằm ở `.lib`, `.lef` trên server. Macro cho `Q` ra ở chu kỳ sau, khác bộ nhớ đọc cạnh xuống hiện tại. Phát xác nhận 09/11: lõi đã chịu được trễ này theo I-09, không phải sửa thêm. Ở cổng lệnh uncore giữ `instr_stall = 1` trong chu kỳ chờ `Q`, ở cổng dữ liệu giữ `bus_stall = 1`. Phần còn lại thuộc uncore: wrapper byte enable cho RAM, và với ROM hai cổng thì chọn hai macro cùng nội dung hoặc một macro chia thời gian (lõi chờ bằng `instr_stall` khi cổng AXI hoặc Boot_Verifier đang đọc).

## Chạy Genus trên server trường (P-20)

Soạn 12/11/2026 cho riêng HRoT_SoC (top `ASIC_Top`, SDC `ASIC_Top.sdc`, kết quả trong `asic/`). Server trường, Genus 21.10, PDK ở `~/PDK_GPDK45`. Chạy lần đầu trên server ngày 12/11/2026, kết quả ở mục "Kết quả Genus" bên dưới.

| File | Nội dung |
| --- | --- |
| `genus/config.tcl` | Đường dẫn PDK. Mặc định `~/PDK_GPDK45`, đổi bằng biến môi trường `PDK_DIR`. Cấm `BUFX2`, `CLKBUFX2` (cell cao gấp đôi) |
| `genus/synth.tcl` | Tổng hợp `ASIC_Top`: kiểm trước tổng hợp, `syn_generic`, `syn_map`, `syn_opt` (effort medium), report. Cấm scan flop, giữ mọi flop để LEC khớp 1:1, `ideal_seq_async_pins false` để buffer cây reset |
| `ASIC_Top.sdc` | Ràng buộc dùng chung cho Genus, Innovus, Tempus |

Điều kiện (tỉ lệ theo Lab 01):

| Mục | Giá trị |
| --- | --- |
| Clock | `PERIOD` (mặc định 20 ns), duty 50% |
| Clock uncertainty, transition | Setup 0,15 ns, hold 0,08 ns, transition 0,08 ns |
| Input delay | Max 24% chu kỳ, min 0,3 ns cho `uart*_rx`, `gpio*_i`. `rst_pad_n` và `boot_strap` là false path, input delay 0 |
| Output delay | Max 20% chu kỳ, min 0,2 ns |
| Input transition, output load | 0,1 ns, 0,05 pF |
| Design rule | `set_max_transition 0.5`, `set_max_fanout 32` |
| Clock gating | Bật mặc định (`CG=1`, `lp_clock_gating_min_flops 4`). `CG=0` cho bản so sánh |
| Thư viện | `slow_vdd1v0_basiccells.lib` (corner setup). Genus chỉ kiểm setup, hold và recovery, removal để cho Tempus |

4 bộ nhớ là black box (không đọc `rtl/mem`), vì wrapper macro SRAM của HRoT_SoC chưa có. Khi có wrapper thì đọc thêm `sram_2k_macro.lib` và đổi số bộ nhớ cần kiểm trong `synth.tcl`.

Các bước trong MobaXterm (SSH vào server):

```bash
git clone https://github.com/NguyenDinhNhatNguyen/HRoT_SoC.git ~/HRoT_SoC   # lần đầu
cd ~/HRoT_SoC && git pull                                                   # các lần sau
which genus && ls ~/PDK_GPDK45/lib/slow_vdd1v0_basiccells.lib               # kiểm tool và PDK
make asic-genus > genus_run.txt 2>&1 &                                      # chạy nền
grep -E 'Genus done|ERROR|WARNING' genus_run.txt                            # xem tiến độ
```

| Lệnh | Làm gì | Kết quả |
| --- | --- | --- |
| `make asic-genus` | Genus, có clock gating, 20 ns | `asic/out_genus/` (netlist, SDC, SDF, `reports/`), log ở `asic/run_genus/genus.log` |
| `make asic-genus PERIOD=10` | Đổi chu kỳ, độ trễ vào ra đổi theo | Như trên, ghi đè |
| `make asic-genus CG=0` | Không clock gating, để so công suất | Đổi tên `asic/out_genus` thành `asic/out_genus_cg0` trước khi chạy bản `CG=1` |
| `make asic-genus-save` | Chép riêng `.rpt` và `summary.txt` vào `asic/reports/genus/` | Commit thư mục này. Netlist, SDF ở lại `asic/out_genus/` (bị `.gitignore`) |

PDK ở chỗ khác thì `export PDK_DIR=<đường dẫn>` trước khi chạy.

Tiêu chí nghiệm thu, report trong `asic/out_genus/reports/`:

| Report | Đạt khi |
| --- | --- |
| `audit/pre_syn_unresolved.rpt` | Chỉ 4 instance chưa phân giải: `master_ram`, `app_ram`, `boot_rom`, `app_rom` (black box). Ngoài 4 cái này là lỗi |
| `audit/pre_syn_design_lint.rpt` | 0 latch, 0 loop, 0 multi-driven |
| `audit/pre_syn_timing_intent.rpt` | 0 unconstrained endpoint, trừ chân của 4 black box |
| `audit/post_syn_design_lint.rpt` | 0 floating input, không còn assign |
| `synthesis/timing.rpt`, `summary.txt` (`wns_ps`) | Slack >= 0 ở 20 ns |
| `synthesis/design_rules.rpt` | 0 max_transition, 0 max_capacitance, 0 max_fanout (cây reset đã buffer) |
| `synthesis/clock_gating.rpt` (bản `CG=1`) | Đa số flop được gate |
| `synthesis/power.rpt` | So hai bản `CG=0` và `CG=1` |
| `summary.txt` | `memories_black_box=4`, `scan_flops=0`, `latches=0` |

Lưu ý về Genus trên server: Genus đọc Verilog-2001 nên không khai báo `localparam` trong `generate` (RTL hiện tại không có). Genus không ghi đè log mà tạo `genus.log1`, `genus.log2` (`make` đã xoá log cũ). Không dùng `git add -f`.

Giới hạn: bộ nhớ là black box nên report không có diện tích bộ nhớ và đường đi qua bộ nhớ không được tính giờ, giống lần chạy Yosys. Số đầy đủ cần wrapper macro SRAM (xem mục "Macro SRAM của trường").

## Kết quả Genus (12/11/2026)

Genus 21.10, GPDK45 `slow_vdd1v0` (0,9 V, 125 °C), top `ASIC_Top`, `CG=1`, 4 bộ nhớ là black box. Report bản 20 ns nằm ở `asic/reports/genus/` (`cab84df`).

| Chỉ số (20 ns) | Giá trị |
| --- | --- |
| Timing | Đạt, slack +6,977 ns, đường xấu nhất 12,774 ns |
| Đường xấu nhất | Lõi App: `MEM_WB_Reg/Rd_WB` qua `Forwarding_Unit`, bộ so sánh của ALU, tới `PC[31]` |
| Diện tích logic | 73.256 µm², 24.791 cell (không gồm bộ nhớ) |
| Flip-flop | 7.069, trong đó 6.234 (88%) được gate bởi 213 cell clock gating |
| Scan flop, latch | 8 cell `SMDFFHQX1` (xem ghi chú dưới bảng quét), 0 latch |
| Design rule | 0 vi phạm max transition, max capacitance, max fanout (cây reset đã được buffer) |
| Ràng buộc | 0 đầu vào, đầu ra thiếu delay, slew hay tải |
| Thời gian chạy | Khoảng 10 phút |

Quét chu kỳ cùng ngày (report còn trên server ở `asic/out_sweep/`, chưa vào repo):

| Chu kỳ | Slack (WNS) | F_max ước lượng | Diện tích logic | Design rule |
| --- | --- | --- | --- | --- |
| 20 ns | +6,977 ns | 77 MHz | 73.256 µm² | 0 vi phạm |
| 12 ns | +1,737 ns | 97 MHz | 73.314 µm² | 0 vi phạm |
| 10 ns | +0,625 ns | 107 MHz | 73.436 µm² | 0 vi phạm |
| 8 ns | +0,175 ns | 128 MHz | 74.114 µm² | 0 vi phạm |

F_max = 1 / (chu kỳ − WNS), chỉ là ước lượng từ đường xấu nhất, đã gồm 0,15 ns uncertainty. Chưa quét 7 ns và 6 ns nên chưa chốt chu kỳ.

Điểm cần biết khi đọc report:

- `summary.txt` ghi `flops=7061` và `scan_flops=0`, nhưng `clock_gating.rpt` đếm 7.069 flop. 8 flop chênh là cell `SMDFFHQX1` (flop có mux tích hợp, thuộc nhóm cell scan của gsclib045), thấy trong danh sách cell ở cuối `post_syn_design_lint.rpt`. Lần chạy 12/11 chỉ cấm và chỉ đếm tên `SDFF*` nên sót. Genus dùng chúng như flop có mux, không phải chuỗi scan, nên chức năng và timing không sai, nhưng tiêu chí "0 scan flop" chưa đạt. `synth.tcl` đã sửa 13/11 (cấm và đếm cả `SEDFF*`, `SMDFF*`), cần chạy lại trên server để xác nhận.
- `pre_syn_timing_intent.rpt` báo "multiple drivers" trên `clk`, `app_instr_addr`, `boot_addr`, `reg_raddr`, `reg_wdata`, `reg_wen`, `reg_wstrb`. Đây đều là net nối vào chân của 4 bộ nhớ black box: Genus không biết hướng chân của module chưa phân giải nên coi chúng là nguồn lái. Không phải lỗi RTL.
- Netlist còn 68 lệnh `assign` (`reg_wstrb` 4, `reg_wdata` 32, `reg_raddr` 32 bit), cùng nguyên nhân trên. Innovus không nhận `assign`, nên cần wrapper macro SRAM trước P-21.
- `post_syn_design_lint.rpt` báo 502 chân module không có nguồn lái. Tất cả có fanout 0: đó là các bit không dùng (bit địa chỉ cao của slave AXI, chân `stall` hằng của lõi App), vô hại.
- `gates.rpt` không đưa vào repo vì nó liệt kê từng cell của thư viện kèm diện tích.

## Việc chỉ làm được trên server trường (Phát, P-20 và P-21)

Ghi 09/11/2026. Những việc dưới cần GPDK45, macro SRAM hoặc công cụ Cadence nên không làm ở nhà được.

| Việc | Cần gì | Ghi chú |
| --- | --- | --- |
| Chốt `CLK_PERIOD_NS` và `IO_DELAY_NS` | Genus với GPDK45, thông số pad | Từ 12/11 độ trễ vào ra theo tỉ lệ 24% và 20% chu kỳ của Lab 01, nên chỉ còn chốt chu kỳ. Genus đạt tới 8 ns, chờ quét 7 và 6 ns. Xong thì báo Nguyên để đóng N-30 |
| Chạy Genus với `ASIC_Top` làm top, nạp `ASIC_Top.sdc` | GPDK45 | Đã chạy 12/11 bằng `make asic-genus`, đạt từ 20 tới 8 ns, cây reset đã được buffer. Còn: quét 7 và 6 ns, bản `CG=0`. Recovery và removal của reset kiểm bằng Tempus |
| Đọc diện tích, thời gian truy cập của macro `sram_2k` | `.lib`, `.lef` của macro trên server | Cộng diện tích bộ nhớ vào số Yosys và Genus, kiểm trễ `Q` có vừa một chu kỳ không |
| Kiểm tương đương netlist với RTL | Conformal LEC | Sau Genus |
| Mô phỏng netlist (GLS) | Mô hình hành vi cell GPDK45 | `RISCV_Core_prog_tb` dùng lại được (bọc phần in thanh ghi bằng `ifndef GLS`) |
| Innovus, so sánh PPA FPGA và ASIC (P-21) | Innovus, Tempus | Số FPGA ở `docs/project/PPA_FPGA.md` |
