// Passive monitor: AW + W + B make one write, AR + R make one read.
// Each channel is captured when VALID && READY on a clock edge (sampled through mon_cb).
class axi4_lite_monitor extends uvm_monitor;
    `uvm_component_utils(axi4_lite_monitor)

    axi4_lite_agent_cfg                 cfg;
    virtual axi4_lite_if                vif;
    uvm_analysis_port #(axi4_lite_item) ap;

    typedef struct packed {
        bit [31:0] data;
        bit [3:0]  strb;
    } w_beat_t;

    bit [31:0] aw_q[$];
    w_beat_t   w_q [$];
    bit [31:0] ar_q[$];

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (cfg == null)
            `uvm_fatal("NO_CFG", "axi4_lite_monitor: cfg is not set")
        ap = new("ap", this);
    endfunction

    task run_phase(uvm_phase phase);
        axi4_lite_item t;
        w_beat_t       beat;
        vif = cfg.vif;
        forever begin
            @(vif.mon_cb);
            if (vif.mon_cb.rst_n !== 1'b1) begin   // in reset: drop any partial transaction
                aw_q.delete();
                w_q.delete();
                ar_q.delete();
                continue;
            end

            if (vif.mon_cb.awvalid && vif.mon_cb.awready)
                aw_q.push_back(vif.mon_cb.awaddr);
            if (vif.mon_cb.wvalid && vif.mon_cb.wready) begin
                beat.data = vif.mon_cb.wdata;
                beat.strb = vif.mon_cb.wstrb;
                w_q.push_back(beat);
            end
            if (vif.mon_cb.arvalid && vif.mon_cb.arready)
                ar_q.push_back(vif.mon_cb.araddr);

            // Write response
            if (vif.mon_cb.bvalid && vif.mon_cb.bready) begin
                if (aw_q.size() == 0 || w_q.size() == 0) begin
                    `uvm_error("MON", "B handshake before both AW and W")
                end else begin
                    t          = axi4_lite_item::type_id::create("mon_wr");
                    t.is_write = 1'b1;
                    t.addr     = aw_q.pop_front();
                    beat       = w_q.pop_front();
                    t.data     = beat.data;
                    t.wstrb    = beat.strb;
                    t.bresp    = vif.mon_cb.bresp;
                    `uvm_info("MON", t.convert2string(), UVM_MEDIUM)
                    ap.write(t);
                end
            end

            // Read response
            if (vif.mon_cb.rvalid && vif.mon_cb.rready) begin
                if (ar_q.size() == 0) begin
                    `uvm_error("MON", "R handshake before AR")
                end else begin
                    t          = axi4_lite_item::type_id::create("mon_rd");
                    t.is_write = 1'b0;
                    t.addr     = ar_q.pop_front();
                    t.rdata    = vif.mon_cb.rdata;
                    t.rresp    = vif.mon_cb.rresp;
                    `uvm_info("MON", t.convert2string(), UVM_MEDIUM)
                    ap.write(t);
                end
            end
        end
    endtask
endclass
