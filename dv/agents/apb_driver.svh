// Master driver: idle cycles, setup phase (PSEL), access phase (PENABLE) until PREADY.
// Back-to-back transfers go straight from one access phase to the next setup phase.
class apb_driver extends uvm_driver #(apb_item);
    `uvm_component_utils(apb_driver)

    apb_agent_cfg  cfg;
    virtual apb_if vif;
    bit            in_flight;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (cfg == null)
            `uvm_fatal("NO_CFG", "apb_driver: cfg is not set")
    endfunction

    task run_phase(uvm_phase phase);
        vif = cfg.vif;
        forever begin
            drive_idle();
            wait (vif.rst_n === 1'b1);
            @(vif.drv_cb);
            fork
                drive_items();
                @(negedge vif.rst_n);
            join_any
            disable fork;
            if (in_flight) begin
                req.aborted = 1'b1;
                `uvm_info("APB_DRV", {"Reset mid-transfer, aborted: ", req.convert2string()}, UVM_LOW)
                seq_item_port.item_done();
                in_flight = 1'b0;
            end
        end
    endtask

    task drive_idle();
        vif.drv_cb.psel    <= 1'b0;
        vif.drv_cb.penable <= 1'b0;
        vif.drv_cb.pwrite  <= 1'b0;
        vif.drv_cb.paddr   <= '0;
        vif.drv_cb.pwdata  <= '0;
        vif.drv_cb.pstrb   <= '0;
    endtask

    task drive_items();
        forever begin
            seq_item_port.try_next_item(req);
            if (req == null) begin
                vif.drv_cb.psel    <= 1'b0;
                vif.drv_cb.penable <= 1'b0;
                @(vif.drv_cb);
                continue;
            end
            in_flight = 1'b1;
            do_transfer(req);
            `uvm_info("APB_DRV", req.convert2string(), UVM_HIGH)
            seq_item_port.item_done();
            in_flight = 1'b0;
        end
    endtask

    task do_transfer(apb_item t);
        int unsigned n = 0;
        if (t.idle != 0) begin
            vif.drv_cb.psel    <= 1'b0;
            vif.drv_cb.penable <= 1'b0;
            repeat (t.idle) @(vif.drv_cb);
        end
        // setup phase
        vif.drv_cb.psel    <= 1'b1;
        vif.drv_cb.penable <= 1'b0;
        vif.drv_cb.paddr   <= t.addr;
        vif.drv_cb.pwrite  <= t.is_write;
        vif.drv_cb.pwdata  <= t.is_write ? t.data : 32'h0;
        vif.drv_cb.pstrb   <= t.is_write ? t.strb : 4'h0;
        @(vif.drv_cb);
        // access phase until PREADY
        vif.drv_cb.penable <= 1'b1;
        do begin
            @(vif.drv_cb);
            n++;
            if (n > cfg.timeout_cycles)
                `uvm_fatal("APB_DRV_TMO", $sformatf("no PREADY after %0d cycles: %s", cfg.timeout_cycles,
                                                    t.convert2string()))
        end while (vif.drv_cb.pready !== 1'b1);
        t.rdata  = vif.drv_cb.prdata;
        t.slverr = vif.drv_cb.pslverr;
        vif.drv_cb.penable <= 1'b0;
        vif.drv_cb.psel    <= 1'b0;
    endtask
endclass
