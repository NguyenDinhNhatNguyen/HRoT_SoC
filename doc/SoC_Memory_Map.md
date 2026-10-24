# HRoT_SoC v2 — Bản đồ địa chỉ & thanh ghi (thế giới Secure)

> Người giữ: Nguyên (RTL). Cập nhật: Tuần 8. Firmware/HAL lấy địa chỉ từ file này.
> Mọi thanh ghi 32-bit, truy cập word căn lề. Ngoại vi APB trả kết quả ngay (0 wait state).

## Bus Master (AXI4-Lite)

| Địa chỉ | Khối | Ghi chú |
|---|---|---|
| `0x0000_0000` 4 KB | Boot ROM | chỉ fetch lệnh (`firmware_imem.hex`) |
| `0x1000_0000` 4 KB | RAM Master | `.rodata/.data/.bss`, stack (`firmware_dmem.hex`) |
| `0x4000_0000` 64 KB | Cầu AXI→APB | bus ngoại vi, mỗi slave 4 KB (bảng dưới) |
| `0x5000_0000` | SHA-256 | xem `SHA256_Register_Map.md` |
| `0x6000_0000` 4 KB | ROM App, cổng B | chỉ đọc; ghi → `SLVERR` |
| còn lại | default slave | `DECERR`, không treo bus |

## Bus ngoại vi APB (`0x4000_0000`)

| Địa chỉ | Khối | Trạng thái |
|---|---|---|
| `0x4000_0000` | SYSCSR | Tuần 8 |
| `0x4000_1000` | UART0 | Tuần 8 |
| `0x4000_2000` | GPIO0 | Tuần 8 |
| `0x4000_3000` | TIMER0 | Tuần 9 |
| `0x4000_4000` | WDT | Tuần 9 |
| `0x4000_5000` | PLIC-lite | Tuần 9 |
| `0x4000_6000` | MAILBOX | Tuần 10 |
| `0x4000_7000` | (trống) | `SLVERR` |

Offset chưa dùng trong một cửa sổ có slave: đọc ra 0, ghi bị bỏ qua (OKAY).

## SYSCSR (`0x4000_0000`)

| Offset | Tên | Truy cập | Mô tả |
|---|---|---|---|
| `0x00` | APP_CTRL | RW | bit0 `APP_RUN`: 1 = nhả reset App Core, 0 = giữ reset. Tương thích địa chỉ Reset Controller cũ |
| `0x04` | CHIP_ID | RO | `0x4852_4F54` ("HROT") |
| `0x08` | VERSION | RO | `0x0002_0000` |
| `0x0C` | BOOT_STRAP | RO | [3:0] chân boot strap, chốt lúc reset |
| `0x10` | RST_CAUSE | RW1C | bit0 POR, bit1 WDT, bit2 SW. Chỉ POR hoặc ghi 1 mới xóa (còn nguyên sau SW/WDT reset) |
| `0x14` | SW_RESET | WO | ghi `0x5A5A_0001` → reset toàn thế giới Secure (App bị giữ reset lại) |

## UART0 (`0x4000_1000`) — 8N1, lấy mẫu 16x, FIFO TX/RX 8 byte

| Offset | Tên | Truy cập | Mô tả |
|---|---|---|---|
| `0x00` | TXDATA | WO | [7:0] đẩy vào FIFO TX (bỏ qua nếu đầy) |
| `0x04` | RXDATA | RO | [7:0] lấy từ FIFO RX (đọc = pop); bit31 = 1 nếu FIFO rỗng |
| `0x08` | STATUS | RO / W1C | bit0 TX_FULL, bit1 TX_IDLE, bit2 RX_VALID, bit3 RX_OVERRUN (W1C), bit4 FRAME_ERR (W1C) |
| `0x0C` | BAUD_DIV | RW | `f_clk / (16 × baud) − 1`. Mặc định 26 = 115200 baud @ 50 MHz. Có hiệu lực ngay |
| `0x10` | IRQ_EN | RW | bit0 ngắt khi RX_VALID, bit1 ngắt khi TX_IDLE |

## GPIO0 (`0x4000_2000`) — 8 ra, 8 vào

| Offset | Tên | Truy cập | Mô tả |
|---|---|---|---|
| `0x00` | DATA_OUT | RW | [7:0] → chân `gpio0_o` (LED) |
| `0x04` | DATA_IN | RO | [7:0] ← chân `gpio0_i`, đã đồng bộ 2 tầng |
| `0x08` | IRQ_EN | RW | [7:0] bật ngắt cạnh lên theo từng chân |
| `0x0C` | IRQ_STAT | W1C | [7:0] chân đã có cạnh lên |

## Ngắt (nối vào PLIC-lite ở Tuần 9)

| Nguồn | Tín hiệu |
|---|---|
| UART0 | `uart0_irq` |
| GPIO0 | `gpio0_irq` |
