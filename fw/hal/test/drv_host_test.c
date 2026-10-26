/* UART and GPIO driver unit test on the host (P-11). make -C fw/hal/test test runs it before the SHA-256 HAL test.
 * Prints "DRV RESULT: PASS|FAIL" (not "==== PASSED", which sim/regress.sh reserves for hal_host_test). */
#include "uart.h"
#include "gpio.h"
#include "drv_mock.h"
#include <stdio.h>
#include <string.h>

static int g_fail = 0;
static int g_pass = 0;

#define CHECK(cond, ...)                                    \
    do {                                                    \
        if (cond) {                                         \
            g_pass++;                                       \
        } else {                                            \
            g_fail++;                                       \
            printf("  FAIL %s:%d: ", __FILE__, __LINE__);   \
            printf(__VA_ARGS__);                            \
            printf("\n");                                   \
        }                                                   \
    } while (0)

/* D1: init sets the divisor, turns interrupts off and clears the sticky errors */
static void t_uart_init(void)
{
    printf("[D1] uart_init\n");
    drv_mock_reset();
    g_uart[0].irq_en = 3;
    g_uart[0].err = UART_ST_RX_OVERRUN | UART_ST_FRAME_ERR;
    uart_init(MOCK_UART_A, 13);
    CHECK(g_uart[0].baud_div == 13, "BAUD_DIV = %u", g_uart[0].baud_div);
    CHECK(g_uart[0].irq_en == 0, "IRQ_EN = %u", g_uart[0].irq_en);
    CHECK(g_uart[0].err == 0, "errors not cleared: %x", g_uart[0].err);
    CHECK(UART_DIV_FOR(50000000u, 115200u) == UART_BAUD_DIV_DEFAULT, "UART_DIV_FOR(50 MHz, 115200) = %u",
          UART_DIV_FOR(50000000u, 115200u));
    CHECK(UART_DIV_FOR(50000000u, 9600u) == 325u, "UART_DIV_FOR(50 MHz, 9600) = %u", UART_DIV_FOR(50000000u, 9600u));
}

/* D2: putc/puts wait for room, never write a full FIFO, and turn "\n" into "\r\n" */
static void t_uart_tx(void)
{
    const char *msg = "Secure boot\nhash ok\n";
    printf("[D2] uart_puts with a slow line\n");
    drv_mock_reset();
    g_uart[0].drain_every = 7;                    /* the FIFO fills up and the driver must wait */
    CHECK(uart_puts(MOCK_UART_A, msg) == UART_OK, "puts");
    CHECK(uart_flush(MOCK_UART_A) == UART_OK, "flush");
    CHECK(!strcmp(g_uart[0].line, "Secure boot\r\nhash ok\r\n"), "line = \"%s\"", g_uart[0].line);
    CHECK(g_uart[0].tx_write_when_full == 0, "%u writes while TX_FULL", g_uart[0].tx_write_when_full);
    CHECK(uart_puts(MOCK_UART_A, 0) == UART_OK, "puts(NULL) is a no-op");
}

/* D3: hex output */
static void t_uart_hex(void)
{
    printf("[D3] uart_put_hex32\n");
    drv_mock_reset();
    CHECK(uart_put_hex32(MOCK_UART_A, 0xDEADBEEFu) == UART_OK, "hex");
    CHECK(uart_put_hex32(MOCK_UART_A, 0x0000000Au) == UART_OK, "hex");
    CHECK(uart_flush(MOCK_UART_A) == UART_OK, "flush");
    CHECK(!strcmp(g_uart[0].line, "deadbeef0000000a"), "line = \"%s\"", g_uart[0].line);
}

/* D4: a stuck TX FIFO gives a timeout instead of a hang */
static void t_uart_timeout(void)
{
    int i;
    printf("[D4] TX timeout\n");
    drv_mock_reset();
    g_uart[0].tx_stuck = 1;
    for (i = 0; i < 8; i++)
        CHECK(uart_putc(MOCK_UART_A, 'x') == UART_OK, "byte %d fits in the FIFO", i);
    CHECK(uart_putc(MOCK_UART_A, 'y') == UART_ERR_TIMEOUT, "9th byte times out");
    CHECK(uart_flush(MOCK_UART_A) == UART_ERR_TIMEOUT, "flush times out");
    CHECK(g_uart[0].tx_write_when_full == 0, "no write while TX_FULL");
}

/* D5: RX reads pop exactly one byte each and report an empty FIFO as -1 */
static void t_uart_rx(void)
{
    printf("[D5] uart_getc\n");
    drv_mock_reset();
    uart_mock_rx_push(0, "OK");
    CHECK(uart_status(MOCK_UART_A) & UART_ST_RX_VALID, "RX_VALID");
    CHECK(uart_getc(MOCK_UART_A) == 'O', "first byte");
    CHECK(uart_getc(MOCK_UART_A) == 'K', "second byte");
    CHECK(uart_getc(MOCK_UART_A) == -1, "empty");
    CHECK(g_uart[0].rx_reads == 3, "one RXDATA read per call, got %u", g_uart[0].rx_reads);
    uart_mock_rx_push(0, "\xff");
    CHECK(uart_getc(MOCK_UART_A) == 0xFF, "byte 0xFF is data, not -1");
}

/* D6: error clear and interrupt enable */
static void t_uart_misc(void)
{
    printf("[D6] uart_clear_errors, uart_set_irq\n");
    drv_mock_reset();
    g_uart[0].err = UART_ST_FRAME_ERR;
    CHECK(uart_status(MOCK_UART_A) & UART_ST_FRAME_ERR, "FRAME_ERR set");
    uart_clear_errors(MOCK_UART_A);
    CHECK((uart_status(MOCK_UART_A) & UART_ST_FRAME_ERR) == 0, "FRAME_ERR cleared");
    uart_set_irq(MOCK_UART_A, 0xFFu);
    CHECK(g_uart[0].irq_en == 3, "IRQ_EN = %u (only bits 1:0)", g_uart[0].irq_en);
}

/* D7: GPIO outputs, inputs and edge flags */
static void t_gpio(void)
{
    printf("[D7] gpio\n");
    drv_mock_reset();
    gpio_write(MOCK_GPIO_A, 0x5A);
    CHECK(g_gpio[0].data_out == 0x5A, "DATA_OUT = %x", g_gpio[0].data_out);
    CHECK(gpio_read_out(MOCK_GPIO_A) == 0x5A, "read back");
    gpio_set(MOCK_GPIO_A, 0x81);
    CHECK(g_gpio[0].data_out == 0xDB, "set -> %x", g_gpio[0].data_out);
    gpio_clear(MOCK_GPIO_A, 0x0F);
    CHECK(g_gpio[0].data_out == 0xD0, "clear -> %x", g_gpio[0].data_out);
    gpio_toggle(MOCK_GPIO_A, 0xF0);
    CHECK(g_gpio[0].data_out == 0x20, "toggle -> %x", g_gpio[0].data_out);
    g_gpio[0].data_in = 0xC3;
    CHECK(gpio_read_in(MOCK_GPIO_A) == 0xC3, "DATA_IN");
    gpio_set_irq(MOCK_GPIO_A, 0x0F);
    CHECK(g_gpio[0].irq_en == 0x0F, "IRQ_EN");
    g_gpio[0].irq_stat = 0x09;
    CHECK(gpio_irq_pending(MOCK_GPIO_A) == 0x09, "IRQ_STAT");
    gpio_irq_clear(MOCK_GPIO_A, 0x01);
    CHECK(g_gpio[0].irq_stat == 0x08, "W1C clears only bit 0 -> %x", g_gpio[0].irq_stat);
}

/* D8: the same driver serves a second block at another base (UART1/GPIO1 of the App world) */
static void t_second_instance(void)
{
    printf("[D8] second instance\n");
    drv_mock_reset();
    uart_init(MOCK_UART_B, 5);
    CHECK(uart_puts(MOCK_UART_B, "app") == UART_OK, "puts B");
    CHECK(uart_flush(MOCK_UART_B) == UART_OK, "flush B");
    gpio_write(MOCK_GPIO_B, 0x3C);
    CHECK(!strcmp(g_uart[1].line, "app") && g_uart[1].baud_div == 5, "UART B");
    CHECK(g_uart[0].line_n == 0 && g_uart[0].baud_div == 26, "UART A untouched");
    CHECK(g_gpio[1].data_out == 0x3C && g_gpio[0].data_out == 0, "GPIO B only");
    CHECK(g_bad_access == 0, "%u accesses outside the blocks", g_bad_access);
}

int main(void)
{
    t_uart_init();
    t_uart_tx();
    t_uart_hex();
    t_uart_timeout();
    t_uart_rx();
    t_uart_misc();
    t_gpio();
    t_second_instance();
    printf("\nSUMMARY DRV: PASS = %d | FAIL = %d\n", g_pass, g_fail);
    printf("DRV RESULT: %s\n", g_fail ? "FAIL" : "PASS");
    return g_fail != 0;
}
