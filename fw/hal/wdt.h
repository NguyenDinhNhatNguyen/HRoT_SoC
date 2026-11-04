/*
 * wdt.h -- Driver for the Secure-world watchdog (P-13 follow-up, 04/11)
 *
 * Register map: docs/spec/SoC_Memory_Map.md (offsets and bits in soc_map.h). The WDT counts down
 * from LOAD and resets the whole Secure world when it reaches 0 (SYSCSR.RST_CAUSE.WDT). Once on,
 * only a reset turns it off, and LOAD is locked. Boot Guard LOCK survives that reset, so a hang
 * during Secure Boot never lets the App Core run.
 */
#ifndef WDT_H
#define WDT_H

#include <stdint.h>
#include "soc_map.h"

#ifdef __cplusplus
extern "C" {
#endif

#define WDT_LOAD_1S      50000000u      /* 1 s at 50 MHz, the RTL reset value */

/* Set the timeout (cycles) and start the watchdog. LOAD is ignored if it already runs */
void wdt_start(uint32_t load_cycles);

/* Reload COUNT = LOAD */
void wdt_kick(void);

#ifdef __cplusplus
}
#endif
#endif /* WDT_H */
