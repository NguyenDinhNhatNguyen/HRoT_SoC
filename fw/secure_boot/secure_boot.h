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

/* End of the Boot ROM (I-03, settled 04/11), read over the Boot ROM data port. linker.ld keeps code
 * and constants below SB_TAG_ADDR.
 *   0xFC0 HMAC tag, 8 words, for Boot_Verifier MODE 1 (not used yet, the build leaves it zero)
 *   0xFE0 golden hash: sha256sum of the 4 KB App ROM image as a .bin (little-endian words, I-04),
 *         which is what the Secure DMA gives with SWAP on (P-15), stored as 8 big-endian words
 *         H0..H7 so Boot_Verifier can compare it word by word with the SHA-256 result */
#define SB_TAG_ADDR       0x00000FC0u
#define SB_GOLDEN_ADDR    0x00000FE0u
#define SB_APP_VER_OFF    0x00000FFCu    /* APP_VER, last word of the App ROM, inside the hashed image (I-04) */
#define SB_APP_ROM_SIZE   4096u          /* the whole App ROM is hashed, unused words included (I-04) */
#define SB_WDT_LOAD       50000000u      /* WDT timeout: 1 s at 50 MHz, Secure Boot takes about 9 ms */

/* Result, also shown on the GPIO0 LEDs. Every result but SB_RELEASED comes with Boot Guard LOCK
 * (App held until POR, App RAM cleared), except SB_HW_ERROR from a LOCK that did not finish */
typedef enum {
    SB_RELEASED      = 0x01,   /* hash matches: App Core released */
    SB_LOCKED        = 0xEE,   /* hash mismatch */
    SB_BUS_ERROR     = 0xBE,   /* SYSCSR.BUS_ERR or DMA ERR_BUS while hashing or reading the golden hash */
    SB_SELFTEST_FAIL = 0x5F,   /* SHA-256 failed its NIST self-test */
    SB_VERIFY_FAIL   = 0xBF,   /* software compare matched but Boot_Verifier did not say VERIFIED, or the
                                  release gate held APP_RUN (hardware and software disagree, I-08) */
    SB_HW_ERROR      = 0xE0    /* Secure DMA error (firewall, timeout, busy), or LOCK did not finish */
} sb_result_t;

sb_result_t secure_boot_run(void);

/* After SB_RELEASED: if the App Core has sent a Mailbox word, log it on UART0 as
 * "App says <8 hex digits>" (P-16). Does not wait, call it in the idle loop (main.c), which
 * also kicks the WDT */
void secure_boot_relay_app(void);

#ifdef __cplusplus
}
#endif
#endif /* SECURE_BOOT_H */
