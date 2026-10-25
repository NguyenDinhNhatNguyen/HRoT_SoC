// base_test builds the env and config, sets the drain time, guards against hangs and prints PASS/FAIL.
// By default it runs axi4_lite_smoke_seq (one write and one read back).
class base_test extends uvm_test;
    `uvm_component_utils(base_test)

    hrot_env            m_env;
    axi4_lite_agent_cfg m_axi_cfg;
    int unsigned        timeout_us;

    function new(string name = "base_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        m_axi_cfg = axi4_lite_agent_cfg::type_id::create("m_axi_cfg");
        if (!uvm_config_db#(virtual axi4_lite_if)::get(this, "", "vif", m_axi_cfg.vif))
            `uvm_fatal("NO_VIF", "virtual interface 'vif' not found in config_db")
        uvm_config_db#(axi4_lite_agent_cfg)::set(this, "m_env.*", "cfg", m_axi_cfg);
        m_env = hrot_env::type_id::create("m_env", this);
        timeout_us = compute_timeout_us();
    endfunction

    // Hang guard: default_timeout_us() plus 2 us per transaction (+NUM_TRANS),
    // overridden by +TEST_TIMEOUT_US=<n>.
    virtual function int unsigned default_timeout_us();
        return 1000;
    endfunction

    function int unsigned compute_timeout_us();
        int unsigned n_trans = 0;
        int unsigned tmo     = default_timeout_us();
        if ($value$plusargs("NUM_TRANS=%d", n_trans))
            tmo = tmo + 2 * n_trans;
        void'($value$plusargs("TEST_TIMEOUT_US=%d", tmo));
        return tmo;
    endfunction

    function void end_of_elaboration_phase(uvm_phase phase);
        super.end_of_elaboration_phase(phase);
        uvm_top.print_topology();
    endfunction

    task run_phase(uvm_phase phase);
        phase.raise_objection(this, "stimulus");
        // Let the monitor and scoreboard finish (get_objection works on UVM 1.1d, 1.2 and IEEE 1800.2)
        phase.get_objection().set_drain_time(this, 100ns);
        // The watchdog delay is written in this package, so it follows this package's timescale.
        // uvm_top.set_timeout() reads its argument in uvm_pkg's time unit instead, which on Questa
        // (vsim -t 1ps) made a 1600 us limit fire after 1.6 us (P-22).
        fork
            begin
                #(real'(timeout_us) * 1us);
                `uvm_fatal("TEST_TIMEOUT", $sformatf("test still running after %0d us (+TEST_TIMEOUT_US to change)",
                                                     timeout_us))
            end
        join_none
        `uvm_info("TEST", $sformatf("Starting AXI4-Lite stimulus (timeout %0d us)", timeout_us), UVM_LOW)
        run_stimulus();
        phase.drop_objection(this, "stimulus");
    endtask

    // Child tests override this task to change the scenario
    virtual task run_stimulus();
        axi4_lite_smoke_seq seq = axi4_lite_smoke_seq::type_id::create("seq");
        seq.start(m_env.m_axi_agent.m_sequencer);
    endtask

    // SVA failures use $error and never reach the UVM counters, so read the interface counter here
    function void check_phase(uvm_phase phase);
        super.check_phase(phase);
        if (m_axi_cfg.vif.assert_fail_count != 0)
            `uvm_error("SVA", $sformatf("%0d AXI4-Lite protocol assertions failed (see the simulator $error log)",
                                        m_axi_cfg.vif.assert_fail_count))
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


class axi4_lite_wstrb_test extends base_test;
    `uvm_component_utils(axi4_lite_wstrb_test)

    function new(string name = "axi4_lite_wstrb_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual task run_stimulus();
        axi4_lite_wstrb_seq seq = axi4_lite_wstrb_seq::type_id::create("seq");
        seq.start(m_env.m_axi_agent.m_sequencer);
    endtask
endclass


// +NUM_TRANS=<n> sets the number of random transactions (default 200)
class axi4_lite_rand_test extends base_test;
    `uvm_component_utils(axi4_lite_rand_test)

    function new(string name = "axi4_lite_rand_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual task run_stimulus();
        axi4_lite_rand_seq seq = axi4_lite_rand_seq::type_id::create("seq");
        int unsigned n;
        seq.num_trans = 200;
        if ($value$plusargs("NUM_TRANS=%d", n))
            seq.num_trans = n;
        seq.start(m_env.m_axi_agent.m_sequencer);
    endtask
endclass


// Runs smoke, then wstrb, then random
class axi4_lite_full_test extends base_test;
    `uvm_component_utils(axi4_lite_full_test)

    function new(string name = "axi4_lite_full_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual task run_stimulus();
        axi4_lite_smoke_seq smoke = axi4_lite_smoke_seq::type_id::create("smoke");
        axi4_lite_wstrb_seq wstrb = axi4_lite_wstrb_seq::type_id::create("wstrb");
        axi4_lite_rand_seq  rnd   = axi4_lite_rand_seq::type_id::create("rnd");
        int unsigned n;
        rnd.num_trans = 200;
        if ($value$plusargs("NUM_TRANS=%d", n))
            rnd.num_trans = n;
        smoke.start(m_env.m_axi_agent.m_sequencer);
        wstrb.start(m_env.m_axi_agent.m_sequencer);
        rnd.start(m_env.m_axi_agent.m_sequencer);
    endtask
endclass
