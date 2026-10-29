/*
 * main.c -- App Core demo firmware (P-16)
 *
 * Runs only after Secure Boot has hashed the App ROM (this image, padded to 4 KB) and released
 * the App Core.
 * 1. UART1 says "App running" (UART1 has no pin on the DE2, it shows in simulation)
 * 2. APP_MSG_HELLO to the Secure world through the Mailbox, the Master logs it on UART0
 * 3. Running light on the GPIO1 LEDs (LEDG[8:1] on the DE2), one step every APP_STEP_TICKS of
 *    TIMER1, and APP_MSG_STEP | step count to the Secure world after each step
 * The App Core cannot read its ROM as data (app.ld): no strings or tables, so the text goes out
 * one character at a time and uart_puts() is not used.
 */
#include "uart.h"
#include "gpio.h"
#include "mailbox.h"
#include "hal_io.h"
#include "soc_map.h"
#include "app_msg.h"

#ifndef APP_STEP_TICKS
#define APP_STEP_TICKS  12500000u       /* 0.25 s at 50 MHz */
#endif

static void say_running(void)
{
    (void)uart_putc(APP_UART1_BASE, 'A');
    (void)uart_putc(APP_UART1_BASE, 'p');
    (void)uart_putc(APP_UART1_BASE, 'p');
    (void)uart_putc(APP_UART1_BASE, ' ');
    (void)uart_putc(APP_UART1_BASE, 'r');
    (void)uart_putc(APP_UART1_BASE, 'u');
    (void)uart_putc(APP_UART1_BASE, 'n');
    (void)uart_putc(APP_UART1_BASE, 'n');
    (void)uart_putc(APP_UART1_BASE, 'i');
    (void)uart_putc(APP_UART1_BASE, 'n');
    (void)uart_putc(APP_UART1_BASE, 'g');
    (void)uart_putc(APP_UART1_BASE, '\r');
    (void)uart_putc(APP_UART1_BASE, '\n');
}

/* Wait until TIMER1 is ticks past start (unsigned difference, so the 32-bit wrap does no harm) */
static void wait_until(uint32_t start, uint32_t ticks)
{
    while ((uint32_t)(HAL_RD32(APP_TIMER1_BASE, TIMER_MTIME_LO) - start) < ticks) {
    }
}

int main(void)
{
    uint32_t t;
    uint32_t step = 0u;
    uint8_t led = 0x01u;

    uart_init(APP_UART1_BASE, UART_BAUD_DIV_DEFAULT);
    say_running();
    gpio_write(APP_GPIO1_BASE, led);
    (void)mbox_send(APP_MAILBOX_BASE, APP_MSG_HELLO);

    t = HAL_RD32(APP_TIMER1_BASE, TIMER_MTIME_LO);
    for (;;) {
        wait_until(t, APP_STEP_TICKS);
        t += APP_STEP_TICKS;
        led = (uint8_t)((led << 1) | (led >> 7));
        gpio_write(APP_GPIO1_BASE, led);
        step++;
        (void)mbox_send(APP_MAILBOX_BASE, APP_MSG_STEP | (step & 0xFFFFu));
    }
}
