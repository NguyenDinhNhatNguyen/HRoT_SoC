class hrot_env extends uvm_env;
    `uvm_component_utils(hrot_env)

    axi4_lite_agent      m_axi_agent;
    axi4_lite_scoreboard m_scoreboard;      // memory model: only when the DUT is a memory (the model slave)
    bit                  has_mem_scoreboard = 1;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        void'(uvm_config_db#(bit)::get(this, "", "has_mem_scoreboard", has_mem_scoreboard));
        m_axi_agent = axi4_lite_agent::type_id::create("m_axi_agent", this);
        if (has_mem_scoreboard)
            m_scoreboard = axi4_lite_scoreboard::type_id::create("m_scoreboard", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        if (has_mem_scoreboard)
            m_axi_agent.ap.connect(m_scoreboard.item_export);
    endfunction
endclass
