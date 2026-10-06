#ifndef CPU_DUMMY_INITIATOR_H
#define CPU_DUMMY_INITIATOR_H

#include <systemc.h>
#include <tlm.h>
#include <tlm_utils/simple_initiator_socket.h>

#include <cstdint> 

SC_MODULE(CPU_Dummy_Initiator) {
    tlm_utils::simple_initiator_socket<CPU_Dummy_Initiator> initiator_socket;

    SC_CTOR(CPU_Dummy_Initiator) : initiator_socket("initiator_socket") {
        SC_THREAD(run_secure_boot_sequence);
    }

    void run_secure_boot_sequence() {
        tlm::tlm_generic_payload trans;
        sc_time delay = sc_time(10, SC_NS);
        uint32_t unlock_code = 0x00000001;

        // Giả lập CPU ghi vào địa chỉ của Reset Controller (vd: 0x40000000)
        trans.set_command(tlm::TLM_WRITE_COMMAND);
        trans.set_address(0x40000000);
        trans.set_data_ptr(reinterpret_cast<unsigned char*>(&unlock_code));
        trans.set_data_length(4);
        trans.set_response_status(tlm::TLM_INCOMPLETE_RESPONSE);

        initiator_socket->b_transport(trans, delay);
        wait(delay);
    }
};
#endif