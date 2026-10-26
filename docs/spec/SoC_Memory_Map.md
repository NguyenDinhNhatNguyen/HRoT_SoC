# HRoT_SoC v2 — Bản đồ địa chỉ & thanh ghi

> Người giữ: Nguyên (RTL). Cập nhật: 26/10/2026 (thêm Boot Guard, PLIC-lite, Mailbox, Secure DMA, thế giới App). Firmware/HAL lấy địa chỉ từ file này, bản C của nó là `fw/hal/soc_map.h`.
> Mọi thanh ghi 32-bit, truy cập word căn lề. Ngoại vi APB trả kết quả ngay (0 wait state).

## Thế giới Secure: bus Master (AXI4-Lite)

Một master AXI duy nhất, dùng chung cho CPU và Secure DMA (xoay vòng, DMA đi qua tường lửa).

| Địa chỉ | Khối | Ghi chú |
| --- | --- | --- |
| `0x0000_0000` 4 KB | Boot ROM | cổng A: fetch lệnh. Cổng B: lệnh `lw` đọc được ROM, chỉ đọc, ghi → `SLVERR` (để đặt `.rodata` và golden hash trong ROM, I-03). Nạp từ `firmware_imem.hex` |
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
| `0x4000_5000` | PLIC-lite | Có (Tuần 8) |
| `0x4000_6000` | MAILBOX (phía Secure) | Có (Tuần 8) |
| `0x4000_7000` | Secure DMA | Có (Tuần 8) |
| `0x4000_8000` trở đi | (ngoài slave cuối) | `SLVERR` |

Cửa sổ chưa có slave trả `SLVERR`. Offset chưa dùng trong một cửa sổ có slave: đọc ra 0, ghi bị bỏ qua (OKAY).

## SYSCSR (`0x4000_0000`)

| Offset | Tên | Truy cập | Mô tả |
| --- | --- | --- | --- |
| `0x00` | APP_CTRL | RW | bit0 `APP_RUN`: 1 = nhả reset App Core, 0 = giữ reset |
| `0x04` | CHIP_ID | RO | `0x4852_4F54` ("HROT") |
| `0x08` | VERSION | RO | `0x0002_0000` |
| `0x0C` | BOOT_STRAP | RO | [3:0] chân boot strap, chốt lúc reset |
| `0x10` | RST_CAUSE | RW1C | bit0 POR, bit1 WDT, bit2 SW. Chỉ POR hoặc ghi 1 mới xóa (còn nguyên sau SW/WDT reset) |
| `0x14` | SW_RESET | WO | ghi `0x5A5A_0001` → reset toàn thế giới Secure (App bị giữ reset lại) |
| `0x18` | BUS_ERR | RW1C | Lỗi bus đầu tiên của Master kể từ lần xóa gần nhất: bit0 `VALID`, bit1 `WRITE` (1 = ghi), [3:2] `RESP` (2 = SLVERR, 3 = DECERR), bit4 `OVERFLOW` (có thêm lỗi sau lỗi đầu). Ghi 1 vào bit0 để xóa cả thanh ghi |
| `0x1C` | BUS_ERR_ADDR | RO | Địa chỉ của lỗi đang giữ trong BUS_ERR |
| `0x20` | GUARD | RW | Boot Guard. Ghi 1 vào bit0 `LOCK`: giữ App Core trong reset tới khi bật lại nguồn (POR), mặc kệ `APP_CTRL` và mọi SW/WDT reset, đồng thời xóa toàn bộ RAM App. Đọc: bit0 `LOCK`, bit1 `ZERO_BUSY`, bit2 `ZERO_DONE`. Không có cách mở khóa bằng phần mềm |

## UART0 (`0x4000_1000`) — 8N1, lấy mẫu 16x, FIFO TX/RX 8 byte

| Offset | Tên | Truy cập | Mô tả |
| --- | --- | --- | --- |
| `0x00` | TXDATA | WO | [7:0] đẩy vào FIFO TX (bỏ qua nếu đầy) |
| `0x04` | RXDATA | RO | [7:0] lấy từ FIFO RX (đọc = pop), bit31 = 1 nếu FIFO rỗng |
| `0x08` | STATUS | RO / W1C | bit0 TX_FULL, bit1 TX_IDLE, bit2 RX_VALID, bit3 RX_OVERRUN (W1C), bit4 FRAME_ERR (W1C) |
| `0x0C` | BAUD_DIV | RW | `f_clk / (16 × baud) − 1`. Mặc định 26 = 115200 baud @ 50 MHz. Có hiệu lực ngay |
| `0x10` | IRQ_EN | RW | bit0 ngắt khi RX_VALID, bit1 ngắt khi TX_IDLE |

## GPIO0 (`0x4000_2000`) — 8 ra, 8 vào

| Offset | Tên | Truy cập | Mô tả |
| --- | --- | --- | --- |
| `0x00` | DATA_OUT | RW | [7:0] → chân `gpio0_o` (LED) |
| `0x04` | DATA_IN | RO | [7:0] ← chân `gpio0_i`, đã đồng bộ 2 tầng |
| `0x08` | IRQ_EN | RW | [7:0] bật ngắt cạnh lên theo từng chân |
| `0x0C` | IRQ_STAT | W1C | [7:0] chân đã có cạnh lên |

## TIMER0 (`0x4000_3000`) — kiểu CLINT, `mtime` tăng mỗi chu kỳ clk

| Offset | Tên | Truy cập | Mô tả |
| --- | --- | --- | --- |
| `0x00` | MTIME_LO | RW | `mtime[31:0]` |
| `0x04` | MTIME_HI | RW | `mtime[63:32]`. Đọc 64-bit: HI → LO → HI, đọc lại nếu HI đổi |
| `0x08` | MTIMECMP_LO | RW | `mtimecmp[31:0]` |
| `0x0C` | MTIMECMP_HI | RW | `mtimecmp[63:32]`. Reset = toàn 1 (không ngắt sau reset) |

Chỉ ghi cả word 32-bit. `timer0_irq` mức cao khi `mtime >= mtimecmp` (trễ 1 chu kỳ). Xóa ngắt bằng cách ghi `mtimecmp` mới.
Khi đặt `mtimecmp` 64-bit, ghi `MTIMECMP_HI = 0xFFFF_FFFF` trước, rồi LO, rồi HI thật, để tránh ngắt giả giữa chừng.

## WDT (`0x4000_4000`)

| Offset | Tên | Truy cập | Mô tả |
| --- | --- | --- | --- |
| `0x00` | CTRL | RW | bit0 `EN`: ghi 1 để bật (nạp COUNT = LOAD). Đã bật thì chỉ reset mới tắt |
| `0x04` | LOAD | RW | Số chu kỳ tới hạn, mặc định 50.000.000 (1 s @ 50 MHz). Bị khóa khi `EN = 1` |
| `0x08` | COUNT | RO | Giá trị đếm hiện tại |
| `0x0C` | KICK | WO | Ghi `0x5A5A_0002` → nạp lại COUNT = LOAD. Giá trị khác bị bỏ qua |

COUNT về 0 khi đang bật → reset toàn thế giới Secure qua SYSCSR, `RST_CAUSE.WDT = 1`.

## PLIC-lite (`0x4000_5000`) — 8 nguồn mức, nguồn có chỉ số nhỏ nhất thắng

| Offset | Tên | Truy cập | Mô tả |
| --- | --- | --- | --- |
| `0x00` | PENDING | RO | [7:0] trạng thái thô của các nguồn |
| `0x04` | ENABLE | RW | [7:0] bật từng nguồn |
| `0x08` | CLAIM | RO | 1 + chỉ số nguồn nhỏ nhất đang pending và được bật, 0 nếu không có |

Không có ưu tiên riêng, ngưỡng hay chốt claim: nguồn còn pending tới khi thiết bị của nó tự xóa. `irq_ext` = OR của (PENDING & ENABLE), nối vào `irq_ext` của lõi Master (lõi có cổng từ P-09 ngày 26/10, còn chờ nối trong `SoC_Top`, I-01).

## Mailbox (Secure `0x4000_6000`, App `0x4000_3000` trên bus App)

Cầu dữ liệu duy nhất giữa hai thế giới ngoài cổng B của ROM App: mỗi chiều một từ 32-bit kèm cờ FULL. Hai phía có cùng bố cục thanh ghi.

| Offset | Tên | Truy cập | Mô tả |
| --- | --- | --- | --- |
| `0x00` | OUT | RW | Ghi để gửi một từ sang phía kia. Bị bỏ qua khi `OUT_FULL` = 1 |
| `0x04` | IN | RO | Từ phía kia gửi sang. Đọc xong thì xóa `IN_FULL` |
| `0x08` | STATUS | RO | bit0 `IN_FULL` (có từ đang chờ tôi), bit1 `OUT_FULL` (từ của tôi chưa được đọc) |
| `0x0C` | IRQ_EN | RW | bit0: ngắt khi `IN_FULL` |

## Secure DMA (`0x4000_7000`)

Đọc ROM App qua cổng B rồi đẩy vào thanh ghi khối của SHA-256, từng khối 64 byte, nên CPU không phải chép từng từ. Khi `BUSY` thì DMA giữ SHA-256: CPU không được đụng vào.

| Offset | Tên | Truy cập | Mô tả |
| --- | --- | --- | --- |
| `0x00` | SRC | RW | Địa chỉ byte của từ đầu tiên, căn word. Reset `0x6000_0000` |
| `0x04` | NBLK | RW | Số khối 64 byte. Reset 64 (đủ 4 KB). 0 = không làm gì, `DONE` ngay |
| `0x08` | CTRL | RW | bit0 `START` (ghi 1), bit1 `SWAP`, bit2 `PAD`, bit3 `IRQ_EN`. `SWAP` đảo byte từng từ, khi đó digest = sha256 của ảnh little-endian, tức `sha256sum` của file `.bin`. `PAD` băm thêm khối đệm cho thông điệp NBLK × 64 byte |
| `0x0C` | STATUS | RW1C | bit0 `BUSY` (RO), bit1 `DONE`, bit2 `ERR_FW` (tường lửa chặn), bit3 `ERR_BUS` (SLVERR/DECERR). `START` xóa `DONE` và hai bit lỗi |

SRC, NBLK và các tùy chọn CTRL bị khóa khi `BUSY`. Kết quả đọc ở thanh ghi `HASH` của SHA-256 (`0x5000_0050`).

**Tường lửa của DMA:** dù thanh ghi đặt gì, DMA chỉ được đọc cửa sổ ROM App (`0x6000_0000`, 4 KB) và thanh ghi STATUS của SHA-256, chỉ được ghi thanh ghi khối và CTRL của SHA-256 (`0x5000_0000` tới `0x5000_0043`). Mọi yêu cầu khác (RAM, ngoại vi APB, Boot ROM, địa chỉ lạ, lệch word) bị chặn ngay, không tới bus, và `ERR_FW` được bật.

## Thế giới App (chỉ lõi App thấy)

| Địa chỉ | Khối |
| --- | --- |
| `0x4000_0000` | UART1 (cùng bố cục UART0) |
| `0x4000_1000` | GPIO1 (cùng bố cục GPIO0) |
| `0x4000_2000` | TIMER1 (cùng bố cục TIMER0) |
| `0x4000_3000` | MAILBOX (phía App) |
| địa chỉ khác | RAM App 4 KB (alias như trước) |

Lõi App không có đường nào sang bus Secure. Bus APB của App truy cập trong một chu kỳ (lõi không stall) và bỏ qua `PSLVERR` cho tới khi lõi có access fault qua trap (làm sau P-09). Boot Guard xóa RAM App khi `LOCK`.

## Ngắt

| Nguồn | Tín hiệu | Đích |
| --- | --- | --- |
| UART0 | `uart0_irq` | PLIC-lite nguồn 0 |
| GPIO0 | `gpio0_irq` | PLIC-lite nguồn 1 |
| Secure DMA | `dma_irq` | PLIC-lite nguồn 2 |
| Mailbox (từ App đang chờ) | `mbox_irq_s` | PLIC-lite nguồn 3 |
| TIMER0 | `timer0_irq` | thẳng vào `irq_timer` của lõi Master (lõi có cổng từ P-09, chờ nối trong `SoC_Top`, I-01), không qua PLIC |
| PLIC-lite | `plic_irq` | `irq_ext` của lõi Master (lõi có cổng từ P-09, chờ nối trong `SoC_Top`, I-01) |
| TIMER1 | `timer1_irq` | `irq_timer` của lõi App (lõi có cổng từ P-09, chờ nối trong `SoC_Top`) |
| UART1, GPIO1, Mailbox (từ Secure đang chờ) | OR của `uart1_irq`, `gpio1_irq`, `mbox_irq_a` | `irq_ext` của lõi App (lõi có cổng từ P-09, chờ nối trong `SoC_Top`) |
