# asic/

Điểm xuất phát cho luồng ASIC (Genus, Innovus) của Phát (P-20, P-21).

| File | Nội dung |
| --- | --- |
| `SoC_Top.sdc` | Khung SDC cho `SoC_Top`: một clock `clk`, false path cho các đầu vào bất đồng bộ, `set_output_delay` cho đầu ra |
| `run_yosys.sh`, `yosys/` | Chạy thử Yosys + NanGate45 cho `SoC_Top` trong docker để lấy số sơ bộ (`make asic-yosys`). Bộ nhớ là black box (`yosys/mem_bb.v`) |

File này chưa có chu kỳ clock và độ trễ I/O, vì chúng phụ thuộc PDK mà Phát chọn. Đặt hai biến `CLK_PERIOD_NS` và `IO_DELAY_NS` trước khi `source`, nếu thiếu thì SDC báo lỗi. Cổng lấy từ `rtl/top/SoC_Top.v`. Các đầu vào được coi là bất đồng bộ theo ràng buộc FPGA (`fpga/intel/de2/constraints.sdc`), cần kiểm lại khi có vòng pad của ASIC, nhất là `reset_system` (top FPGA đồng bộ nó trước khi vào `SoC_Top`).

Số đo FPGA để so sánh nằm ở `docs/project/PPA_FPGA.md`.

## Quy tắc khi chạy luồng ASIC

Repo này công khai. `rv32i_soc` từng đưa file dựng từ GPDK45 của trường (`.gds`, `.spef`, netlist PnR) lên repo công khai và phải xử lý lại, nên áp cùng quy tắc ở đây.

| Quy tắc | Chi tiết |
| --- | --- |
| Chỉ commit report văn bản | Report timing, diện tích, DRC dạng `.rpt` hoặc `.txt` |
| Không commit file dựng từ PDK | Thư viện cell (`.lib`, `.lef`, `.tf`, `.captbl`), netlist, `.spef`, `.sdf`, `.gds`, `.def`. `.gitignore` đã chặn các đuôi này trong `asic/` |
| Thư viện GPDK45 chỉ ở server trường | Không chép về máy cá nhân hay repo. Đường dẫn do server cấu hình (`rv32i_soc` dùng biến `PDK_DIR`) |
| Genus, Innovus, Tempus chỉ chạy trên server trường | Docker `hpretl/iic-osic-tools` trên máy Nguyên là bộ công cụ mã nguồn mở (Yosys, OpenROAD, OpenSTA), không có các công cụ Cadence |
| Số từ Yosys với NanGate45 chỉ là sơ bộ | Ghi rõ là Yosys, thư viện mở, không dùng thay số Genus trong báo cáo chính thức |

## Số sơ bộ Yosys + NanGate45 (07/11/2026)

Chạy bằng `make asic-yosys` trong WSL, cần container `hpretl/iic-osic-tools` đang chạy (Yosys 0.70, OpenSTA 3.1.0). Thư viện NanGate45 lấy từ bản của `rv32i_soc` (kiểm sha256, không chép vào repo). Kết quả văn bản nằm ở `asic/out_yosys/` (bị `.gitignore`).

| Chỉ số | Giá trị |
| --- | --- |
| Số cell (gồm flip-flop và 4 black box) | 41.060 |
| Diện tích logic (không gồm bộ nhớ) | 72.012 µm² |
| Flip-flop | 7.004 (`DFF_X1` 6.386, `DFFR_X1` 618) |
| Bộ nhớ (black box) | 4 khối 4 KB, tổng 16 KB, không có diện tích |
| Đường flop sang flop chậm nhất | 4,022 ns chu kỳ tối thiểu, F_max 249 MHz (clock 20 ns, slack +15,978 ns) |
| Vào sang flop, flop ra | 0,114 ns, 3,739 ns |

Hai lần chạy liên tiếp cho cùng diện tích và số flop.

Đường chậm nhất bắt đầu từ một flop reset nội bộ có fanout 893 và độ dốc 1,43 ns, nghĩa là cây reset chưa được buffer. Genus và Innovus sẽ buffer cây này (`rv32i_soc` thêm `set_max_fanout` vào SDC cho việc đó), nên F_max thật có thể cao hơn. Đường reset thuộc loại recovery cũng đo ra slack +17,505 ns, không vi phạm.

Giới hạn, chỉ là xu hướng:

- NanGate45 là thư viện mở, không phải GPDK45, và Yosys khác Genus.
- Bộ nhớ là black box: không có diện tích bộ nhớ, đường đi qua bộ nhớ không được tính giờ, `Data_Memory` mất 32 cổng AND của `MemRead`. Diện tích ASIC thật phải cộng macro SRAM.
- SDC tối thiểu: độ trễ I/O bằng 0, không có `set_max_transition` hay `set_max_fanout`, không đặt dây, clock lý tưởng.
- 7.004 flip-flop nhiều hơn 4.925 thanh ghi của Quartus trên DE2. Phần lớn là file thanh ghi: một `Register_File` ra 1.024 flip-flop trong Yosys (đo riêng, `$_DFFE_PP_`), hai lõi là 2.048. Quartus đưa file thanh ghi vào M4K, nên bộ nhớ DE2 là 135.168 bit = 131.072 bit của 4 bộ nhớ cộng 4.096 bit (2 lõi, mỗi lõi 2 bản cho 2 cổng đọc). Chênh 7.004 − 4.925 = 2.079 nên còn 31 flip-flop chưa giải thích.
- Yosys báo `check` không có vòng tổ hợp, không có chân nhiều driver hay chân không driver (0 vấn đề), không suy ra latch, và chỉ một cảnh báo: bộ nhớ `W` của SHA-256 (16 × 32 bit) thành thanh ghi.
- Không kiểm tương đương netlist với RTL. Tên flip-flop mất sau tổng hợp nên so sánh tự động không khớp được, và netlist cần mô hình hành vi của cell NanGate45 để mô phỏng. Việc này để cho LEC (Conformal) trên server trường, như `rv32i_soc` làm.
- Không kiểm tương đương netlist với RTL.

## Macro SRAM của trường

Chân của `sram_2k_macro` (từ `rv32i_soc`, `syn/yosys/sram_2k_macro_bb.v`): `CLK`, `CEN`, `WEN`, `A[9:0]`, `D[31:0]`, `Q[31:0]`. Một cổng địa chỉ, nghĩa là bộ nhớ một cổng đọc ghi (1RW) sâu 1.024 từ 32 bit (4 KB). Theo `docs/macro_notes.md` của `rv32i_soc`, 16 KB là 4 macro.

| Bộ nhớ của `SoC_Top` | Cổng cần | Ghép với macro |
| --- | --- | --- |
| `master_ram`, `app_ram` (`Data_Memory`) | 1 cổng đọc ghi, có `wstrb` | Vừa một macro, cần wrapper cho byte enable (macro không có chân tương ứng) |
| `boot_rom`, `app_rom` (`Dual_Port_ROM`) | 2 cổng đọc cùng lúc (A: lấy lệnh, B: AXI và Boot_Verifier) | Một macro chỉ có một cổng nên cần hai macro chứa cùng nội dung, hoặc chia thời gian truy cập (đổi thiết kế) |

Chưa biết diện tích, thời gian truy cập và lớp kim loại chắn của macro: các số này nằm ở `.lib`, `.lef` trên server (`rv32i_soc` có `scripts/macro_info.sh` để in ra). Macro cho `Q` ra ở chu kỳ sau, khác bộ nhớ đọc cạnh xuống hiện tại, nên thay vào là sửa thiết kế (đường lấy lệnh của lõi), cần Phát xác nhận.
