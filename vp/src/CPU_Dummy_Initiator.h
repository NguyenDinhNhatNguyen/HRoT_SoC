#ifndef CPU_DUMMY_INITIATOR_H
#define CPU_DUMMY_INITIATOR_H

// CPU gia lap cua the gioi Secure: chay HAL SHA-256 that cua firmware (fw/hal, -DHAL_HOST_MODEL).
// Moi lan HAL doc/ghi thanh ghi -> 1 giao dich TLM tren VP_Bus (hook hal_host_* trong main.cpp).
// Kich ban secure boot: doc CHIP_ID -> bam ROM App (0x6000_0000) -> so voi golden -> nha / giu reset App.
#include <systemc.h>
#include <tlm.h>
#include <tlm_utils/simple_initiator_socket.h>
#include <cstdint>
#include <cstdio>
#include <cstring>

extern "C" {
#include "sha256_hal.h"
}

namespace vp_map {
    const uint64_t SYSCSR  = 0x40000000;
    const uint64_t SHA256  = 0x50000000;
    const uint64_t APP_ROM = 0x60000000;
}

SC_MODULE(CPU_Dummy_Initiator) {
    tlm_utils::simple_initiator_socket<CPU_Dummy_Initiator> initiator_socket;

    uint32_t app_len = 0;          // so byte image App can bam
    uint8_t  golden[32]{};         // golden hash (tinh luc "ky" image, truoc khi nap ROM)
    bool     boot_ok = false;
    int      bus_errors = 0;

    SC_CTOR(CPU_Dummy_Initiator) : initiator_socket("initiator_socket") {
        SC_THREAD(run_secure_boot_sequence);
    }

    // Giao dich 32-bit; delay duoc cong don roi wait() ngay (loosely-timed, khong quantum keeper)
    uint32_t access(bool write, uint64_t addr, uint32_t data) {
        tlm::tlm_generic_payload trans;
        sc_time delay = SC_ZERO_TIME;
        trans.set_command(write ? tlm::TLM_WRITE_COMMAND : tlm::TLM_READ_COMMAND);
        trans.set_address(addr);
        trans.set_data_ptr(reinterpret_cast<unsigned char*>(&data));
        trans.set_data_length(4);
        trans.set_streaming_width(4);
        trans.set_byte_enable_ptr(nullptr);
        trans.set_response_status(tlm::TLM_INCOMPLETE_RESPONSE);
        initiator_socket->b_transport(trans, delay);
        if (trans.is_response_error()) {
            bus_errors++;
            std::printf("[%s] LOI BUS tai 0x%08llx (%s)\n", sc_time_stamp().to_string().c_str(),
                        (unsigned long long)addr, trans.get_response_string().c_str());
        }
        wait(delay);
        return data;
    }
    uint32_t rd(uint64_t a)             { return access(false, a, 0); }
    void     wr(uint64_t a, uint32_t v) { access(true, a, v); }

    void run_secure_boot_sequence() {
        std::printf("[%s] Secure CPU: bat dau secure boot\n", sc_time_stamp().to_string().c_str());
        uint32_t id = rd(vp_map::SYSCSR + 0x04);
        std::printf("  CHIP_ID = 0x%08x %s\n", id, id == 0x48524F54u ? "(HROT)" : "(SAI)");

        uint8_t digest[32];
        sha256_status_t st = sha256_digest_mem(vp_map::APP_ROM, app_len, digest);
        std::printf("  sha256_digest_mem(0x60000000, %u byte) -> status %d\n  hash   = ", app_len, (int)st);
        for (int i = 0; i < 32; i++) std::printf("%02x", digest[i]);
        std::printf("\n  golden = ");
        for (int i = 0; i < 32; i++) std::printf("%02x", golden[i]);
        std::printf("\n");

        boot_ok = (st == SHA256_OK) && sha256_compare(digest, golden, 32) == 0;
        if (boot_ok) {
            wr(vp_map::SYSCSR + 0x00, 1);       // APP_CTRL.APP_RUN = 1
        } else {
            std::printf("  Hash KHONG KHOP -> giu App Core trong reset\n");
            wr(vp_map::SYSCSR + 0x00, 0);
        }
        wr(vp_map::APP_ROM, 0xDEADBEEF);       // thu ghi ROM: phai bi tu choi
        sc_stop();
    }
};

#endif
