/* Models for the Secure Boot host test: App ROM (port B), Boot ROM golden slot, SYSCSR, UART0, GPIO0 */
#ifndef SB_MOCK_H
#define SB_MOCK_H
#include <stdint.h>

typedef struct {
    /* configuration */
    uint8_t  app_rom[4096];             /* App ROM image, bytes in memory order (= the .bin) */
    uint8_t  golden[32];                /* bytes at SB_GOLDEN_ADDR in the Boot ROM */
    int      bus_err_word;              /* >= 0: reading this App ROM word gives a bus error (SLVERR) */
    int      zero_never_done;           /* 1: Boot Guard zeroization never finishes */
    /* SYSCSR state */
    uint32_t app_ctrl;
    uint32_t bus_err;
    uint32_t bus_err_addr;
    uint32_t lock;
    uint32_t guard_polls;
    /* UART0 and GPIO0 */
    char     log[1024];
    uint32_t log_n;
    uint32_t baud_div;
    uint32_t led;
    /* counters */
    uint32_t rom_reads;
    uint32_t bad_access;
} sb_mock_t;

extern sb_mock_t g_sb;
void sb_mock_reset(void);
#endif
