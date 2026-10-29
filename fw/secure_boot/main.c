/*
 * main.c -- Master Core firmware: run Secure Boot once (P-13), then relay the App's Mailbox words to UART0 (P-16)
 */
#include "secure_boot.h"

int main(void)
{
    if (secure_boot_run() == SB_RELEASED) {
        for (;;)
            secure_boot_relay_app();
    }
    for (;;) {
    }
}
