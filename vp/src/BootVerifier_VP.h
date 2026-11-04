#ifndef BOOT_VERIFIER_VP_H
#define BOOT_VERIFIER_VP_H

// Functional TLM model of Boot_Verifier (N-37, I-08), added by Phát on 04/11 so the Secure Boot firmware
// (vp_sim --fw) can run its CHECK. Same registers as rtl/periph/Boot_Verifier.v:
//   0x00 CTRL (bit0 CHECK once per reset, bit1 KEY_LOCK), 0x04 STATUS (bit0 VERIFIED, bit1 FAIL,
//   bit2 KEY_LOCKED, bit3 CHECKED, bit4 BUSY), 0x08 MIN_VER, 0x0C APP_VER.
// CHECK compares the SHA-256 result with the golden hash at 0xFE0 of the Boot ROM (8 big-endian words
// H0..H7, I-03) at once, so the verdict is there on the next read. MODE 1 (HMAC tag) and the key
// registers are not modelled.
#include "VP_Peripherals.h"
#include "SHA256_VP_Wrapper.h"

SC_MODULE(BootVerifier_VP) {
    tlm_utils::simple_target_socket<BootVerifier_VP> target_socket;
    SHA256_VP_Wrapper* sha = nullptr;       // set by main
    Memory_VP*         boot_rom = nullptr;  // set by main

    static constexpr uint32_t GOLDEN = 0xFE0;

    uint32_t app_ver = 0, min_ver = 0;
    bool     checked = false, ok = false, fail = false, key_lock = false;

    SC_CTOR(BootVerifier_VP) : target_socket("target_socket") {
        target_socket.register_b_transport(this, &BootVerifier_VP::b_transport);
    }

    void check(const sc_time& now) {
        checked = true;
        sha->settle(now);
        bool pass = sha->done && !sha->busy(now) && app_ver >= min_ver;
        for (int i = 0; pass && i < 8; i++) {
            uint32_t w;
            std::memcpy(&w, &boot_rom->mem[GOLDEN + 4 * i], 4);
            if (w != sha->h[i])
                pass = false;
        }
        ok = pass;
        fail = !pass;
        if (pass && app_ver > min_ver)
            min_ver = app_ver;
    }

    void b_transport(tlm::tlm_generic_payload& trans, sc_time& delay) {
        uint64_t off = trans.get_address();
        uint32_t* p = reinterpret_cast<uint32_t*>(trans.get_data_ptr());
        sc_time now = sc_time_stamp() + delay;
        if (trans.is_write()) {
            if (off == 0x00 && (*p & 2))
                key_lock = true;
            if (off == 0x00 && (*p & 1) && !checked)
                check(now);
            if (off == 0x08 && *p > min_ver)
                min_ver = *p;
            if (off == 0x0C && !checked)
                app_ver = *p;
        } else {
            *p = off == 0x04 ? ((checked ? 8u : 0u) | (key_lock ? 4u : 0u) | (fail ? 2u : 0u) | (ok ? 1u : 0u)) :
                 off == 0x08 ? min_ver : off == 0x0C ? app_ver : 0u;
        }
        delay += sc_time(120, SC_NS);
        trans.set_response_status(tlm::TLM_OK_RESPONSE);
    }
};

#endif
