// Virtual Platform HRoT_SoC (the gioi Secure): CPU gia lap chay HAL that + bus + SYSCSR + SHA-256 + ROM App.
//   vp_sim <app.hex> [--tamper]
//   --tamper: sua 1 word ROM sau khi "ky" -> secure boot phai tu choi, App bi giu reset.
// Ma thoat: 0 = ket qua dung nhu mong doi, 1 = sai.
#include <systemc.h>
#include <cstring>
#include <string>
#include "VP_Bus.h"
#include "VP_Peripherals.h"
#include "SHA256_VP_Wrapper.h"
#include "CPU_Dummy_Initiator.h"

static CPU_Dummy_Initiator* g_cpu = nullptr;

// Hook cua HAL (sha256_regs.h, che do HAL_HOST_MODEL) -> giao dich TLM that tren bus
extern "C" uint32_t hal_host_read32(uint32_t off)            { return g_cpu->rd(vp_map::SHA256 + off); }
extern "C" void     hal_host_write32(uint32_t off, uint32_t v) { g_cpu->wr(vp_map::SHA256 + off, v); }
extern "C" uint32_t hal_host_memread32(uintptr_t addr)       { return g_cpu->rd(addr); }

int sc_main(int argc, char* argv[]) {
    if (argc < 2) { std::printf("dung: %s <app.hex> [--tamper]\n", argv[0]); return 2; }
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

    cpu.app_len = app_rom.load_hex(argv[1]);
    // "Ky" image: golden hash tinh truoc khi nap (sau nay do buoc build firmware sinh ra)
    sha256_ref(app_rom.mem.data(), cpu.app_len, cpu.golden);
    if (tamper) { app_rom.mem[0] ^= 0x01; std::printf("[tamper] da sua 1 bit trong ROM App\n"); }

    sc_start();

    bool expect_ok = !tamper;
    bool pass = (cpu.boot_ok == expect_ok) && (syscsr.app_running() == expect_ok) && cpu.bus_errors == 1;
    std::printf("VP RESULT: %s (boot_ok=%d, app_running=%d, loi bus=%d [mong doi 1: ghi ROM])\n",
                pass ? "PASS" : "FAIL", cpu.boot_ok, syscsr.app_running(), cpu.bus_errors);
    return pass ? 0 : 1;
}
