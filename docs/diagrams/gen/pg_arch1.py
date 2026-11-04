from dlib import Page

def overview():
    p = Page("01 System Overview", 1600, 850)
    p.group("Secure Boot (Hardware Root of Trust)", 20, 20, 1560, 810, "root", dashed=False, size=16)
    p.group("Secure Zone (Vùng tin cậy)", 40, 70, 1040, 740, "zone")
    p.group("App Zone (Vùng chỉ chạy sau khi được xác minh)", 1110, 70, 450, 560, "app")
    core = p.block("Master Core", "5 tầng, Zicsr, Trap (Page 04)", 70, 120, 170, 64, "core")
    axi = p.block("AXI4-Lite Master", "Arbiter CPU / DMA (Page 03)", 340, 120, 190, 64, "bus")
    ic = p.block("AXI4-Lite Interconnect", "6 Slaves (Page 03)", 600, 120, 170, 64, "bus")
    ram = p.block("Master RAM", "4 KB 0x1000_0000", 850, 90, 200, 46, "mem")
    sha = p.block("SHA-256", "0x5000_0000 (Page 05)", 850, 150, 200, 46, "sha")
    arom = p.block("App ROM (Port B)", "0x6000_0000, Read-Only", 850, 210, 200, 46, "mem")
    brg = p.block("AXI to APB Bridge", "0x4000_0000", 850, 270, 200, 46, "bus")
    brom = p.block("Boot ROM", "4 KB, Golden Hash 0xFE0", 70, 270, 170, 64, "mem")
    dma = p.block("Secure DMA + Firewall", "0x4000_7000 (Page 05)", 340, 270, 190, 64, "sha")
    apb = p.block("APB Peripherals", "UART0, GPIO0, TIMER0, WDT, PLIC-lite, Mailbox, DMA Registers (Page 08)", 550, 420, 300, 70, "per")
    sysc = p.block("SYSCSR + Boot Guard", "App Reset, LOCK, Zeroization (Page 07)", 260, 560, 230, 70, "sys")
    bv = p.block("Boot_Verifier", "0x4000_8000, Hardware Verdict (Page 06)", 580, 560, 200, 70, "sec")
    acore = p.block("App Core", "RV32I 5 tầng (Page 09)", 1140, 120, 170, 64, "core")
    aper = p.block("App Peripherals", "UART1, GPIO1, TIMER1, Mailbox (App)", 1350, 120, 180, 64, "per")
    arom2 = p.block("App ROM", "4 KB, Port A: Fetch", 1140, 260, 170, 64, "mem")
    aram = p.block("App RAM", "4 KB, Zeroized by Boot Guard", 1350, 260, 180, 64, "mem")
    p.wire(core, axi, "Load / Store", "core")
    p.wire(core, brom, "Instruction Fetch", "core")
    p.wire(axi, ic, "AXI4-Lite", "bus")
    for s in (ram, sha, arom, brg):
        p.wire(ic, s, "", "bus", exit=("1", "0.5"), entry=("0", "0.5"))
    p.wire(dma, axi, "DMA Request", "sha", exit=("0.5", "0"), entry=("0.5", "1"))
    p.wire(ic, brom, "Data Read (Port B)", "mem", pts=[(685, 240), (206, 240)], exit=("0.5", "1"), entry=("0.8", "0"))
    p.wire(brg, apb, "APB", "bus", pts=[(950, 385), (700, 385)], exit=("0.5", "1"), entry=("0.5", "0"))
    p.wire(apb, sysc, "APB", "bus", pts=[(565, 520), (375, 520)], exit=("0.05", "1"), entry=("0.5", "0"))
    p.wire(apb, bv, "APB", "bus", exit=("0.8", "1"), entry=("0.5", "0"))
    p.wire(sha, bv, "Digest, Done, Busy", "sec", pts=[(1065, 173), (1065, 595)], exit=("1", "0.5"), entry=("1", "0.5"))
    p.wire(bv, brom, "Golden Hash Read (Shared Port B)", "sec", pts=[(680, 670), (110, 670)], exit=("0.5", "1"), entry=("0.235", "1"))
    p.wire(bv, sysc, "Verified", "sec", exit=("0", "0.5"), entry=("1", "0.5"))
    p.wire(apb, core, "IRQ Timer, IRQ External", "irq", pts=[(520, 455), (50, 455), (50, 152)], exit=("0", "0.5"), entry=("0", "0.5"))
    p.wire(sysc, acore, "App Reset (Hold)", "sys", pts=[(330, 700), (1095, 700), (1095, 152)], exit=("0.3", "1"), entry=("0", "0.5"))
    p.wire(sysc, aram, "Zeroization", "sys", pts=[(420, 740), (1440, 740)], exit=("0.7", "1"), entry=("0.5", "1"))
    p.wire(arom, arom2, "Image Hash (Port B)", "mem", pts=[(1085, 233), (1085, 292)], exit=("1", "0.5"), entry=("0", "0.5"))
    p.wire(arom2, acore, "Instruction Fetch", "core", exit=("0.3", "0"), entry=("0.3", "1"))
    p.wire(acore, aper, "Load / Store", "core")
    p.wire(acore, aram, "Load / Store", "core", pts=[(1260, 225), (1440, 225)], exit=("0.8", "1"), entry=("0.5", "0"))
    p.text("Mailbox: Secure side in APB Peripherals, App side in App Peripherals (two APB ports, two-way)", 1115, 380, 440, 40, 11, False, "#1F2937")
    return p

def bus_fabric():
    p = Page("03 Secure Bus Fabric", 1500, 860)
    p.group("Secure Bus Fabric (rtl/top/SoC_Top.v, rtl/bus)", 20, 20, 1460, 820, "bus")
    cpu = p.block("Master Core", "CPU data port (lw / sw)", 60, 120, 170, 56, "core")
    dma = p.block("Secure DMA", "via DMA Firewall", 60, 260, 170, 56, "sha")
    arb = p.block("Arbiter", "Round-Robin at request level (own_dma_q)", 300, 185, 190, 70, "bus")
    axi = p.block("AXI4-Lite Master", "FSM: IDLE, WRITE_ADDR_DATA, WRITE_RESP, READ_ADDR, READ_DATA", 560, 185, 250, 70, "bus")
    dec = p.block("Address Decoder", "4 KB: RAM, Boot ROM, App ROM. 64 KB: APB, SHA. Others: DECERR", 880, 185, 240, 70, "bus")
    sl = [("S0 Master RAM", "0x1000_0000, 4 KB", "mem"), ("S1 AXI to APB Bridge", "0x4000_0000, 64 KB", "bus"),
          ("S2 SHA-256", "0x5000_0000, 64 KB", "sha"), ("S3 App ROM Port B", "0x6000_0000, Read-Only", "mem"),
          ("S4 Boot ROM Port B", "0x0000_0000, Read-Only", "mem"), ("S5 Default Slave", "DECERR", "neutral")]
    ids = []
    for i, (n, d, k) in enumerate(sl):
        ids.append(p.block(n, d, 1240, 70 + i * 66, 210, 50, k))
    for i in ids:
        p.wire(dec, i, "", "bus", exit=("1", "0.5"), entry=("0", "0.5"))
    p.wire(cpu, arb, "Request", "core", exit=("1", "0.5"), entry=("0", "0.3"))
    p.wire(dma, arb, "Request", "sha", exit=("1", "0.5"), entry=("0", "0.7"))
    p.wire(arb, axi, "Granted Request", "bus")
    p.wire(axi, dec, "AXI4-Lite", "bus")
    ber = p.block("Bus Error Capture", "SLVERR / DECERR response", 560, 330, 250, 56, "sec")
    p.wire(axi, ber, "Response Code", "sec")
    sy = p.block("SYSCSR BUS_ERR, BUS_ERR_ADDR", "First error, W1C", 300, 450, 220, 56, "sys")
    de = p.block("Master Core data_err", "Trap mcause 5 (load) / 7 (store)", 580, 450, 230, 56, "core")
    p.wire(ber, sy, "Capture", "sys", exit=("0.2", "1"), entry=("0.5", "0"))
    p.wire(ber, de, "CPU Access Only", "core", exit=("0.8", "1"), entry=("0.5", "0"))
    p.text("The response (RDATA, BRESP, RRESP) returns from the selected slave through the same decode. A DMA error goes to the DMA STATUS and BUS_ERR, never to a trap.", 870, 290, 260, 90, 11)
    dec2 = p.block("APB Decoder", "9 Slaves, 4 KB each, PSLVERR for empty windows", 590, 560, 300, 56, "bus")
    p.wire(ids[1], dec2, "APB", "bus", pts=[(1465, 169), (1465, 588)], exit=("1", "0.5"), entry=("1", "0.5"))
    names = [("SYSCSR", "+0x0000"), ("UART0", "+0x1000"), ("GPIO0", "+0x2000"), ("TIMER0", "+0x3000"), ("WDT", "+0x4000"),
             ("PLIC-lite", "+0x5000"), ("Mailbox", "+0x6000"), ("DMA Regs", "+0x7000"), ("Boot_Verifier", "+0x8000")]
    for i, (n, a) in enumerate(names):
        k = "sec" if n == "Boot_Verifier" else ("sys" if n == "SYSCSR" else "per")
        b = p.block(n, a, 50 + i * 155, 700, 140, 56, k)
        p.wire(dec2, b, "", "bus", pts=[(740, 650), (120 + i * 155, 650)], exit=("0.5", "1"), entry=("0.5", "0"))
    return p
