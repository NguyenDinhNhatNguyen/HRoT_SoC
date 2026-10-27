/*
 * main.c -- Master Core firmware: run Secure Boot once, then idle (P-13)
 */
#include "secure_boot.h"

int main(void)
{
    (void)secure_boot_run();
    for (;;) {
    }
}
