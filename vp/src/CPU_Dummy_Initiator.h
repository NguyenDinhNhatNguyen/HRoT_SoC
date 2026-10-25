#ifndef CPU_DUMMY_INITIATOR_H
#define CPU_DUMMY_INITIATOR_H

// Stand-in Secure-world CPU that runs the firmware's real SHA-256 HAL (fw/hal, -DHAL_HOST_MODEL).
// Every HAL register access becomes one TLM transaction on VP_Bus (hal_host_* hooks in main.cpp).
// Secure boot flow: read CHIP_ID, read the golden hash from the Boot ROM, run the WDT, hash the App ROM
// (0x6000_0000), compare, then release the App or lock it out with Boot Guard. Progress goes out on UART0.
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
    const uint64_t BOOT_ROM = 0x00000000;
    const uint64_t SYSCSR   = 0x40000000;
    const uint64_t UART0    = 0x40001000;
    const uint64_t TIMER0   = 0x40003000;
    const uint64_t WDT      = 0x40004000;
    const uint64_t DMA      = 0x40007000;
    const uint64_t SHA256   = 0x50000000;
    const uint64_t APP_ROM  = 0x60000000;
    const uint64_t GOLDEN   = 0x600;       // offset of the golden hash in the Boot ROM (same as dv/sw/mkhex.py)
}

SC_MODULE(CPU_Dummy_Initiator) {
    tlm_utils::simple_initiator_socket<CPU_Dummy_Initiator> initiator_socket;

    uint32_t app_len = 0;          // App image size to hash, in bytes
    uint8_t  golden[32]{};         // golden hash, read back from the Boot ROM over the bus
    bool     boot_ok = false;
    bool     dma_match = false;    // the Secure DMA's digest equals the golden hash
    bool     fw_ok = false;        // the DMA firewall refused a source outside the App ROM
    int      bus_errors = 0;

    SC_CTOR(CPU_Dummy_Initiator) : initiator_socket("initiator_socket") {
        SC_THREAD(run_secure_boot_sequence);
    }

    // 32-bit transactions. The delay is accumulated and waited right away (loosely timed, no quantum keeper)
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
            std::printf("[%s] Bus error at 0x%08llx (%s)\n", sc_time_stamp().to_string().c_str(),
                        (unsigned long long)addr, trans.get_response_string().c_str());
        }
        wait(delay);
        return data;
    }
    uint32_t rd(uint64_t a)             { return access(false, a, 0); }
    void     wr(uint64_t a, uint32_t v) { access(true, a, v); }

    void uart_puts(const char* s) {
        while (*s)
            wr(vp_map::UART0, static_cast<uint8_t>(*s++));
    }

    uint64_t mtime() {
        uint64_t lo = rd(vp_map::TIMER0);
        uint64_t hi = rd(vp_map::TIMER0 + 4);
        return (hi << 32) | lo;
    }

    void run_secure_boot_sequence() {
        uart_puts("HRoT secure boot\n");
        std::printf("[%s] Secure CPU: starting secure boot\n", sc_time_stamp().to_string().c_str());
        uint32_t id = rd(vp_map::SYSCSR + 0x04);
        std::printf("  CHIP_ID = 0x%08x %s\n", id, id == 0x48524F54u ? "(HROT)" : "(unexpected)");

        for (int i = 0; i < 8; i++) {
            uint32_t w = rd(vp_map::BOOT_ROM + vp_map::GOLDEN + 4 * i);
            std::memcpy(golden + 4 * i, &w, 4);
        }

        wr(vp_map::WDT + 0x04, 50000000);          // 1 s at 50 MHz
        wr(vp_map::WDT + 0x00, 1);
        uint64_t t0 = mtime();
        uint8_t digest[32];
        sha256_status_t st = sha256_digest_mem(vp_map::APP_ROM, app_len, digest);
        std::printf("  sha256_digest_mem(0x60000000, %u bytes) -> status %d\n  hash   = ", app_len, (int)st);
        for (int i = 0; i < 32; i++)
            std::printf("%02x", digest[i]);
        std::printf("\n  golden = ");
        for (int i = 0; i < 32; i++)
            std::printf("%02x", golden[i]);
        std::printf("\n");

        wr(vp_map::WDT + 0x0C, 0x5A5A0002);        // kick: the hash is done

        // Secure DMA: the same hash without the CPU moving a word (SWAP gives the little-endian image hash)
        wr(vp_map::DMA + 0x00, vp_map::APP_ROM);
        wr(vp_map::DMA + 0x04, 64);
        wr(vp_map::DMA + 0x08, 0x7);               // START | SWAP | PAD
        while (!(rd(vp_map::DMA + 0x0C) & 2)) {
        }
        uint8_t dma_digest[32];
        for (int i = 0; i < 8; i++) {
            uint32_t w = rd(vp_map::SHA256 + 0x50 + 4 * i);
            for (int b = 0; b < 4; b++)
                dma_digest[4 * i + b] = static_cast<uint8_t>(w >> (24 - 8 * b));
        }
        dma_match = sha256_compare(dma_digest, golden, 32) == 0;
        wr(vp_map::DMA + 0x0C, 0x2);               // clear DONE
        // Firewall: a source outside the App ROM must be refused
        wr(vp_map::DMA + 0x00, vp_map::BOOT_ROM);
        wr(vp_map::DMA + 0x04, 1);
        wr(vp_map::DMA + 0x08, 0x1);
        fw_ok = (rd(vp_map::DMA + 0x0C) & 6) == 6;
        wr(vp_map::DMA + 0x0C, 0xE);
        std::printf("  Secure DMA digest %s the golden hash, firewall %s\n", dma_match ? "matches" : "differs from",
                    fw_ok ? "blocked the bad source" : "FAILED to block");
        std::printf("  hashing took %llu timer ticks, WDT COUNT = %u\n", static_cast<unsigned long long>(mtime() - t0),
                    rd(vp_map::WDT + 0x08));

        boot_ok = (st == SHA256_OK) && sha256_compare(digest, golden, 32) == 0;
        if (boot_ok) {
            wr(vp_map::SYSCSR + 0x00, 1);       // APP_CTRL.APP_RUN = 1
            uart_puts("App released\n");
        } else {
            std::printf("  Hash mismatch, locking the App Core out\n");
            uart_puts("Hash mismatch, App locked out\n");
            wr(vp_map::SYSCSR + 0x20, 1);       // Boot Guard LOCK
            wr(vp_map::SYSCSR + 0x00, 1);       // an attacker's release attempt: must have no effect
        }
        wr(vp_map::APP_ROM, 0xDEADBEEF);       // try writing the ROM: must be rejected
        sc_stop();
    }
};

#endif
