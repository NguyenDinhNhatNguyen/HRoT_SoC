/*
 * secure_boot.h -- Secure Boot of the Master Core (P-13)
 *
 * secure_boot_run() checks the App ROM and either releases the App Core or locks it out.
 * It only touches the hardware through the HAL, the UART driver and HAL_RD32/HAL_WR32, so the
 * same code runs on the RTL (fw/secure_boot/main.c), on the virtual platform (vp_sim --fw)
 * and in the host unit test (fw/hal/test/sb_host_test.c).
 */
#ifndef SECURE_BOOT_H
#define SECURE_BOOT_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Golden hash: last 32 bytes of the Boot ROM, read over the Boot ROM data port (I-03).
 * Bytes in digest order: sha256sum of the 4 KB App ROM image as a .bin (little-endian words, I-04).
 * linker.ld keeps code and constants below this address. */
#define SB_GOLDEN_ADDR    0x00000FE0u
#define SB_APP_ROM_SIZE   4096u          /* the whole App ROM is hashed, unused words included (I-04) */

/* Result, also shown on the GPIO0 LEDs */
typedef enum {
    SB_RELEASED      = 0x01,   /* hash matches: App Core released */
    SB_LOCKED        = 0xEE,   /* hash mismatch: Boot Guard LOCK, App RAM cleared, App held until POR */
    SB_BUS_ERROR     = 0xBE,   /* SYSCSR.BUS_ERR set while hashing: App kept in reset */
    SB_SELFTEST_FAIL = 0x5F,   /* SHA-256 failed its NIST self-test: App kept in reset */
    SB_HW_ERROR      = 0xE0    /* SHA-256 HAL error (timeout, busy) or LOCK did not finish: App kept in reset */
} sb_result_t;

sb_result_t secure_boot_run(void);

#ifdef __cplusplus
}
#endif
#endif /* SECURE_BOOT_H */
