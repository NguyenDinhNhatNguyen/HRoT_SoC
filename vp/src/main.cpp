// HRoT_SoC virtual platform (Secure world): a stand-in CPU running the real HAL, plus the bus,
// SYSCSR, SHA-256 and the App ROM.
//   vp_sim <app.hex> [--tamper]
//   --tamper flips one ROM bit after the image is "signed", so secure boot must refuse it
//   and keep the App in reset.
// Exit code: 0 = behaved as expected, 1 = didn't.
#include <systemc.h>
#include <cstring>
#include <string>
#include "VP_Bus.h"
#include "VP_Peripherals.h"
#include "SHA256_VP_Wrapper.h"
#include "CPU_Dummy_Initiator.h"

static CPU_Dummy_Initiator* g_cpu = nullptr;

// HAL hooks (sha256_regs.h, HAL_HOST_MODEL build) turned into real TLM transactions on the bus
extern "C" uint32_t hal_host_read32(uint32_t off)            { return g_cpu->rd(vp_map::SHA256 + off); }
extern "C" void     hal_host_write32(uint32_t off, uint32_t v) { g_cpu->wr(vp_map::SHA256 + off, v); }
extern "C" uint32_t hal_host_memread32(uintptr_t addr)       { return g_cpu->rd(addr); }

int sc_main(int argc, char* argv[]) {
    if (argc < 2) {
        std::printf("usage: %s <app.hex> [--tamper]\n", argv[0]);
        return 2;
    }
    bool tamper = argc > 2 && std::strcmp(argv[2], "--tamper") == 0;

    CPU_Dummy_Initiator cpu("cpu");
    VP_Bus              bus("bus", {{"to_syscsr", vp_map::SYSCSR,  0x1000},
                                    {"to_sha",    vp_map::SHA256,  0x1000},
                                    {"to_approm", vp_map::APP_ROM, 0x1000}});
    SYSCSR_VP           syscsr("syscsr");
    SHA256_VP_Wrapper   sha("sha");
    Memory_VP           app_rom("app_rom", 4096, true);
    g_cpu = &cpu;

    cpu.initiator_socket.bind(bus.target_socket);
    bus.port(0).bind(syscsr.target_socket);
    bus.port(1).bind(sha.target_socket);
    bus.port(2).bind(app_rom.target_socket);

    app_rom.load_hex(argv[1]);
    // "Sign" the whole 4 KB ROM as I-04 says (unused words stay zero), before any tampering
    cpu.app_len = app_rom.mem.size();
    sha256_ref(app_rom.mem.data(), cpu.app_len, cpu.golden);
    if (tamper) {
        app_rom.mem[0] ^= 0x01;
        std::printf("[Tamper] Flipped one bit in the App ROM\n");
    }

    sc_start();

    bool expect_ok = !tamper;
    bool pass = (cpu.boot_ok == expect_ok) && (syscsr.app_running() == expect_ok) && cpu.bus_errors == 1;
    std::printf("VP RESULT: %s (boot_ok=%d, app_running=%d, bus errors=%d, expected 1 from the ROM write)\n",
                pass ? "PASS" : "FAIL", cpu.boot_ok, syscsr.app_running(), cpu.bus_errors);
    return pass ? 0 : 1;
}
