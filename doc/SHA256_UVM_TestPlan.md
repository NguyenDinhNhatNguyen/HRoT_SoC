# Test Plan UVM — SHA-256 AXI4-Lite Slave

> Phiên bản: Tuần 6 · Người viết: Phát (DV) · Phục vụ: Tuần 7 (sequence ngẫu nhiên), Tuần 10 (nhiễu), Tuần 11 (coverage)
> Register map & hợp đồng: `doc/SHA256_Register_Map.md`

## 1. Phạm vi và mục tiêu

**DUT:** `SHA256_Wrapper` (AXI4-Lite slave, base `0x5000_0000`) bọc `SHA256_Core` (64 chu kỳ/khối).

**Mục tiêu:** chứng minh (a) hash đúng với mọi độ dài message, (b) giao thức thanh ghi đúng (START/INIT/BUSY/DONE), (c) tuân thủ AXI4-Lite dưới mọi thứ tự và độ trễ handshake, (d) hồi phục đúng sau reset, (e) không hỏng dữ liệu khi bị truy cập sai thứ tự.

**Ngoài phạm vi:** logic Secure Boot ở mức SoC (Tuần 10), Dual-Port ROM và Reset Controller.

## 2. Giả định (cần Nguyên xác nhận)

| # | Giả định | Nếu sai thì |
|---|---|---|
| A1 | Truy cập địa chỉ ngoài map: `OKAY`, đọc 0, ghi bỏ qua | Đổi một cờ trong `sha256_cfg` (`unmapped_resp`) |
| A2 | Độ trễ khối = 64 chu kỳ từ START đến DONE; ngưỡng kiểm tra đặt tham số `MAX_LATENCY` (mặc định 80) | Chỉnh `MAX_LATENCY` |
| A3 | `DONE` sticky, xóa khi START; ghi lúc `BUSY` bị bỏ qua | Xem test `sha256_ctl_protocol_test` (mục 5) |
| A4 | Reset ở RTL là active-high, interface UVM là active-low (`rst_n`) → `tb_top` nối `~rst_n` | – |

## 3. Kiến trúc kiểm chứng

Tái sử dụng agent AXI4-Lite đã có (driver, monitor, sequencer, SVA trong `axi4_lite_if`). Thay slave mô hình bằng DUT thật, thêm:

| Thành phần mới | Vai trò |
|---|---|
| `sha256_ref_dpi.c` | Golden model: bọc `fw/hal/test/sha256_ref.c` bằng DPI-C (`sha256_ref_compress`, độ dài tuỳ ý) |
| `sha256_reg_model` | Mô hình thanh ghi: BLOCK (W), CTRL, STATUS, HASH (RO), quy tắc bỏ qua ghi khi BUSY |
| `sha256_scoreboard` | Dựng lại khối từ các ghi BLOCK, mỗi START gọi golden (có/không INIT), so với HASH đọc ra; kiểm quy tắc STATUS |
| `sha256_cov` | Covergroup (mục 6) |
| `sha256_seq_lib` | Sequence cấp "hash message" dựa trên `write_word`/`read_word` của `axi4_lite_base_seq` |
| `sha256_base_test` + test con | Mục 5. Mỗi test ghi đè `run_stimulus()` giống `base_test` hiện tại |

`axi4_lite_scoreboard` (mô hình bộ nhớ chung) **không dùng** cho DUT này vì thanh ghi RO/W1-clear/side-effect không khớp mô hình bộ nhớ.

Sequence cấp cao `sha256_hash_seq` (tham số: `msg_len`, nội dung, cờ INIT mỗi khối, độ trễ AXI) thực hiện đúng luồng của HAL: kiểm BUSY → ghi 16 BLOCK → ghi CTRL → poll STATUS đến DONE (có timeout) → đọc 8 HASH.

## 4. Danh sách tính năng cần kiểm (Verification Plan)

| ID | Tính năng | Kiểm tra / Tiêu chí PASS | Cách kiểm | Ưu tiên |
|---|---|---|---|---|
| F-REG-01 | Giá trị sau reset | STATUS=0; BLOCK/CTRL đọc về 0; HASH đọc 0 hoặc IV (ghi rõ theo RTL) | SVA + test đọc | Cao |
| F-REG-02 | BLOCK ghi/đọc đúng, theo WSTRB | Ghi từng byte lane, đọc lại khớp mô hình | Scoreboard | Cao |
| F-REG-03 | Thanh ghi RO không bị ghi đè | Ghi vào STATUS/HASH không đổi giá trị | Scoreboard | Trung bình |
| F-REG-04 | Địa chỉ ngoài map | Theo A1; không tác dụng phụ lên trạng thái | Scoreboard | Trung bình |
| F-HASH-01 | Một khối, KAT chuẩn | Digest rỗng, "abc" khớp NIST | KAT test | Cao |
| F-HASH-02 | Nhiều khối, chaining | "abcdbcde…nopq" (56 byte, 2 khối) và 1M×'a' khớp | KAT test | Cao |
| F-HASH-03 | Mọi độ dài biên | Độ dài 0,1,55,56,57,63,64,65,119,120,127,128 khớp golden | Directed + rand | Cao |
| F-HASH-04 | INIT đúng | INIT nạp lại IV: hai message liên tiếp độc lập; thiếu INIT thì chaining | Directed | Cao |
| F-CTL-01 | START tự xóa | Sau START, ghi lại CTRL không tự chạy thêm | Scoreboard | Cao |
| F-CTL-02 | BUSY/DONE đúng pha | START → BUSY=1,DONE=0 → (≤MAX_LATENCY) BUSY=0,DONE=1 | SVA + scoreboard | Cao |
| F-CTL-03 | DONE sticky, xóa khi START | DONE giữ 1 qua nhiều lần đọc; về 0 khi START kế | Scoreboard | Cao |
| F-CTL-04 | Độ trễ khối | DONE trong khoảng [64, MAX_LATENCY] chu kỳ | SVA | Trung bình |
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

Chạy bằng `vsim -c -do "set TEST <tên>; do run_uvm.do"` (giống test AXI hiện có).

| Test | Sequence | Feature | Tuần | Ghi chú |
|---|---|---|---|---|
| `sha256_reg_reset_test` | đọc toàn map sau reset | F-REG-01 | 7 | Smoke, chạy đầu tiên |
| `sha256_reg_rw_test` | ghi/đọc BLOCK có WSTRB, ghi RO, địa chỉ ngoài map | F-REG-02/03/04 | 7 | |
| `sha256_kat_test` | `sha256_kat_seq`: các vector NIST | F-HASH-01/02 | 7 | Có đáp án cứng, không phụ thuộc DPI |
| `sha256_len_sweep_test` | độ dài 0..300 và các biên 119/120/127/128 | F-HASH-03 | 7 | So golden DPI |
| `sha256_ctl_protocol_test` | START×2, ghi lúc BUSY, đọc HASH sớm, DONE sticky | F-CTL-01..07 | 7 | Trình tự kiểm tra cố định, không phụ thuộc delay |
| `sha256_init_chain_test` | message liên tiếp có/không INIT | F-HASH-04 | 7 | |
| `sha256_reset_mid_op_test` | reset ở pha ngẫu nhiên khi BUSY, rồi băm lại | F-RST-01 | 7 | |
| `sha256_rand_msg_test` | `sha256_rand_seq`: độ dài ngẫu nhiên có trọng số vào các biên, delay AXI ngẫu nhiên | F-HASH-03, F-AXI-01/02 | 7 | `+NUM_TRANS=<n>` |
| `sha256_axi_stress_test` | đọc STATUS liên tục + ghi khối kế + back-pressure tối đa | F-AXI-03 | 7 | |
| `sha256_noise_test` | xen giao dịch bất hợp lệ vào luồng hợp lệ | F-ROB-01 | 10 | Tuần 10 |
| `sha256_full_test` | chạy lần lượt toàn bộ ở trên | tất cả | 7→11 | Dùng để chốt coverage |

**Seed:** mỗi test ngẫu nhiên chạy tối thiểu 20 seed (`SEED=1..20`) trước khi báo cáo.

## 6. Kế hoạch Functional Coverage (Tuần 11)

| Covergroup | Điểm lấy mẫu (bins) |
|---|---|
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

- Test PASS khi: không có `UVM_ERROR/UVM_FATAL`, `assert_fail_count == 0`, scoreboard đã nhận ≥ 1 giao dịch (kiểm có sẵn ở `check_phase`), và không chạm timeout toàn cục.
- Mọi test lỗi phải tái lập được bằng `TEST`+`SEED` (ghi vào log).
- Mỗi lỗi RTL tìm ra được ghi vào bảng bug với ID, test phát hiện, seed.

## 8. Lộ trình triển khai

| Tuần | Việc |
|---|---|
| 6 (xong) | Test plan này + HAL (`fw/hal`) + golden C có sẵn |
| 7 | Dựng `sha256_scoreboard`, `sha256_reg_model`, DPI golden, sequence và các test ở mục 5 (trừ noise); chạy rand với DUT Nguyên bàn giao |
| 8 | Dùng chung vector KAT giữa UVM và firmware Secure Boot trên VP |
| 10 | `sha256_noise_test`, chạy Full SoC |
| 11 | Covergroup mục 6, xuất báo cáo coverage |

## 9. Phụ thuộc và rủi ro

- **RTL SHA-256 chưa hoàn chỉnh** (xem bảng "Điểm cần xử lý" trong `SHA256_Register_Map.md`): các test F-HASH/F-CTL chỉ chạy được sau khi Nguyên sửa xong. Có thể dùng trước slave mô hình hành vi để phát triển sequence/scoreboard song song.
- **Reset khác cực** giữa RTL (active-high) và interface UVM (active-low): xử lý ở `tb_top`.
- **Thông số chưa chốt** (A1, A2): đã tách thành cấu hình để không phải sửa test.