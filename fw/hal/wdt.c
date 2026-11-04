/*
 * wdt.c -- Watchdog driver (see wdt.h)
 */
#include "wdt.h"
#include "hal_io.h"

void wdt_start(uint32_t load_cycles)
{
    HAL_WR32(SOC_WDT_BASE, WDT_LOAD, load_cycles);
    HAL_WR32(SOC_WDT_BASE, WDT_CTRL, WDT_CTRL_EN);
}

void wdt_kick(void)
{
    HAL_WR32(SOC_WDT_BASE, WDT_KICK, WDT_KICK_KEY);
}
