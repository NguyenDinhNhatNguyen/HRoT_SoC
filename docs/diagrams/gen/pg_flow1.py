from dlib import Page

def secure_boot_flow():
    p = Page("11 Secure Boot Flow", 1500, 1560)
    p.text("Secure Boot Flow (fw/secure_boot/secure_boot.c, secure_boot_run)", 40, 8, 900, 28, 16, True)
    cx, w = 330, 330
    x0 = cx - w // 2
    y = 50
    ids = []
    def place(kind, label, h, **kw):
        nonlocal y
        if kind == "term": i = p.term(label, x0 + 40, y, w - 80, h, kw.get("k", "neutral"))
        elif kind == "step": i = p.step(label, x0, y, w, h, kw.get("k", "bus"))
        else: i = p.decision(label, x0 - 10, y, w + 20, h)
        ids.append((i, y, h, kind)); y += h + 34; return i
    s0 = place("term", "Reset (POR)", 40, k="ok")
    s1 = place("step", "Master Core boots from Boot ROM 0x0000_0000<br>SYSCSR holds App Core in reset (APP_RUN = 0)", 54, k="core")
    s2 = place("step", "Init UART0, start WDT (SB_WDT_LOAD)", 40)
    d1 = place("decision", "SHA-256 self-test OK?", 70)
    s3 = place("step", "Clear BUS_ERR. Secure DMA hashes the 4 KB App ROM (SWAP + PAD), kick WDT", 56, k="sha")
    d2 = place("decision", "Bus error or DMA error?", 70)
    s4 = place("step", "Read golden hash from Boot ROM 0xFE0 (8 words)", 44, k="mem")
    d3 = place("decision", "Bus error while reading?", 70)
    d4 = place("decision", "Digest = Golden?<br>(software, constant time)", 80)
    s5 = place("step", "Read APP_VER from App ROM 0x6000_0FFC", 44, k="mem")
    d5 = place("decision", "Bus error while reading?", 70)
    s6 = place("step", "bv_check(APP_VER): Boot_Verifier CHECK<br>hardware compare + anti-rollback", 56, k="sec")
    d6 = place("decision", "Hardware verdict VERIFIED?", 70)
    s7 = place("step", "bv_key_lock(): KEY_LOCK (sticky until POR)", 44, k="sec")
    s8 = place("step", "Write SYSCSR.APP_CTRL = 1 (APP_RUN)", 44, k="sys")
    d7 = place("decision", "APP_CTRL reads 1?<br>(release gate open)", 80)
    s9 = place("term", "App released (SB_RELEASED 0x01)", 44, k="ok")
    s10 = place("step", "Main loop: kick WDT, relay App Mailbox words to UART0", 48, k="core")
    seq = [s0, s1, s2, d1, s3, d2, s4, d3, d4, s5, d5, s6, d6, s7, s8, d7, s9, s10]
    for a, b in zip(seq, seq[1:]):
        lab = "Yes" if a in (d1, d2, d3, d4, d5, d6, d7) and False else ""
        p.wire(a, b, "", "n")
    # relabel decision exits: for "Bus error?" style decisions the "No" goes down
    # (kept unlabeled lines would be ambiguous, so add small text labels next to the lines)
    by = {i: (yy, h) for i, yy, h, k in ids}
    for i, lab in ((d1, "Yes"), (d2, "No"), (d3, "No"), (d4, "Yes"), (d5, "No"), (d6, "Yes"), (d7, "Yes")):
        yy, h = by[i]
        p.text(lab, cx + 8, yy + h - 2, 40, 20, 11, True, "#2E7D32")
    # failure routine: a tall box, every error wire lands on its left edge
    fx, fy, fw = 760, 190, 400
    fh = 1330
    fail = p.group("fail(code, why): the only way out of a failed boot", fx, fy, fw, fh, "sec", dashed=False, size=13)
    steps = [
        ("1. Kick WDT", 40), ("2. bv_key_lock(): hide the HMAC key", 40),
        ("3. Write SYSCSR.GUARD = LOCK<br>Boot Guard locks the App (sticky until POR)", 60),
        ("4. Hardware zeroizes the App RAM (1024 words)", 50),
        ("5. Poll GUARD.ZERO_DONE (limit SB_GUARD_POLL_LIMIT)", 50),
        ("6. Log the reason on UART0", 40), ("7. LED = result code (GPIO0), kick WDT", 50),
    ]
    sy = fy + 520
    sids = []
    for lab, hh in steps:
        sids.append(p.step(lab, fx + 40, sy, fw - 80, hh, "sec")); sy += hh + 22
    for a, b in zip(sids, sids[1:]):
        p.wire(a, b, "", "sec")
    p.text("ZERO_DONE never set: result SB_HW_ERROR 0xE0, App stays in reset", fx + 40, sy - 6, fw - 80, 40, 11, False, "#B85450")
    end_bad = p.term("App locked out<br>(result code on LED, WDT kicked for ever)", fx + 60, fy + fh + 40, fw - 120, 56, "bad")
    p.wire(fail, end_bad, "", "bad")
    codes = {d1: "SB_SELFTEST_FAIL 0x5F", d2: "SB_BUS_ERROR 0xBE or SB_HW_ERROR 0xE0", d3: "SB_BUS_ERROR 0xBE",
             d4: "SB_LOCKED 0xEE (hash mismatch)", d5: "SB_BUS_ERROR 0xBE", d6: "SB_VERIFY_FAIL 0xBF", d7: "SB_VERIFY_FAIL 0xBF"}
    lab_no = {d1: "No", d2: "Yes", d3: "Yes", d4: "No", d5: "Yes", d6: "No", d7: "No"}
    for i, code in codes.items():
        yy, h = by[i]
        ey = min(0.97, max(0.03, (yy + h / 2 - fy) / fh))
        p.wire(i, fail, lab_no[i] + ": " + code, "bad", exit=("1", "0.5"), entry=("0", "%.3f" % ey))
    p.text("Trap path: any trap (access fault, illegal instruction) goes to trap_handler, then secure_boot_trap(), which calls the same fail(SB_TRAP 0xAF)",
           fx, fy + fh + 120, fw + 100, 50, 11, False, "#1F2937")
    return p

def build_test():
    from dlib import write
    write([secure_boot_flow()], "out/test.drawio")

if __name__ == "__main__":
    build_test()
