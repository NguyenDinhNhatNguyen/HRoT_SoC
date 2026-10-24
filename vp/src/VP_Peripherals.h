#ifndef VP_PERIPHERALS_H
#define VP_PERIPHERALS_H

// Simple TLM models of memory and SYSCSR (match the RTL, see docs/spec/SoC_Memory_Map.md)
#include <systemc.h>
#include <tlm.h>
#include <tlm_utils/simple_target_socket.h>
#include <cstdint>
#include <cstring>
#include <fstream>
#include <string>
#include <vector>

// 32-bit word memory stored as little-endian bytes (like RISC-V). read_only: writes fail (SLVERR)
SC_MODULE(Memory_VP) {
    tlm_utils::simple_target_socket<Memory_VP> target_socket;
    std::vector<uint8_t> mem;
    bool read_only = false;

    Memory_VP(sc_module_name n, size_t bytes, bool ro) : sc_module(n), target_socket("target_socket"), mem(bytes, 0), read_only(ro) {
        target_socket.register_b_transport(this, &Memory_VP::b_transport);
    }

    // Load a $readmemh-style hex file (one word per line, '@' lines skipped) and return the byte count
    size_t load_hex(const std::string& path) {
        std::ifstream f(path);
        std::string tok;
        size_t n = 0;
        while (f >> tok) {
            if (tok[0] == '@') continue;
            uint32_t w = std::stoul(tok, nullptr, 16);
            if (n + 4 > mem.size()) break;
            std::memcpy(&mem[n], &w, 4);
            n += 4;
        }
        return n;
    }

    void b_transport(tlm::tlm_generic_payload& trans, sc_time& delay) {
        uint64_t a = trans.get_address();
        unsigned len = trans.get_data_length();
        if (a + len > mem.size()) { trans.set_response_status(tlm::TLM_ADDRESS_ERROR_RESPONSE); return; }
        if (trans.is_write()) {
            if (read_only) { trans.set_response_status(tlm::TLM_COMMAND_ERROR_RESPONSE); return; }
            std::memcpy(&mem[a], trans.get_data_ptr(), len);
        } else {
            std::memcpy(trans.get_data_ptr(), &mem[a], len);
        }
        delay += sc_time(80, SC_NS);
        trans.set_response_status(tlm::TLM_OK_RESPONSE);
    }
};

// SYSCSR: APP_CTRL (0x00, bit0 releases the App), CHIP_ID (0x04), VERSION (0x08)
SC_MODULE(SYSCSR_VP) {
    tlm_utils::simple_target_socket<SYSCSR_VP> target_socket;
    uint32_t app_ctrl = 0;

    SC_CTOR(SYSCSR_VP) : target_socket("target_socket") {
        target_socket.register_b_transport(this, &SYSCSR_VP::b_transport);
    }

    bool app_running() const { return app_ctrl & 1; }

    void b_transport(tlm::tlm_generic_payload& trans, sc_time& delay) {
        uint64_t off = trans.get_address();
        uint32_t* p = reinterpret_cast<uint32_t*>(trans.get_data_ptr());
        if (trans.is_write()) {
            if (off == 0x00) {
                app_ctrl = *p & 1;
                std::cout << "[" << sc_time_stamp() + delay << "] SYSCSR: App Core "
                          << (app_running() ? "released from reset" : "held in reset") << std::endl;
            }
        } else {
            *p = off == 0x00 ? app_ctrl : off == 0x04 ? 0x48524F54u : off == 0x08 ? 0x00020000u : 0u;
        }
        delay += sc_time(120, SC_NS);
        trans.set_response_status(tlm::TLM_OK_RESPONSE);
    }
};

#endif
