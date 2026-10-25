/*
 * sha256_regs.h -- register map of the SHA-256 AXI4-Lite slave (SHA256_Wrapper)
 *
 * Firmware-side source of truth for the SHA-256 offsets and bits. The base address comes
 * from soc_map.h (I-02), so the whole address map lives in one place. Matches the RTL
 * (rtl/crypto/SHA256_Wrapper.v) and the VP (vp/src/SHA256_VP_Wrapper.h), settled in I-05.
 * Details and the HW/SW contract: docs/spec/SHA256_Register_Map.md.
 *
 *   Offset       Name          Access  Description
 *   0x00-0x3C    BLOCK[0..15]  W       512-bit message block. BLOCK[0] = W0 (first word,
 *                                      first message byte in bits [31:24])
 *   0x40         CTRL          W       bit0 START (self-clearing), bit1 INIT
 *   0x44         STATUS        R       bit0 DONE (sticky), bit1 BUSY
 *   0x48-0x4C    (reserved)    -       read 0, writes ignored
 *   0x50-0x6C    HASH[0..7]    R       256-bit digest. HASH[0] = H0 = bits [255:224]
 *   0x70-0xFFFF  (empty)       -       read 0, writes ignored
 * One block takes 66 cycles from START to DONE.
 */
#ifndef SHA256_REGS_H
#define SHA256_REGS_H

#include <stdint.h>
#include "soc_map.h"

#ifndef SHA256_BASE_ADDR
#define SHA256_BASE_ADDR     SOC_SHA256_BASE
#endif

#define SHA256_REG_BLOCK(i)  (0x00u + 4u * (uint32_t)(i))   /* i = 0..15 */
#define SHA256_REG_CTRL      0x40u
#define SHA256_REG_STATUS    0x44u
#define SHA256_REG_HASH(i)   (0x50u + 4u * (uint32_t)(i))   /* i = 0..7  */

#define SHA256_BLOCK_WORDS   16u
#define SHA256_HASH_WORDS    8u

/* CTRL */
#define SHA256_CTRL_START    (1u << 0)  /* compress one block (64 rounds)            */
#define SHA256_CTRL_INIT     (1u << 1)  /* load IV H0..H7 first (first block only)    */

/* STATUS */
#define SHA256_STATUS_DONE   (1u << 0)  /* finished, held until the next START        */
#define SHA256_STATUS_BUSY   (1u << 1)  /* compressing                                */

/* Register access
 * On the SoC: volatile MMIO.
 * On the host (-DHAL_HOST_MODEL): routed to a behavioural peripheral model so the unit
 * tests run in WSL without hardware or the VP. */
#ifdef HAL_HOST_MODEL
uint32_t hal_host_read32(uint32_t offset);
void     hal_host_write32(uint32_t offset, uint32_t value);
#define SHA256_RD(off)       hal_host_read32((uint32_t)(off))
#define SHA256_WR(off, val)  hal_host_write32((uint32_t)(off), (uint32_t)(val))
#else
#define SHA256_RD(off) \
    (*(volatile uint32_t *)((uintptr_t)SHA256_BASE_ADDR + (uintptr_t)(off)))
#define SHA256_WR(off, val) \
    (*(volatile uint32_t *)((uintptr_t)SHA256_BASE_ADDR + (uintptr_t)(off)) = (uint32_t)(val))
#endif

/* Read one 32-bit word from memory (App ROM through the Dual-Port ROM). Always an aligned
 * 32-bit access, the AXI4-Lite bus has no byte reads. */
#ifdef HAL_HOST_MODEL
uint32_t hal_host_memread32(uintptr_t addr);   /* records every ROM read for the tests */
#define HAL_MEM_RD32(addr)   hal_host_memread32((uintptr_t)(addr))
#else
#define HAL_MEM_RD32(addr)   (*(volatile const uint32_t *)(uintptr_t)(addr))
#endif
/* ROM reads: sha256_update_mem() only reads ALIGNED 32-bit words, and only the words that
 * hold at least one byte of [addr, addr+len). Extra bytes in the first and last word are
 * read and dropped, never hashed. Memory regions always end on a multiple of 4, so a read
 * never leaves the mapped region as long as the ROM base is 4-byte aligned. */

#endif /* SHA256_REGS_H */
