// Env of tb_apb_top (P-17): one APB agent per bus and the register predictor
class apb_env extends uvm_env;
    `uvm_component_utils(apb_env)

    apb_agent      m_secure;
    apb_agent      m_app;
    apb_scoreboard m_scoreboard;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        m_secure     = apb_agent::type_id::create("m_secure", this);
        m_app        = apb_agent::type_id::create("m_app", this);
        m_scoreboard = apb_scoreboard::type_id::create("m_scoreboard", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        m_secure.ap.connect(m_scoreboard.secure_export);
        m_app.ap.connect(m_scoreboard.app_export);
    endfunction
endclass
