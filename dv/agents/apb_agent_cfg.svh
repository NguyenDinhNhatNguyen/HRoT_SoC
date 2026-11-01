// Configuration shared by the APB agent, driver and monitor (P-17)
class apb_agent_cfg extends uvm_object;
    `uvm_object_utils(apb_agent_cfg)

    virtual apb_if          vif;
    uvm_active_passive_enum is_active      = UVM_ACTIVE;
    int unsigned            timeout_cycles = 200;   // max wait states per transfer
    string                  bus_name       = "apb"; // "secure" or "app" in tb_apb_top, used by the scoreboard

    function new(string name = "apb_agent_cfg");
        super.new(name);
    endfunction
endclass
