from dlib import Page


def dma_fsm():
    p = Page("14 Secure DMA FSM and Firewall Decision", 1560, 1000)
    p.text("Secure DMA FSM and Firewall Decision (rtl/bus/Secure_DMA.v, DMA_Firewall.v)", 40, 8, 1000, 28, 16, True)
    idle = p.block("IDLE", "START with NBLK > 0: BUSY = 1, ptr = SRC, left = NBLK, w = 0, first = 1. NBLK = 0: DONE at once", 60, 120, 300, 100, "sha")
    rd = p.block("RD", "Read the source word at ptr (App ROM). Swap the bytes of the response if SWAP", 480, 120, 300, 100, "sha")
    wr = p.block("WR", "Write the word into SHA W[w]. Then ptr += 4, w += 1", 900, 120, 300, 100, "sha")
    ctl = p.block("CTL", "w = 15: write SHA CTRL = START (and INIT on the first block)", 900, 360, 300, 90, "sha")
    poll = p.block("POLL", "Read SHA STATUS until DONE = 1. A not-done answer polls again", 480, 360, 300, 90, "sha")
    p.wire(idle, rd, "Request read", "sha")
    p.wire(rd, wr, "Word received", "sha")
    p.wire(wr, rd, "w < 15, data blocks", "sha", pts=[(1050, 280), (630, 280)], exit=("0.5", "1"), entry=("0.5", "1"))
    p.wire(wr, ctl, "w = 15", "sha")
    p.wire(ctl, poll, "CTRL written", "sha", exit=("0", "0.4"), entry=("1", "0.4"))
    nxt = p.step("left > 1: left -= 1, w = 0.<br>Back to RD for the next 64-byte block", 480, 540, 300, 60, "sha")
    pad = p.step("left = 1 and PAD: switch to the padding block (in_pad = 1, w = 0).<br>Back to WR to write the padding words, then CTL and POLL", 60, 540, 360, 70, "sha")
    done = p.step("left = 1 without PAD, or the padding block hashed:<br>BUSY = 0, DONE = 1, back to IDLE", 900, 540, 300, 64, "ok")
    p.wire(poll, nxt, "DONE, more blocks", "sha")
    p.wire(poll, pad, "DONE, last block with PAD", "sha", pts=[(240, 420)], exit=("0", "0.5"), entry=("0.5", "0"))
    p.wire(poll, done, "DONE, last block", "ok", pts=[(840, 440), (840, 572)], exit=("1", "0.8"), entry=("0", "0.5"))
    p.wire(nxt, rd, "", "sha", pts=[(440, 570), (440, 170)], exit=("0", "0.5"), entry=("0", "0.5"))
    p.wire(pad, wr, "padding words", "sha", pts=[(30, 575), (30, 70), (1050, 70)], exit=("0", "0.5"), entry=("0.5", "0"), dashed=True)
    err = p.step("In RD, WR, CTL and POLL: fw_viol sets ERR_FW. A bus error response (resp_err) sets ERR_BUS.<br>Either way: BUSY = 0, DONE = 1, back to IDLE, no trap", 60, 720, 580, 70, "bad")
    p.group("Firewall decision for every request (DMA_Firewall.v)", 700, 700, 780, 250, "sec", dashed=False)
    d1 = p.decision("aligned?", 730, 790, 150, 70)
    d2 = p.decision("write?", 930, 790, 130, 70)
    r1 = p.step("Read: App ROM window<br>0x6000_0000 + 4 KB, or<br>SHA STATUS 0x5000_0044?", 1100, 750, 190, 70, "sec")
    r2 = p.step("Write: SHA registers<br>0x5000_0000 to 0x5000_0043?", 1100, 850, 190, 60, "sec")
    ok = p.term("allow", 1340, 765, 120, 40, "ok")
    no = p.term("violation: ERR_FW", 1310, 860, 160, 40, "bad")
    p.wire(d1, d2, "Yes", "n")
    p.wire(d1, no, "No", "bad", pts=[(805, 925), (1390, 925)], exit=("0.5", "1"), entry=("0.5", "1"))
    p.wire(d2, r1, "No (read)", "n", exit=("1", "0.3"), entry=("0", "0.5"))
    p.wire(d2, r2, "Yes (write)", "n", exit=("1", "0.7"), entry=("0", "0.5"))
    p.wire(r1, ok, "Yes", "ok")
    p.wire(r2, no, "No", "bad")
    p.wire(r1, no, "No", "bad", pts=[(1300, 785), (1300, 880)], exit=("1", "0.8"), entry=("0", "0.5")) if False else None
    return p


def verif_flow():
    p = Page("18 Verification Flow", 1700, 1000)
    p.text("Verification Flow (make test, sim/regress.sh, then the FPGA flow)", 40, 8, 1000, 28, 16, True)
    src = p.block("Sources", "rtl, dv, fw, vp, sim scripts", 30, 300, 170, 80, "neutral")
    g = p.group("make test (QuestaSim 10.2c and SystemC, run in WSL)", 250, 50, 1050, 570, "bus")
    col = [
        ("Core", 280, [("11 unit testbenches", "core"), ("ISA program, trap test", "core"), ("RISCV_Core_tb", "core"), ("Hazard test", "core")]),
        ("UVM", 530, [("AXI4-Lite full", "per"), ("Reset mid-transaction", "per"), ("SHA-256, SHA-256 with reset", "per"), ("APB peripherals", "per")]),
        ("IP", 780, [("HAL SHA-256 on host", "sha"), ("APB peripherals (79 checks)", "per"), ("Boot_Verifier_tb (30 checks)", "sec")]),
        ("SoC", 1030, [("Secure boot: good, +TAMPER", "sys"), ("Firmware: good, tampered, access fault", "sys"), ("App firmware: good, tampered", "sys"), ("Interrupts, both cores", "sys"), ("VP: 4 scenarios", "mem")]),
    ]
    for title, x, items in col:
        p.text(title, x, 80, 200, 24, 13, True)
        yy = 115
        for n, k in items:
            p.block(n, "", x, yy, 230, 50, k)
            yy += 64
    reg = p.block("regress.sh", "Greps each log for its PASS marker. ** Error or Fatal is a failure. A SKIP also fails", 400, 520, 760, 70, "bus")
    res = p.term("PASS / FAIL per check<br>logs in build/logs/", 1360, 520, 250, 70, "ok")
    p.block("make cov", "Questa coverage: 12 runs, 16 covergroups (SHA-256, APB, core) and code coverage", 1360, 380, 250, 110, "per")
    p.wire(src, g, "vsim, vlog, make", "n")
    p.wire(reg, res, "", "ok")
    p.group("FPGA flow (separate from make test)", 250, 680, 1400, 260, "sys")
    de2 = p.block("make de2", "Quartus II 13.0sp1, cyclone II EP2C35", 290, 740, 300, 70, "sys")
    xil = p.block("make xilinx", "Vivado 2025.2, Artix-7 xc7a35t", 290, 840, 300, 70, "sys")
    rep = p.block("fpga/reports", "Fit summary, Fmax, Artix-7 timing and utilization", 700, 790, 300, 70, "sys")
    p.wire(de2, rep, "", "sys", exit=("1", "0.5"), entry=("0", "0.3"))
    p.wire(xil, rep, "", "sys", exit=("1", "0.5"), entry=("0", "0.7"))
    p.wire(src, de2, "", "sys", pts=[(115, 775)], exit=("0.5", "1"), entry=("0", "0.5"), dashed=True)
    p.text("Checks after every RTL change: DE2 memory stays at 135,168 bits and RISCV_Core:master_core appears in the map report. Artix-7: WNS and WHS stay positive. Simulation cannot see these: on 04/11 a ROM with three read ports lost its M4K mapping and Quartus removed the Master Core.", 1050, 760, 570, 120, 12)
    return p
