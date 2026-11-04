from dlib import Page


def stack(p, cx, y0, items, w=300, gap=34):
    """Place flowchart items top to bottom around centre x. items: (kind, label, h, style kind). Returns ids and (y, h)."""
    ids, pos = [], []
    y = y0
    for kind, label, h, k in items:
        if kind == "term":
            i = p.term(label, cx - (w - 60) // 2, y, w - 60, h, k)
        elif kind == "dec":
            i = p.decision(label, cx - (w + 20) // 2, y, w + 20, h)
        else:
            i = p.step(label, cx - w // 2, y, w, h, k)
        ids.append(i)
        pos.append((y, h))
        y += h + gap
    return ids, pos, y


def tamper_flow():
    p = Page("12 Tamper and Lockdown Flow", 1560, 1100)
    p.text("Tamper and Lockdown Flow (fail() in secure_boot.c with SYSCSR Boot Guard)", 40, 8, 900, 28, 16, True)
    p.group("Firmware (Master Core)", 20, 50, 440, 1010, "core")
    p.group("Hardware (SYSCSR Boot Guard)", 540, 50, 460, 700, "sys")
    fi, fp, _ = stack(p, 240, 100, [
        ("term", "fail(code, why) called<br>(hash mismatch, bus error, trap...)", 52, "bad"),
        ("step", "wdt_kick(), bv_key_lock()<br>hide the HMAC key", 52, "sec"),
        ("step", "Write SYSCSR.GUARD = LOCK", 44, "sys"),
        ("step", "Poll GUARD.ZERO_DONE<br>(limit SB_GUARD_POLL_LIMIT)", 52, "bus"),
        ("dec", "ZERO_DONE seen?", 70, None),
        ("step", "Log the reason on UART0<br>LED = result code, kick WDT", 52, "bus"),
        ("term", "App locked out (result code)", 44, "bad"),
    ], 330)
    for a, b in zip(fi, fi[1:]):
        p.wire(a, b, "", "n")
    bad = p.step("SB_HW_ERROR 0xE0<br>log: LOCK did not finish<br>App stays in reset anyway (LOCK is set)", 380, 790, 300, 66, "bad") if False else None
    hz = p.step("Result SB_HW_ERROR 0xE0: App stays in reset anyway,<br>because LOCK is already set", 70, 880, 340, 60, "bad")
    p.wire(fi[4], hz, "No", "bad", pts=[(45, fp[4][0] + 35), (45, 910)], exit=("0", "0.5"), entry=("0", "0.5"), dashed=True)
    p.text("Yes", 250, fp[4][0] + 72, 40, 20, 11, True, "#2E7D32")
    hi, hp, _ = stack(p, 770, 100, [
        ("step", "LOCK flop set (sticky), zero_busy = 1,<br>zero_cnt = 0", 60, "sec"),
        ("step", "app_rst = 1 at once<br>(sys_rst OR NOT APP_RUN OR LOCK)", 60, "sys"),
        ("step", "Zeroization FSM writes 0 to the App RAM,<br>zero_cnt 0 to 1023 (one word per cycle)", 64, "sec"),
        ("step", "zero_busy = 0, zero_done = 1", 48, "sec"),
    ], 330)
    for a, b in zip(hi, hi[1:]):
        p.wire(a, b, "", "sec")
    p.wire(fi[2], hi[0], "GUARD write", "sys", exit=("1", "0.5"), entry=("0", "0.5"))
    p.wire(hi[3], fi[3], "ZERO_DONE bit", "sec", pts=[(770, 720), (480, 720), (480, fp[3][0] + 26)], exit=("0.5", "1"), entry=("1", "0.5"), dashed=True)
    p.group("After the lockdown", 540, 780, 460, 280, "zone")
    a1 = p.step("Release attempt: write APP_CTRL = 1", 560, 830, 420, 40, "sys")
    a2 = p.decision("LOCK = 1?", 640, 890, 260, 70)
    a3 = p.step("App stays in reset. The APP_CTRL write has no effect", 560, 985, 420, 50, "bad")
    p.wire(a1, a2, "", "n")
    p.wire(a2, a3, "Yes (always, until POR)", "bad")
    c = p.group("Which resets clear LOCK?", 1040, 50, 480, 360, "zone")
    r1 = p.step("Software reset (SW_RESET key 0x5A5A_0001)<br>LOCK survives, App stays in reset", 1060, 110, 440, 60, "bad")
    r2 = p.step("Watchdog reset<br>LOCK survives, App stays in reset", 1060, 200, 440, 60, "bad")
    r3 = p.step("Power-on reset (POR)<br>LOCK cleared, the boot starts again from the beginning", 1060, 290, 440, 60, "ok")
    t = p.group("Tests that cover this flow", 1040, 440, 480, 300, "zone")
    p.text("SoC_Top_tb +TAMPER: one bit of the App ROM flipped. Expected: App stays in reset, RAM reads 0, LED 0xEE, and a later APP_CTRL write fails.", 1060, 490, 440, 60, 12)
    p.text("SoC_Fw_tb and SoC_App_tb with +TAMPER: the real firmware locks the App out and the Boot_Verifier never reaches VERIFIED.", 1060, 570, 440, 60, 12)
    p.text("SoC_Fw_tb +FAULT: an access fault on the APP_VER load reaches the trap handler, which runs the same lockdown (mcause 5).", 1060, 650, 440, 60, 12)
    return p


def check_fsm():
    p = Page("13 Boot_Verifier CHECK FSM", 1560, 1180)
    p.text("Boot_Verifier CHECK FSM (rtl/periph/Boot_Verifier.v)", 40, 8, 900, 28, 16, True)
    ids, pos, y_end = stack(p, 420, 60, [
        ("term", "sys_rst: verdict cleared (CHECKED, VERIFIED, FAIL = 0), state IDLE", 52, "ok"),
        ("dec", "IDLE: write CTRL with CHECK = 1<br>and CHECKED = 0?", 90, None),
        ("step", "CHECKED = 1 (a second CHECK is ignored)", 44, "sec"),
        ("dec", "SHA done and not busy<br>and APP_VER >= MIN_VER?", 90, None),
        ("step", "FETCH: cnt = 0, mismatch = 0<br>rom_addr = MODE ? 0xFC0 (HMAC tag) : 0xFE0 (golden hash)", 64, "sec"),
        ("step", "Each cycle: ROM word = digest word H[cnt]?<br>If not, mismatch = 1. rom_addr += 4, cnt += 1", 64, "sec"),
        ("dec", "cnt = 7 (last word)?", 70, None),
        ("dec", "mismatch, or last word differs?", 80, None),
        ("step", "VERIFIED = 1, MIN_VER = APP_VER", 48, "ok"),
        ("term", "Back to IDLE (verdict is held)", 44, "neutral"),
    ], 360)
    (st, chk, c1, d2, fe, lp, d3, d4, okk, end) = ids
    p.wire(st, chk, "", "n")
    p.wire(chk, c1, "Yes", "n")
    p.wire(c1, d2, "", "n")
    p.wire(d2, fe, "Yes", "n")
    p.wire(fe, lp, "", "n")
    p.wire(lp, d3, "", "n")
    p.wire(d3, d4, "Yes", "n")
    p.wire(d4, okk, "No", "ok")
    p.wire(okk, end, "", "n")
    p.wire(d3, lp, "No (next word)", "n", pts=[(730, pos[6][0] + 35), (730, pos[5][0] + 32)], exit=("1", "0.5"), entry=("1", "0.5"))
    fail = p.step("FAIL = 1<br>(App stays held, firmware calls fail())", 880, pos[3][0] + 20, 340, 56, "bad")
    p.wire(d2, fail, "No", "bad", exit=("1", "0.5"), entry=("0", "0.5"))
    p.wire(d4, fail, "Yes", "bad", pts=[(880, pos[7][0] + 40), (880, pos[3][0] + 48)], exit=("1", "0.5"), entry=("0", "0.7"))
    p.wire(chk, end, "No (ignored)", "n", dashed=True, pts=[(120, pos[1][0] + 45), (120, pos[9][0] + 22)], exit=("0", "0.5"), entry=("0", "0.5"))
    p.wire(fail, end, "", "bad", pts=[(1050, pos[9][0] + 22)], exit=("0.5", "1"), entry=("1", "0.5"), dashed=True)
    p.group("STATUS register (offset 0x04)", 880, 60, 340, 200, "sec", dashed=False)
    p.text("bit 0 VERIFIED<br>bit 1 FAIL<br>bit 2 KEY_LOCKED<br>bit 3 CHECKED<br>bit 4 BUSY (state = FETCH)", 900, 100, 300, 140, 12)
    p.text("Rules: CHECK runs once per system reset. A passing CHECK raises MIN_VER to APP_VER. MIN_VER and KEY_LOCK survive sys_rst, only POR clears them. While BUSY the ROM Port B belongs to this block.", 880, 1000, 340, 100, 11)
    return p


def dma_fsm():
    p = Page("14 Secure DMA FSM and Firewall Decision", 1560, 960)
    p.text("Secure DMA FSM and Firewall Decision (rtl/bus/Secure_DMA.v, DMA_Firewall.v)", 40, 8, 1000, 28, 16, True)
    idle = p.block("IDLE", "START with NBLK > 0: BUSY = 1, ptr = SRC, left = NBLK, w = 0, first = 1. NBLK = 0: DONE at once", 60, 120, 300, 100, "sha")
    rd = p.block("RD", "Read the source word at ptr (App ROM). Response: swap the bytes if SWAP", 480, 120, 300, 100, "sha")
    wr = p.block("WR", "Write the word into SHA W[w]. Then ptr += 4, w += 1", 900, 120, 300, 100, "sha")
    ctl = p.block("CTL", "w = 15: write SHA CTRL = START (and INIT on the first block)", 900, 360, 300, 90, "sha")
    poll = p.block("POLL", "Read SHA STATUS until DONE = 1. Request stays up, a not-done answer polls again", 480, 360, 300, 90, "sha")
    p.wire(idle, rd, "Request read", "sha")
    p.wire(rd, wr, "Word received", "sha")
    p.wire(wr, rd, "w < 15 and not padding", "sha", pts=[(1050, 270), (630, 270)], exit=("0.5", "1"), entry=("0.5", "1"))
    p.wire(wr, ctl, "w = 15", "sha")
    p.wire(ctl, poll, "CTRL written", "sha")
    nxt = p.step("left > 1: left -= 1, w = 0, back to RD for the next 64-byte block", 480, 520, 300, 56, "sha")
    pad = p.step("left = 1 and PAD: hash the padding block (state WR with in_pad)", 60, 520, 330, 56, "sha")
    done = p.step("left = 1 without PAD, or the padding block done:<br>BUSY = 0, DONE = 1, back to IDLE", 480, 640, 300, 64, "ok")
    p.wire(poll, nxt, "DONE, more blocks", "sha")
    p.wire(poll, pad, "DONE, last block with PAD", "sha", pts=[(630, 480), (225, 480)], exit=("0", "0.5"), entry=("0.5", "0"))
    p.wire(poll, done, "DONE, last block", "ok", pts=[(840, 480), (840, 672)], exit=("1", "0.5"), entry=("1", "0.5"))
    p.wire(nxt, rd, "", "sha", pts=[(440, 548), (440, 170)], exit=("0", "0.5"), entry=("0", "0.5"))
    p.wire(pad, wr, "", "sha", pts=[(225, 720), (1250, 720), (1250, 170)], exit=("0.5", "1"), entry=("1", "0.5"), dashed=True)
    err = p.step("In RD, WR, CTL and POLL: fw_viol sets ERR_FW. A bus error response (resp_err) sets ERR_BUS.<br>Either way: BUSY = 0, DONE = 1, back to IDLE, no trap", 60, 790, 560, 70, "bad")
    p.group("Firewall decision for every request (DMA_Firewall.v)", 700, 740, 780, 190, "sec", dashed=False)
    d1 = p.decision("aligned?", 730, 790, 150, 70)
    d2 = p.decision("write?", 920, 790, 130, 70)
    r1 = p.step("Read: App ROM window<br>0x6000_0000 + 4 KB, or<br>SHA STATUS 0x5000_0044?", 1090, 770, 190, 70, "sec")
    r2 = p.step("Write: SHA registers<br>0x5000_0000 to 0x5000_0043?", 1090, 850, 190, 60, "sec")
    ok = p.term("allow", 1320, 770, 120, 40, "ok")
    no = p.term("violation: ERR_FW", 1290, 860, 180, 40, "bad")
    p.wire(d1, d2, "Yes", "n")
    p.wire(d2, r1, "No", "n", exit=("1", "0.3"), entry=("0", "0.5"))
    p.wire(d2, r2, "Yes", "n", exit=("1", "0.7"), entry=("0", "0.5"))
    p.wire(r1, ok, "Yes", "ok")
    p.wire(r2, ok, "Yes", "ok", pts=[(1300, 880), (1300, 790)], exit=("1", "0.5"), entry=("0", "0.8")) if False else None
    p.wire(r2, no, "No", "bad")
    return p


def bus_flow():
    p = Page("15 Bus Transaction and Error Flow", 1560, 1280)
    p.text("Bus Transaction and Error Flow (AXI4_Lite_Master.v, SoC_Top.v, SYSCSR.v)", 40, 8, 1000, 28, 16, True)
    ids, pos, _ = stack(p, 400, 60, [
        ("term", "Master Core runs lw or sw<br>(or the Secure DMA issues a request)", 56, "core"),
        ("step", "bus_stall = 1 until the response arrives<br>Arbiter grants one master, Round-Robin", 60, "bus"),
        ("step", "AXI4-Lite Master FSM: address and data phase<br>IDLE, WRITE_ADDR_DATA, WRITE_RESP, READ_ADDR, READ_DATA", 64, "bus"),
        ("dec", "Address decode", 70, None),
        ("step", "Selected slave answers<br>RAM, Boot ROM, App ROM, SHA-256, APB bridge", 60, "bus"),
        ("dec", "Response code", 70, None),
        ("step", "OKAY: data returns, bus_stall = 0,<br>the pipeline continues", 56, "ok"),
    ], 340)
    (s0, s1, s2, dd, sl, rc, okb) = ids
    for a, b in zip(ids[:3], ids[1:4]):
        p.wire(a, b, "", "n")
    p.wire(dd, sl, "Hit", "n")
    p.wire(sl, rc, "", "n")
    p.wire(rc, okb, "OKAY", "ok")
    dflt = p.step("No hit: Default Slave answers DECERR<br>(the bus never hangs, reads return 0)", 760, pos[3][0] + 5, 330, 60, "neutral")
    p.wire(dd, dflt, "No hit, or outside the 4 KB of a memory", "n", exit=("1", "0.5"), entry=("0", "0.5"))
    notes = p.step("SLVERR sources: write to Boot ROM or App ROM,<br>APB window with no slave (PSLVERR)", 1130, pos[3][0] + 5, 340, 60, "bus")
    be = p.step("Bus Error Capture: SYSCSR.BUS_ERR keeps the first error<br>(VALID, WRITE, RESP, OVERFLOW) and BUS_ERR_ADDR", 330, 750, 340, 66, "sys")
    p.wire(rc, be, "SLVERR or DECERR", "bad", exit=("1", "0.5"), entry=("1", "0.5"), pts=[(640, pos[5][0] + 35), (700, pos[5][0] + 35), (700, 783)])
    p.wire(dflt, be, "DECERR", "bad", pts=[(925, 783)], exit=("0.5", "1"), entry=("1", "0.5"), dashed=True)
    dsrc = p.decision("Master of this access?", 270, 880, 260, 84)
    p.wire(be, dsrc, "", "n")
    cpu = p.step("CPU: data_err = 1 in the same cycle as resp_valid<br>Trap: mcause 5 (load) or 7 (store), mtval = address", 60, 1030, 340, 70, "core")
    dm = p.step("DMA: STATUS.ERR_BUS = 1, the DMA aborts<br>BUSY = 0, DONE = 1, no trap", 450, 1030, 330, 70, "sha")
    p.wire(dsrc, cpu, "CPU", "core", exit=("0", "0.5"), entry=("0.5", "0"))
    p.wire(dsrc, dm, "DMA", "sha", exit=("1", "0.5"), entry=("0.5", "0"))
    tr = p.step("Firmware trap_handler (Master): log mcause, mepc, mtval,<br>then fail(SB_TRAP 0xAF): LOCK the App, show the code", 60, 1150, 340, 70, "bad")
    p.wire(cpu, tr, "", "bad")
    p.text("The App bus is a separate, single-cycle APB bus: it ignores PSLVERR and the App Core data_err input is tied to 0.", 450, 1150, 330, 60, 11)
    return p


def irq_flow():
    p = Page("16 Interrupt and Trap Flow", 1560, 1180)
    p.text("Interrupt and Trap Flow (CSR_Unit.v, crt0.S, secure_boot.c)", 40, 8, 900, 28, 16, True)
    p.group("Asynchronous: interrupts", 20, 50, 520, 720, "bus")
    p.group("Synchronous: exceptions", 580, 50, 460, 720, "core")
    ids, pos, _ = stack(p, 280, 100, [
        ("term", "Source raises its level line", 44, "per"),
        ("step", "TIMER0: mtime >= mtimecmp, goes straight to irq_timer<br>PLIC-lite: UART0, GPIO0, DMA, Mailbox, goes to irq_ext", 70, "per"),
        ("step", "mip.MTIP (bit 7) or mip.MEIP (bit 11) set, level held until the source clears", 60, "core"),
        ("dec", "mstatus.MIE = 1 and the mie bit set<br>and the instruction is not a load or store?", 100, None),
        ("step", "Take the trap: mepc = PC, mcause = 0x8000_000B (MEI) or 0x8000_0007 (MTI)<br>MEI has priority. MPIE = MIE, MIE = 0, PC = mtvec", 80, "core"),
    ], 420)
    (i0, i1, i2, i3, i4) = ids
    for a, b in zip(ids, ids[1:]):
        p.wire(a, b, "", "n")
    wait = p.step("Wait: interrupts are not taken now, so a load or store is never cut or replayed", 60, pos[3][0] + 170, 200, 70, "neutral") if False else None
    p.text("No: the interrupt waits. After reset MIE = 0 and mie = 0, so firmware that does not enable them runs unchanged. A load or store is never cut or replayed.", 40, 700, 460, 50, 11)
    ex = [("illegal instruction", "2"), ("EBREAK", "3"), ("ECALL", "11"), ("access fault on load (data_err)", "5, mtval = address"),
          ("access fault on store (data_err)", "7, mtval = address")]
    e0 = p.term("Instruction in MEM raises an exception", 640, 100, 340, 44, "core")
    y = 180
    prev = e0
    eb = []
    for n, c in ex:
        b = p.step("%s: mcause %s" % (n, c), 640, y, 340, 40, "core")
        eb.append(b)
        y += 60
    p.wire(e0, eb[0], "", "n")
    tr = p.step("Take the trap: mepc = PC of the instruction, mcause as above,<br>MPIE = MIE, MIE = 0, PC = mtvec", 640, y + 10, 340, 66, "core")
    for b in eb:
        p.wire(b, tr, "", "n", exit=("1", "0.5"), entry=("1", "0.5"), pts=[(1010, 0)]) if False else None
    p.text("Older instructions finish, younger ones are flushed. A load that faulted does not write its register.", 640, y + 100, 340, 50, 11)
    p.step("MRET (when a handler returns): MIE = MPIE, PC = mepc", 640, y + 170, 340, 44, "bus")
    h1 = p.step("crt0.S trap_entry: start a fresh stack, read mcause, mepc, mtval", 340, 830, 360, 56, "bus")
    h2 = p.step("call trap_handler(mcause, mepc, mtval)", 340, 920, 360, 44, "bus")
    p.wire(i4, h1, "", "n", pts=[(280, 790), (470, 790)], exit=("0.5", "1"), entry=("0.5", "0"))
    p.wire(tr, h1, "", "n", pts=[(810, 800), (570, 800)], exit=("0.5", "1"), entry=("0.5", "0"))
    p.wire(h1, h2, "", "n")
    d = p.decision("Which firmware?", 380, 1000, 280, 70)
    p.wire(h2, d, "", "n")
    m = p.step("Master: secure_boot_trap() logs the cause, then fail(SB_TRAP 0xAF)<br>LOCK the App and the key, LED 0xAF", 40, 1100, 440, 60, "bad")
    a = p.step("App demo: weak trap_handler loops for ever<br>(MRET restores MIE and returns to mepc if a handler uses it)", 560, 1100, 440, 60, "neutral")
    p.wire(d, m, "Secure Boot", "bad", exit=("0", "0.5"), entry=("0.5", "0"))
    p.wire(d, a, "App", "n", exit=("1", "0.5"), entry=("0.5", "0"))
    return p


def reset_flow():
    p = Page("17 Reset and Power Flow", 1560, 880)
    p.text("Reset and Power Flow (SYSCSR.v, Boot_Verifier.v, SoC_Top.v)", 40, 8, 900, 28, 16, True)
    por = p.block("Power-on reset (POR)", "reset_system: power or push button", 40, 100, 240, 70, "neutral")
    wdt = p.block("Watchdog timeout", "WDT, wdt_rst_req", 40, 240, 240, 70, "per")
    sw = p.block("Software reset", "Write SW_RESET = 0x5A5A_0001", 40, 380, 240, 70, "core")
    gen = p.block("Reset Generator (SYSCSR)", "Holds sys_rst high for RST_HOLD cycles after the last request", 420, 240, 280, 90, "sys")
    p.wire(por, gen, "por_rst", "n", exit=("1", "0.5"), entry=("0", "0.2"))
    p.wire(wdt, gen, "wdt_rst_req", "n")
    p.wire(sw, gen, "sw_req", "n", exit=("1", "0.5"), entry=("0", "0.8"))
    g1 = p.group("Cleared by every sys_rst (POR, WDT, software reset)", 820, 60, 700, 250, "sec")
    p.text("Bus, interconnect, peripherals, SHA-256, Secure DMA, Mailbox, App world peripherals (via app_rst)<br>Boot_Verifier verdict: CHECKED, VERIFIED, FAIL, APP_VER<br>APP_RUN = 0, so app_rst = 1 and the App Core is held<br>BUS_ERR capture<br>Master Core restarts at 0x0000_0000 and runs Secure Boot again", 850, 100, 640, 160, 13)
    p.group("Cleared only by POR", 820, 360, 700, 230, "sys")
    p.text("Boot Guard LOCK, ZERO_BUSY, ZERO_DONE: the App stays locked after a failed boot<br>Boot_Verifier MIN_VER: the anti-rollback floor<br>Boot_Verifier KEY_LOCK: the key stays hidden after use<br>RST_CAUSE: set to POR by POR, WDT and SW bits are added by those resets (RW1C to clear)", 850, 400, 640, 160, 13)
    p.wire(gen, g1, "sys_rst", "sys")
    p.text("A hung boot is caught by the WDT, which started before the hash. The reset keeps LOCK, so a boot that failed once cannot release the App after a watchdog reset.", 420, 400, 320, 120, 12)
    return p


def verif_flow():
    p = Page("18 Verification Flow", 1700, 900)
    p.text("Verification Flow (make test, sim/regress.sh, then the FPGA flow)", 40, 8, 1000, 28, 16, True)
    src = p.block("Sources", "rtl, dv, fw, vp, sim scripts", 30, 380, 160, 80, "neutral")
    p.group("make test (QuestaSim 10.2c and SystemC, run in WSL)", 250, 50, 1050, 780, "bus")
    col = [
        ("Core", 270, 100, [("11 unit testbenches", "core"), ("ISA program, trap test", "core"), ("RISCV_Core_tb", "core"), ("Hazard test", "core")]),
        ("UVM", 520, 100, [("AXI4-Lite full", "per"), ("Reset mid-transaction", "per"), ("SHA-256, SHA-256 with reset", "per"), ("APB peripherals", "per")]),
        ("IP", 770, 100, [("HAL SHA-256 on host", "sha"), ("APB peripherals (79 checks)", "per"), ("Boot_Verifier_tb (30 checks)", "sec")]),
        ("SoC", 1020, 100, [("Secure boot: good, +TAMPER", "sys"), ("Firmware: good, tampered, access fault", "sys"), ("App firmware: good, tampered", "sys"), ("Interrupts, both cores", "sys"), ("VP: 4 scenarios", "mem")]),
    ]
    firsts = []
    for title, x, y, items in col:
        p.text(title, x, y - 30, 200, 24, 13, True)
        yy = y
        for i, (n, k) in enumerate(items):
            b = p.block(n, "", x, yy, 230, 56, k)
            if i == 0:
                firsts.append(b)
            yy += 76
    reg = p.block("regress.sh", "Greps each log for its PASS marker. ** Error or Fatal is a failure. A SKIP also fails", 400, 600, 760, 70, "bus")
    p.wire(src, firsts[0], "vsim, vlog, make", "n", pts=[(210, 420), (210, 128)], exit=("1", "0.5"), entry=("0", "0.5"))
    res = p.term("PASS / FAIL per check, logs in build/logs/", 1370, 400, 270, 60, "ok")
    p.wire(reg, res, "", "ok", pts=[(1340, 635), (1340, 430)], exit=("1", "0.5"), entry=("0", "0.5")) if False else None
    p.wire(reg, res, "", "ok", exit=("1", "0.5"), entry=("0.5", "1"), pts=[(1500, 635)])
    p.group("FPGA flow", 250, 860, 1050, 120, "sys") if False else None
    de2 = p.block("make de2", "Quartus II 13.0sp1. Check: 135,168 memory bits and master_core in the map report", 1340, 520, 330, 80, "sys")
    xil = p.block("make xilinx", "Vivado 2025.2. Check WNS and WHS, fpga/reports", 1340, 640, 330, 70, "sys")
    p.wire(src, de2, "", "sys", pts=[(110, 860), (1500, 860)], exit=("0.5", "1"), entry=("0.5", "1"), dashed=True) if False else None
    rep = p.block("fpga/reports", "Fit summary, Fmax, Artix-7 timing and utilization", 1340, 740, 330, 70, "sys")
    p.wire(de2, rep, "", "sys", exit=("0.5", "1"), entry=("0.5", "0"), pts=[(1505, 620)]) if False else None
    p.text("The FPGA run finds what simulation cannot: a ROM with three read ports lost its M4K mapping and Quartus removed the Master Core (04/11).", 1340, 150, 330, 100, 11)
    return p
