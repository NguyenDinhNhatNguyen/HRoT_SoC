/*
 * gpio.c -- GPIO driver (see gpio.h)
 */
#include "gpio.h"
#include "hal_io.h"

void gpio_write(uintptr_t base, uint8_t value)
{
    HAL_WR32(base, GPIO_DATA_OUT, value);
}

uint8_t gpio_read_out(uintptr_t base)
{
    return (uint8_t)HAL_RD32(base, GPIO_DATA_OUT);
}

void gpio_set(uintptr_t base, uint8_t mask)
{
    gpio_write(base, (uint8_t)(gpio_read_out(base) | mask));
}

void gpio_clear(uintptr_t base, uint8_t mask)
{
    gpio_write(base, (uint8_t)(gpio_read_out(base) & (uint8_t)~mask));
}

void gpio_toggle(uintptr_t base, uint8_t mask)
{
    gpio_write(base, (uint8_t)(gpio_read_out(base) ^ mask));
}

uint8_t gpio_read_in(uintptr_t base)
{
    return (uint8_t)HAL_RD32(base, GPIO_DATA_IN);
}

void gpio_set_irq(uintptr_t base, uint8_t mask)
{
    HAL_WR32(base, GPIO_IRQ_EN, mask);
}

uint8_t gpio_irq_pending(uintptr_t base)
{
    return (uint8_t)HAL_RD32(base, GPIO_IRQ_STAT);
}

void gpio_irq_clear(uintptr_t base, uint8_t mask)
{
    HAL_WR32(base, GPIO_IRQ_STAT, mask);
}
