// base_test : dựng env, cấu hình, drain time, tổng kết PASS/FAIL.
//             Mặc định chạy axi4_lite_smoke_seq (1 ghi + 1 đọc).
class base_test extends uvm_test;
  `uvm_component_utils(base_test)

  hrot_env            m_env;
  axi4_lite_agent_cfg m_axi_cfg;

  function new(string name = "base_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    m_axi_cfg = axi4_lite_agent_cfg::type_id::create("m_axi_cfg");
    if (!uvm_config_db#(virtual axi4_lite_if)::get(this, "", "vif", m_axi_cfg.vif))
      `uvm_fatal("NO_VIF", "Khong tim thay virtual interface 'vif' trong config_db")
    uvm_config_db#(axi4_lite_agent_cfg)::set(this, "m_env.*", "cfg", m_axi_cfg);
    m_env = hrot_env::type_id::create("m_env", this);
    set_global_timeout();
  endfunction

  // Chốt chặn toàn cục chống treo. Mặc định default_timeout_us() + 2 us cho mỗi giao dịch (+NUM_TRANS);
  // ghi đè bằng +TEST_TIMEOUT_US=<n>. Phải đặt trước run_phase nên làm ở build_phase.
  virtual function int unsigned default_timeout_us();
    return 1000;
  endfunction

  function void set_global_timeout();
    int unsigned n_trans = 0;
    int unsigned tmo_us  = default_timeout_us();
    time         tmo;
    if ($value$plusargs("NUM_TRANS=%d", n_trans)) tmo_us = tmo_us + 2 * n_trans;
    void'($value$plusargs("TEST_TIMEOUT_US=%d", tmo_us));
    tmo = time'(real'(tmo_us) * 1us);
    uvm_top.set_timeout(tmo, 0);
  endfunction

  function void end_of_elaboration_phase(uvm_phase phase);
    super.end_of_elaboration_phase(phase);
    uvm_top.print_topology();
  endfunction

  task run_phase(uvm_phase phase);
    phase.raise_objection(this, "stimulus");
    // chờ monitor/scoreboard xử lý xong (get_objection: chạy được cả UVM 1.2 và IEEE 1800.2,
    // phase_done đã bị bỏ trong 1800.2)
    phase.get_objection().set_drain_time(this, 100ns);
    `uvm_info("TEST", "Bat dau kich thich AXI4-Lite", UVM_LOW)
    run_stimulus();
    phase.drop_objection(this, "stimulus");
  endtask

  // Test con ghi đè hàm này để đổi kịch bản
  virtual task run_stimulus();
    axi4_lite_smoke_seq seq = axi4_lite_smoke_seq::type_id::create("seq");
    seq.start(m_env.m_axi_agent.m_sequencer);
  endtask

  // SVA dùng $error nên không vào bộ đếm của UVM: đọc bộ đếm riêng của interface
  function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    if (m_axi_cfg.vif.assert_fail_count != 0)
      `uvm_error("SVA", $sformatf("%0d assertion giao thuc AXI4-Lite that bai (xem log $error cua simulator)",
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


// +NUM_TRANS=<n> để đổi số giao dịch ngẫu nhiên (mặc định 200)
class axi4_lite_rand_test extends base_test;
  `uvm_component_utils(axi4_lite_rand_test)
  function new(string name = "axi4_lite_rand_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction
  virtual task run_stimulus();
    axi4_lite_rand_seq seq = axi4_lite_rand_seq::type_id::create("seq");
    int unsigned n;
    seq.num_trans = 200;
    if ($value$plusargs("NUM_TRANS=%d", n)) seq.num_trans = n;
    seq.start(m_env.m_axi_agent.m_sequencer);
  endtask
endclass


// Chạy lần lượt: smoke -> wstrb -> ngẫu nhiên
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
    if ($value$plusargs("NUM_TRANS=%d", n)) rnd.num_trans = n;
    smoke.start(m_env.m_axi_agent.m_sequencer);
    wstrb.start(m_env.m_axi_agent.m_sequencer);
    rnd.start (m_env.m_axi_agent.m_sequencer);
  endtask
endclass
