// UVM tests for SHA256_Wrapper (P-08). Run with the top dv/env/tb_sha256_top.sv:
//   vsim -c -do "set DUT sha256; set TEST sha256_full_test; do run_uvm.do"
// sha256_kat_test | sha256_ctl_test | sha256_rand_test (+NUM_MSGS=<n>) | sha256_reg_test | sha256_full_test
// sha256_alias_test: offsets >= 0x100 read 0 and do not alias (passes since RTL fix a968cce)
// Reset in the middle: sha256_rand_test +RESET_AT_NS=<t>

class sha256_base_test extends base_test;
    `uvm_component_utils(sha256_base_test)

    function new(string name = "sha256_base_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        // SHA registers are not a memory: no memory scoreboard. The sequences self-check, and the
        // passive DPI scoreboard (P-17) predicts every read on its own
        uvm_config_db#(bit)::set(this, "m_env", "has_mem_scoreboard", 1'b0);
        uvm_config_db#(bit)::set(this, "m_env", "has_sha_scoreboard", 1'b1);
        super.build_phase(phase);
    endfunction

    virtual function int unsigned default_timeout_us();
        return 5000;
    endfunction

    virtual task run_stimulus();
        sha256_kat_seq seq = sha256_kat_seq::type_id::create("kat");
        seq.start(m_env.m_axi_agent.m_sequencer);
    endtask
endclass


class sha256_kat_test extends sha256_base_test;
    `uvm_component_utils(sha256_kat_test)
    function new(string name = "sha256_kat_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
endclass


class sha256_ctl_test extends sha256_base_test;
    `uvm_component_utils(sha256_ctl_test)
    function new(string name = "sha256_ctl_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    virtual task run_stimulus();
        sha256_ctl_seq seq = sha256_ctl_seq::type_id::create("ctl");
        seq.start(m_env.m_axi_agent.m_sequencer);
    endtask
endclass


// +NUM_MSGS=<n> (default 40), +MAX_LEN=<bytes> (default 600)
class sha256_rand_test extends sha256_base_test;
    `uvm_component_utils(sha256_rand_test)
    function new(string name = "sha256_rand_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    virtual task run_stimulus();
        sha256_rand_seq seq = sha256_rand_seq::type_id::create("rnd");
        void'($value$plusargs("NUM_MSGS=%d", seq.num_msgs));
        void'($value$plusargs("MAX_LEN=%d", seq.max_len));
        seq.start(m_env.m_axi_agent.m_sequencer);
    endtask
endclass


// Register corner cases after reset: map reset values, CTRL without START, WSTRB, late poll (P-19)
class sha256_reg_test extends sha256_base_test;
    `uvm_component_utils(sha256_reg_test)
    function new(string name = "sha256_reg_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    virtual task run_stimulus();
        sha256_reg_seq seq = sha256_reg_seq::type_id::create("reg");
        seq.start(m_env.m_axi_agent.m_sequencer);
    endtask
endclass


// Register corner cases (must come first, while IDLE) -> KAT -> control corner cases -> random messages
// (used by make test)
class sha256_full_test extends sha256_base_test;
    `uvm_component_utils(sha256_full_test)
    function new(string name = "sha256_full_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    virtual task run_stimulus();
        sha256_reg_seq  rg  = sha256_reg_seq::type_id::create("reg");
        sha256_kat_seq  kat = sha256_kat_seq::type_id::create("kat");
        sha256_ctl_seq  ctl = sha256_ctl_seq::type_id::create("ctl");
        sha256_rand_seq rnd = sha256_rand_seq::type_id::create("rnd");
        void'($value$plusargs("NUM_MSGS=%d", rnd.num_msgs));
        void'($value$plusargs("MAX_LEN=%d", rnd.max_len));
        rg.start(m_env.m_axi_agent.m_sequencer);
        kat.start(m_env.m_axi_agent.m_sequencer);
        ctl.start(m_env.m_axi_agent.m_sequencer);
        rnd.start(m_env.m_axi_agent.m_sequencer);
    endtask
endclass


class sha256_alias_test extends sha256_base_test;
    `uvm_component_utils(sha256_alias_test)
    function new(string name = "sha256_alias_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    virtual task run_stimulus();
        sha256_alias_seq seq = sha256_alias_seq::type_id::create("alias");
        seq.start(m_env.m_axi_agent.m_sequencer);
    endtask
endclass
