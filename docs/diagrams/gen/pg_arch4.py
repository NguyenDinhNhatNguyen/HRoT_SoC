from dlib import Page


def pmod_j2():
    p = Page("19 KV260 Pmod J2", 900, 620)
    p.text("KV260 Pmod J2 (HDR 2x6, 3.3 V): connector pin, net, FPGA pin, SoC port", 40, 8, 820, 28, 16, True)
    p.text("J2 pin numbers: AMD carrier card schematic XTP682 (rev 1.0 and 2.0, sheet 17). FPGA pins: AMD XDC (Kria-PYNQ). Not measured on a board yet, "
           "use fpga/xilinx/kv260/pintest to check", 40, 38, 820, 40, 12)
    rows = [
        (1, "HDA11 / H12", "uart_tx", 2, "HDA15 / B10", "led[1]", "bus"),
        (3, "HDA12 / E10", "uart_rx", 4, "HDA16_CC / E12", "led[2]", "bus"),
        (5, "HDA13 / D10", "led_app", 6, "HDA17 / D11", "led[3]", "bus"),
        (7, "HDA14 / C11", "led[0]", 8, "HDA18 / B11", "led[4]", "bus"),
        (9, "GND", "", 10, "GND", "", "neutral"),
        (11, "PMOD_3V3", "", 12, "PMOD_3V3", "", "sys"),
    ]
    p.text("PORT", 40, 92, 130, 20, 11, True, align="center")
    p.text("NET / FPGA PIN", 180, 92, 190, 20, 11, True, align="center")
    p.text("NET / FPGA PIN", 530, 92, 190, 20, 11, True, align="center")
    p.text("PORT", 730, 92, 130, 20, 11, True, align="center")
    y = 118
    for a, an, ap, b, bn, bp, kind in rows:
        p.block(ap, "", 40, y, 130, 44, kind)
        p.block(an, "", 180, y, 190, 44, kind)
        p.block(str(a), "", 390, y, 50, 44, "sys")
        p.block(str(b), "", 440, y, 50, 44, "sys")
        p.block(bn, "", 530, y, 190, 44, kind)
        p.block(bp, "", 730, y, 130, 44, kind)
        y += 62
    p.text("Odd pins (J2.1, 3, 5...)", 180, y, 190, 20, 11, color="#555555", align="center")
    p.text("Even pins (J2.2, 4, 6...)", 530, y, 190, 20, 11, color="#555555", align="center")
    return p


def vp_arch():
    p = Page("20 VP Architecture", 1700, 1090)
    p.text("Virtual Platform (SystemC 2.3.x, TLM-2.0 loosely timed), Secure world only (vp/src/)", 40, 8, 1200, 28, 16, True)
    p.group("Initiator, two ways to drive the bus", 30, 50, 380, 420, "core")
    scn = p.block("CPU_Dummy_Initiator", "C++ secure boot scenario: read CHIP_ID and golden, enable WDT, hash App ROM, compare, DMA and firewall checks, release App or lock", 60, 90, 320, 120, "core")
    fw = p.block("Firmware (--fw)", "fw/secure_boot/secure_boot.c built with -DHAL_HOST_MODEL, fw/hal runs on the host", 60, 250, 320, 100, "core")
    hook = p.block("hal_host_* hooks", "Every HAL register read or write becomes one TLM transaction (main.cpp)", 60, 380, 320, 60, "sys")
    p.wire(fw, hook, "HAL calls", "core")
    bus = p.block("VP_Bus", "1 initiator, N targets, same address decode as SoC_Top. Unknown address: DECERR (TLM_ADDRESS_ERROR)", 500, 200, 260, 140, "bus")
    p.wire(scn, bus, "TLM b_transport", "bus", exit=("1", "0.5"), entry=("0", "0.3"))
    p.wire(hook, bus, "TLM b_transport", "bus", exit=("1", "0.5"), entry=("0", "0.7"))
    p.group("Targets (VP_Peripherals.h and models)", 860, 50, 800, 690, "bus")
    items = [
        ("Boot ROM 0x0000_0000", "Read-only, 4 KB. Golden hash at 0x600 for the C++ scenario, at 0xFE0 for Boot_Verifier_VP", "mem"),
        ("SYSCSR 0x4000_0000", "With Boot Guard, verified gate (SYSCSR_VP.verified)", "sys"),
        ("UART0 0x4000_1000", "Prints to console and keeps a log", "per"),
        ("TIMER0 0x4000_3000", "mtime at 50 MHz of simulated time", "per"),
        ("WDT 0x4000_4000", "Counts, does not reset", "per"),
        ("Secure DMA 0x4000_7000", "DMA_VP.h: same registers and firewall rules as the RTL", "sha"),
        ("Boot_Verifier 0x4000_8000", "BootVerifier_VP.h (I-08): CHECK, MIN_VER, KEY_LOCK", "sec"),
        ("SHA-256 0x5000_0000", "SHA256_VP_Wrapper.h, 66 cycles per block like the RTL", "sha"),
        ("App ROM 0x6000_0000", "Read-only, 4 KB, hashed by the Master", "mem"),
    ]
    yy = 90
    for n, d, k in items:
        t = p.block(n, d, 900, yy, 720, 54, k)
        p.wire(bus, t, "", "bus", exit=("1", "0.5"), entry=("0", "0.5"), width=1)
        yy += 70
    p.group("Not modelled", 30, 770, 1630, 80, "zone")
    p.text("GPIO (a bus error line is printed at 0x4000_2000 in --fw mode, harmless), PLIC-lite, Mailbox, the App world bus and peripherals, interrupts, reset requested by the WDT", 50, 800, 1590, 40, 12)
    p.group("Run: make vp (sim/run_vp.sh), 4 scenarios, each must print VP RESULT: PASS", 30, 880, 1630, 170, "sys")
    p.text("Good image and image with one flipped bit (--tamper), each with the C++ scenario and with the real firmware (--fw). "
           "Good image: APP_RUN before CHECK is refused, after CHECK STATUS = 0x9, firmware ends VERIFIED and locks KEY. "
           "Tampered image: STATUS = 0xA, Boot Guard locks the App.", 50, 925, 1590, 100, 13)
    return p


def fpga_testbed():
    p = Page("21 FPGA Testbed", 1700, 1000)
    p.text("FPGA testbed: one RTL (rtl/), a board top for each kit", 40, 8, 1100, 28, 16, True)
    p.group("Common to every kit", 650, 260, 360, 300, "core")
    soc = p.block("SoC_Top", "VERIFY_GATE = 1. Parameters BOOT_HEX, RAM_HEX, APP_HEX load the memories (fw/build/*.hex, or the mkhex.py test firmware)", 680, 310, 300, 130, "core")
    uart = p.block("UART0 at 115200 8N1", "The 115200 baud setting assumes the 50 MHz clock", 680, 470, 300, 60, "per")
    p.wire(soc, uart, "", "n")
    p.group("DE2 (Intel, Quartus II 13.0sp1, make de2)", 30, 50, 560, 400, "sys")
    p.block("CLOCK_50", "50 MHz oscillator", 60, 100, 160, 50, "neutral")
    p.block("KEY0", "Reset (synchronized)", 60, 170, 160, 50, "neutral")
    p.block("SW[13:0]", "GPIO0 in SW[7:0], GPIO1 in SW[13:8], boot strap", 60, 240, 160, 70, "neutral")
    de2 = p.block("DE2_Top", "Pins from de2_pins.tcl (52 pins). constraints.sdc: clk50 20 ns", 270, 170, 280, 100, "sys")
    p.block("LEDR[7:0]", "GPIO0 out", 270, 310, 130, 50, "neutral")
    p.block("LEDG[8:0]", "LEDG0 = app_running, LEDG[8:1] = GPIO1", 410, 310, 140, 70, "neutral")
    p.block("UART_TXD / RXD", "RS-232 DB9 through a USB-serial adapter", 270, 390, 280, 40, "neutral")
    p.wire(de2, soc, "clk, reset_system, gpio, uart", "sys", exit=("1", "0.5"), entry=("0", "0.3"))
    p.group("Kria KV260 (Vivado 2025.2, make kv260)", 1070, 50, 600, 480, "sys")
    ps = p.block("Zynq UltraScale+ PS", "kv260_bd.tcl: pl_clk0 50 MHz from the IOPLL, pl_resetn0. The PL has no oscillator of its own", 1100, 100, 540, 80, "sys")
    kv = p.block("KV260_Top", "2-flop reset synchronizer. gpio0_i = 0, boot_strap = 0. kv260.xdc: LVCMOS33", 1100, 220, 540, 80, "sys")
    p.wire(ps, kv, "pl_clk0, pl_resetn0", "sys")
    p.block("Pmod J2 (3.3 V)", "uart_tx J2.1, uart_rx J2.3, led_app J2.5, led[0] J2.7, led[1] J2.2, led[2] J2.4, led[3] J2.6, led[4] J2.8 (page 19)", 1100, 360, 540, 80, "neutral")
    p.text("Only 5 LEDs fit on the 8 Pmod pins. The 8-bit boot result still prints on the UART.", 1100, 450, 540, 40, 12)
    p.wire(kv, soc, "clk, reset_system, uart, led", "sys", exit=("0", "0.5"), entry=("1", "0.3"))
    p.group("Artix-7 trial flow (Vivado, make xilinx)", 30, 490, 560, 150, "bus")
    p.block("Xilinx_Top", "clk, btn_rst, sw, sw_boot, led, led_app, uart. xc7a35t, no board yet. Stops after place and route", 60, 540, 500, 70, "bus")
    p.group("Loading and checking", 30, 680, 1640, 280, "zone")
    p.block("DE2", "Quartus Programmer, USB-Blaster, hrot_de2.sof. Press KEY0, read the UART, read the LEDs (guide D-01 to D-07)", 60, 730, 500, 90, "sys")
    p.block("KV260", "make_on_pc.ps1 makes .bit.bin and .dtbo, install_on_board.sh, xmutil loadapp kv260-hrot (guide K-01 to K-10)", 600, 730, 500, 90, "sys")
    p.block("Expected output", "UART: HRoT secure boot, App ROM hash, App version, App released. Good image: LEDR = 0x01. Tampered image: Hash mismatch, App locked out, LEDR = 0xEE", 1140, 730, 500, 90, "ok")
    p.text("Checks after every RTL change: DE2 memory stays 135,168 bits and RISCV_Core:master_core is in the map report. WNS and WHS stay positive on Vivado. Power in the reports is an estimate, not a measurement.", 60, 850, 1580, 60, 12)
    return p
