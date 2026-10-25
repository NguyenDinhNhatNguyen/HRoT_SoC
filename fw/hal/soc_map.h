/* soc_map.h - Secure-world address map for firmware (I-02).
 * Source of truth: docs/spec/SoC_Memory_Map.md. Change both together and tell the other side first. */
#ifndef SOC_MAP_H
#define SOC_MAP_H

#include <stdint.h>

#define SOC_BOOT_ROM_BASE    0x00000000u
#define SOC_RAM_BASE         0x10000000u
#define SOC_APB_BASE         0x40000000u
#define SOC_SYSCSR_BASE      (SOC_APB_BASE + 0x0000u)
#define SOC_UART0_BASE       (SOC_APB_BASE + 0x1000u)
#define SOC_GPIO0_BASE       (SOC_APB_BASE + 0x2000u)
#define SOC_TIMER0_BASE      (SOC_APB_BASE + 0x3000u)
#define SOC_WDT_BASE         (SOC_APB_BASE + 0x4000u)
#define SOC_PLIC_BASE        (SOC_APB_BASE + 0x5000u)
#define SOC_MAILBOX_BASE     (SOC_APB_BASE + 0x6000u)
#define SOC_DMA_BASE         (SOC_APB_BASE + 0x7000u)
#define SOC_SHA256_BASE      0x50000000u
#define SOC_APP_ROM_BASE     0x60000000u
#define SOC_MEM_SIZE         0x1000u          /* boot ROM, RAM and App ROM are 4 KB each */
/* Loads from 0x0000_xxxx read the Boot ROM (read-only), so .rodata and the golden hash can live in ROM (I-03) */

#define SOC_REG(base, off)   (*(volatile uint32_t *)((uintptr_t)(base) + (uintptr_t)(off)))

/* SYSCSR */
#define SYSCSR_APP_CTRL      0x00u            /* bit0 APP_RUN */
#define SYSCSR_CHIP_ID       0x04u
#define SYSCSR_VERSION       0x08u
#define SYSCSR_BOOT_STRAP    0x0Cu
#define SYSCSR_RST_CAUSE     0x10u            /* W1C */
#define SYSCSR_SW_RESET      0x14u
#define SYSCSR_BUS_ERR       0x18u            /* W1C, first Master bus error since the last clear */
#define SYSCSR_BUS_ERR_ADDR  0x1Cu
#define SYSCSR_CHIP_ID_HROT  0x48524F54u
#define SYSCSR_SW_RESET_KEY  0x5A5A0001u
#define RST_CAUSE_POR        (1u << 0)
#define RST_CAUSE_WDT        (1u << 1)
#define RST_CAUSE_SW         (1u << 2)
#define BUS_ERR_VALID        (1u << 0)
#define BUS_ERR_WRITE        (1u << 1)
#define BUS_ERR_RESP(v)      (((v) >> 2) & 3u)  /* 2 = SLVERR, 3 = DECERR */
#define BUS_ERR_OVERFLOW     (1u << 4)
#define SYSCSR_GUARD         0x20u            /* write 1 to LOCK: App held in reset until POR, App RAM cleared */
#define GUARD_LOCK           (1u << 0)
#define GUARD_ZERO_BUSY      (1u << 1)
#define GUARD_ZERO_DONE      (1u << 2)

/* UART0 */
#define UART_TXDATA          0x00u
#define UART_RXDATA          0x04u            /* bit31 = RX FIFO empty */
#define UART_STATUS          0x08u
#define UART_BAUD_DIV        0x0Cu            /* f_clk / (16 * baud) - 1, 26 = 115200 at 50 MHz */
#define UART_IRQ_EN          0x10u
#define UART_RX_EMPTY        (1u << 31)
#define UART_ST_TX_FULL      (1u << 0)
#define UART_ST_TX_IDLE      (1u << 1)
#define UART_ST_RX_VALID     (1u << 2)
#define UART_ST_RX_OVERRUN   (1u << 3)
#define UART_ST_FRAME_ERR    (1u << 4)

/* GPIO0 */
#define GPIO_DATA_OUT        0x00u
#define GPIO_DATA_IN         0x04u
#define GPIO_IRQ_EN          0x08u
#define GPIO_IRQ_STAT        0x0Cu            /* W1C */

/* TIMER0 (CLINT-style, full 32-bit writes only) */
#define TIMER_MTIME_LO       0x00u
#define TIMER_MTIME_HI       0x04u
#define TIMER_MTIMECMP_LO    0x08u
#define TIMER_MTIMECMP_HI    0x0Cu

/* WDT */
#define WDT_CTRL             0x00u            /* bit0 EN, only a reset clears it */
#define WDT_LOAD             0x04u            /* locked while EN = 1 */
#define WDT_COUNT            0x08u
#define WDT_KICK             0x0Cu
#define WDT_CTRL_EN          (1u << 0)
#define WDT_KICK_KEY         0x5A5A0002u

/* PLIC-lite: 8 level sources, lowest index wins */
#define PLIC_PENDING         0x00u
#define PLIC_ENABLE          0x04u
#define PLIC_CLAIM           0x08u            /* 1 + index of the lowest pending and enabled source, 0 if none */
#define PLIC_SRC_UART0       (1u << 0)
#define PLIC_SRC_GPIO0       (1u << 1)
#define PLIC_SRC_DMA         (1u << 2)
#define PLIC_SRC_MAILBOX     (1u << 3)

/* Mailbox, same layout on both sides (Secure base SOC_MAILBOX_BASE, App base APP_MAILBOX_BASE) */
#define MBOX_OUT             0x00u            /* write sends a word, ignored while OUT_FULL */
#define MBOX_IN              0x04u            /* read gets the other side's word and clears IN_FULL */
#define MBOX_STATUS          0x08u
#define MBOX_IRQ_EN          0x0Cu            /* bit0: interrupt while IN_FULL */
#define MBOX_ST_IN_FULL      (1u << 0)
#define MBOX_ST_OUT_FULL     (1u << 1)

/* Secure DMA: streams the App ROM into SHA-256. It owns the SHA-256 block while BUSY */
#define DMA_SRC              0x00u            /* reset 0x6000_0000, must stay inside the App ROM */
#define DMA_NBLK             0x04u            /* 64-byte blocks, reset 64 = the whole 4 KB */
#define DMA_CTRL             0x08u
#define DMA_STATUS           0x0Cu            /* DONE, ERR_FW, ERR_BUS are W1C */
#define DMA_CTRL_START       (1u << 0)
#define DMA_CTRL_SWAP        (1u << 1)        /* byte-swap each word: digest = sha256 of the little-endian image */
#define DMA_CTRL_PAD         (1u << 2)        /* hash the padding block after the data */
#define DMA_CTRL_IRQ_EN      (1u << 3)
#define DMA_ST_BUSY          (1u << 0)
#define DMA_ST_DONE          (1u << 1)
#define DMA_ST_ERR_FW        (1u << 2)        /* the firewall blocked a request */
#define DMA_ST_ERR_BUS       (1u << 3)

/* App world: addresses seen by the App Core only. UART, GPIO and TIMER use the same register layouts as above */
#define APP_APB_BASE         0x40000000u
#define APP_UART1_BASE       (APP_APB_BASE + 0x0000u)
#define APP_GPIO1_BASE       (APP_APB_BASE + 0x1000u)
#define APP_TIMER1_BASE      (APP_APB_BASE + 0x2000u)
#define APP_MAILBOX_BASE     (APP_APB_BASE + 0x3000u)

#endif /* SOC_MAP_H */
