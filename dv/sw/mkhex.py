"""Build boot.hex / app.hex / labels.vh for the SoC testbench with a tiny RV32I assembler.

Usage: python3 dv/sw/mkhex.py <out_dir> [--baud-div N]

The Master test firmware exercises the whole Secure world, then does a real secure boot:
hash the 4 KB App ROM once with the CPU and twice with the Secure DMA, compare against golden
hashes stored in the Boot ROM, and release the App only if they match. Otherwise it locks the
App out with Boot Guard. Two golden hashes sit in the Boot ROM (read back through ROM port B):
  GOLD_BE  sha256 of the words as the CPU loads them (message bytes = big-endian bytes of each word)
  GOLD_LE  sha256 of the little-endian memory image, i.e. sha256sum of the .bin (the DMA with SWAP = 1)
"""
import sys, os, struct, hashlib
out = sys.argv[1]
# --baud-div N: UART BAUD_DIV value (0 = 16 clocks/bit for fast sim, 26 = 115200 baud at 50 MHz on a board)
baud_div = int(sys.argv[sys.argv.index('--baud-div') + 1]) if '--baud-div' in sys.argv else 0

def r(v, n):
    return v & ((1 << n) - 1)
def I(op, rd, f3, rs1, imm):
    return r(imm,12)<<20 | rs1<<15 | f3<<12 | rd<<7 | op
def S(rs2, rs1, imm, f3=2):
    return r(imm>>5,7)<<25 | rs2<<20 | rs1<<15 | f3<<12 | r(imm,5)<<7 | 0x23
def B(f3, rs1, rs2, off):
    o = r(off, 13)
    return (o>>12&1)<<31 | (o>>5&0x3f)<<25 | rs2<<20 | rs1<<15 | f3<<12 | (o>>1&0xf)<<8 | (o>>11&1)<<7 | 0x63
def LUI(rd, imm20):
    return r(imm20,20)<<12 | rd<<7 | 0x37
def ADDI(rd, rs1, imm):
    return I(0x13, rd, 0, rs1, imm)
def ANDI(rd, rs1, imm):
    return I(0x13, rd, 7, rs1, imm)
def LW(rd, rs1, imm):
    return I(0x03, rd, 2, rs1, imm)
def SW(rs2, rs1, imm):
    return S(rs2, rs1, imm)
def JAL(rd, off):
    o = r(off, 21)
    return (o>>20&1)<<31 | (o>>1&0x3ff)<<21 | (o>>11&1)<<20 | (o>>12&0xff)<<12 | rd<<7 | 0x6f
def LI(rd, v):
    lo = v & 0xfff
    lo = lo - 0x1000 if lo & 0x800 else lo
    return [LUI(rd, (v - lo) >> 12), ADDI(rd, rd, lo)]

# App image: 3 words of code, the rest of the 4 KB ROM is zero (the whole ROM gets hashed)
APP = [ADDI(1, 0, 42), SW(1, 0, 0), JAL(0, 0)] + [0] * 1021

GOLD_AT   = 0x600                         # byte offset of the golden hashes in the Boot ROM data window
GOLD_BE   = GOLD_AT
GOLD_LE   = GOLD_AT + 0x20
digest_be = hashlib.sha256(b''.join(struct.pack('>I', w) for w in APP)).digest()
digest_le = hashlib.sha256(b''.join(struct.pack('<I', w) for w in APP)).digest()

prog, labels, fix = [], {}, []
def emit(*ws):
    for w in ws: prog.append(w)
def here():
    return 4 * len(prog)
def br(kind, f3, rs1, rs2, label):
    fix.append((len(prog), kind, f3, rs1, rs2, label))
    prog.append(0)
uniq = [0]
def new_label(base):
    uniq[0] += 1
    name = "%s%d" % (base, uniq[0])
    labels[name] = here()
    return name

def poll_bit(base_reg, off, mask):
    """spin until (mem[base_reg + off] & mask) != 0, using x21"""
    name = new_label('poll')
    emit(LW(21, base_reg, off), ANDI(21, 21, mask))
    br('b', 0, 21, 0, name)

def check_hash(gold_off, fail_label):
    """compare the 8 SHA-256 result words (x1 = SHA base) with the golden hash in the Boot ROM"""
    for i in range(8):
        emit(LW(4, 1, 0x50 + 4 * i), LW(5, 0, gold_off + 4 * i))
        br('b', 1, 4, 5, fail_label)

# RAM 0x1000_0000
emit(LUI(10, 0x10000), ADDI(11, 0, 0x55), SW(11, 10, 0), LW(12, 10, 0))
br('b', 1, 12, 11, 'fail')
# SB over AXI must change only byte 1 of the word (checks WSTRB all the way to RAM)
emit(*LI(15, 0x11223344), SW(15, 10, 4), ADDI(16, 0, 0xAA), S(16, 10, 5, f3=0), LW(17, 10, 4), *LI(18, 0x1122AA44))
br('b', 1, 17, 18, 'fail')
# SHA-256("abc")
emit(LUI(1, 0x50000), *LI(2, 0x61626380), SW(2, 1, 0))
for i in range(1, 15):
    emit(SW(0, 1, 4 * i))
emit(ADDI(2, 0, 0x18), SW(2, 1, 60), ADDI(2, 0, 3), SW(2, 1, 0x40))
labels['poll'] = here()
emit(LW(3, 1, 0x44), ANDI(3, 3, 1))
br('b', 0, 3, 0, 'poll')
emit(LW(4, 1, 0x50), *LI(5, 0xba7816bf))
br('b', 1, 4, 5, 'fail')
emit(LW(4, 1, 0x6C), *LI(5, 0xf20015ad))
br('b', 1, 4, 5, 'fail')
# A write to the App ROM gets SLVERR and leaves the ROM alone (checked by the read below)
emit(LUI(9, 0x60000), SW(0, 9, 4))
# SYSCSR.BUS_ERR must have caught it: valid, write, SLVERR (0xB) at 0x6000_0004. Then clear it
emit(LUI(20, 0x40000), LW(21, 20, 0x18), ADDI(22, 0, 0xB))
br('b', 1, 21, 22, 'fail')
emit(LW(21, 20, 0x1C), *LI(22, 0x60000004))
br('b', 1, 21, 22, 'fail')
emit(ADDI(22, 0, 1), SW(22, 20, 0x18), LW(21, 20, 0x18))
br('b', 1, 21, 0, 'fail')
# 0x7000_0000 maps to nothing: DECERR, the bus doesn't hang, reads return 0
emit(LUI(14, 0x70000), LW(13, 14, 0), SW(13, 14, 0))
br('b', 1, 13, 0, 'fail')
# BUS_ERR keeps the read DECERR (0xD) and flags the write after it as overflow (0x10). Then clear it
emit(LW(21, 20, 0x18), ADDI(22, 0, 0x1D))
br('b', 1, 21, 22, 'fail')
emit(LW(21, 20, 0x1C), LUI(22, 0x70000))
br('b', 1, 21, 22, 'fail')
emit(ADDI(22, 0, 1), SW(22, 20, 0x18))
# App ROM port B 0x6000_0000
emit(LUI(9, 0x60000), LW(8, 9, 4), *LI(5, APP[1]))
br('b', 1, 8, 5, 'fail')
# APB through the bridge: SYSCSR CHIP_ID, UART0 sends "OK", GPIO0 lights the LEDs, one UART byte back -> LEDs
emit(LUI(20, 0x40000), LW(21, 20, 4), *LI(22, 0x48524F54))
br('b', 1, 21, 22, 'fail')
emit(LUI(23, 0x40001), ADDI(31, 0, baud_div), SW(31, 23, 0xC))   # BAUD_DIV (0 by default for sim)
emit(ADDI(24, 0, ord('O')), SW(24, 23, 0), ADDI(24, 0, ord('K')), SW(24, 23, 0))
emit(LUI(25, 0x40002), ADDI(26, 0, 0xA5), SW(26, 25, 0))       # LED = 0xA5 tells the tb to send a byte on RX
labels['rxwait'] = here()
emit(LW(27, 23, 8), ANDI(27, 27, 4))
br('b', 0, 27, 0, 'rxwait')
emit(LW(28, 23, 4), ANDI(28, 28, 0xFF), SW(28, 25, 0))          # LED = the byte received
emit(LUI(29, 0x40008), LW(30, 29, 0))                           # window past the last APB slave -> SLVERR, no hang

# ---- Secure boot: hash the whole 4 KB App ROM and compare it with the golden hash in the Boot ROM ----
# 1) The CPU copies 64 blocks of 16 words from the App ROM into the SHA-256 block registers
emit(LUI(1, 0x50000), LUI(2, 0x60000), ADDI(3, 0, 64), ADDI(7, 0, 3))   # x7 = CTRL: START | INIT, then START only
labels['blk'] = here()
emit(ADDI(8, 0, 16), ADDI(9, 1, 0))
labels['wd'] = here()
emit(LW(6, 2, 0), SW(6, 9, 0), ADDI(2, 2, 4), ADDI(9, 9, 4), ADDI(8, 8, -1))
br('b', 1, 8, 0, 'wd')
emit(SW(7, 1, 0x40), ADDI(7, 0, 1))
poll_bit(1, 0x44, 1)
emit(ADDI(3, 3, -1))
br('b', 1, 3, 0, 'blk')
# padding block for a 4096-byte message: 0x80, zeros, bit length 0x8000
emit(LUI(4, 0x80000), SW(4, 1, 0))
for i in range(1, 15):
    emit(SW(0, 1, 4 * i))
emit(LUI(4, 0x8), SW(4, 1, 60), SW(7, 1, 0x40))
poll_bit(1, 0x44, 1)
check_hash(GOLD_BE, 'tamper')

# 2) The same hash with the Secure DMA (no byte swap), then with SWAP against the little-endian golden
emit(LUI(20, 0x40007), LUI(23, 0x40005))                         # x20 = DMA, x23 = PLIC-lite

def dma_hash(ctrl, gold_off):
    emit(LUI(21, 0x60000), SW(21, 20, 0), ADDI(21, 0, 64), SW(21, 20, 4), ADDI(21, 0, ctrl), SW(21, 20, 8))
    poll_bit(20, 0xC, 2)                                         # STATUS.DONE
    emit(LW(21, 20, 0xC), ANDI(21, 21, 0xC))                     # no firewall or bus error
    br('b', 1, 21, 0, 'fail')
    emit(LUI(1, 0x50000))
    check_hash(gold_off, 'fail')

dma_hash(0x5, GOLD_BE)                                           # START | PAD
dma_hash(0xF, GOLD_LE)                                           # START | SWAP | PAD | IRQ_EN
# DMA done shows up in PLIC-lite source 2: pending, claimable once enabled, gone after DONE is cleared
emit(LW(22, 23, 0), ANDI(22, 22, 4))
br('b', 0, 22, 0, 'fail')
emit(ADDI(22, 0, 4), SW(22, 23, 4), LW(22, 23, 8), ADDI(24, 0, 3))
br('b', 1, 22, 24, 'fail')
emit(ADDI(21, 0, 2), SW(21, 20, 0xC), LW(22, 23, 0), ANDI(22, 22, 4))
br('b', 1, 22, 0, 'fail')

# 3) Firewall: point the DMA at the Master RAM. It must be blocked before it reaches the bus
emit(LUI(21, 0x10000), SW(21, 20, 0), ADDI(21, 0, 1), SW(21, 20, 4), SW(21, 20, 8))
poll_bit(20, 0xC, 2)
emit(LW(21, 20, 0xC), ADDI(22, 0, 6))                            # DONE | ERR_FW and nothing else
br('b', 1, 21, 22, 'fail')
emit(ADDI(21, 0, 0xE), SW(21, 20, 0xC), LW(21, 20, 0xC))
br('b', 1, 21, 0, 'fail')

# Good image: Boot Guard must still be open. Release the App Core (SYSCSR APP_CTRL at 0x4000_0000)
emit(LUI(24, 0x40000), LW(21, 24, 0x20))
br('b', 1, 21, 0, 'fail')
emit(LUI(6, 0x40000), ADDI(7, 0, 1), SW(7, 6, 0))
labels['pass'] = here()
emit(JAL(0, 0))

# Tampered image: lock the App out for good and clear its RAM, then try to release it anyway (must not work)
labels['tamper'] = here()
emit(LUI(24, 0x40000), ADDI(22, 0, 1), SW(22, 24, 0x20))
poll_bit(24, 0x20, 4)                                            # GUARD.ZERO_DONE
emit(LUI(6, 0x40000), ADDI(7, 0, 1), SW(7, 6, 0))
emit(LUI(25, 0x40002), ADDI(26, 0, 0xEE), SW(26, 25, 0))         # LED = 0xEE
emit(JAL(0, 0))

# Any other check failed: LED = 0xFF and stop
labels['fail'] = here()
emit(LUI(25, 0x40002), ADDI(26, 0, 0xFF), SW(26, 25, 0))
emit(JAL(0, 0))
for idx, kind, f3, rs1, rs2, label in fix:
    prog[idx] = B(f3, rs1, rs2, labels[label] - 4 * idx)

assert 4 * len(prog) <= GOLD_AT, "code overlaps the golden hashes in the Boot ROM"
rom = prog + [0] * (GOLD_AT // 4 - len(prog)) + list(struct.unpack('>8I', digest_be)) + list(struct.unpack('>8I', digest_le))

def dump(name, ws):
    with open(os.path.join(out, name), 'w') as f:
        f.write("\n".join("%08x" % w for w in ws) + "\n")
dump("boot.hex", rom)
dump("app.hex", APP)
with open(os.path.join(out, "labels.vh"), "w") as f:
    f.write("localparam PASS_PC = 32'h%08x, FAIL_PC = 32'h%08x;\n" % (labels['pass'], labels['fail']))
print(len(prog), "words; pass@%x fail@%x tamper@%x" % (labels['pass'], labels['fail'], labels['tamper']))
