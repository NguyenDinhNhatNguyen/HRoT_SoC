// Passive monitor: one item per completed transfer (PSEL && PENABLE && PREADY on a clock edge)
class apb_monitor extends uvm_monitor;
    `uvm_component_utils(apb_monitor)

    apb_agent_cfg                 cfg;
    virtual apb_if                vif;
    uvm_analysis_port #(apb_item) ap;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (cfg == null)
            `uvm_fatal("NO_CFG", "apb_monitor: cfg is not set")
        ap = new("ap", this);
    endfunction

    task run_phase(uvm_phase phase);
        apb_item     t;
        int unsigned waits = 0;
        vif = cfg.vif;
        forever begin
            @(vif.mon_cb);
            if (vif.mon_cb.rst_n !== 1'b1) begin
                waits = 0;
                continue;
            end
            if (!(vif.mon_cb.psel && vif.mon_cb.penable))
                continue;
            if (vif.mon_cb.pready !== 1'b1) begin
                waits++;
                continue;
            end
            t           = apb_item::type_id::create("mon");
            t.is_write  = vif.mon_cb.pwrite;
            t.addr      = vif.mon_cb.paddr;
            t.data      = vif.mon_cb.pwdata;
            t.strb      = vif.mon_cb.pstrb;
            t.rdata     = vif.mon_cb.prdata;
            t.slverr    = vif.mon_cb.pslverr;
            t.waits     = waits;
            t.done_time = $time;
            t.bus       = cfg.bus_name;
            waits       = 0;
            `uvm_info("APB_MON", t.convert2string(), UVM_HIGH)
            ap.write(t);
        end
    endtask
endclass
