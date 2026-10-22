class axi4_lite_agent extends uvm_agent;
  `uvm_component_utils(axi4_lite_agent)

  axi4_lite_agent_cfg                 cfg;
  axi4_lite_sequencer                 m_sequencer;
  axi4_lite_driver                    m_driver;
  axi4_lite_monitor                   m_monitor;
  uvm_analysis_port #(axi4_lite_item) ap;     // chuyển tiếp ap của monitor

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(axi4_lite_agent_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("NO_CFG", "axi4_lite_agent: khong tim thay cfg trong config_db")
    if (cfg.vif == null)
      `uvm_fatal("NO_VIF", "axi4_lite_agent_cfg.vif chua duoc gan")
    is_active = cfg.is_active;

    m_monitor     = axi4_lite_monitor::type_id::create("m_monitor", this);
    m_monitor.cfg = cfg;
    if (is_active == UVM_ACTIVE) begin
      m_sequencer  = axi4_lite_sequencer::type_id::create("m_sequencer", this);
      m_driver     = axi4_lite_driver::type_id::create("m_driver", this);
      m_driver.cfg = cfg;
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    ap = m_monitor.ap;
    if (is_active == UVM_ACTIVE)
      m_driver.seq_item_port.connect(m_sequencer.seq_item_export);
  endfunction
endclass