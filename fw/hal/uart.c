/*
 * uart.c -- UART driver (see uart.h)
 */
#include "uart.h"
#include "hal_io.h"

static uart_status_t wait_clear(uintptr_t base, uint32_t busy_mask)
{
    uint32_t n;

    for (n = UART_POLL_LIMIT; n != 0u; n--) {
        if ((HAL_RD32(base, UART_STATUS) & busy_mask) == 0u)
            return UART_OK;
    }
    return UART_ERR_TIMEOUT;
}

void uart_init(uintptr_t base, uint32_t baud_div)
{
    HAL_WR32(base, UART_IRQ_EN, 0u);
    HAL_WR32(base, UART_BAUD_DIV, baud_div);
    HAL_WR32(base, UART_STATUS, UART_ST_RX_OVERRUN | UART_ST_FRAME_ERR);
}

uart_status_t uart_putc(uintptr_t base, uint8_t c)
{
    if (wait_clear(base, UART_ST_TX_FULL) != UART_OK)
        return UART_ERR_TIMEOUT;
    HAL_WR32(base, UART_TXDATA, c);
    return UART_OK;
}

uart_status_t uart_puts(uintptr_t base, const char *s)
{
    uart_status_t st;

    if (s == 0)
        return UART_OK;
    while (*s != '\0') {
        if (*s == '\n') {
            st = uart_putc(base, '\r');
            if (st != UART_OK)
                return st;
        }
        st = uart_putc(base, (uint8_t)*s);
        if (st != UART_OK)
            return st;
        s++;
    }
    return UART_OK;
}

uart_status_t uart_put_hex32(uintptr_t base, uint32_t v)
{
    static const char digits[16] = {
        '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f'
    };
    uart_status_t st;
    int shift;

    for (shift = 28; shift >= 0; shift -= 4) {
        st = uart_putc(base, (uint8_t)digits[(v >> shift) & 0xFu]);
        if (st != UART_OK)
            return st;
    }
    return UART_OK;
}

uart_status_t uart_flush(uintptr_t base)
{
    uint32_t n;

    for (n = UART_POLL_LIMIT; n != 0u; n--) {
        if (HAL_RD32(base, UART_STATUS) & UART_ST_TX_IDLE)
            return UART_OK;
    }
    return UART_ERR_TIMEOUT;
}

int uart_getc(uintptr_t base)
{
    uint32_t v = HAL_RD32(base, UART_RXDATA);     /* one read: pops a byte if there is one */

    if (v & UART_RX_EMPTY)
        return -1;
    return (int)(v & 0xFFu);
}

uint32_t uart_status(uintptr_t base)
{
    return HAL_RD32(base, UART_STATUS);
}

void uart_clear_errors(uintptr_t base)
{
    HAL_WR32(base, UART_STATUS, UART_ST_RX_OVERRUN | UART_ST_FRAME_ERR);
}

void uart_set_irq(uintptr_t base, uint32_t mask)
{
    HAL_WR32(base, UART_IRQ_EN, mask & 3u);
}
