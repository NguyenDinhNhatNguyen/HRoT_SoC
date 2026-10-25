# SHA-256 Accelerator — Register Map & Hợp đồng HW/SW

> Người giữ: Phát (HAL). Cập nhật 25/10/2026, khớp RTL `rtl/crypto/SHA256_Wrapper.v` + `SHA256_Core.v` (Nguyên) và VP `vp/src/SHA256_VP_Wrapper.h`. Thông số đã chốt ở giao diện I-05 trong sheet.
> Nguồn sự thật phía phần mềm: `fw/hal/sha256_regs.h` (địa chỉ nền lấy từ `fw/hal/soc_map.h`).

Slave AXI4-Lite tại `0x5000_0000`. `SoC_Top` cấp cho SHA-256 cửa sổ 64 KB (`0x5000_0000`–`0x5000_FFFF`).

| Offset | Tên | Truy cập | Mô tả |
| --- | --- | --- | --- |
| 0x00–0x3C | `BLOCK[0..15]` | W | Khối message 512-bit. `BLOCK[0]` = W0, byte đầu của message nằm ở bit [31:24]. Đọc ra 0 |
| 0x40 | `CTRL` | W | bit0 `START` (tự xóa), bit1 `INIT` |
| 0x44 | `STATUS` | R | bit0 `DONE` (sticky), bit1 `BUSY` |
| 0x48–0x4C | reserved | – | Đọc 0, ghi bỏ qua |
| 0x50–0x6C | `HASH[0..7]` | R | Digest 256-bit. `HASH[0]` = H0 = `hash_out[255:224]` |
| 0x70–0xFFFF | trống | – | Đọc 0, ghi bỏ qua, không alias vào thanh ghi (sửa 25/10, commit `a968cce`) |

Mọi truy cập trong cửa sổ trả `OKAY`. Địa chỉ ngoài mọi slave của bus Master trả `DECERR` (default slave trong `SoC_Top`).

## Hợp đồng hành vi (HAL dựa vào các điều sau)

1. Ghi đủ `BLOCK[0..15]`, rồi ghi `CTRL`. Khối đầu của message ghi `START|INIT`, các khối sau ghi `START` (không `INIT`).
2. `INIT` nạp IV (H0..H7) trước khi nén. Không có `INIT` thì nén **tiếp từ trạng thái H của khối trước** (chaining). Lõi giữ H giữa các khối và cộng H cũ vào kết quả sau 64 vòng.
3. `START` xóa `DONE` và đặt `BUSY` ngay khi giao dịch ghi được chấp nhận (trước khi có BVALID), để HAL không đọc nhầm `DONE` cũ.
4. Xong khối: `BUSY=0`, `DONE=1`, **giữ nguyên đến START kế tiếp** (không phải xung 1 chu kỳ).
5. `HASH` hợp lệ khi `DONE=1`.
6. Ghi `BLOCK`/`START` khi `BUSY=1` bị bỏ qua. HAL chủ động không làm vậy (kiểm `BUSY` trước), UVM kiểm hành vi này ở `sha256_ctl_seq`.
7. Truy cập luôn 32-bit căn lề. Wrapper bỏ qua `WSTRB`, mỗi lần ghi luôn ghi cả word.

## Thông số đã chốt (I-05)

| Mục | Giá trị | Ghi chú |
| --- | --- | --- |
| Độ trễ một khối | **66 chu kỳ** từ lúc `START` được chấp nhận đến `DONE` | Lõi 64 vòng + 1 chu kỳ cộng H, cộng 1 chu kỳ nhận lệnh qua AXI |
| Offset trống trong cửa sổ | `OKAY`, đọc 0, ghi bỏ qua | Gồm `0x48`, `0x4C` và `0x70`–`0xFFFF` |
| Ngoài mọi slave | `DECERR` | Default slave của `SoC_Top` |

## Kiểm chứng

- HAL trên host: `make -C fw/hal/test test` (mô hình hành vi theo đúng hợp đồng trên).
- UVM trên DUT thật (P-08): `sha256_full_test` (KAT, điều khiển, message ngẫu nhiên), `sha256_alias_test` (offset `0x100` trở lên), chạy với `set DUT sha256` trong `sim/run_uvm.do`.
- VP: `make vp` chạy HAL thật trên mô hình SystemC của SHA-256.
