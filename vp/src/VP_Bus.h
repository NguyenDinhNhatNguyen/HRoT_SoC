#ifndef VP_BUS_H
#define VP_BUS_H

// Loosely-timed TLM-2.0 bus: 1 initiator to N targets, decoded by address the same way as SoC_Top.
// An address that hits no target gets TLM_ADDRESS_ERROR_RESPONSE (DECERR on the RTL).
#include <systemc.h>
#include <tlm.h>
#include <tlm_utils/simple_initiator_socket.h>
#include <tlm_utils/simple_target_socket.h>
#include <cstdint>
#include <vector>

SC_MODULE(VP_Bus) {
    tlm_utils::simple_target_socket<VP_Bus> target_socket;

    struct Region {
        uint64_t base, size;
        tlm_utils::simple_initiator_socket<VP_Bus>* socket;
    };
    std::vector<Region> regions;

    struct RegionCfg { const char* name; uint64_t base, size; };

    // SystemC sockets must be created in the constructor, so the region list comes in here
    VP_Bus(sc_module_name n, const std::vector<RegionCfg>& cfg) : sc_module(n), target_socket("target_socket") {
        target_socket.register_b_transport(this, &VP_Bus::b_transport);
        for (const auto& c : cfg)
            regions.push_back({c.base, c.size, new tlm_utils::simple_initiator_socket<VP_Bus>(c.name)});
    }

    // Socket to target i (in cfg order). The target sees the address with its base removed
    tlm_utils::simple_initiator_socket<VP_Bus>& port(size_t i) { return *regions[i].socket; }

    void b_transport(tlm::tlm_generic_payload& trans, sc_time& delay) {
        uint64_t addr = trans.get_address();
        for (auto& r : regions) {
            if (addr >= r.base && addr < r.base + r.size) {
                trans.set_address(addr - r.base);
                (*r.socket)->b_transport(trans, delay);
                trans.set_address(addr);
                return;
            }
        }
        trans.set_response_status(tlm::TLM_ADDRESS_ERROR_RESPONSE);
    }
};

#endif
