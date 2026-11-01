/* DPI-C golden model for the SHA-256 scoreboard (P-17).
 * Wraps the firmware's reference model fw/hal/test/sha256_ref.c, so the UVM scoreboard, the HAL host
 * test and the VP all check against the same C code. Compiled into every UVM build (Verilator: pass
 * this file on the command line, Questa: vlog compiles it, see sim/run_uvm.do).
 *
 * SV side (dv/env/sha256_scoreboard.svh):
 *   import "DPI-C" function void sha256_ref_compress_dpi(inout int unsigned h[8], input int unsigned w[16]);
 *   import "DPI-C" function int unsigned sha256_ref_iv_dpi(input int i);
 */
#include "../../fw/hal/test/sha256_ref.c"

/* Verilator compiles this file as C++: keep the DPI names unmangled */
#ifdef __cplusplus
extern "C" {
#endif

/* One SHA-256 compression: h = compress(h, w). Words are big-endian message words, H0 first */
void sha256_ref_compress_dpi(unsigned int *h, const unsigned int *w)
{
    uint32_t hh[8];
    uint32_t ww[16];
    int i;

    for (i = 0; i < 8; i++)
        hh[i] = h[i];
    for (i = 0; i < 16; i++)
        ww[i] = w[i];
    sha256_ref_compress(hh, ww);
    for (i = 0; i < 8; i++)
        h[i] = hh[i];
}

/* Initial hash value H0..H7 */
unsigned int sha256_ref_iv_dpi(int i)
{
    return SHA256_REF_IV[i & 7];
}

#ifdef __cplusplus
}
#endif
