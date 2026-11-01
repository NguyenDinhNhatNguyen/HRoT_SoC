// Passive monitor: AW + W + B make one write, AR + R make one read.
// Each channel is captured when VALID && READY on a clock edge (sampled through mon_cb).
// accept_time = edge of the later of AW and W (write) or of AR (read), see axi4_lite_item.
class axi4_lite_monitor extends uvm_monitor;
    `uvm_component_utils(axi4_lite_monitor)

    axi4_lite_agent_cfg                 cfg;
    virtual axi4_lite_if                vif;
    uvm_analysis_port #(axi4_lite_item) ap;

    typedef struct {
        bit [31:0] data;
        bit [3:0]  strb;
        time       t;
    } w_beat_t;

    typedef struct {
        bit [31:0] addr;
        time       t;
    } a_beat_t;

    a_beat_t   aw_q[$];
    w_beat_t   w_q [$];
    a_beat_t   ar_q[$];

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
        a_beat_t       a;
        vif = cfg.vif;
        forever begin
            @(vif.mon_cb);
            if (vif.mon_cb.rst_n !== 1'b1) begin   // in reset: drop any partial transaction
                aw_q.delete();
                w_q.delete();
                ar_q.delete();
                continue;
            end

            if (vif.mon_cb.awvalid && vif.mon_cb.awready) begin
                a.addr = vif.mon_cb.awaddr;
                a.t    = $time;
                aw_q.push_back(a);
            end
            if (vif.mon_cb.wvalid && vif.mon_cb.wready) begin
                beat.data = vif.mon_cb.wdata;
                beat.strb = vif.mon_cb.wstrb;
                beat.t    = $time;
                w_q.push_back(beat);
            end
            if (vif.mon_cb.arvalid && vif.mon_cb.arready) begin
                a.addr = vif.mon_cb.araddr;
                a.t    = $time;
                ar_q.push_back(a);
            end

            // Write response
            if (vif.mon_cb.bvalid && vif.mon_cb.bready) begin
                if (aw_q.size() == 0 || w_q.size() == 0) begin
                    `uvm_error("MON", "B handshake before both AW and W")
                end else begin
                    t          = axi4_lite_item::type_id::create("mon_wr");
                    t.is_write = 1'b1;
                    a          = aw_q.pop_front();
                    beat       = w_q.pop_front();
                    t.addr     = a.addr;
                    t.data     = beat.data;
                    t.wstrb    = beat.strb;
                    t.accept_time = (a.t > beat.t) ? a.t : beat.t;
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
                    a          = ar_q.pop_front();
                    t.addr     = a.addr;
                    t.accept_time = a.t;
                    t.rdata    = vif.mon_cb.rdata;
                    t.rresp    = vif.mon_cb.rresp;
                    `uvm_info("MON", t.convert2string(), UVM_MEDIUM)
                    ap.write(t);
                end
            end
        end
    endtask
endclass
