/*
 * linker.ld -- Ban do bo nho firmware Master Core (Secure Boot)
 *
 * Lõi RISC-V là Harvard: lệnh fetch từ ROM qua cổng lệnh, còn load/store đi
 * qua bus dữ liệu. Lõi KHÔNG đọc được ROM bằng lệnh load, nên mọi dữ liệu
 * (.rodata, .data) phải nằm trong RAM và được nạp sẵn từ firmware_dmem.hex
 * (readmemh khi mô phỏng / init BRAM trên FPGA). Không có bước copy ROM->RAM.
 *
 *   ROM  0x0000_0000  4 KB   .text           -> firmware_imem.hex
 *   RAM  0x1000_0000  4 KB   .rodata .data   -> firmware_dmem.hex
 *                            .bss (crt0 xóa về 0), stack ở cuối RAM
 *
 * ĐỀ XUẤT, cần Nguyên xác nhận khi ghép SoC_Top: địa chỉ RAM 0x1000_0000 trên
 * bus dữ liệu của Master (ngoại vi: 0x4000_0000 Reset Controller,
 * 0x5000_0000 SHA-256). Kích thước khớp Instruction_Memory / Data_Memory (1024 word).
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
        KEEP(*(.text.start))            /* crt0: _start phải ở địa chỉ reset 0x0 */
        *(.text .text.*)
    } > ROM

    .rodata :
    {
        . = ALIGN(4);
        *(.srodata .srodata.*)
        *(.rodata .rodata.*)
    } > RAM

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
