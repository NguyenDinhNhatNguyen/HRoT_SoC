/*
 * uart.h -- Driver for UART0 (Secure world) and UART1 (App world), P-11
 *
 * Register map: docs/spec/SoC_Memory_Map.md (offsets and bits in soc_map.h).
 * 8N1, 16x oversampling, 8-byte TX and RX FIFOs. Every function takes the base address of
 * the block (SOC_UART0_BASE, or APP_UART1_BASE on the App Core), so one driver serves both.
 * Polling only: the caller may turn on interrupts with uart_set_irq().
 * No libc and no multiply/divide: runs on plain rv32i.
 */
#ifndef UART_H
#define UART_H

#include <stdint.h>
#include "soc_map.h"

#ifdef __cplusplus
extern "C" {
#endif

/* BAUD_DIV for a compile-time clock and baud rate: f_clk / (16 * baud) - 1, rounded */
#define UART_DIV_FOR(clk_hz, baud)   ((((clk_hz) + 8u * (baud)) / (16u * (baud))) - 1u)
#define UART_BAUD_DIV_DEFAULT        26u      /* 115200 baud at 50 MHz (I-06), the reset value */

/* Max STATUS reads while waiting for room in the TX FIFO or for TX_IDLE */
#ifndef UART_POLL_LIMIT
#define UART_POLL_LIMIT              100000u
#endif

typedef enum {
    UART_OK          =  0,
    UART_ERR_TIMEOUT = -1     /* TX FIFO stayed full (or TX never went idle) for UART_POLL_LIMIT reads */
} uart_status_t;

/* Set the divisor, turn the UART interrupts off and clear the sticky error bits */
void uart_init(uintptr_t base, uint32_t baud_div);

/* Send one byte, waiting while the TX FIFO is full */
uart_status_t uart_putc(uintptr_t base, uint8_t c);

/* Send a NUL-terminated string. "\n" is sent as "\r\n" for a terminal */
uart_status_t uart_puts(uintptr_t base, const char *s);

/* Send v as 8 lower-case hex digits (for hashes, addresses, register dumps) */
uart_status_t uart_put_hex32(uintptr_t base, uint32_t v);

/* Wait until the TX FIFO is empty and the last stop bit is out (before a reset or a LOCK) */
uart_status_t uart_flush(uintptr_t base);

/* Read one byte without waiting: 0..255, or -1 if the RX FIFO is empty */
int uart_getc(uintptr_t base);

/* Raw STATUS (UART_ST_* bits) */
uint32_t uart_status(uintptr_t base);

/* Clear RX_OVERRUN and FRAME_ERR (write 1 to clear) */
void uart_clear_errors(uintptr_t base);

/* IRQ_EN: bit0 interrupt while RX_VALID, bit1 interrupt while TX_IDLE */
void uart_set_irq(uintptr_t base, uint32_t mask);

#ifdef __cplusplus
}
#endif
#endif /* UART_H */
