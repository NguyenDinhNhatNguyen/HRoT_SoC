/*
 * main.c -- Master Core firmware: run Secure Boot once (P-13), then relay the App's Mailbox words to UART0 (P-16).
 * The WDT started by Secure Boot is kicked for ever, released or locked, so it only fires on a real hang.
 * Any trap (P-24: access fault, illegal instruction...) goes through crt0.S to trap_handler below
 */
#include "secure_boot.h"
#include "wdt.h"

/* Every trap: lock the App out and report (secure_boot_trap), then wait for ever with the WDT kicked */
void trap_handler(uint32_t mcause, uint32_t mepc, uint32_t mtval)
{
    secure_boot_trap(mcause, mepc, mtval);
    for (;;)
        wdt_kick();
}

int main(void)
{
    sb_result_t r = secure_boot_run();

    for (;;) {
        if (r == SB_RELEASED)
            secure_boot_relay_app();
        wdt_kick();
    }
}
