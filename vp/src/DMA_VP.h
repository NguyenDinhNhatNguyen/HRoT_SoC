#ifndef DMA_VP_H
#define DMA_VP_H

// Functional TLM model of Secure_DMA (same registers as the RTL, see docs/spec/SoC_Memory_Map.md):
//   0x00 SRC, 0x04 NBLK, 0x08 CTRL (bit0 START, bit1 SWAP, bit2 PAD, bit3 IRQ_EN),
//   0x0C STATUS (bit0 BUSY, bit1 DONE, bit2 ERR_FW, bit3 ERR_BUS, DONE and the errors are write-1-to-clear)
// A START write runs the whole transfer before it returns, by driving the SHA-256 model directly, so the
// CPU sees DONE on its first poll and the simulation clock still advances by the time the SHA-256 takes.
// The firewall is checked up front for the whole range: a source outside the App ROM window gives ERR_FW
// with nothing hashed (the RTL stops at the first word that leaves the window). No interrupt in the VP.
#include "VP_Peripherals.h"
#include "SHA256_VP_Wrapper.h"

SC_MODULE(DMA_VP) {
    tlm_utils::simple_target_socket<DMA_VP> target_socket;
    Memory_VP*         rom = nullptr;       // the App ROM, set by main
    SHA256_VP_Wrapper* sha = nullptr;       // the SHA-256 model, set by main

    static constexpr uint64_t ROM_BASE = 0x60000000;
    static constexpr uint64_t ROM_SIZE = 0x1000;

    uint32_t src = 0x60000000;
    uint32_t nblk = 64;
    bool     swap = false, pad = false, irq_en = false;
    bool     done = false, err_fw = false;

    SC_CTOR(DMA_VP) : target_socket("target_socket") {
        target_socket.register_b_transport(this, &DMA_VP::b_transport);
    }

    // One 32-bit access to the SHA-256 model. t carries the simulated time that has gone by
    uint32_t sha_access(bool write, uint64_t off, uint32_t value, sc_time& t) {
        tlm::tlm_generic_payload trans;
        uint32_t data = value;
        trans.set_command(write ? tlm::TLM_WRITE_COMMAND : tlm::TLM_READ_COMMAND);
        trans.set_address(off);
        trans.set_data_ptr(reinterpret_cast<unsigned char*>(&data));
        trans.set_data_length(4);
        trans.set_streaming_width(4);
        trans.set_byte_enable_ptr(nullptr);
        trans.set_response_status(tlm::TLM_INCOMPLETE_RESPONSE);
        sha->b_transport(trans, t);
        return data;
    }

    void hash_block(uint32_t ctrl, sc_time& t) {
        sha_access(true, 0x40, ctrl, t);
        while (!(sha_access(false, 0x44, 0, t) & 1)) {
        }
    }

    void run(sc_time& t) {
        done = false;
        err_fw = false;
        if (nblk == 0) {
            done = true;
            return;
        }
        if ((src & 3) || src < ROM_BASE || static_cast<uint64_t>(src) + static_cast<uint64_t>(nblk) * 64 > ROM_BASE + ROM_SIZE) {
            err_fw = true;
            done = true;
            return;
        }
        uint32_t off = src - ROM_BASE;
        for (uint32_t b = 0; b < nblk; b++) {
            for (int i = 0; i < 16; i++) {
                uint32_t w;
                std::memcpy(&w, &rom->mem[off], 4);
                off += 4;
                sha_access(true, 4 * i, swap ? __builtin_bswap32(w) : w, t);
            }
            hash_block(b == 0 ? 3 : 1, t);
        }
        if (pad) {
            for (int i = 0; i < 16; i++)
                sha_access(true, 4 * i, i == 0 ? 0x80000000u : i == 15 ? nblk << 9 : 0u, t);
            hash_block(1, t);
        }
        done = true;
    }

    void b_transport(tlm::tlm_generic_payload& trans, sc_time& delay) {
        uint64_t off = trans.get_address();
        uint32_t* p = reinterpret_cast<uint32_t*>(trans.get_data_ptr());
        if (trans.is_write()) {
            if (off == 0x00)
                src = *p;
            if (off == 0x04)
                nblk = *p;
            if (off == 0x08) {
                swap = (*p >> 1) & 1;
                pad = (*p >> 2) & 1;
                irq_en = (*p >> 3) & 1;
                if (*p & 1)
                    run(delay);
            }
            if (off == 0x0C) {
                if (*p & 2)
                    done = false;
                if (*p & 4)
                    err_fw = false;
            }
        } else {
            *p = off == 0x00 ? src : off == 0x04 ? nblk : off == 0x08 ? (irq_en << 3 | pad << 2 | swap << 1) :
                 off == 0x0C ? (err_fw << 2 | done << 1) : 0u;
        }
        delay += sc_time(120, SC_NS);
        trans.set_response_status(tlm::TLM_OK_RESPONSE);
    }
};

#endif
