#include "drv_mock.h"
#include "soc_map.h"
#include <string.h>

uart_mock_t g_uart[2];
gpio_mock_t g_gpio[2];
mbox_mock_t g_mbox;
uint32_t    g_bad_access;

void drv_mock_reset(void)
{
    memset(g_uart, 0, sizeof g_uart);
    memset(g_gpio, 0, sizeof g_gpio);
    memset(&g_mbox, 0, sizeof g_mbox);
    g_bad_access = 0;
    g_uart[0].baud_div = 26;
    g_uart[1].baud_div = 26;
}

void uart_mock_rx_push(int idx, const char *s)
{
    uart_mock_t *u = &g_uart[idx];
    while (*s != '\0' && u->rx_n < 8) {
        u->rx_fifo[(u->rx_head + u->rx_n) % 8] = (uint8_t)*s;
        u->rx_n++;
        s++;
    }
}

static int find(uintptr_t addr, uintptr_t base0, uintptr_t base1, uint32_t *off)
{
    if (addr >= base0 && addr < base0 + 0x1000u) {
        *off = (uint32_t)(addr - base0);
        return 0;
    }
    if (addr >= base1 && addr < base1 + 0x1000u) {
        *off = (uint32_t)(addr - base1);
        return 1;
    }
    return -1;
}

static void uart_drain(uart_mock_t *u)
{
    if (u->tx_stuck || u->tx_n == 0)
        return;
    u->polls++;
    if (u->drain_every != 0 && (u->polls % u->drain_every) != 0)
        return;
    if (u->line_n < sizeof u->line - 1) {
        u->line[u->line_n] = (char)u->tx_fifo[0];
        u->line_n++;
    }
    memmove(u->tx_fifo, u->tx_fifo + 1, 7);
    u->tx_n--;
}

static uint32_t uart_read(uart_mock_t *u, uint32_t off)
{
    uint32_t v;
    switch (off) {
    case UART_RXDATA:
        u->rx_reads++;
        if (u->rx_n == 0)
            return UART_RX_EMPTY;
        v = u->rx_fifo[u->rx_head];
        u->rx_head = (u->rx_head + 1) % 8;
        u->rx_n--;
        return v;
    case UART_STATUS:
        uart_drain(u);
        v = u->err;
        if (u->tx_n == 8)
            v |= UART_ST_TX_FULL;
        if (u->tx_n == 0)
            v |= UART_ST_TX_IDLE;
        if (u->rx_n != 0)
            v |= UART_ST_RX_VALID;
        return v;
    case UART_BAUD_DIV:
        return u->baud_div;
    case UART_IRQ_EN:
        return u->irq_en;
    default:
        return 0;
    }
}

static void uart_write(uart_mock_t *u, uint32_t off, uint32_t v)
{
    switch (off) {
    case UART_TXDATA:
        if (u->tx_n == 8) {
            u->tx_write_when_full++;              /* the hardware drops it */
            return;
        }
        u->tx_fifo[u->tx_n] = (uint8_t)v;
        u->tx_n++;
        return;
    case UART_STATUS:
        u->err &= ~(v & (UART_ST_RX_OVERRUN | UART_ST_FRAME_ERR));
        return;
    case UART_BAUD_DIV:
        u->baud_div = v;
        return;
    case UART_IRQ_EN:
        u->irq_en = v & 3u;
        return;
    default:
        return;
    }
}

static uint32_t gpio_read(gpio_mock_t *g, uint32_t off)
{
    switch (off) {
    case GPIO_DATA_OUT:
        return g->data_out;
    case GPIO_DATA_IN:
        return g->data_in;
    case GPIO_IRQ_EN:
        return g->irq_en;
    case GPIO_IRQ_STAT:
        return g->irq_stat;
    default:
        return 0;
    }
}

static void gpio_write_reg(gpio_mock_t *g, uint32_t off, uint32_t v)
{
    switch (off) {
    case GPIO_DATA_OUT:
        g->data_out = v & 0xFFu;
        return;
    case GPIO_IRQ_EN:
        g->irq_en = v & 0xFFu;
        return;
    case GPIO_IRQ_STAT:
        g->irq_stat &= ~(v & 0xFFu);
        return;
    default:
        return;
    }
}

/* side 0 = A (Secure), side 1 = B (App). OUT of a side fills its slot, IN reads the other side's slot */
static uint32_t mbox_read(int side, uint32_t off)
{
    int other = 1 - side;
    uint32_t w;

    switch (off) {
    case MBOX_IN:
        w = g_mbox.word[other];
        g_mbox.full[other] = 0;
        return w;
    case MBOX_STATUS:
        return (g_mbox.full[other] ? MBOX_ST_IN_FULL : 0u) | (g_mbox.full[side] ? MBOX_ST_OUT_FULL : 0u);
    case MBOX_IRQ_EN:
        return g_mbox.irq_en[side];
    default:
        return 0;
    }
}

static void mbox_write(int side, uint32_t off, uint32_t val)
{
    if (off == MBOX_OUT) {
        if (g_mbox.full[side]) {
            g_mbox.write_when_full++;                       /* the hardware ignores it */
            return;
        }
        g_mbox.word[side] = val;
        g_mbox.full[side] = 1;
        g_mbox.sent[side]++;
    } else if (off == MBOX_IRQ_EN) {
        g_mbox.irq_en[side] = val & 1u;
    }
}

uint32_t hal_host_mmio_read32(uintptr_t addr)
{
    uint32_t off;
    int i = find(addr, MOCK_UART_A, MOCK_UART_B, &off);
    if (i >= 0)
        return uart_read(&g_uart[i], off);
    i = find(addr, MOCK_GPIO_A, MOCK_GPIO_B, &off);
    if (i >= 0)
        return gpio_read(&g_gpio[i], off);
    i = find(addr, MOCK_MBOX_A, MOCK_MBOX_B, &off);
    if (i >= 0)
        return mbox_read(i, off);
    g_bad_access++;
    return 0;
}

void hal_host_mmio_write32(uintptr_t addr, uint32_t val)
{
    uint32_t off;
    int i = find(addr, MOCK_UART_A, MOCK_UART_B, &off);
    if (i >= 0) {
        uart_write(&g_uart[i], off, val);
        return;
    }
    i = find(addr, MOCK_GPIO_A, MOCK_GPIO_B, &off);
    if (i >= 0) {
        gpio_write_reg(&g_gpio[i], off, val);
        return;
    }
    i = find(addr, MOCK_MBOX_A, MOCK_MBOX_B, &off);
    if (i >= 0) {
        mbox_write(i, off, val);
        return;
    }
    g_bad_access++;
}
