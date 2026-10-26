/* Behavioural models of UART and GPIO for the host driver test (register map: docs/spec/SoC_Memory_Map.md) */
#ifndef DRV_MOCK_H
#define DRV_MOCK_H
#include <stdint.h>

#define MOCK_UART_A  0x40001000u        /* same as SOC_UART0_BASE */
#define MOCK_UART_B  0x70000000u        /* a second instance at another base (like UART1 of the App world) */
#define MOCK_GPIO_A  0x40002000u        /* same as SOC_GPIO0_BASE */
#define MOCK_GPIO_B  0x70001000u

typedef struct {
    /* configuration */
    int      tx_stuck;                  /* 1: the TX FIFO never drains (timeout test) */
    uint32_t drain_every;               /* one TX byte leaves the FIFO every n STATUS reads (0 = every read) */
    /* registers and state */
    uint32_t baud_div;
    uint32_t irq_en;
    uint32_t err;                       /* RX_OVERRUN | FRAME_ERR, write 1 to clear */
    uint8_t  tx_fifo[8];
    uint32_t tx_n;
    uint32_t polls;
    uint8_t  rx_fifo[8];
    uint32_t rx_head;
    uint32_t rx_n;
    /* what went out on the line, and misuse counters */
    char     line[256];
    uint32_t line_n;
    uint32_t tx_write_when_full;
    uint32_t rx_reads;
} uart_mock_t;

typedef struct {
    uint32_t data_out;
    uint32_t data_in;
    uint32_t irq_en;
    uint32_t irq_stat;
} gpio_mock_t;

extern uart_mock_t g_uart[2];
extern gpio_mock_t g_gpio[2];
extern uint32_t    g_bad_access;        /* accesses to an address no model owns */

void drv_mock_reset(void);
void uart_mock_rx_push(int idx, const char *s);
#endif
