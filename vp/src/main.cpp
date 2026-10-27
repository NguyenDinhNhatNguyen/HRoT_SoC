// HRoT_SoC virtual platform (Secure world): a stand-in CPU running the real HAL, plus the bus,
// Boot ROM, SYSCSR, UART0, TIMER0, WDT, Secure DMA, SHA-256 and the App ROM.
//   vp_sim <app.hex> [--tamper] [--fw]
//   --tamper flips one ROM bit after the image is "signed", so secure boot must refuse it
//   and keep the App in reset.
//   --fw runs the real Secure Boot firmware (fw/secure_boot, P-13) instead of the built-in scenario.
// Exit code: 0 = behaved as expected, 1 = didn't.
#include <systemc.h>
#include <cstring>
#include <string>
#include "VP_Bus.h"
#include "VP_Peripherals.h"
#include "SHA256_VP_Wrapper.h"
#include "DMA_VP.h"
#include "CPU_Dummy_Initiator.h"

static CPU_Dummy_Initiator* g_cpu = nullptr;

// HAL hooks (sha256_regs.h, HAL_HOST_MODEL build) turned into real TLM transactions on the bus
extern "C" uint32_t hal_host_read32(uint32_t off)            { return g_cpu->rd(vp_map::SHA256 + off); }
extern "C" void     hal_host_write32(uint32_t off, uint32_t v) { g_cpu->wr(vp_map::SHA256 + off, v); }
extern "C" uint32_t hal_host_memread32(uintptr_t addr)       { return g_cpu->rd(addr); }
// UART/GPIO drivers and the firmware's own register accesses (hal_io.h, HAL_HOST_MODEL build)
extern "C" uint32_t hal_host_mmio_read32(uintptr_t addr)             { return g_cpu->rd(addr); }
extern "C" void     hal_host_mmio_write32(uintptr_t addr, uint32_t v) { g_cpu->wr(addr, v); }

int sc_main(int argc, char* argv[]) {
    if (argc < 2) {
        std::printf("usage: %s <app.hex> [--tamper] [--fw]\n", argv[0]);
        return 2;
    }
    bool tamper = false;
    bool fw = false;
    for (int i = 2; i < argc; i++) {
        if (std::strcmp(argv[i], "--tamper") == 0)
            tamper = true;
        else if (std::strcmp(argv[i], "--fw") == 0)
            fw = true;
    }

    CPU_Dummy_Initiator cpu("cpu");
    VP_Bus              bus("bus", {{"to_syscsr",  vp_map::SYSCSR,   0x1000},
                                    {"to_sha",     vp_map::SHA256,   0x1000},
                                    {"to_approm",  vp_map::APP_ROM,  0x1000},
                                    {"to_bootrom", vp_map::BOOT_ROM, 0x1000},
                                    {"to_uart0",   vp_map::UART0,    0x1000},
                                    {"to_timer0",  vp_map::TIMER0,   0x1000},
                                    {"to_wdt",     vp_map::WDT,      0x1000},
                                    {"to_dma",     vp_map::DMA,      0x1000}});
    SYSCSR_VP           syscsr("syscsr");
    SHA256_VP_Wrapper   sha("sha");
    Memory_VP           app_rom("app_rom", 4096, true);
    Memory_VP           boot_rom("boot_rom", 4096, true);
    UART0_VP            uart0("uart0");
    TIMER0_VP           timer0("timer0");
    WDT_VP              wdt("wdt");
    DMA_VP              dma("dma");
    g_cpu = &cpu;

    cpu.initiator_socket.bind(bus.target_socket);
    bus.port(0).bind(syscsr.target_socket);
    bus.port(1).bind(sha.target_socket);
    bus.port(2).bind(app_rom.target_socket);
    bus.port(3).bind(boot_rom.target_socket);
    bus.port(4).bind(uart0.target_socket);
    bus.port(5).bind(timer0.target_socket);
    bus.port(6).bind(wdt.target_socket);
    bus.port(7).bind(dma.target_socket);
    dma.rom = &app_rom;
    dma.sha = &sha;

    app_rom.load_hex(argv[1]);
    // "Sign" the whole 4 KB ROM as I-04 says (unused words stay zero), before any tampering.
    // The golden hash goes into the Boot ROM, where the CPU reads it over the bus like the RTL firmware does
    cpu.app_len = app_rom.mem.size();
    uint8_t golden[32];
    sha256_ref(app_rom.mem.data(), cpu.app_len, golden);
    std::memcpy(&boot_rom.mem[vp_map::GOLDEN], golden, 32);
    std::memcpy(&boot_rom.mem[SB_GOLDEN_ADDR], golden, 32);   // the slot the real firmware reads (P-13)
    cpu.fw_mode = fw;
    if (tamper) {
        app_rom.mem[0] ^= 0x01;
        std::printf("[Tamper] Flipped one bit in the App ROM\n");
    }

    sc_start();

    bool expect_ok = !tamper;
    if (fw) {
        bool said = uart0.tx_log.find(tamper ? "App locked out" : "App released") != std::string::npos;
        bool fw_pass = cpu.fw_result == (tamper ? SB_LOCKED : SB_RELEASED) && syscsr.app_running() == expect_ok
                       && syscsr.lock == tamper && said;
        std::printf("VP RESULT: %s (firmware result 0x%02x, app_running=%d, lock=%d, UART log %s)\n",
                    fw_pass ? "PASS" : "FAIL", cpu.fw_result, syscsr.app_running(), syscsr.lock, said ? "ok" : "missing");
        return fw_pass ? 0 : 1;
    }
    bool said_so = uart0.tx_log.find(tamper ? "App locked out" : "App released") != std::string::npos;
    bool pass = (cpu.boot_ok == expect_ok) && (syscsr.app_running() == expect_ok) && cpu.bus_errors == 1
                && said_so && wdt.kicks == 1 && syscsr.lock == tamper && cpu.dma_match == expect_ok && cpu.fw_ok;
    std::printf("VP RESULT: %s (boot_ok=%d, app_running=%d, bus errors=%d, expected 1 from the ROM write, UART log %s, DMA %s)\n",
                pass ? "PASS" : "FAIL", cpu.boot_ok, syscsr.app_running(), cpu.bus_errors, said_so ? "ok" : "missing",
                cpu.dma_match == expect_ok && cpu.fw_ok ? "ok" : "wrong");
    return pass ? 0 : 1;
}
