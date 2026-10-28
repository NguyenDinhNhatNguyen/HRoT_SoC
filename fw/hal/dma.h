/*
 * dma.h -- Driver for the Secure DMA (P-15)
 *
 * Register map: docs/spec/SoC_Memory_Map.md (offsets and bits in soc_map.h).
 * The Secure DMA reads 64-byte blocks through the App ROM port B and pushes them into the
 * SHA-256 block registers, then the padding block, so the CPU only programs it and reads the
 * digest. Its firewall only lets it read the App ROM window (0x6000_0000, 4 KB).
 * While BUSY the DMA owns the SHA-256 block (R17): the CPU must not touch SHA-256 and must not
 * have a sha256_hal session open when it starts the DMA.
 * Polling only (no interrupt): the core treats WFI as a NOP, so waiting for an interrupt saves nothing.
 * No libc and no multiply/divide: runs on plain rv32i.
 */
#ifndef DMA_H
#define DMA_H

#include <stdint.h>
#include "soc_map.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Max STATUS reads while waiting for DONE. Hashing the 4 KB App ROM takes about 17,000 cycles on
 * the RTL and one poll with its pause takes more than 50, so this leaves a wide margin */
#ifndef DMA_POLL_LIMIT
#define DMA_POLL_LIMIT     20000u
#endif

/* Empty loop turns between two STATUS reads. Each read goes over the AXI master the DMA uses,
 * so polling without a pause slows the DMA down. The pause only fetches from the Boot ROM */
#ifndef DMA_POLL_PAUSE
#define DMA_POLL_PAUSE     16u
#endif

typedef enum {
    DMA_OK          =  0,
    DMA_ERR_PARAM   = -1,   /* nblk = 0 or too large, src not word aligned                     */
    DMA_ERR_BUSY    = -2,   /* the DMA or the SHA-256 block was already busy: nothing started  */
    DMA_ERR_TIMEOUT = -3,   /* no DONE within DMA_POLL_LIMIT reads. The DMA may still own SHA-256 */
    DMA_ERR_FW      = -4,   /* the firewall blocked a request (source outside the App ROM)     */
    DMA_ERR_BUS     = -5    /* SLVERR or DECERR on the bus (also recorded in SYSCSR.BUS_ERR)   */
} dma_status_t;

/* SHA-256 of nblk 64-byte blocks starting at src, padding included, so the result is the
 * digest of the whole nblk * 64-byte message (32 bytes, standard byte order).
 * swap = 1: each word is byte-swapped, the digest is sha256 of the little-endian image, i.e.
 *           sha256sum of the .bin (I-04, the golden hash of Secure Boot).
 * swap = 0: the message is the big-endian bytes of each word.
 * out is only written on DMA_OK. Once the DMA has finished, DONE and the error bits are cleared. */
dma_status_t dma_sha256(uint32_t src, uint32_t nblk, int swap, uint8_t out[32]);

#ifdef __cplusplus
}
#endif
#endif /* DMA_H */
