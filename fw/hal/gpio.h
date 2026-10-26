/*
 * gpio.h -- Driver for GPIO0 (Secure world, LEDs) and GPIO1 (App world), P-11
 *
 * Register map: docs/spec/SoC_Memory_Map.md (offsets in soc_map.h). 8 outputs, 8 inputs
 * (inputs synchronised in hardware), rising-edge interrupt flags per input pin.
 * Every function takes the base address of the block (SOC_GPIO0_BASE, or APP_GPIO1_BASE
 * on the App Core). Not thread-safe: gpio_set/clear/toggle read DATA_OUT, then write it.
 */
#ifndef GPIO_H
#define GPIO_H

#include <stdint.h>
#include "soc_map.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Outputs */
void    gpio_write(uintptr_t base, uint8_t value);
uint8_t gpio_read_out(uintptr_t base);
void    gpio_set(uintptr_t base, uint8_t mask);
void    gpio_clear(uintptr_t base, uint8_t mask);
void    gpio_toggle(uintptr_t base, uint8_t mask);

/* Inputs */
uint8_t gpio_read_in(uintptr_t base);

/* Rising-edge flags: enable per pin, read the pending pins, clear them (write 1 to clear) */
void    gpio_set_irq(uintptr_t base, uint8_t mask);
uint8_t gpio_irq_pending(uintptr_t base);
void    gpio_irq_clear(uintptr_t base, uint8_t mask);

#ifdef __cplusplus
}
#endif
#endif /* GPIO_H */
