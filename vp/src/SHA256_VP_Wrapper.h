#ifndef SHA256_VP_WRAPPER_H
#define SHA256_VP_WRAPPER_H

// Mo hinh TLM cua SHA256_Wrapper (RTL). Ban do thanh ghi giong RTL / fw/hal/sha256_regs.h:
//   0x00-0x3C BLOCK (W), 0x40 CTRL (bit0 START, bit1 INIT), 0x44 STATUS (bit0 DONE, bit1 BUSY),
//   0x50-0x6C HASH (R). Offset khac: doc 0, ghi bo qua.
// Thoi gian: 1 block = 66 chu ky clock (giong RTL), BUSY=1 trong khoang do.
#include <systemc.h>
#include <tlm.h>
#include <tlm_utils/simple_target_socket.h>
#include <cstdint>
#include <cstring>

extern "C" {
#include "sha256_ref.h"
}

SC_MODULE(SHA256_VP_Wrapper) {
    tlm_utils::simple_target_socket<SHA256_VP_Wrapper> target_socket;

    sc_time  clk_period{20, SC_NS};
    uint32_t block[16]{};
    uint32_t h[8]{};
    uint32_t h_next[8]{};
    bool     done = false;
    sc_time  busy_until = SC_ZERO_TIME;

    SC_CTOR(SHA256_VP_Wrapper) : target_socket("target_socket") {
        target_socket.register_b_transport(this, &SHA256_VP_Wrapper::b_transport);
        std::memcpy(h, SHA256_REF_IV, sizeof h);
    }

    bool busy(const sc_time& now) const { return now < busy_until; }

    // Ket qua chi "hien" ra khi het BUSY, giong RTL
    void settle(const sc_time& now) {
        if (!done && busy_until != SC_ZERO_TIME && !busy(now)) {
            std::memcpy(h, h_next, sizeof h);
            done = true;
        }
    }

    void b_transport(tlm::tlm_generic_payload& trans, sc_time& delay) {
        uint64_t off = trans.get_address();
        uint32_t* ptr = reinterpret_cast<uint32_t*>(trans.get_data_ptr());
        sc_time now = sc_time_stamp() + delay;
        settle(now);

        if (trans.get_data_length() != 4 || (off & 3)) {
            trans.set_response_status(tlm::TLM_BURST_ERROR_RESPONSE);
            return;
        }
        if (trans.is_write()) {
            uint32_t v = *ptr;
            if (off < 0x40) {
                if (!busy(now)) block[off >> 2] = v;
            } else if (off == 0x40 && (v & 1) && !busy(now)) {
                if (v & 2) std::memcpy(h, SHA256_REF_IV, sizeof h);
                std::memcpy(h_next, h, sizeof h);
                sha256_ref_compress(h_next, block);
                done = false;
                busy_until = now + 66 * clk_period;
            }
        } else {
            uint32_t v = 0;
            if (off == 0x44)                    v = (busy(now) ? 2u : 0u) | (done ? 1u : 0u);
            else if (off >= 0x50 && off <= 0x6C) v = h[(off - 0x50) >> 2];
            *ptr = v;
        }
        delay += clk_period * 4;   // ~ do tre 1 giao dich AXI4-Lite tren RTL
        trans.set_response_status(tlm::TLM_OK_RESPONSE);
    }
};

#endif
