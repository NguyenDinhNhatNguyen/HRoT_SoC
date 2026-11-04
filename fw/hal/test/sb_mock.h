/* Models for the Secure Boot host test: App ROM, Boot ROM golden slot, SYSCSR, UART0, GPIO0,
 * Secure DMA and the SHA-256 STATUS/HASH registers the DMA path reads (P-15), Secure side of the Mailbox (P-16),
 * WDT (04/11), Boot_Verifier and the SYSCSR release gate (I-08) */
#ifndef SB_MOCK_H
#define SB_MOCK_H
#include <stdint.h>

typedef struct {
    /* configuration */
    uint8_t  app_rom[4096];             /* App ROM image, bytes in memory order (= the .bin) */
    uint8_t  golden[32];                /* digest stored at SB_GOLDEN_ADDR (read back as big-endian words) */
    int      bus_err_word;              /* >= 0: reading this App ROM word gives a bus error (SLVERR) */
    int      dma_err_fw;                /* 1: the DMA firewall blocks the first request */
    int      dma_never_done;            /* 1: the DMA stays BUSY after START */
    int      dma_busy;                  /* 1: the DMA is already BUSY before the firmware starts it */
    int      sha_busy;                  /* 1: SHA-256 STATUS shows BUSY */
    uint32_t dma_busy_polls;            /* STATUS reads that still show BUSY after START */
    int      golden_bus_err;            /* 1: reading the golden slot gives a bus error (SLVERR) */
    int      zero_never_done;           /* 1: Boot Guard zeroization never finishes */
    int      verify_gate;               /* 1: SYSCSR VERIFY_GATE, APP_RUN only while Boot_Verifier says VERIFIED */
    int      bv_force_fail;             /* 1: Boot_Verifier says FAIL whatever it compares */
    int      bv_never_done;             /* 1: Boot_Verifier stays BUSY after CHECK */
    int      app_run_stuck;             /* 1: SYSCSR never takes APP_RUN (a gate that holds it) */
    uint32_t bv_min_ver;                /* anti-rollback floor */
    /* SYSCSR state */
    uint32_t app_ctrl;
    uint32_t bus_err;
    uint32_t bus_err_addr;
    uint32_t lock;
    uint32_t guard_polls;
    /* Secure DMA */
    uint32_t dma_src;
    uint32_t dma_nblk;
    uint32_t dma_ctrl;                  /* options of the last START (SWAP, PAD, IRQ_EN) */
    uint32_t dma_status;                /* DONE, ERR_FW, ERR_BUS */
    uint32_t dma_pending;
    uint32_t sha_hash[8];               /* HASH[0..7] after the DMA run */
    int      dma_ok;                    /* the last DMA run finished without an error */
    /* Mailbox, Secure side: a word from the App waiting in IN */
    uint32_t mbox_in;
    int      mbox_in_full;
    uint32_t mbox_in_reads;
    /* Boot_Verifier */
    uint32_t bv_app_ver;
    int      bv_checked;
    int      bv_ok;
    int      bv_fail;
    int      bv_key_lock;
    uint32_t bv_checks;                 /* CHECK writes */
    uint32_t bv_busy_polls;
    /* WDT */
    uint32_t wdt_en;
    uint32_t wdt_load;
    uint32_t wdt_kicks;
    uint32_t wdt_bad_key;
    /* UART0 and GPIO0 */
    char     log[1024];
    uint32_t log_n;
    uint32_t baud_div;
    uint32_t led;
    /* counters */
    uint32_t rom_reads;                 /* App ROM words read by the CPU */
    uint32_t dma_starts;
    uint32_t dma_polls;                 /* STATUS reads after START */
    uint32_t hash_reads;
    uint32_t hash_read_early;           /* HASH read while the DMA was busy or after a failed run */
    uint32_t bad_access;
} sb_mock_t;

extern sb_mock_t g_sb;
void sb_mock_reset(void);
#endif
