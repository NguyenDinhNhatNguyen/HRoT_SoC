/*
 * main.c -- Master Core firmware: run Secure Boot once (P-13), then relay the App's Mailbox words to UART0 (P-16).
 * The WDT started by Secure Boot is kicked for ever, released or locked, so it only fires on a real hang
 */
#include "secure_boot.h"
#include "wdt.h"

int main(void)
{
    sb_result_t r = secure_boot_run();

    for (;;) {
        if (r == SB_RELEASED)
            secure_boot_relay_app();
        wdt_kick();
    }
}
