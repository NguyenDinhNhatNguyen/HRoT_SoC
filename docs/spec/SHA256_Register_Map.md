# SHA-256 Accelerator — Register Map & Hợp đồng HW/SW

> Phiên bản: Tuần 6 · Người viết: Phát (HAL) · Cần Nguyên (RTL/VP) xác nhận
> Nguồn sự thật phía phần mềm: `fw/hal/sha256_regs.h`

Slave AXI4-Lite, địa chỉ nền `0x5000_0000` (khớp `SHA256_VP_Wrapper.h`).

| Offset | Tên | Truy cập | Mô tả |
| --- | --- | --- | --- |
| 0x00–0x3C | `BLOCK[0..15]` | W | Khối message 512-bit. `BLOCK[0]` = W0, byte đầu của message nằm ở bit [31:24] |
| 0x40 | `CTRL` | W | bit0 `START` (tự xóa), bit1 `INIT` |
| 0x44 | `STATUS` | R | bit0 `DONE` (sticky), bit1 `BUSY` |
| 0x48–0x4C | reserved | – | Đọc 0, ghi bỏ qua |
| 0x50–0x6C | `HASH[0..7]` | R | Digest 256-bit. `HASH[0]` = H0 = `hash_out[255:224]` |

Offset `0x40`, `0x44`, `0x50` đã có trong RTL/VP hiện tại. Các offset còn lại là **đề xuất mở rộng** để đủ 16 word block và 8 word digest.

## Hợp đồng hành vi (HAL dựa vào các điều sau)

1. Ghi đủ `BLOCK[0..15]`, rồi ghi `CTRL`. Khối đầu của message ghi `START|INIT`; các khối sau ghi `START` (không `INIT`).
2. `INIT` nạp IV (H0..H7) trước khi nén. Không có `INIT` thì nén **tiếp từ trạng thái H của khối trước** (chaining). Lõi phải giữ H giữa các khối và cộng H cũ vào kết quả sau 64 vòng.
3. `START` xóa `DONE` và đặt `BUSY` ngay khi giao dịch ghi được chấp nhận (trước khi có BVALID), để HAL không đọc nhầm `DONE` cũ.
4. Xong khối: `BUSY=0`, `DONE=1`, **giữ nguyên đến START kế tiếp** (không phải xung 1 chu kỳ).
5. `HASH` hợp lệ khi `DONE=1`.
6. Ghi `BLOCK`/`START` khi `BUSY=1` bị bỏ qua. HAL chủ động không làm vậy (kiểm `BUSY` trước), nhưng đây là hành vi UVM sẽ kiểm tra.
7. Truy cập luôn 32-bit căn lề (AXI4-Lite, không truy cập byte).

## Điểm cần xử lý trong RTL hiện tại (phát hiện khi đọc code)

Các điểm dưới đây làm HAL **chưa chạy được trên RTL**, cần Nguyên sửa ở `SHA256_Wrapper.v`/`SHA256_Core.v`:

| # | Vấn đề | Hệ quả |
| --- | --- | --- |
| 1 | Wrapper chỉ phát `start` 1 chu kỳ, còn Core chỉ chạy khi `start` đang ở mức 1 (`else if (start)`) | Core dừng sau vòng đầu. Cần cờ `busy` chốt lại đến khi xong |
| 2 | Core đặt `done <= 0` ngay khi `start=0` | `DONE` chỉ là xung 1 chu kỳ, HAL polling sẽ bỏ lỡ. Cần `DONE` sticky |
| 3 | Core chưa có logic vòng (K, W, Ch/Maj/Σ) và chưa cộng H cũ vào kết quả | Chưa tính ra hash (Tuần 6 của Nguyên) |
| 4 | Wrapper chỉ lưu `block_in[31:0]` (offset 0x00) và chỉ đọc được `hash_out[255:224]` (0x50) | Cần đủ 16 word block và 8 word hash |
| 5 | Chưa có `INIT`, và Core nạp IV chỉ lúc `reset` | Không băm được message thứ hai/nhiều khối. Cần nạp IV theo `INIT` |
| 6 | Wrapper chưa có kênh B (`BVALID/BREADY/BRESP`), `AWREADY/WREADY/ARREADY` không được gán, `RDATA` không có giá trị mặc định | Không đúng AXI4-Lite, mô hình UVM (`axi4_lite_if`) sẽ treo hoặc báo SVA |
| 7 | `SHA256_VP_Wrapper.h` chỉ xử lý 2 địa chỉ (0x40 ghi, 0x44 đọc) | HAL chưa chạy được trên Virtual Platform (cần cho Tuần 8) |

## Câu hỏi mở (cần chốt trước Tuần 7)

- Truy cập địa chỉ ngoài map (`0x48`, `0x4C`, `≥0x70`): trả `OKAY` + đọc 0, hay `SLVERR`? Test plan đang giả định **OKAY/0** (xem mục "Giả định" trong `SHA256_UVM_TestPlan.md`).
- Độ trễ của một khối: chốt là **64 chu kỳ** từ lúc `START` đến `DONE`, hay có thêm chu kỳ nạp/chốt (ví dụ 65–66)? Ảnh hưởng ngưỡng timeout trong test.