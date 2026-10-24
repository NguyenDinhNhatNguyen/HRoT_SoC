# Sinh boot.hex / app.hex cho soc_tb (mini assembler RV32I)
import sys, os
out = sys.argv[1]

def r(v, n): return v & ((1 << n) - 1)
def I(op, rd, f3, rs1, imm): return r(imm,12)<<20 | rs1<<15 | f3<<12 | rd<<7 | op
def S(rs2, rs1, imm, f3=2): return r(imm>>5,7)<<25 | rs2<<20 | rs1<<15 | f3<<12 | r(imm,5)<<7 | 0x23
def B(f3, rs1, rs2, off):
    o = r(off, 13)
    return (o>>12&1)<<31 | (o>>5&0x3f)<<25 | rs2<<20 | rs1<<15 | f3<<12 | (o>>1&0xf)<<8 | (o>>11&1)<<7 | 0x63
def LUI(rd, imm20): return r(imm20,20)<<12 | rd<<7 | 0x37
def ADDI(rd, rs1, imm): return I(0x13, rd, 0, rs1, imm)
def ANDI(rd, rs1, imm): return I(0x13, rd, 7, rs1, imm)
def LW(rd, rs1, imm): return I(0x03, rd, 2, rs1, imm)
def SW(rs2, rs1, imm): return S(rs2, rs1, imm)
def JAL(rd, off):
    o = r(off, 21)
    return (o>>20&1)<<31 | (o>>1&0x3ff)<<21 | (o>>11&1)<<20 | (o>>12&0xff)<<12 | rd<<7 | 0x6f
def LI(rd, v):
    lo = v & 0xfff; lo = lo - 0x1000 if lo & 0x800 else lo
    return [LUI(rd, (v - lo) >> 12), ADDI(rd, rd, lo)]

APP = [ADDI(1, 0, 42), SW(1, 0, 0), JAL(0, 0)]

prog, labels, fix = [], {}, []
def emit(*ws):
    for w in ws: prog.append(w)
def here(): return 4 * len(prog)
def br(kind, f3, rs1, rs2, label): fix.append((len(prog), kind, f3, rs1, rs2, label)); prog.append(0)

# RAM 0x1000_0000
emit(LUI(10, 0x10000), ADDI(11, 0, 0x55), SW(11, 10, 0), LW(12, 10, 0)); br('b', 1, 12, 11, 'fail')
# SB qua AXI: chi doi byte 1 cua word (kiem WSTRB toi RAM)
emit(*LI(15, 0x11223344), SW(15, 10, 4), ADDI(16, 0, 0xAA), S(16, 10, 5, f3=0), LW(17, 10, 4), *LI(18, 0x1122AA44)); br('b', 1, 17, 18, 'fail')
# SHA-256("abc")
emit(LUI(1, 0x50000), *LI(2, 0x61626380), SW(2, 1, 0))
for i in range(1, 15): emit(SW(0, 1, 4 * i))
emit(ADDI(2, 0, 0x18), SW(2, 1, 60), ADDI(2, 0, 3), SW(2, 1, 0x40))
labels['poll'] = here()
emit(LW(3, 1, 0x44), ANDI(3, 3, 1)); br('b', 0, 3, 0, 'poll')
emit(LW(4, 1, 0x50), *LI(5, 0xba7816bf)); br('b', 1, 4, 5, 'fail')
emit(LW(4, 1, 0x6C), *LI(5, 0xf20015ad)); br('b', 1, 4, 5, 'fail')
# Ghi vao ROM App -> SLVERR, ROM khong doi (kiem o buoc doc ben duoi)
emit(LUI(9, 0x60000), SW(0, 9, 4))
# Dia chi khong ton tai 0x7000_0000 -> DECERR, bus khong treo, doc ra 0
emit(LUI(14, 0x70000), LW(13, 14, 0), SW(13, 14, 0)); br('b', 1, 13, 0, 'fail')
# App ROM port B 0x6000_0000
emit(LUI(9, 0x60000), LW(8, 9, 4), *LI(5, APP[1])); br('b', 1, 8, 5, 'fail')
# Nha reset App Core
emit(LUI(6, 0x40000), ADDI(7, 0, 1), SW(7, 6, 0))
labels['pass'] = here(); emit(JAL(0, 0))
labels['fail'] = here(); emit(JAL(0, 0))
for idx, kind, f3, rs1, rs2, label in fix:
    prog[idx] = B(f3, rs1, rs2, labels[label] - 4 * idx)

def dump(name, ws):
    with open(os.path.join(out, name), 'w') as f:
        f.write("\n".join("%08x" % w for w in ws) + "\n")
dump("boot.hex", prog); dump("app.hex", APP)
with open(os.path.join(out, "labels.vh"), "w") as f:
    f.write("localparam PASS_PC = 32'h%08x, FAIL_PC = 32'h%08x;\n" % (labels['pass'], labels['fail']))
print(len(prog), "words; pass@%x fail@%x" % (labels['pass'], labels['fail']))
