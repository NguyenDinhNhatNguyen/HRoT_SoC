// UVM tests for the APB peripherals (P-17). Top dv/env/tb_apb_top.sv:
//   vsim -c -do "set DUT apb; set TEST apb_full_test; do run_uvm.do"
// apb_reg_test: reset values, then random transfers on both buses at the same time (+NUM_TRANS=<n>, default 300)
// apb_periph_test: directed pin checks (GPIO in/out and irq, TIMER irq, Mailbox irq both ways)
// apb_full_test: reset values -> random -> directed (used by make test)
// +APB_MAX_WAIT=<n>: wait states of the RAM model (default 3), +RESET_AT_NS=<t>: reset in the middle

class apb_base_test extends uvm_test;
    `uvm_component_utils(apb_base_test)

    apb_env       m_env;
    apb_agent_cfg m_s_cfg;
    apb_agent_cfg m_a_cfg;
    int unsigned  timeout_us = 2000;
    int unsigned  num_trans  = 300;

    function new(string name = "apb_base_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        m_s_cfg = apb_agent_cfg::type_id::create("m_s_cfg");
        m_a_cfg = apb_agent_cfg::type_id::create("m_a_cfg");
        if (!uvm_config_db#(virtual apb_if)::get(this, "", "s_vif", m_s_cfg.vif))
            `uvm_fatal("NO_VIF", "s_vif not found in config_db")
        if (!uvm_config_db#(virtual apb_if)::get(this, "", "a_vif", m_a_cfg.vif))
            `uvm_fatal("NO_VIF", "a_vif not found in config_db")
        m_s_cfg.bus_name = "secure";
        m_a_cfg.bus_name = "app";
        uvm_config_db#(apb_agent_cfg)::set(this, "m_env.m_secure*", "cfg", m_s_cfg);
        uvm_config_db#(apb_agent_cfg)::set(this, "m_env.m_app*", "cfg", m_a_cfg);
        m_env = apb_env::type_id::create("m_env", this);
        void'($value$plusargs("NUM_TRANS=%d", num_trans));
        timeout_us = timeout_us + num_trans / 10;
        void'($value$plusargs("TEST_TIMEOUT_US=%d", timeout_us));
    endfunction

    function void end_of_elaboration_phase(uvm_phase phase);
        super.end_of_elaboration_phase(phase);
        uvm_top.print_topology();
    endfunction

    // Same hang guard as base_test (the delay is written in this package's timescale, see P-22)
    task run_phase(uvm_phase phase);
        phase.raise_objection(this, "stimulus");
        phase.get_objection().set_drain_time(this, 100ns);
        fork
            begin
                #(real'(timeout_us) * 1us);
                `uvm_fatal("TEST_TIMEOUT", $sformatf("test still running after %0d us (+TEST_TIMEOUT_US to change)",
                                                     timeout_us))
            end
        join_none
        `uvm_info("TEST", $sformatf("Starting APB stimulus (timeout %0d us)", timeout_us), UVM_LOW)
        run_stimulus();
        phase.drop_objection(this, "stimulus");
    endtask

    virtual task run_stimulus();
        apb_reset_seq seq = apb_reset_seq::type_id::create("reset");
        seq.start(m_env.m_secure.m_sequencer);
    endtask

    task run_reset_values();
        apb_reset_seq seq = apb_reset_seq::type_id::create("reset");
        seq.app_sqr = m_env.m_app.m_sequencer;
        seq.start(m_env.m_secure.m_sequencer);
    endtask

    task run_random();
        apb_rand_seq s = apb_rand_seq::type_id::create("rand_secure");
        apb_rand_seq a = apb_rand_seq::type_id::create("rand_app");
        s.num_trans = num_trans;
        a.num_trans = num_trans;
        a.app       = 1'b1;
        fork
            s.start(m_env.m_secure.m_sequencer);
            a.start(m_env.m_app.m_sequencer);
        join
    endtask

    task run_directed();
        apb_periph_seq seq = apb_periph_seq::type_id::create("periph");
        seq.app_sqr = m_env.m_app.m_sequencer;
        seq.start(m_env.m_secure.m_sequencer);
    endtask

    function void check_phase(uvm_phase phase);
        super.check_phase(phase);
        if (m_s_cfg.vif.assert_fail_count + m_a_cfg.vif.assert_fail_count != 0)
            `uvm_error("SVA", $sformatf("%0d APB protocol assertions failed (see the simulator $error log)",
                                        m_s_cfg.vif.assert_fail_count + m_a_cfg.vif.assert_fail_count))
    endfunction

    function void report_phase(uvm_phase phase);
        uvm_report_server svr = uvm_report_server::get_server();
        super.report_phase(phase);
        if (svr.get_severity_count(UVM_ERROR) + svr.get_severity_count(UVM_FATAL) == 0)
            `uvm_info("TEST", "*** TEST PASSED ***", UVM_NONE)
        else
            `uvm_info("TEST", "*** TEST FAILED ***", UVM_NONE)
    endfunction
endclass


class apb_reg_test extends apb_base_test;
    `uvm_component_utils(apb_reg_test)
    function new(string name = "apb_reg_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    virtual task run_stimulus();
        run_reset_values();
        run_random();
    endtask
endclass


class apb_periph_test extends apb_base_test;
    `uvm_component_utils(apb_periph_test)
    function new(string name = "apb_periph_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    virtual task run_stimulus();
        run_directed();
    endtask
endclass


class apb_full_test extends apb_base_test;
    `uvm_component_utils(apb_full_test)
    function new(string name = "apb_full_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    virtual task run_stimulus();
        run_reset_values();
        run_random();
        run_directed();
    endtask
endclass
