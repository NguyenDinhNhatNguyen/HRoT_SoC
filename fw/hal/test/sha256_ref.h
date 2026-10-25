/* Software SHA-256 reference model (independent of the HAL).
 * Used as: (1) the core of the peripheral model in the host unit test,
 *          (2) a possible DPI-C golden model for the UVM scoreboard (P-17). */
#ifndef SHA256_REF_H
#define SHA256_REF_H
#include <stdint.h>
#include <stddef.h>
void sha256_ref_compress(uint32_t h[8], const uint32_t w_in[16]);   /* 1 block, big-endian words */
void sha256_ref(const uint8_t *msg, size_t len, uint8_t out[32]);   /* whole message */
extern const uint32_t SHA256_REF_IV[8];
#endif
