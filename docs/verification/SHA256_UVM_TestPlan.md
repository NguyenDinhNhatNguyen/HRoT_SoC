# Test Plan UVM — SHA-256 AXI4-Lite Slave

> Viết Tuần 6, cập nhật 25/10/2026 theo P-08 và I-05 · Người viết: Phát (DV) · Phục vụ: P-08 (sequence ngẫu nhiên, xong), P-17 (scoreboard DPI), P-19 (coverage)
> Register map và hợp đồng: `docs/spec/SHA256_Register_Map.md`

## 1. Phạm vi và mục tiêu

**DUT:** `SHA256_Wrapper` (AXI4-Lite slave, base `0x5000_0000`) bọc `SHA256_Core` (66 chu kỳ từ START đến DONE cho mỗi khối).

**Mục tiêu:** chứng minh (a) hash đúng với mọi độ dài message, (b) giao thức thanh ghi đúng (START/INIT/BUSY/DONE), (c) tuân thủ AXI4-Lite dưới mọi thứ tự và độ trễ handshake, (d) hồi phục đúng sau reset, (e) không hỏng dữ liệu khi bị truy cập sai thứ tự.

**Ngoài phạm vi:** logic Secure Boot ở mức SoC (Tuần 10), Dual-Port ROM và SYSCSR.

## 2. Thông số đã chốt (I-05)

| # | Thông số | Nguồn |
| --- | --- | --- |
| A1 | Offset trống trong cửa sổ 64 KB (`0x48`, `0x4C`, `0x70`–`0xFFFF`): `OKAY`, đọc 0, ghi bỏ qua, không alias. Ngoài mọi slave: `DECERR` từ default slave của `SoC_Top` | I-05, RTL sửa ở `a968cce` |
| A2 | Độ trễ khối = 66 chu kỳ từ lúc START được chấp nhận đến DONE (64 vòng + 1 cộng H + 1 nhận lệnh AXI). Sequence chờ DONE tối đa `poll_limit` = 500 lần đọc STATUS | I-05 |
| A3 | `DONE` sticky, xóa khi START. Ghi BLOCK hoặc START lúc `BUSY` bị bỏ qua | Hợp đồng HAL #3, #4, #6 |
| A4 | Reset ở RTL là active-high, interface UVM là active-low (`rst_n`) → `tb_sha256_top` nối `~rst_n` | – |
| A5 | Wrapper bỏ qua `WSTRB`, mỗi lần ghi luôn ghi cả word | Hợp đồng HAL #7 |

## 3. Kiến trúc kiểm chứng

Tái sử dụng agent AXI4-Lite đã có (driver, monitor, sequencer, SVA trong `axi4_lite_if`). Top `dv/tb/tb_sha256_top.sv` nối agent thẳng vào DUT thật.

| Thành phần | Vai trò | Tình trạng |
| --- | --- | --- |
| `dv/env/sha256_ref.svh` | Mô hình tham chiếu SHA-256 bằng SV (cùng thuật toán với `fw/hal/test/sha256_ref.c`) | Có (P-08) |
| `dv/tests/sha256_seq_lib.svh` | Sequence tự kiểm tra: băm message theo luồng HAL, so với `sha256_ref`, gom lỗi và bỏ qua kết quả bị reset cắt ngang | Có (P-08) |
| `dv/tests/sha256_tests.svh` | `sha256_base_test` + test con, mỗi test ghi đè `run_stimulus()` | Có (P-08) |
| `sha256_ref_dpi.c` + `sha256_scoreboard` | Golden bọc `fw/hal/test/sha256_ref.c` bằng DPI-C, scoreboard thụ động dựng lại khối từ các ghi BLOCK | P-17 |
| `sha256_reg_model` | Mô hình thanh ghi: BLOCK (W), CTRL, STATUS, HASH (RO), quy tắc bỏ qua ghi khi BUSY | P-17 |
| `sha256_cov` | Covergroup (mục 6) | P-19 |

`axi4_lite_scoreboard` (mô hình bộ nhớ chung) **không dùng** cho DUT này vì thanh ghi RO/W1-clear/side-effect không khớp mô hình bộ nhớ.

Hàm `hash_msg` trong `sha256_base_seq` (tham số: nội dung message, độ trễ AXI ngẫu nhiên, thứ tự ghi BLOCK, đọc STATUS xen kẽ) thực hiện đúng luồng của HAL: kiểm BUSY → ghi 16 BLOCK → ghi CTRL → poll STATUS đến DONE (có timeout) → đọc 8 HASH.

## 4. Danh sách tính năng cần kiểm (Verification Plan)

| ID | Tính năng | Kiểm tra / Tiêu chí PASS | Cách kiểm | Ưu tiên |
| --- | --- | --- | --- | --- |
| F-REG-01 | Giá trị sau reset | STATUS=0, BLOCK/CTRL đọc 0, HASH đọc IV (lõi nạp IV khi reset) | Test đọc | Cao |
| F-REG-02 | BLOCK chỉ ghi, luôn ghi cả word | Ghi với WSTRB bất kỳ vẫn ghi cả word (A5), đọc BLOCK ra 0. Kiểm gián tiếp qua hash | Directed | Cao |
| F-REG-03 | Thanh ghi RO không bị ghi đè | Ghi vào STATUS/HASH không đổi giá trị | Scoreboard | Trung bình |
| F-REG-04 | Địa chỉ ngoài map | Theo A1; không tác dụng phụ lên trạng thái | Scoreboard | Trung bình |
| F-HASH-01 | Một khối, KAT chuẩn | Digest rỗng, "abc" khớp NIST | KAT test | Cao |
| F-HASH-02 | Nhiều khối, chaining | "abcdbcde…nopq" (56 byte, 2 khối) và 1M×'a' khớp | KAT test | Cao |
| F-HASH-03 | Mọi độ dài biên | Độ dài 0,1,55,56,57,63,64,65,119,120,127,128 khớp golden | Directed + rand | Cao |
| F-HASH-04 | INIT đúng | INIT nạp lại IV: hai message liên tiếp độc lập; thiếu INIT thì chaining | Directed | Cao |
| F-CTL-01 | START tự xóa | Sau START, ghi lại CTRL không tự chạy thêm | Scoreboard | Cao |
| F-CTL-02 | BUSY/DONE đúng pha | START → BUSY=1,DONE=0 → BUSY=0,DONE=1, không bao giờ cả hai bằng 1 | Sequence + scoreboard | Cao |
| F-CTL-03 | DONE sticky, xóa khi START | DONE giữ 1 qua nhiều lần đọc; về 0 khi START kế | Scoreboard | Cao |
| F-CTL-04 | Độ trễ khối | DONE đúng 66 chu kỳ sau khi START được chấp nhận (A2) | SVA | Trung bình |
| F-CTL-05 | START khi BUSY | Bị bỏ qua, hash đang chạy không đổi | Directed | Cao |
| F-CTL-06 | Ghi BLOCK khi BUSY | Bị bỏ qua, hash đang chạy không đổi | Directed | Cao |
| F-CTL-07 | Đọc HASH trước DONE | Không treo bus; (không kiểm giá trị) | Directed | Thấp |
| F-RST-01 | Reset giữa chừng | Reset khi BUSY → STATUS=0, IV phục hồi, message kế đúng | Directed | Cao |
| F-AXI-01 | AW/W đến theo mọi thứ tự | AW trước W, W trước AW, đồng thời | Rand delay | Cao |
| F-AXI-02 | Back-pressure | BREADY/RREADY trễ 0–8 chu kỳ, DUT giữ ổn định | Rand delay + SVA | Cao |
| F-AXI-03 | Truy cập đọc/ghi đan xen khi BUSY | Đọc STATUS liên tục trong lúc ghi khối kế | Stress | Cao |
| F-AXI-04 | Tuân thủ giao thức | 0 lỗi SVA (`assert_fail_count == 0`) | SVA có sẵn | Cao |
| F-ROB-01 | Dữ liệu nhiễu (Tuần 10) | Địa chỉ/WSTRB/thứ tự bất hợp lệ không làm hỏng message đang chạy hay treo bus | Noise test | Trung bình |

## 5. Danh sách test

Chạy bằng `vsim -c -do "set DUT sha256; set TEST <tên>; do run_uvm.do"`.

Đã có (P-08, 25/10):

| Test | Sequence | Feature | Ghi chú |
| --- | --- | --- | --- |
| `sha256_kat_test` | `sha256_kat_seq`: rỗng, "abc", 56 byte | F-HASH-01/02 | Đáp án cứng, không phụ thuộc mô hình SV |
| `sha256_ctl_test` | `sha256_ctl_seq`: rác và START khi BUSY, đọc HASH sớm, DONE sticky, CTRL không START, ghi RO và offset trống, chaining, INIT nạp lại IV | F-CTL-01/03/05/06/07, F-HASH-04, F-REG-03/04 | Trình tự cố định, không phụ thuộc delay |
| `sha256_rand_test` | `sha256_rand_seq`: độ dài có trọng số vào các biên, delay AXI, thứ tự ghi BLOCK và đọc HASH ngẫu nhiên, đọc STATUS xen kẽ | F-HASH-03, F-AXI-01/02/03 | `+NUM_MSGS=<n>` (mặc định 40), `+MAX_LEN=<byte>` (mặc định 600). Thêm `+RESET_AT_NS=<t>` để kiểm F-RST-01 |
| `sha256_full_test` | KAT → ctl → rand | các mục trên | Nằm trong `make test` |
| `sha256_alias_test` | `sha256_alias_seq`: offset từ `0x100` trở lên | F-REG-04 | Tìm ra lỗi alias, RTL sửa ở `a968cce`. Không nằm trong `make test` |

Chưa có (làm cùng P-17 hoặc khi cần):

| Test | Feature | Ghi chú |
| --- | --- | --- |
| `sha256_reg_reset_test` | F-REG-01 | Đọc toàn map sau reset |
| `sha256_reg_rw_test` | F-REG-02 | Ghi BLOCK với WSTRB khác `F`, kiểm vẫn ghi cả word |
| `sha256_len_sweep_test` | F-HASH-03 | Quét đủ 0..300 byte, hiện `sha256_rand_test` mới chọn ngẫu nhiên có trọng số |
| `sha256_reset_mid_op_test` | F-RST-01 | Reset ở pha ngẫu nhiên khi BUSY. Hiện dùng `+RESET_AT_NS` với thời điểm cố định |
| `sha256_axi_stress_test` | F-AXI-03 | Back-pressure tối đa liên tục |
| `sha256_noise_test` | F-ROB-01 | Xen giao dịch bất hợp lệ vào luồng hợp lệ |

**Seed:** mỗi test ngẫu nhiên nên chạy tối thiểu 20 seed trước khi báo cáo cuối. P-08 mới chạy 3 seed mỗi test.

## 6. Kế hoạch Functional Coverage (P-19)

| Covergroup | Điểm lấy mẫu (bins) |
| --- | --- |
| `cg_reg_access` | `addr` ∈ {BLOCK0..15, CTRL, STATUS, HASH0..7, reserved, out-of-map} × `is_write`; `wstrb` ∈ {F, 0, từng lane, lẻ} |
| `cg_msg_len` | {0, 1–54, 55, 56, 57–62, 63, 64, 65–118, 119, 120, 121–127, 128, >128} |
| `cg_block_count` | {1, 2, 3, 4+} |
| `cg_ctrl` | `INIT` × `START` × trạng thái (IDLE/BUSY/DONE) — kèm cross **START khi BUSY** và **ghi BLOCK khi BUSY** (illegal-ish, phải được chạm) |
| `cg_status` | chuyển pha IDLE→BUSY→DONE→(START)→BUSY, DONE→IDLE chỉ qua START |
| `cg_axi_timing` | `addr_delay`, `data_delay`, `resp_delay` ∈ {0, 1–3, 4–8}; thứ tự {AW<W, W<AW, đồng thời} |
| `cg_reset` | reset khi {IDLE, BUSY ở đầu/giữa/cuối khối, DONE} |
| `cg_poll` | số lần poll DONE trước khi thấy DONE {1, 2–10, >10} |

**Mục tiêu đóng:** Functional coverage 100% (có waiver ghi lý do cho bin bất khả thi); Code coverage (statement/branch) ≥ 95% trên `SHA256_Wrapper`, ≥ 90% trên `SHA256_Core`; 0 lỗi UVM, 0 lỗi SVA.

## 7. Tiêu chí PASS/FAIL tổng thể

- Test PASS khi: không có `UVM_ERROR/UVM_FATAL`, `assert_fail_count == 0`, sequence không còn lỗi gom lại, và không chạm timeout toàn cục (`+TEST_TIMEOUT_US`). Scoreboard bộ nhớ tắt cho DUT này (`has_mem_scoreboard = 0`).
- Mọi test lỗi phải tái lập được bằng `TEST`+`SEED` (ghi vào log).
- Mỗi lỗi RTL tìm ra được ghi vào bảng bug với ID, test phát hiện, seed.

## 8. Lộ trình triển khai

| Tuần | Việc |
| --- | --- |
| 6 (xong) | Test plan này + HAL (`fw/hal`) + golden C có sẵn |
| 7 (xong, P-08) | Mô hình SV, sequence tự kiểm tra và 5 test đã có ở mục 5, chạy trên DUT thật |
| 10 (P-17, hạn 15/11) | DPI golden, `sha256_scoreboard`, `sha256_reg_model`, các test còn thiếu ở mục 5 |
| 11 (P-18, hạn 22/11) | Regression UVM toàn SoC |
| 12–13 (P-19, P-20) | Covergroup mục 6, báo cáo coverage |

## 9. Phụ thuộc và rủi ro

- **RTL SHA-256:** đã hoàn chỉnh và khớp hợp đồng. Lỗi alias offset ≥ `0x100` do P-08 tìm ra đã sửa ở `a968cce`.
- **Reset khác cực** giữa RTL (active-high) và interface UVM (active-low): xử lý ở `tb_sha256_top`.
- **Thông số:** A1, A2 đã chốt ở I-05 (mục 2).
