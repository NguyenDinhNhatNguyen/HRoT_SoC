#ifndef VP_PERIPHERALS_H
#define VP_PERIPHERALS_H

// Simple TLM models of memory, SYSCSR, UART0, TIMER0 and WDT (match the RTL, see docs/spec/SoC_Memory_Map.md)
// The VP has no interrupts and no reset generator: UART0 only transmits, TIMER0 counts, the WDT never fires.
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
            if (tok[0] == '@')
                continue;
            uint32_t w = std::stoul(tok, nullptr, 16);
            if (n + 4 > mem.size())
                break;
            std::memcpy(&mem[n], &w, 4);
            n += 4;
        }
        return n;
    }

    void b_transport(tlm::tlm_generic_payload& trans, sc_time& delay) {
        uint64_t a = trans.get_address();
        unsigned len = trans.get_data_length();
        if (a + len > mem.size()) {
            trans.set_response_status(tlm::TLM_ADDRESS_ERROR_RESPONSE);
            return;
        }
        if (trans.is_write()) {
            if (read_only) { 
                trans.set_response_status(tlm::TLM_COMMAND_ERROR_RESPONSE);
                return; 
            }
            std::memcpy(&mem[a], trans.get_data_ptr(), len);
        } else {
            std::memcpy(trans.get_data_ptr(), &mem[a], len);
        }
        delay += sc_time(80, SC_NS);
        trans.set_response_status(tlm::TLM_OK_RESPONSE);
    }
};

// SYSCSR: APP_CTRL (0x00, bit0 releases the App), CHIP_ID (0x04), VERSION (0x08), GUARD (0x20)
// GUARD LOCK (write 1) holds the App in reset for good. The VP has no App RAM, so zeroization is instant
SC_MODULE(SYSCSR_VP) {
    tlm_utils::simple_target_socket<SYSCSR_VP> target_socket;
    uint32_t app_ctrl = 0;
    bool     lock = false;

    SC_CTOR(SYSCSR_VP) : target_socket("target_socket") {
        target_socket.register_b_transport(this, &SYSCSR_VP::b_transport);
    }

    bool app_running() const { return (app_ctrl & 1) && !lock; }

    void b_transport(tlm::tlm_generic_payload& trans, sc_time& delay) {
        uint64_t off = trans.get_address();
        uint32_t* p = reinterpret_cast<uint32_t*>(trans.get_data_ptr());
        if (trans.is_write()) {
            if (off == 0x00) {
                app_ctrl = *p & 1;
                std::cout << "[" << sc_time_stamp() + delay << "] SYSCSR: App Core "
                          << (app_running() ? "Released from reset" : "held in reset") << std::endl;
            }
            if (off == 0x20 && (*p & 1) && !lock) {
                lock = true;
                std::cout << "[" << sc_time_stamp() + delay << "] SYSCSR: Boot Guard LOCK set, App Core held in reset until POR" << std::endl;
            }
        } else {
            *p = off == 0x00 ? app_ctrl : off == 0x04 ? 0x48524F54u : off == 0x08 ? 0x00020000u :
                 off == 0x20 ? (lock ? 0x5u : 0u) : 0u;
        }
        delay += sc_time(120, SC_NS);
        trans.set_response_status(tlm::TLM_OK_RESPONSE);
    }
};

// UART0: TXDATA (0x00) prints the byte, RXDATA (0x04) is always empty, STATUS (0x08) is TX_IDLE,
// BAUD_DIV (0x0C) and IRQ_EN (0x10) just store what is written
SC_MODULE(UART0_VP) {
    tlm_utils::simple_target_socket<UART0_VP> target_socket;
    std::string tx_log;                 // everything the firmware sent, for the testbench to check
    uint32_t baud_div = 26;
    uint32_t irq_en = 0;

    SC_CTOR(UART0_VP) : target_socket("target_socket") {
        target_socket.register_b_transport(this, &UART0_VP::b_transport);
    }

    void b_transport(tlm::tlm_generic_payload& trans, sc_time& delay) {
        uint64_t off = trans.get_address();
        uint32_t* p = reinterpret_cast<uint32_t*>(trans.get_data_ptr());
        if (trans.is_write()) {
            if (off == 0x00) {
                char c = static_cast<char>(*p & 0xFF);
                tx_log += c;
                std::cout << c << std::flush;
            }
            if (off == 0x0C)
                baud_div = *p & 0xFFFF;
            if (off == 0x10)
                irq_en = *p & 3;
        } else {
            *p = off == 0x04 ? 0x80000000u : off == 0x08 ? 0x2u : off == 0x0C ? baud_div : off == 0x10 ? irq_en : 0u;
        }
        delay += sc_time(120, SC_NS);
        trans.set_response_status(tlm::TLM_OK_RESPONSE);
    }
};

// TIMER0: 64-bit mtime counting at 50 MHz from the simulation time, MTIMECMP stored but it raises no interrupt
SC_MODULE(TIMER0_VP) {
    tlm_utils::simple_target_socket<TIMER0_VP> target_socket;
    uint64_t mtime_offset = 0;          // what a write to MTIME added or removed
    uint64_t mtimecmp = ~0ull;

    SC_CTOR(TIMER0_VP) : target_socket("target_socket") {
        target_socket.register_b_transport(this, &TIMER0_VP::b_transport);
    }

    uint64_t mtime(const sc_time& t) const { return static_cast<uint64_t>(t.value() / 20000) + mtime_offset; }

    void b_transport(tlm::tlm_generic_payload& trans, sc_time& delay) {
        uint64_t off = trans.get_address();
        uint32_t* p = reinterpret_cast<uint32_t*>(trans.get_data_ptr());
        uint64_t now = mtime(sc_time_stamp() + delay);
        if (trans.is_write()) {
            if (off == 0x00)
                mtime_offset += (now & ~0xFFFFFFFFull) + *p - now;
            if (off == 0x04)
                mtime_offset += (static_cast<uint64_t>(*p) << 32) + (now & 0xFFFFFFFFull) - now;
            if (off == 0x08)
                mtimecmp = (mtimecmp & ~0xFFFFFFFFull) | *p;
            if (off == 0x0C)
                mtimecmp = (mtimecmp & 0xFFFFFFFFull) | (static_cast<uint64_t>(*p) << 32);
        } else {
            *p = off == 0x00 ? static_cast<uint32_t>(now) : off == 0x04 ? static_cast<uint32_t>(now >> 32) :
                 off == 0x08 ? static_cast<uint32_t>(mtimecmp) : off == 0x0C ? static_cast<uint32_t>(mtimecmp >> 32) : 0u;
        }
        delay += sc_time(120, SC_NS);
        trans.set_response_status(tlm::TLM_OK_RESPONSE);
    }
};

// WDT: CTRL (0x00, EN sticks once set), LOAD (0x04, locked while EN), COUNT (0x08, counts down from the
// last kick), KICK (0x0C, key 0x5A5A0002). The VP never resets when COUNT reaches 0, it only keeps count
SC_MODULE(WDT_VP) {
    tlm_utils::simple_target_socket<WDT_VP> target_socket;
    bool     en = false;
    uint32_t load = 50000000;
    sc_time  kicked_at = SC_ZERO_TIME;
    int      kicks = 0;

    SC_CTOR(WDT_VP) : target_socket("target_socket") {
        target_socket.register_b_transport(this, &WDT_VP::b_transport);
    }

    uint32_t count(const sc_time& t) const {
        uint64_t elapsed = en ? static_cast<uint64_t>((t - kicked_at).value() / 20000) : 0;
        return elapsed >= load ? 0u : static_cast<uint32_t>(load - elapsed);
    }

    void b_transport(tlm::tlm_generic_payload& trans, sc_time& delay) {
        uint64_t off = trans.get_address();
        uint32_t* p = reinterpret_cast<uint32_t*>(trans.get_data_ptr());
        sc_time now = sc_time_stamp() + delay;
        if (trans.is_write()) {
            if (off == 0x00 && (*p & 1) && !en) {
                en = true;
                kicked_at = now;
            }
            if (off == 0x04 && !en)
                load = *p;
            if (off == 0x0C && *p == 0x5A5A0002u) {
                kicked_at = now;
                kicks++;
            }
        } else {
            *p = off == 0x00 ? (en ? 1u : 0u) : off == 0x04 ? load : off == 0x08 ? count(now) : 0u;
        }
        delay += sc_time(120, SC_NS);
        trans.set_response_status(tlm::TLM_OK_RESPONSE);
    }
};

#endif
