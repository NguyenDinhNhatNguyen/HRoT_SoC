from dlib import Page


def memory_map():
    p = Page("02 Memory Map", 1500, 900)
    p.text("Memory Map (docs/spec/SoC_Memory_Map.md)", 30, 10, 700, 28, 16, True)
    p.group("Secure World: Master bus (AXI4-Lite)", 20, 50, 560, 820, "zone")
    rows = [("0x0000_0000", "Boot ROM 4 KB", "Port A: Fetch. Port B: lw. HMAC Tag 0xFC0, Golden Hash 0xFE0. Write: SLVERR", "mem", 110),
            ("0x1000_0000", "Master RAM 4 KB", ".data, .bss, Stack. Above 4 KB: DECERR", "mem", 90),
            ("0x4000_0000", "AXI to APB Bridge 64 KB", "9 APB slots of 4 KB (middle column)", "bus", 90),
            ("0x5000_0000", "SHA-256 64 KB", "Registers 0x00-0x6C. 0x100 and above: read 0, write ignored", "sha", 100),
            ("0x6000_0000", "App ROM, Port B 4 KB", "Read-Only. APP_VER at 0xFFC. Write: SLVERR. Above 4 KB: DECERR", "mem", 110),
            ("Other", "Default Slave", "DECERR, the bus never hangs", "neutral", 80)]
    y = 100
    ids = {}
    for a, n, d, k, h in rows:
        p.text(a, 35, y + h / 2 - 22, 120, 24, 12, True)
        ids[n] = p.block(n, d, 160, y, 400, h - 14, k)
        y += h + 20
    p.group("APB slots inside the Bridge window (0x4000_0000)", 640, 50, 380, 820, "bus")
    apb = [("+0x0000", "SYSCSR", "sys"), ("+0x1000", "UART0", "per"), ("+0x2000", "GPIO0", "per"), ("+0x3000", "TIMER0", "per"),
           ("+0x4000", "WDT", "per"), ("+0x5000", "PLIC-lite", "per"), ("+0x6000", "Mailbox (Secure)", "per"),
           ("+0x7000", "Secure DMA", "sha"), ("+0x8000", "Boot_Verifier", "sec"), ("+0x9000", "Empty windows: PSLVERR", "neutral")]
    ay = 100
    first = None
    for a, n, k in apb:
        b = p.block(n, a, 700, ay, 280, 48, k)
        first = first or b
        ay += 74
    p.wire(ids["AXI to APB Bridge 64 KB"], first, "APB Slots", "bus", pts=[(610, 313), (610, 124)], exit=("1", "0.5"), entry=("0", "0.5"))
    p.group("App World: App Core bus (private)", 1080, 50, 400, 820, "app")
    app = [("0x4000_0000", "UART1", "per"), ("0x4000_1000", "GPIO1", "per"), ("0x4000_2000", "TIMER1", "per"),
           ("0x4000_3000", "Mailbox (App)", "per"), ("Other", "App RAM 4 KB (alias)", "mem")]
    ay = 100
    for a, n, k in app:
        p.text(a, 1095, ay + 10, 110, 24, 12, True)
        p.block(n, "", 1215, ay, 240, 44, k)
        ay += 74
    p.text("Instruction fetch: App ROM 4 KB through Port A, separate from the data side. The App Core has no path to the Secure bus. The App APB ignores PSLVERR.", 1095, ay + 10, 360, 70, 11)
    return p


def master_core():
    p = Page("04 Master Core", 1560, 760)
    p.group("Master Core Internals (rtl/top/RISCV_Core.v, rtl/core, 26 modules). The App Core is identical", 20, 20, 1520, 720, "core")
    xs = [40 + i * 162 for i in range(9)]
    labels = [("IF Stage", "PC, PC_Plus_4", "core"), ("IF_ID_Reg", "Hold on stall, NOP on flush", "neutral"),
              ("ID Stage", "Main_Decoder, ALU_decoder, Register_File, Extend, Sys_Decoder", "core"),
              ("ID_EX_Reg", "Bubble on flush or load-use", "neutral"),
              ("EX Stage", "ALU_Mux, ALU, Branch_Unit, PC_Target", "core"), ("EX_MEM_Reg", "Carries funct3", "neutral"),
              ("MEM Stage", "Byte / half lanes, load extend", "core"), ("MEM_WB_Reg", "", "neutral"),
              ("WB Stage", "Result_Mux: ALU, Load, PC+4, PC_Target", "core")]
    pipe = [p.block(n, d, x, 200, 140, 100, k, size=11) for x, (n, d, k) in zip(xs, labels)]
    for a, b in zip(pipe, pipe[1:]):
        p.wire(a, b, "", "core")
    rom = p.block("Instruction Memory", "Boot ROM (Master) or App ROM (App), outside the core", 40, 80, 220, 56, "mem")
    p.wire(pipe[0], rom, "instr_addr", "mem", exit=("0.25", "0"), entry=("0.25", "1"))
    p.wire(rom, pipe[0], "instr_rdata", "mem", exit=("0.75", "1"), entry=("0.75", "0"))
    dp = p.block("Data Port to AXI4-Lite Master", "data_addr, data_wdata, data_wstrb, data_we, data_re, data_rdata", 1000, 80, 330, 56, "bus")
    p.wire(pipe[6], dp, "Address, Data", "bus", exit=("0.25", "0"), entry=("0.1", "1"))
    p.wire(dp, pipe[6], "Read Data", "bus", exit=("0.6", "1"), entry=("0.75", "0"))
    haz = p.block("Hazard_Detection", "Load-use and CSR-use stall", 200, 400, 210, 60, "sec")
    fwd = p.block("Forwarding_Unit", "ForwardA / ForwardB, MEM before WB", 470, 400, 220, 60, "sys")
    csr = p.block("CSR_Unit (in MEM)", "Zicsr, mstatus, mie, mip, mtvec, mscratch, mepc, mcause, mtval. Trap decision", 800, 400, 340, 70, "core")
    p.wire(haz, pipe[3], "Stall, Bubble", "sec", exit=("0.5", "0"), entry=("0.3", "1"))
    p.wire(haz, pipe[0], "Hold PC", "sec", pts=[(305, 360), (110, 360)], exit=("0.3", "0"), entry=("0.5", "1"))
    p.wire(fwd, pipe[4], "ForwardA, ForwardB", "sys", exit=("0.5", "0"), entry=("0.3", "1"))
    p.wire(pipe[6], csr, "Instruction in MEM", "core", pts=[(1082, 340), (1000, 340)], exit=("0.5", "1"), entry=("0.5", "0"))
    p.wire(csr, pipe[0], "Trap / MRET Redirect (mtvec, mepc)", "core", pts=[(970, 560), (90, 560)], exit=("0.5", "1"), entry=("0.2", "1"))
    irq = p.block("Interrupt Lines", "irq_timer, irq_ext (level, high)", 1260, 400, 230, 60, "per")
    err = p.block("Bus Response Error", "data_err: SLVERR or DECERR", 1260, 490, 230, 60, "sec")
    stall = p.block("Bus Stall", "bus_stall freezes the whole pipeline", 1260, 580, 230, 60, "bus")
    p.wire(irq, csr, "MTIP, MEIP", "irq", exit=("0", "0.5"), entry=("1", "0.3"))
    p.wire(err, csr, "mcause 5 (load), 7 (store)", "bad", exit=("0", "0.5"), entry=("1", "0.8"))
    p.text("Branch and jump are resolved in EX and flush IF/ID and ID/EX. Interrupts are taken only on an instruction that does not access memory, so a load or store is never cut or replayed.", 200, 620, 760, 50, 11)
    return p


def dma_sha():
    p = Page("05 Secure DMA, Firewall, SHA-256", 1560, 800)
    p.group("Secure DMA, DMA Firewall and SHA-256 (rtl/bus/Secure_DMA.v, DMA_Firewall.v, rtl/crypto)", 20, 20, 1520, 760, "sha")
    reg = p.block("DMA Registers (APB +0x7000)", "SRC, NBLK, CTRL (START, SWAP, PAD, IRQ_EN), STATUS (BUSY, DONE, ERR_FW, ERR_BUS)", 40, 120, 290, 110, "sha")
    fsm = p.block("DMA FSM", "IDLE, RD, WR, CTL, POLL. Owns SHA-256 while BUSY", 470, 120, 250, 110, "sha")
    fw = p.block("DMA Firewall", "Combinational, blocks before the bus", 860, 120, 250, 110, "sec")
    arb = p.block("Arbiter to AXI4-Lite Master", "Shared with the CPU, Round-Robin", 1250, 120, 250, 110, "bus")
    p.wire(reg, fsm, "Start, SRC, NBLK", "sha")
    p.wire(fsm, fw, "Request", "sha")
    p.wire(fw, arb, "Allowed Request", "bus")
    p.wire(fw, fsm, "fw_viol (ERR_FW)", "bad", pts=[(985, 80), (595, 80)], exit=("0.5", "0"), entry=("0.5", "0"))
    p.wire(arb, fsm, "Response (resp_valid, resp_err)", "bus", pts=[(1375, 275), (595, 275)], exit=("0.5", "1"), entry=("0.5", "1"))
    rules = p.block("Firewall Rules", "Read: App ROM window 0x6000_0000 (4 KB) and SHA STATUS. Write: SHA block registers and CTRL (0x5000_0000 to 0x5000_0043). Aligned only. Everything else is blocked", 700, 340, 330, 120, "sec")
    p.wire(rules, fw, "", "sec", pts=[(865, 310), (985, 310)], exit=("0.5", "0"), entry=("0.5", "1"))
    rom = p.block("App ROM (Port B)", "Source of the 64-byte blocks", 1100, 420, 220, 60, "mem")
    wrap = p.block("SHA-256 Wrapper (0x5000_0000)", "W0..W15, CTRL (START, INIT), STATUS (DONE, BUSY), HASH H0..H7", 1100, 520, 360, 80, "sha")
    core = p.block("SHA-256 Core", "64 Rounds, 66 Cycles per Block, multi-block", 1100, 660, 360, 70, "sha")
    p.wire(arb, rom, "Read Source Word", "mem", pts=[(1400, 320), (1210, 320)], exit=("0.7", "1"), entry=("0.5", "0"))
    p.wire(arb, wrap, "START, Poll", "sha", pts=[(1515, 175), (1515, 560)], exit=("1", "0.5"), entry=("1", "0.5"))
    p.wire(wrap, core, "Block, Start", "sha", exit=("0.3", "1"), entry=("0.3", "0"))
    p.wire(core, wrap, "Digest, Done, Busy", "sha", exit=("0.7", "0"), entry=("0.7", "1"), dashed=True)
    out1 = p.block("Boot_Verifier", "Reads digest_out, done_out, busy_out", 640, 640, 250, 60, "sec")
    out2 = p.block("Master Core (CPU)", "Reads HASH over AXI4-Lite", 330, 640, 250, 60, "core")
    p.wire(wrap, out1, "digest_out", "sec", pts=[(765, 584)], exit=("0", "0.8"), entry=("0.5", "0"))
    p.wire(wrap, out2, "HASH registers", "core", pts=[(455, 544)], exit=("0", "0.3"), entry=("0.5", "0"))
    p.text("SWAP = 1 reverses the bytes of each word, so the digest equals sha256sum of the .bin (little-endian image). PAD = 1 hashes the padding block for NBLK x 64 bytes. NBLK = 0 reports DONE with no hash.", 50, 330, 560, 60, 11)
    p.text("DONE and IRQ_EN raise dma_irq into PLIC-lite source 2.", 50, 410, 520, 24, 11)
    return p
