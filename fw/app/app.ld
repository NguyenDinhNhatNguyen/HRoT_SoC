/*
 * app.ld -- memory map of the App Core demo firmware (P-16)
 *
 * The App Core fetches from the App ROM (port A) but its loads and stores only reach the App
 * world APB (0x4xxx_xxxx) and the App RAM (every other address, 4 KB aliased). It has no data
 * path to its ROM and the App RAM is not preloaded, so the firmware must not have .rodata or
 * initialised .data: the ASSERTs below stop the build if the compiler emits any.
 *
 *   ROM  0x0000_0000  4 KB   .text                 -> app_firmware.hex (padded to 4 KB, hashed whole, I-04)
 *   RAM  0x1000_0000  4 KB   .bss (cleared by crt0), then the 1 KB stack
 */
OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
    ROM (rx)  : ORIGIN = 0x00000000, LENGTH = 4K
    RAM (rw)  : ORIGIN = 0x10000000, LENGTH = 4K
}

__stack_size = 1K;

SECTIONS
{
    .text :
    {
        KEEP(*(.text.start))            /* crt0: _start must sit at the reset address 0x0 */
        *(.text .text.*)
    } > ROM

    .rodata :
    {
        *(.srodata .srodata.*)
        *(.rodata .rodata.*)
    } > ROM

    .data :
    {
        *(.sdata .sdata.*)
        *(.data .data.*)
    } > RAM

    .bss (NOLOAD) :
    {
        . = ALIGN(4);
        __bss_start = .;
        *(.sbss .sbss.*)
        *(.bss .bss.*)
        *(COMMON)
        . = ALIGN(4);
        __bss_end = .;
    } > RAM

    .stack (NOLOAD) :
    {
        . = ALIGN(16);
        . += __stack_size;
        __stack_top = .;
    } > RAM

    /DISCARD/ : { *(.eh_frame .eh_frame.*) *(.comment) }
}

ASSERT(SIZEOF(.rodata) == 0, "App firmware has .rodata, but the App Core cannot read its ROM as data")
ASSERT(SIZEOF(.data) == 0, "App firmware has initialised .data, but the App RAM is not preloaded")
