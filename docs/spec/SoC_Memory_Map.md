# HRoT_SoC v2 — Bản đồ địa chỉ & thanh ghi (thế giới Secure)

> Người giữ: Nguyên (RTL). Cập nhật: 25/10/2026 (Tuần 8, thêm TIMER0 và WDT). Firmware/HAL lấy địa chỉ từ file này.
> Mọi thanh ghi 32-bit, truy cập word căn lề. Ngoại vi APB trả kết quả ngay (0 wait state).

## Bus Master (AXI4-Lite)

| Địa chỉ | Khối | Ghi chú |
| --- | --- | --- |
| `0x0000_0000` 4 KB | Boot ROM | chỉ fetch lệnh (`firmware_imem.hex`) |
| `0x1000_0000` 4 KB | RAM Master | `.rodata/.data/.bss`, stack (`firmware_dmem.hex`) |
| `0x4000_0000` 64 KB | Cầu AXI→APB | bus ngoại vi, mỗi slave 4 KB (bảng dưới) |
| `0x5000_0000` 64 KB | SHA-256 | thanh ghi ở `0x00`–`0x6C`, xem `SHA256_Register_Map.md`. Offset `0x100`–`0xFFFF`: đọc 0, ghi bỏ qua (không alias) |
| `0x6000_0000` 4 KB | ROM App, cổng B | chỉ đọc, ghi → `SLVERR` |
| còn lại | default slave | `DECERR`, không treo bus |

## Bus ngoại vi APB (`0x4000_0000`)

| Địa chỉ | Khối | Trạng thái |
| --- | --- | --- |
| `0x4000_0000` | SYSCSR | Có (Tuần 8) |
| `0x4000_1000` | UART0 | Có (Tuần 8) |
| `0x4000_2000` | GPIO0 | Có (Tuần 8) |
| `0x4000_3000` | TIMER0 | Có (Tuần 8) |
| `0x4000_4000` | WDT | Có (Tuần 8) |
| `0x4000_5000` | PLIC-lite | Tuần 9 |
| `0x4000_6000` | MAILBOX | Tuần 10 |
| `0x4000_7000` | (trống) | `SLVERR` |

Cửa sổ chưa có slave trả `SLVERR`. Offset chưa dùng trong một cửa sổ có slave: đọc ra 0, ghi bị bỏ qua (OKAY).

## SYSCSR (`0x4000_0000`)

| Offset | Tên | Truy cập | Mô tả |
| --- | --- | --- |
| `0x00` | APP_CTRL | RW | bit0 `APP_RUN`: 1 = nhả reset App Core, 0 = giữ reset |
| `0x04` | CHIP_ID | RO | `0x4852_4F54` ("HROT") |
| `0x08` | VERSION | RO | `0x0002_0000` |
| `0x0C` | BOOT_STRAP | RO | [3:0] chân boot strap, chốt lúc reset |
| `0x10` | RST_CAUSE | RW1C | bit0 POR, bit1 WDT, bit2 SW. Chỉ POR hoặc ghi 1 mới xóa (còn nguyên sau SW/WDT reset) |
| `0x14` | SW_RESET | WO | ghi `0x5A5A_0001` → reset toàn thế giới Secure (App bị giữ reset lại) |
| `0x18` | BUS_ERR | RW1C | Lỗi bus đầu tiên của Master kể từ lần xóa gần nhất: bit0 `VALID`, bit1 `WRITE` (1 = ghi), [3:2] `RESP` (2 = SLVERR, 3 = DECERR), bit4 `OVERFLOW` (có thêm lỗi sau lỗi đầu). Ghi 1 vào bit0 để xóa cả thanh ghi |
| `0x1C` | BUS_ERR_ADDR | RO | Địa chỉ của lỗi đang giữ trong BUS_ERR |

## UART0 (`0x4000_1000`) — 8N1, lấy mẫu 16x, FIFO TX/RX 8 byte

| Offset | Tên | Truy cập | Mô tả |
| --- | --- | --- |
| `0x00` | TXDATA | WO | [7:0] đẩy vào FIFO TX (bỏ qua nếu đầy) |
| `0x04` | RXDATA | RO | [7:0] lấy từ FIFO RX (đọc = pop), bit31 = 1 nếu FIFO rỗng |
| `0x08` | STATUS | RO / W1C | bit0 TX_FULL, bit1 TX_IDLE, bit2 RX_VALID, bit3 RX_OVERRUN (W1C), bit4 FRAME_ERR (W1C) |
| `0x0C` | BAUD_DIV | RW | `f_clk / (16 × baud) − 1`. Mặc định 26 = 115200 baud @ 50 MHz. Có hiệu lực ngay |
| `0x10` | IRQ_EN | RW | bit0 ngắt khi RX_VALID, bit1 ngắt khi TX_IDLE |

## GPIO0 (`0x4000_2000`) — 8 ra, 8 vào

| Offset | Tên | Truy cập | Mô tả |
| --- | --- | --- |
| `0x00` | DATA_OUT | RW | [7:0] → chân `gpio0_o` (LED) |
| `0x04` | DATA_IN | RO | [7:0] ← chân `gpio0_i`, đã đồng bộ 2 tầng |
| `0x08` | IRQ_EN | RW | [7:0] bật ngắt cạnh lên theo từng chân |
| `0x0C` | IRQ_STAT | W1C | [7:0] chân đã có cạnh lên |

## TIMER0 (`0x4000_3000`) — kiểu CLINT, `mtime` tăng mỗi chu kỳ clk

| Offset | Tên | Truy cập | Mô tả |
| --- | --- | --- |
| `0x00` | MTIME_LO | RW | `mtime[31:0]` |
| `0x04` | MTIME_HI | RW | `mtime[63:32]`. Đọc 64-bit: HI → LO → HI, đọc lại nếu HI đổi |
| `0x08` | MTIMECMP_LO | RW | `mtimecmp[31:0]` |
| `0x0C` | MTIMECMP_HI | RW | `mtimecmp[63:32]`. Reset = toàn 1 (không ngắt sau reset) |

Chỉ ghi cả word 32-bit. `timer0_irq` mức cao khi `mtime >= mtimecmp` (trễ 1 chu kỳ). Xóa ngắt bằng cách ghi `mtimecmp` mới.
Khi đặt `mtimecmp` 64-bit, ghi `MTIMECMP_HI = 0xFFFF_FFFF` trước, rồi LO, rồi HI thật, để tránh ngắt giả giữa chừng.

## WDT (`0x4000_4000`)

| Offset | Tên | Truy cập | Mô tả |
| --- | --- | --- |
| `0x00` | CTRL | RW | bit0 `EN`: ghi 1 để bật (nạp COUNT = LOAD). Đã bật thì chỉ reset mới tắt |
| `0x04` | LOAD | RW | Số chu kỳ tới hạn, mặc định 50.000.000 (1 s @ 50 MHz). Bị khóa khi `EN = 1` |
| `0x08` | COUNT | RO | Giá trị đếm hiện tại |
| `0x0C` | KICK | WO | Ghi `0x5A5A_0002` → nạp lại COUNT = LOAD. Giá trị khác bị bỏ qua |

COUNT về 0 khi đang bật → reset toàn thế giới Secure qua SYSCSR, `RST_CAUSE.WDT = 1`.

## Ngắt

| Nguồn | Tín hiệu | Đích |
| --- | --- | --- |
| UART0 | `uart0_irq` | PLIC-lite (Tuần 9) |
| GPIO0 | `gpio0_irq` | PLIC-lite (Tuần 9) |
| TIMER0 | `timer0_irq` | thẳng vào `irq_timer` của lõi (chờ P-09, I-01), không qua PLIC |
