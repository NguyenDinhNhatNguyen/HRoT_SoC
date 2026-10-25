/* Behavioural model of the SHA-256 peripheral (follows the contract in sha256_regs.h) plus fault injection. */
#ifndef SHA256_MOCK_H
#define SHA256_MOCK_H
#include <stdint.h>
typedef struct {
    /* Fault / delay configuration */
    uint32_t busy_polls;      /* STATUS reads that return BUSY before DONE (models the 66-cycle run) */
    int      never_done;      /* 1: never DONE (timeout test)                                        */
    int      stuck_busy;      /* 1: BUSY stuck at 1 (ERR_BUSY test)                                  */
    int      corrupt_hash;    /* 1: flip 1 bit of HASH[0] (selftest must catch it)                   */
    /* Internal state */
    uint32_t block[16];
    uint32_t h[8];
    uint32_t digest[8];
    uint32_t pending;
    uint32_t done;
    uint32_t busy;
    /* Counters used to check HAL behaviour */
    uint32_t n_start;
    uint32_t n_init;
    uint32_t n_block_wr;
    uint32_t n_ctrl_wr;
    uint32_t n_hash_rd;
    uint32_t n_status_rd;
    uint32_t init_on_first_only_ok;  /* 1 if INIT only appears on the first START after a reset */
    uint32_t block_wr_while_busy;
    uint32_t rom_rd_n;                         /* ROM read count */
    uint32_t rom_rd_misaligned;                /* misaligned ROM reads */
    uintptr_t rom_rd_lo;                       /* [lo, hi) range read */
    uintptr_t rom_rd_hi;
} sha256_mock_t;
extern sha256_mock_t g_mock;
void sha256_mock_reset(void);   /* Clear everything, fault configuration included */
#endif
