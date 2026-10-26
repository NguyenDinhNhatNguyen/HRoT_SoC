/*
 * hal_io.h -- 32-bit register access for the peripheral drivers (uart.c, gpio.c)
 *
 * On the target every access is a volatile load or store at base + offset.
 * On the host (-DHAL_HOST_MODEL) it goes to hal_host_mmio_read32/write32, so the
 * unit tests in fw/hal/test can model the peripherals.
 */
#ifndef HAL_IO_H
#define HAL_IO_H

#include <stdint.h>

#ifdef HAL_HOST_MODEL
uint32_t hal_host_mmio_read32(uintptr_t addr);
void     hal_host_mmio_write32(uintptr_t addr, uint32_t val);
#define HAL_RD32(base, off)       hal_host_mmio_read32((uintptr_t)(base) + (uintptr_t)(off))
#define HAL_WR32(base, off, val)  hal_host_mmio_write32((uintptr_t)(base) + (uintptr_t)(off), (uint32_t)(val))
#else
#define HAL_RD32(base, off)       (*(volatile uint32_t *)((uintptr_t)(base) + (uintptr_t)(off)))
#define HAL_WR32(base, off, val)  (*(volatile uint32_t *)((uintptr_t)(base) + (uintptr_t)(off)) = (uint32_t)(val))
#endif

#endif /* HAL_IO_H */
