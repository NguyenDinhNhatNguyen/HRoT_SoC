#include <systemc.h>
#include "CPU_Dummy_Initiator.h"
#include "SHA256_VP_Wrapper.h"

int sc_main(int argc, char* argv[]) {
    CPU_Dummy_Initiator cpu("cpu");
    SHA256_VP_Wrapper   sha("sha");

    cpu.initiator_socket.bind(sha.target_socket);

    sc_start();
    return 0;
}
