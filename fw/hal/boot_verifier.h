/*
 * boot_verifier.h -- Driver for the Boot_Verifier (N-37, interface I-08)
 *
 * Register map: soc_map.h (BV_*), RTL rtl/periph/Boot_Verifier.v. The block fetches the golden hash
 * from the Boot ROM itself and compares it with what SHA-256 holds, so the release of the App Core
 * does not depend on the firmware's own compare. CHECK is accepted once per reset.
 * Call bv_check() right after the Secure DMA has hashed the App ROM and before anything else uses
 * SHA-256: the block compares the digest SHA-256 holds at that moment. MODE 0 only (golden hash).
 */
#ifndef BOOT_VERIFIER_H
#define BOOT_VERIFIER_H

#include <stdint.h>
#include "soc_map.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Max STATUS reads while waiting for the verdict (the compare takes about 10 cycles) */
#ifndef BV_POLL_LIMIT
#define BV_POLL_LIMIT  1000u
#endif

typedef enum {
    BV_OK          =  0,   /* VERIFIED */
    BV_ERR_FAIL    = -1,   /* FAIL: digest differs, SHA-256 had no finished digest, or APP_VER < MIN_VER */
    BV_ERR_TIMEOUT = -2,   /* no verdict within BV_POLL_LIMIT reads */
    BV_ERR_USED    = -3    /* CHECK was already used since the reset: nothing was done */
} bv_status_t;

/* Write APP_VER, start CHECK in MODE 0 and wait for the verdict */
bv_status_t bv_check(uint32_t app_ver);

/* Set KEY_LOCK: the HMAC key reads 0 from now on, until POR */
void bv_key_lock(void);

#ifdef __cplusplus
}
#endif
#endif /* BOOT_VERIFIER_H */
