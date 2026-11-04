from dlib import Page


def boot_verifier():
    p = Page("06 Boot_Verifier", 1560, 780)
    p.group("Boot_Verifier (rtl/periph/Boot_Verifier.v, APB +0x8000)", 300, 40, 960, 700, "sec", dashed=False)
    sha = p.block("SHA-256 Wrapper", "digest_out (256 bit), done_out, busy_out", 40, 100, 220, 70, "sha")
    apb = p.block("APB Master (Master Core)", "Writes CTRL, APP_VER, MIN_VER. Reads STATUS, KEY", 40, 300, 220, 70, "core")
    b1 = p.block("CHECK Gate", "CHECK accepted once per reset. Needs SHA done, not busy, APP_VER >= MIN_VER", 340, 100, 250, 100, "sec")
    b2 = p.block("CHECK FSM", "IDLE, FETCH (8 cycles). rom_addr += 4, busy = 1", 680, 100, 210, 100, "sec")
    b6 = p.block("MIN_VER", "Anti-rollback floor. Writes only raise it. Raised to APP_VER after a pass. POR clears", 340, 270, 250, 100, "sec")
    b3 = p.block("Word Comparator", "ROM word i equals digest word H[i]", 680, 270, 210, 80, "sec")
    b4 = p.block("Verdict Logic", "Any mismatch: FAIL. Word 7 matched: VERIFIED", 680, 430, 210, 90, "sec")
    b5 = p.block("STATUS", "VERIFIED, FAIL, CHECKED, BUSY", 1040, 430, 190, 80, "sec")
    b7 = p.block("KEY0..7 + KEY_LOCK", "Demo HMAC key. Reads 0 after KEY_LOCK. Sticky until POR", 1040, 560, 190, 90, "sec")
    rom = p.block("Boot ROM (Port B)", "Golden Hash 0xFE0 or HMAC Tag 0xFC0. Port B is lent while busy", 1330, 100, 190, 90, "mem")
    sysc = p.block("SYSCSR", "VERIFY_GATE input: verified", 1330, 430, 190, 80, "sys")
    p.wire(sha, b1, "done, busy", "sha", exit=("1", "0.3"), entry=("0", "0.3"))
    p.wire(sha, b3, "Digest Word H[i]", "sha", pts=[(150, 20), (635, 20), (635, 310)], exit=("0.5", "0"), entry=("0", "0.5"))
    p.wire(apb, b1, "CTRL.CHECK, APP_VER", "core", pts=[(150, 245), (340, 245)], exit=("0.5", "0"), entry=("0", "0.9"))
    p.wire(apb, b6, "MIN_VER Write", "core", exit=("1", "0.5"), entry=("0", "0.5"))
    p.wire(apb, b7, "Read KEY", "core", pts=[(150, 605), (1040, 605)], exit=("0.5", "1"), entry=("0", "0.5"))
    p.wire(b1, b2, "Start", "sec")
    p.wire(b6, b1, "MIN_VER", "sec", exit=("0.5", "0"), entry=("0.5", "1"))
    p.wire(b2, rom, "rom_addr", "mem", exit=("1", "0.3"), entry=("0", "0.3"))
    p.wire(rom, b3, "rom_data", "mem", pts=[(1425, 330)], exit=("0.5", "1"), entry=("1", "0.5"))
    p.wire(b2, b3, "Word Index", "sec", exit=("0.5", "1"), entry=("0.5", "0"))
    p.wire(b3, b4, "Match or Mismatch", "sec")
    p.wire(b4, b5, "Set VERIFIED or FAIL", "sec")
    p.wire(b4, b6, "Raise MIN_VER (on pass)", "sec", pts=[(500, 475)], exit=("0", "0.5"), entry=("0.5", "1"))
    p.wire(b5, sysc, "verified", "sec")
    p.text("CHECK is accepted once per reset. A new system reset clears the verdict. MIN_VER and KEY_LOCK survive it and only POR clears them.", 340, 690, 760, 40, 11)
    return p


def syscsr():
    p = Page("07 SYSCSR and Boot Guard", 1560, 800)
    p.group("SYSCSR (rtl/periph/SYSCSR.v, APB +0x0000)", 290, 40, 1000, 720, "sys")
    por = p.block("por_rst", "Power-on or push button, synchronized", 40, 100, 200, 56, "neutral")
    wdt = p.block("WDT Reset Request", "wdt_rst_req pulse", 40, 200, 200, 56, "per")
    be_in = p.block("AXI4-Lite Master", "bus_err pulse, write flag, resp, address", 40, 300, 200, 70, "bus")
    ver = p.block("Boot_Verifier", "verified", 40, 447, 200, 56, "sec")
    apb = p.block("APB Master (Master Core)", "APP_CTRL, SW_RESET, GUARD, BUS_ERR clear", 40, 540, 200, 70, "core")
    rg = p.block("Reset Generator", "POR, WDT request or SW_RESET key 0x5A5A_0001. Holds sys_rst for RST_HOLD cycles", 330, 90, 270, 90, "sys")
    rc = p.block("RST_CAUSE (RW1C)", "POR, WDT, SW bits. Survives SW and WDT reset", 330, 220, 270, 70, "sys")
    be = p.block("Bus Error Capture", "BUS_ERR: first error, overflow, W1C. BUS_ERR_ADDR", 330, 330, 270, 80, "sys")
    lock = p.block("LOCK (GUARD bit 0)", "Sticky. Cleared only by POR", 700, 220, 220, 70, "sec")
    zero = p.block("Zeroization FSM", "Counter 0..1023 writes zero into the App RAM. ZERO_BUSY, ZERO_DONE", 1000, 220, 250, 80, "sec")
    ar = p.block("APP_RUN Register", "Reset by sys_rst. Write 1 only if verified (VERIFY_GATE)", 700, 430, 190, 90, "sys")
    gate = p.block("app_rst", "sys_rst OR NOT APP_RUN OR LOCK", 1000, 430, 250, 80, "sys")
    sysrst = p.block("Secure World sys_rst", "Resets bus, peripherals, SHA, DMA", 1340, 90, 190, 60, "neutral")
    ramw = p.block("App RAM", "write zero (app_zero_en, app_zero_addr)", 1340, 220, 190, 70, "mem")
    acore = p.block("App Core and App peripherals", "Held in reset while app_rst = 1", 1340, 430, 190, 80, "core")
    p.wire(por, rg, "por_rst", "n", exit=("1", "0.5"), entry=("0", "0.3"))
    p.wire(wdt, rg, "wdt_rst_req", "n", exit=("1", "0.5"), entry=("0", "0.7"))
    p.wire(rg, sysrst, "sys_rst", "n", exit=("1", "0.5"), entry=("0", "0.5"))
    p.wire(rg, rc, "Cause", "sys")
    p.wire(be_in, be, "bus_err", "bus", exit=("1", "0.5"), entry=("0", "0.5"))
    p.wire(ver, ar, "verified", "sec", exit=("1", "0.5"), entry=("0", "0.5"))
    p.wire(apb, ar, "APP_CTRL write", "core", pts=[(795, 585)], exit=("1", "0.7"), entry=("0.5", "1"))
    p.wire(apb, lock, "GUARD.LOCK write", "core", pts=[(650, 564), (650, 255)], exit=("1", "0.35"), entry=("0", "0.5"))
    p.wire(lock, zero, "Start", "sec")
    p.wire(zero, ramw, "Zeroization", "sec", exit=("1", "0.5"), entry=("0", "0.5"), pts=[(1300, 260), (1300, 255)])
    p.wire(ar, gate, "APP_RUN", "sys", exit=("1", "0.5"), entry=("0", "0.3"))
    p.wire(lock, gate, "LOCK", "sec", pts=[(909, 485)], exit=("0.95", "1"), entry=("0", "0.7"))
    p.wire(gate, acore, "app_rst", "sys")
    p.text("LOCK is cleared only by POR, so no software or watchdog reset can unlock the App after a failed boot. RST_CAUSE and LOCK are never cleared by sys_rst. Read-only registers: CHIP_ID 0x4852_4F54, VERSION, BOOT_STRAP.", 330, 650, 640, 60, 11)
    return p


def peripherals():
    p = Page("08 Secure Peripherals and Interrupts", 1560, 700)
    p.group("Secure Peripherals (rtl/periph, APB slots 1 to 7)", 20, 20, 1520, 660, "bus")
    uart = p.block("UART0 (+0x1000)", "8N1, 16x sampling, 8-byte FIFOs", 60, 120, 220, 60, "per")
    gpio = p.block("GPIO0 (+0x2000)", "8 outputs (LEDs), 8 inputs", 60, 200, 220, 60, "per")
    dma = p.block("Secure DMA (+0x7000)", "dma_irq on DONE when IRQ_EN", 60, 280, 220, 60, "sha")
    mb = p.block("Mailbox, Secure side (+0x6000)", "mbox_irq_s when the App has a word waiting", 60, 360, 220, 60, "per")
    wdt = p.block("WDT (+0x4000)", "LOAD, KICK key 0x5A5A_0002, reset on timeout", 60, 520, 220, 60, "per")
    plic = p.block("PLIC-lite (+0x5000)", "8 level sources, lowest index wins. Claim and Complete", 520, 200, 240, 140, "per")
    tim = p.block("TIMER0 (+0x3000)", "CLINT style: mtime, mtimecmp", 520, 70, 240, 60, "per")
    core = p.block("Master Core", "mip.MTIP (irq_timer), mip.MEIP (irq_ext). MEI before MTI", 1060, 150, 240, 90, "core")
    sysc = p.block("SYSCSR", "RST_CAUSE bit 1: WDT", 1060, 520, 240, 60, "sys")
    amb = p.block("Mailbox, App side (0x4000_3000 on the App bus)", "irq_a into the App Core irq_ext", 1060, 360, 240, 70, "per")
    p.wire(uart, plic, "Source 0", "irq", exit=("1", "0.5"), entry=("0", "0.2"))
    p.wire(gpio, plic, "Source 1", "irq", exit=("1", "0.5"), entry=("0", "0.4"))
    p.wire(dma, plic, "Source 2", "irq", exit=("1", "0.5"), entry=("0", "0.6"))
    p.wire(mb, plic, "Source 3", "irq", exit=("1", "0.5"), entry=("0", "0.8"))
    p.wire(plic, core, "irq_ext", "irq", exit=("1", "0.5"), entry=("0", "0.7"))
    p.wire(tim, core, "irq_timer (no PLIC)", "irq", exit=("1", "0.5"), entry=("0", "0.2"), pts=[(900, 100), (900, 170)])
    p.wire(wdt, sysc, "wdt_rst_req on timeout", "sys", exit=("1", "0.5"), entry=("0", "0.5"))
    p.wire(mb, amb, "Two-Way Message Words", "mem", pts=[(300, 450), (1180, 450)], exit=("0.9", "1"), entry=("0.5", "1"), dashed=True)
    p.text("Sources 4 to 7 of the PLIC-lite are unused (tied to 0). The App world has its own UART1, GPIO1, TIMER1, see page 09.", 520, 470, 440, 50, 11)
    return p


def app_world():
    p = Page("09 App World", 1560, 720)
    p.group("App World (private bus, no path to the Secure bus)", 20, 20, 1520, 680, "app")
    rom = p.block("App ROM 4 KB", "Port A: instruction fetch. Port B belongs to the Secure bus (read-only)", 60, 100, 230, 80, "mem")
    core = p.block("App Core", "RISCV_Core, same RTL as the Master Core. Reset by app_rst", 60, 300, 230, 90, "core")
    ram = p.block("App RAM 4 KB", "Reached by any address outside 0x4000_xxxx (alias). Zeroized by Boot Guard", 420, 520, 230, 90, "mem")
    dec = p.block("App APB Decoder", "0x4000_xxxx, 4 slaves, one cycle, PSLVERR ignored", 420, 300, 230, 90, "bus")
    u1 = p.block("UART1 (+0x0000)", "Same layout as UART0", 790, 120, 220, 56, "per")
    g1 = p.block("GPIO1 (+0x1000)", "LEDG[8:1] on the DE2", 790, 210, 220, 56, "per")
    t1 = p.block("TIMER1 (+0x2000)", "Same layout as TIMER0", 790, 300, 220, 56, "per")
    m1 = p.block("Mailbox, App side (+0x3000)", "Shared with the Secure Mailbox", 790, 390, 220, 56, "per")
    orr = p.block("irq_ext = OR", "UART1, GPIO1, Mailbox (App)", 1130, 210, 200, 70, "bus")
    sysc = p.block("SYSCSR (Secure)", "app_rst (hold) and Zeroization", 60, 530, 230, 70, "sys")
    smb = p.block("Mailbox, Secure side", "Secure APB slot 6", 790, 520, 220, 56, "per")
    p.wire(rom, core, "Instruction Fetch", "core", pts=[(230, 240)], exit=("0.75", "1"), entry=("0.75", "0"))
    p.wire(core, dec, "Load / Store", "core")
    for b in (u1, g1, t1, m1):
        p.wire(dec, b, "", "bus", exit=("1", "0.5"), entry=("0", "0.5"))
    p.wire(dec, ram, "Other Addresses", "mem", exit=("0.5", "1"), entry=("0.5", "0"))
    p.wire(u1, orr, "", "irq", exit=("1", "0.5"), entry=("0", "0.2"))
    p.wire(g1, orr, "", "irq", exit=("1", "0.5"), entry=("0", "0.5"))
    p.wire(m1, orr, "irq_a", "irq", pts=[(1060, 418), (1060, 262)], exit=("1", "0.5"), entry=("0", "0.8"))
    p.wire(orr, core, "irq_ext", "irq", pts=[(1230, 70), (40, 70), (40, 345)], exit=("0.5", "0"), entry=("0", "0.5"))
    p.wire(t1, core, "irq_timer", "irq", pts=[(1070, 328), (1070, 90), (30, 90), (30, 370)], exit=("1", "0.5"), entry=("0", "0.8"))
    p.wire(sysc, core, "app_rst (hold)", "sys", exit=("0.5", "0"), entry=("0.5", "1"))
    p.wire(sysc, ram, "Zeroization", "sys", exit=("1", "0.5"), entry=("0", "0.5"))
    p.wire(smb, m1, "Two-Way Message Words", "mem", exit=("0.5", "0"), entry=("0.5", "1"))
    p.text("Peripherals of the App World are reset by app_rst, the Mailbox by sys_rst. The App ROM image is hashed through its Port B by the Secure DMA before the App Core is released.", 700, 630, 700, 40, 11)
    return p


def security_arch():
    p = Page("10 Security Architecture", 1620, 760)
    p.text("Chain of Trust and Protection Layers (docs/spec/Security_Model.md, SR-01 to SR-11)", 30, 10, 900, 28, 16, True)
    p.group("Chain of Trust: boot to release", 20, 50, 1580, 250, "root", dashed=False)
    chain = [("Boot ROM", "Immutable code and Golden Hash. No write path (SR-04)", "mem"),
             ("Secure Boot Firmware", "Runs on the Master Core only", "core"),
             ("Secure DMA + Firewall", "Reads only App ROM, writes only SHA-256 (SR-08)", "sha"),
             ("SHA-256", "Digest of the whole 4 KB App image", "sha"),
             ("Boot_Verifier", "Hardware compare, anti-rollback (SR-03, SR-06)", "sec"),
             ("VERIFY_GATE", "APP_RUN ignored until VERIFIED (SR-02)", "sys"),
             ("App Core", "Held in reset until released (SR-01)", "core")]
    ids = []
    for i, (n, d, k) in enumerate(chain):
        ids.append(p.block(n, d, 40 + i * 223, 130, 190, 100, k))
    for a, b in zip(ids, ids[1:]):
        p.wire(a, b, "", "n")
    p.group("Protection layers around the chain", 20, 330, 1580, 400, "zone")
    lay = [("Boot Guard LOCK", "Sticky until POR. Locks the App after a failed boot (SR-05)", "sec"),
           ("Zeroization", "Hardware clears the App RAM on LOCK (SR-05)", "sec"),
           ("KEY_LOCK", "Hides the HMAC key after use, sticky until POR (SR-07)", "sec"),
           ("MIN_VER", "Refuses an older App image (SR-06)", "sec"),
           ("App Bus Isolation", "App Core has no path to the Secure bus (SR-09)", "core"),
           ("4 KB Address Decode", "Reads outside a memory give DECERR, no alias (SR-10)", "bus"),
           ("BUS_ERR Capture", "First bus error and its address are kept for firmware (SR-11)", "sys"),
           ("WDT", "Resets a hung boot. LOCK survives the reset (SR-05)", "per")]
    lids = []
    for i, (n, d, k) in enumerate(lay):
        col, row = i % 4, i // 4
        lids.append(p.block(n, d, 60 + col * 385, 400 + row * 140, 340, 90, k))
    p.wire(ids[4], lids[0], "Any failure", "bad", pts=[(1008, 372), (230, 372)], exit=("0.5", "1"), entry=("0.5", "0"), dashed=True)
    p.wire(ids[4], lids[3], "Version check", "sec", pts=[(1150, 330), (1150, 370), (1600, 370)], exit=("0.7", "1"), entry=("1", "0.5"), dashed=True) if False else None
    p.text("Every failed boot ends in the same fail() routine: kick WDT, hide the key, set LOCK, wait for ZERO_DONE, log, show the code on the LEDs.", 60, 690, 1000, 30, 11)
    return p
