class axi4_lite_driver extends uvm_driver #(axi4_lite_item);
    `uvm_component_utils(axi4_lite_driver)

    axi4_lite_agent_cfg   cfg;   // set by the agent before the driver build_phase
    virtual axi4_lite_if  vif;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (cfg == null)
            `uvm_fatal("NO_CFG", "axi4_lite_driver: cfg is not set")
    endfunction

    bit in_flight;                        // item taken but item_done not called yet

    // Each outer loop = one reset-free window. Reset in the middle: abort the running
    // transaction, return the item with aborted = 1, drive the bus idle, wait for reset release.
    task run_phase(uvm_phase phase);
        vif = cfg.vif;
        forever begin
            drive_idle();
            wait (vif.rst_n === 1'b1);        // level-sensitive: never misses the reset edge
            @(vif.drv_cb);                    // align to the clock edge
            fork
                drive_items();
                @(negedge vif.rst_n);
            join_any
            disable fork;
            if (in_flight) begin
                req.aborted = 1'b1;
                `uvm_info("DRV", {"Reset mid-transaction, aborted: ", req.convert2string()}, UVM_LOW)
                seq_item_port.item_done();
                in_flight = 1'b0;
            end
        end
    endtask

    // Always start a transaction on a clock edge. If an item is ready, drive it at once
    // (back-to-back, no idle cycle). Otherwise wait 1 cycle and ask again.
    task drive_items();
        forever begin
            seq_item_port.try_next_item(req);
            if (req == null) begin
                @(vif.drv_cb);
                continue;
            end
            in_flight = 1'b1;
            if (req.is_write)
                do_write(req);
            else
                do_read(req);
            `uvm_info("DRV", req.convert2string(), UVM_HIGH)
            seq_item_port.item_done();
            in_flight = 1'b0;
        end
    endtask

    task drive_idle();
        vif.drv_cb.awvalid <= 1'b0;
        vif.drv_cb.wvalid  <= 1'b0;
        vif.drv_cb.bready  <= 1'b0;
        vif.drv_cb.arvalid <= 1'b0;
        vif.drv_cb.rready  <= 1'b0;
        vif.drv_cb.awaddr  <= '0;
        vif.drv_cb.wdata   <= '0;
        vif.drv_cb.wstrb   <= '0;
        vif.drv_cb.araddr  <= '0;
    endtask

    function void chk_timeout(int unsigned n, string what);
        if (n > cfg.timeout_cycles)
            `uvm_fatal("DRV_TMO", $sformatf("Timeout after %0d cycles waiting for %s", cfg.timeout_cycles, what))
    endfunction

    task do_write(axi4_lite_item t);
        int unsigned n;
        fork
            begin : aw_ch
                int unsigned k = 0;
                repeat (t.addr_delay) @(vif.drv_cb);
                vif.drv_cb.awaddr  <= t.addr;
                vif.drv_cb.awvalid <= 1'b1;
                do begin
                    @(vif.drv_cb);
                    k++;
                    chk_timeout(k, "AWREADY");
                end while (vif.drv_cb.awready !== 1'b1);  // READY sampled on the edge where VALID = 1, X/Z counts as not ready
                vif.drv_cb.awvalid <= 1'b0;
            end
            begin : w_ch
                int unsigned k = 0;
                repeat (t.data_delay) @(vif.drv_cb);
                vif.drv_cb.wdata  <= t.data;
                vif.drv_cb.wstrb  <= t.wstrb;
                vif.drv_cb.wvalid <= 1'b1;
                do begin
                    @(vif.drv_cb);
                    k++;
                    chk_timeout(k, "WREADY");
                end while (vif.drv_cb.wready !== 1'b1);
                vif.drv_cb.wvalid <= 1'b0;
            end
        join

        // B channel: delay BREADY by resp_delay to exercise a held BVALID
        repeat (t.resp_delay) @(vif.drv_cb);
        vif.drv_cb.bready <= 1'b1;
        n = 0;
        do begin
            @(vif.drv_cb);
            n++;
            chk_timeout(n, "BVALID");
        end while (vif.drv_cb.bvalid !== 1'b1);
        t.bresp = vif.drv_cb.bresp;
        vif.drv_cb.bready <= 1'b0;
    endtask

    task do_read(axi4_lite_item t);
        int unsigned n;
        repeat (t.addr_delay) @(vif.drv_cb);
        vif.drv_cb.araddr  <= t.addr;
        vif.drv_cb.arvalid <= 1'b1;
        n = 0;
        do begin
            @(vif.drv_cb);
            n++;
            chk_timeout(n, "ARREADY");
        end while (vif.drv_cb.arready !== 1'b1);
        vif.drv_cb.arvalid <= 1'b0;

        repeat (t.resp_delay) @(vif.drv_cb);
        vif.drv_cb.rready <= 1'b1;
        n = 0;
        do begin
            @(vif.drv_cb);
            n++;
            chk_timeout(n, "RVALID");
        end while (vif.drv_cb.rvalid !== 1'b1);
        t.rdata = vif.drv_cb.rdata;
        t.rresp = vif.drv_cb.rresp;
        vif.drv_cb.rready <= 1'b0;
    endtask
endclass
