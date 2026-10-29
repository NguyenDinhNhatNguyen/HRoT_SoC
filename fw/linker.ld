/*
 * linker.ld -- memory map of the Master Core (Secure Boot) firmware
 *
 * The core is Harvard: instructions come from the boot ROM through the fetch port and
 * loads/stores go over the data bus. Since N-21 a load can also read the boot ROM (read-only
 * data port at 0x0000_0000), so constants stay in ROM where nothing can overwrite them (I-03).
 *
 *   ROM  0x0000_0000  4 KB   .text .rodata   -> firmware_imem.hex
 *        0x0000_0FE0  32 B   golden hash of the App ROM (secure_boot.h SB_GOLDEN_ADDR), filled
 *                            in after the build: the golden step of fw/CMakeLists.txt writes it
 *                            into firmware_imem.hex (I-04, P-16), SoC_Fw_tb and the VP write their own
 *   RAM  0x1000_0000  4 KB   .data           -> firmware_dmem.hex
 *                            .bss (cleared by crt0), then the 1 KB stack right after it
 *                            (__stack_top = end of .stack, not the end of RAM)
 *
 * Confirmed with SoC_Top on 25/10 (docs/spec/SoC_Memory_Map.md, fw/hal/soc_map.h): RAM is
 * 4 KB at 0x1000_0000, 0x4000_0000 is the APB bus with SYSCSR at its base (it replaced the
 * old Reset Controller), 0x5000_0000 is SHA-256, 0x6000_0000 is App ROM port B.
 */
OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
    ROM (rx)  : ORIGIN = 0x00000000, LENGTH = 4K - 32     /* the last 32 bytes hold the golden hash */
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
        . = ALIGN(4);
        *(.srodata .srodata.*)
        *(.rodata .rodata.*)
    } > ROM

    .data :
    {
        . = ALIGN(4);
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
