// APB4 master agent (P-17), same structure and reset handling as the AXI4-Lite agent.
// One agent per APB bus, each with its own apb_if, found in config_db under the agent's cfg.
class apb_agent extends uvm_agent;
    `uvm_component_utils(apb_agent)

    apb_agent_cfg                 cfg;
    apb_sequencer                 m_sequencer;
    apb_driver                    m_driver;
    apb_monitor                   m_monitor;
    uvm_analysis_port #(apb_item) ap;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(apb_agent_cfg)::get(this, "", "cfg", cfg))
            `uvm_fatal("NO_CFG", "apb_agent: cfg not found in config_db")
        if (cfg.vif == null)
            `uvm_fatal("NO_VIF", "apb_agent_cfg.vif is not set")
        is_active = cfg.is_active;
        m_monitor     = apb_monitor::type_id::create("m_monitor", this);
        m_monitor.cfg = cfg;
        if (is_active == UVM_ACTIVE) begin
            m_sequencer  = apb_sequencer::type_id::create("m_sequencer", this);
            m_driver     = apb_driver::type_id::create("m_driver", this);
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
