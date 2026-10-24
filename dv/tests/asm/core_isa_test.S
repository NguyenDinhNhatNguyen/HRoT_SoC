/*
 * core_isa_test.S -- Chuong trinh tu kiem tra RV32I cho RISCV_Core (5-stage)
 *
 * Kiem tra: forwarding MEM/WB, load-use stall, branch/jump flush, AUIPC/LUI,
 * load/store byte/half/word, x0, goi ham co stack, vong lap.
 *
 * Quy uoc ket qua (giong riscv-tests): ghi vao TOHOST (bo nho du lieu)
 *     1           -> PASS
 *     (n << 1)|1  -> FAIL tai CHECK thu n (x31 = n)
 *
 * Bo nho (Harvard, theo dv/tb/RISCV_Core_prog_tb.sv): ROM lenh tu 0x0,
 * RAM du lieu 0x000-0x3FF rieng biet, TOHOST = 0x3FC, stack bat dau 0x3F0.
 *
 * Tao lai file .hex (can riscv64-unknown-elf-gcc):
 *   riscv64-unknown-elf-gcc -march=rv32i -mabi=ilp32 -nostdlib -Ttext=0 \
 *       -o core_isa_test.elf core_isa_test.S
 *   riscv64-unknown-elf-objcopy -O verilog --verilog-data-width=4 -j .text \
 *       core_isa_test.elf core_isa_test.hex
 */
#define TOHOST 0x3FC

.macro CHECK reg, val
    addi x31, x31, 1
    li   x30, \val
    bne  \reg, x30, fail
.endm

/* Nhu CHECK nhung so voi dia chi cua mot nhan */
.macro CHECK_ADDR reg, sym
    addi x31, x31, 1
    la   x30, \sym
    bne  \reg, x30, fail
.endm

    .text
    .globl _start
_start:
    li   x31, 0                 /* so thu tu CHECK */
    li   sp, 0x3F0

    /* ---- 1. Forwarding MEM->EX, WB->EX ---- */
    addi x1, x0, 5
    addi x27, x1, 3             /* x1 tu MEM */
    add  x3, x1, x27            /* x1 tu WB, x27 tu MEM */
    sub  x4, x3, x1
    CHECK x27, 8
    CHECK x3, 13
    CHECK x4, 8

    /* ---- 2. ALU ---- */
    li   x5, -7
    li   x6, 3
    and  x7, x5, x6
    CHECK x7, 1
    or   x7, x5, x6
    CHECK x7, -5
    xor  x7, x5, x6
    CHECK x7, -6
    sll  x7, x6, x6
    CHECK x7, 24
    srl  x7, x5, x6
    CHECK x7, 0x1FFFFFFF
    sra  x7, x5, x6
    CHECK x7, -1
    slt  x7, x5, x6
    CHECK x7, 1
    sltu x7, x5, x6
    CHECK x7, 0
    slti x7, x5, -6
    CHECK x7, 1
    sltiu x7, x6, -1
    CHECK x7, 1
    srai x7, x5, 1
    CHECK x7, -4
    srli x7, x5, 28
    CHECK x7, 15
    slli x7, x6, 31
    CHECK x7, 0x80000000
    xori x7, x6, -1
    CHECK x7, -4

    /* ---- 3. Load/Store word, load-use, load -> store ---- */
    li   x8, 0x12345678
    sw   x8, 0x100(x0)          /* WriteData forward tu MEM */
    lw   x9, 0x100(x0)
    addi x10, x9, 1             /* load-use: stall 1 chu ky */
    CHECK x10, 0x12345679
    lw   x11, 0x100(x0)
    sw   x11, 0x104(x0)         /* load -> store data */
    lw   x12, 0x104(x0)
    CHECK x12, 0x12345678
    addi x13, x0, 0x100
    lw   x14, 4(x13)            /* base forward tu MEM */
    CHECK x14, 0x12345678

    /* ---- 4. Byte / Half ---- */
    sw   x0, 0x110(x0)
    li   x15, 0xAB
    sb   x15, 0x111(x0)
    li   x15, 0x8001
    sh   x15, 0x112(x0)
    lw   x16, 0x110(x0)
    CHECK x16, 0x8001AB00
    lb   x16, 0x111(x0)
    CHECK x16, 0xFFFFFFAB
    lbu  x16, 0x111(x0)
    CHECK x16, 0xAB
    lh   x16, 0x112(x0)
    CHECK x16, 0xFFFF8001
    lhu  x16, 0x112(x0)
    CHECK x16, 0x8001
    lb   x16, 0x110(x0)
    CHECK x16, 0
    li   x15, 0x7F
    sb   x15, 0x113(x0)         /* ghi de byte 3 */
    lw   x16, 0x110(x0)
    CHECK x16, 0x7F01AB00
    lb   x17, 0x113(x0)
    addi x17, x17, 1            /* load-use voi LB */
    CHECK x17, 0x80

    /* ---- 5. AUIPC / LUI ---- */
    la   x18, label_a           /* auipc + addi: AUIPC forward tu MEM */
label_a:
    auipc x19, 0
    CHECK_ADDR x18, label_a
    CHECK_ADDR x19, label_a
    lui  x20, 0x12345
    addi x20, x20, 0x678
    CHECK x20, 0x12345678

    /* ---- 6. Branch: lenh sau nhanh taken phai bi flush ---- */
    li   x21, 0
    beq  x1, x1, 1f
    addi x21, x21, 1
    addi x21, x21, 1
1:  bne  x1, x1, fail
    blt  x5, x6, 2f             /* -7 < 3 */
    addi x21, x21, 1
2:  bge  x5, x6, fail
    bge  x6, x5, 3f
    addi x21, x21, 1
3:  bltu x5, x6, fail           /* 0xFFFFFFF9 > 3 unsigned */
    bgeu x5, x6, 4f
    addi x21, x21, 1
4:  CHECK x21, 0
    li   x22, 0
    bne  x22, x0, fail          /* branch dung ket qua vua tinh (forward) */

    /* ---- 7. JAL / JALR ---- */
    jal  x23, 5f
link_jal:
    addi x21, x21, 1
5:  CHECK_ADDR x23, link_jal
    CHECK x21, 0
    la   x24, 6f
    addi x24, x24, 1            /* JALR phai xoa bit 0 cua dich */
    jalr x25, 0(x24)
link_jalr:
    addi x21, x21, 1
6:  CHECK_ADDR x25, link_jalr
    CHECK x21, 0

    /* ---- 8. x0 luon bang 0 ---- */
    addi x0, x0, 123
    add  x26, x0, x0
    CHECK x26, 0

    /* ---- 9. Goi ham + stack + vong lap: tong 1..10 ---- */
    li   a0, 10
    call sum_to_n
    CHECK a0, 55
    CHECK sp, 0x3F0             /* stack phai can bang sau ham */

    /* ---- PASS ---- */
    li   x30, 1
    sw   x30, TOHOST(x0)
done:
    j    done

fail:
    slli x30, x31, 1
    ori  x30, x30, 1
    sw   x30, TOHOST(x0)
    j    done

/* a0 = 1 + 2 + ... + a0 (dung stack de luu ra, s0) */
sum_to_n:
    addi sp, sp, -8
    sw   ra, 4(sp)
    sw   s0, 0(sp)
    mv   s0, a0
    li   a0, 0
7:  add  a0, a0, s0
    addi s0, s0, -1
    bnez s0, 7b
    lw   s0, 0(sp)
    lw   ra, 4(sp)
    addi sp, sp, 8
    ret
