#ifndef SHA256_VP_WRAPPER_H
#define SHA256_VP_WRAPPER_H

#include <systemc.h>
#include <tlm.h>
#include <tlm_utils/simple_target_socket.h>

#include <cstdint> 

SC_MODULE(SHA256_VP_Wrapper) {
    tlm_utils::simple_target_socket<SHA256_VP_Wrapper> target_socket;
    uint32_t hash_status; // Thanh ghi giả lập trạng thái Done

    SC_CTOR(SHA256_VP_Wrapper) : target_socket("target_socket") {
        target_socket.register_b_transport(this, &SHA256_VP_Wrapper::b_transport);
        hash_status = 0;
    }

    void b_transport(tlm::tlm_generic_payload& trans, sc_time& delay) {
        tlm::tlm_command cmd = trans.get_command();
        uint64_t addr = trans.get_address();
        unsigned char* ptr = trans.get_data_ptr();

        if (cmd == tlm::TLM_WRITE_COMMAND && addr == 0x50000040) { // Địa chỉ Start SHA
            hash_status = 1; 
        } else if (cmd == tlm::TLM_READ_COMMAND && addr == 0x50000044) { // Địa chỉ READ Status
            memcpy(ptr, &hash_status, 4);
        }
        trans.set_response_status(tlm::TLM_OK_RESPONSE);
    }
};
#endif