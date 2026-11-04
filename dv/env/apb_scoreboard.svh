// APB register predictor for tb_apb_top (P-17). Listens to both APB monitors and predicts every
// transfer: read data, PSLVERR and the side effects of writes.
//   Secure bus, PADDR[15:12]: 0 GPIO, 1 TIMER, 2 Mailbox (Secure side), 3 RAM model, 4..15 no slave
//   App bus: App side of the Mailbox
// Rules come from the RTL headers (rtl/periph/*.v):
//   - a transfer acts on the edge where it completes, a read returns the state before that edge.
//     Both buses can complete on the same edge (Mailbox), so every item of one edge is checked against
//     the state before the edge (snapshot), then its effect goes into the next state
//   - GPIO: DATA_OUT and IRQ_EN need PSTRB[0], IRQ_STAT is write-1-to-clear. DATA_IN and IRQ_STAT are
//     predicted only while gpio_i has stayed 0 since the reset, sequences that drive gpio_i check them
//   - TIMER: mtime counts every clock, a write of one half replaces that half instead of counting,
//     MTIMECMP resets to all ones, PSTRB is ignored
//   - Mailbox: OUT is ignored while OUT_FULL, reading IN clears IN_FULL, IRQ_EN needs PSTRB[0].
//     A send and a read of the same slot on one edge: the send wins (it is later in the RTL always
//     block), whatever order the two monitors deliver them in
//   - RAM model: byte strobes, keeps its content over a reset
//   - offsets that are not registers read 0, windows without a slave give PSLVERR and read 0
`uvm_analysis_imp_decl(_secure)
`uvm_analysis_imp_decl(_app)

class apb_scoreboard extends uvm_component;
    `uvm_component_utils(apb_scoreboard)

    uvm_analysis_imp_secure #(apb_item, apb_scoreboard) secure_export;
    uvm_analysis_imp_app    #(apb_item, apb_scoreboard) app_export;

    virtual apb_sb_if sb_vif;
    virtual apb_if    s_vif;

    typedef struct {
        bit [7:0]    gpio_out, gpio_en, gpio_stat;
        bit [63:0]   mtime_v0;      // mtime right after edge mtime_t0
        time         mtime_t0;
        bit [63:0]   mtimecmp;
        bit [31:0]   m2a_data, a2m_data;
        bit          m2a_full, a2m_full;
        bit          s_irq_en, a_irq_en;
    } state_t;

    state_t      cur, snap;
    time         snap_edge = -1;
    bit          m2a_sent, a2m_sent;   // a send was accepted on snap_edge
    bit [31:0]   ram[256];
    time         period;
    bit          gpio_in_used;      // gpio_i went non-zero since the reset: DATA_IN/IRQ_STAT not predicted

    int unsigned n_checked, n_skipped, n_errors, n_slverr;
    int unsigned n_per_slave[string];

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        secure_export = new("secure_export", this);
        app_export    = new("app_export", this);
        if (!uvm_config_db#(virtual apb_sb_if)::get(this, "", "sb_vif", sb_vif))
            `uvm_fatal("NO_VIF", "apb_scoreboard: sb_vif not found")
        if (!uvm_config_db#(virtual apb_if)::get(this, "", "s_vif", s_vif))
            `uvm_fatal("NO_VIF", "apb_scoreboard: s_vif not found")
        foreach (ram[i])
            ram[i] = 32'h0;
        reset_model(0);
    endfunction

    function void reset_model(time first_edge);
        cur           = '{default: '0};
        cur.mtimecmp  = '1;
        cur.mtime_v0  = 64'h0;
        cur.mtime_t0  = first_edge - period;   // last edge still in reset: mtime = 0 after it
        snap          = cur;
        snap_edge     = -1;
        gpio_in_used  = 1'b0;
    endfunction

    // Clock period, model reset at every reset release, and gpio_i activity
    task run_phase(uvm_phase phase);
        time t0;
        @(posedge s_vif.clk);
        t0 = $time;
        @(posedge s_vif.clk);
        period = $time - t0;
        fork
            forever begin
                wait (s_vif.rst_n === 1'b0);
                wait (s_vif.rst_n === 1'b1);
                @(posedge s_vif.clk);
                reset_model($time);
            end
            forever begin
                @(sb_vif.gpio_i);
                if (sb_vif.gpio_i !== 8'h00)
                    gpio_in_used = 1'b1;
            end
        join
    endtask

    function bit [63:0] mtime_after(state_t s, time edge_t);
        return s.mtime_v0 + (edge_t - s.mtime_t0) / period;
    endfunction

    function void write_secure(apb_item t);
        check_item(t, 1'b0);
    endfunction

    function void write_app(apb_item t);
        check_item(t, 1'b1);
    endfunction

    // Not named check(): uvm_component has a check() method of its own (Questa rejects the clash)
    function void check_item(apb_item t, bit app);
        bit [31:0] exp;
        bit        exp_err = 1'b0;
        bit        known   = 1'b1;
        bit [11:0] off     = t.addr[11:0];
        int        slave   = app ? 2 : t.addr[15:12];
        string     name;
        if (period == 0)
            `uvm_fatal("APB_SB", "transfer seen before the clock period was measured")
        if (t.done_time != snap_edge) begin
            snap      = cur;
            snap_edge = t.done_time;
            m2a_sent  = 1'b0;
            a2m_sent  = 1'b0;
        end
        exp = 32'h0;
        case (slave)
            0: begin
                name = "gpio";
                case (off)
                    12'h000: exp = {24'b0, snap.gpio_out};
                    12'h004: begin
                        exp   = {24'b0, sb_vif.gpio_i};
                        known = !gpio_in_used;
                    end
                    12'h008: exp = {24'b0, snap.gpio_en};
                    12'h00C: begin
                        exp   = {24'b0, snap.gpio_stat};
                        known = !gpio_in_used;
                    end
                    default: exp = 32'h0;
                endcase
                if (t.is_write && off == 12'h000 && t.strb[0])
                    cur.gpio_out = t.data[7:0];
                if (t.is_write && off == 12'h008 && t.strb[0])
                    cur.gpio_en = t.data[7:0];
                if (t.is_write && off == 12'h00C)
                    cur.gpio_stat = cur.gpio_stat & ~t.data[7:0];
            end
            1: begin
                bit [63:0] mt = mtime_after(snap, t.done_time - period);
                name = "timer";
                case (off)
                    12'h000: exp = mt[31:0];
                    12'h004: exp = mt[63:32];
                    12'h008: exp = snap.mtimecmp[31:0];
                    12'h00C: exp = snap.mtimecmp[63:32];
                    default: exp = 32'h0;
                endcase
                if (t.is_write && (off == 12'h000 || off == 12'h004)) begin
                    cur.mtime_v0 = (off == 12'h000) ? {mt[63:32], t.data} : {t.data, mt[31:0]};
                    cur.mtime_t0 = t.done_time;
                end
                if (t.is_write && off == 12'h008)
                    cur.mtimecmp[31:0] = t.data;
                if (t.is_write && off == 12'h00C)
                    cur.mtimecmp[63:32] = t.data;
            end
            2: begin
                name = app ? "mbox_app" : "mbox_secure";
                // seen from this side: "out" is my slot, "in" is the other side's slot
                case (off)
                    12'h000: exp = app ? snap.a2m_data : snap.m2a_data;
                    12'h004: exp = app ? snap.m2a_data : snap.a2m_data;
                    12'h008: exp = app ? {30'b0, snap.a2m_full, snap.m2a_full} : {30'b0, snap.m2a_full, snap.a2m_full};
                    12'h00C: exp = {31'b0, app ? snap.a_irq_en : snap.s_irq_en};
                    default: exp = 32'h0;
                endcase
                if (!t.is_write && off == 12'h004) begin
                    if (app && !m2a_sent)
                        cur.m2a_full = 1'b0;
                    if (!app && !a2m_sent)
                        cur.a2m_full = 1'b0;
                end
                if (t.is_write && off == 12'h000) begin
                    if (app && !snap.a2m_full) begin
                        cur.a2m_data = t.data;
                        cur.a2m_full = 1'b1;
                        a2m_sent     = 1'b1;
                    end
                    if (!app && !snap.m2a_full) begin
                        cur.m2a_data = t.data;
                        cur.m2a_full = 1'b1;
                        m2a_sent     = 1'b1;
                    end
                end
                if (t.is_write && off == 12'h00C && t.strb[0]) begin
                    if (app)
                        cur.a_irq_en = t.data[0];
                    else
                        cur.s_irq_en = t.data[0];
                end
            end
            3: begin
                name = "ram";
                exp  = ram[off[9:2]];
                if (t.is_write)
                    for (int b = 0; b < 4; b++)
                        if (t.strb[b])
                            ram[off[9:2]][8*b +: 8] = t.data[8*b +: 8];
            end
            default: begin
                name    = "no_slave";
                exp_err = 1'b1;
            end
        endcase

        if (n_per_slave.exists(name))
            n_per_slave[name]++;
        else
            n_per_slave[name] = 1;
        if (t.slverr)
            n_slverr++;
        if (t.slverr !== exp_err) begin
            n_errors++;
            `uvm_error("APB_SB", $sformatf("%s: PSLVERR %0d, expected %0d", t.convert2string(), t.slverr, exp_err))
        end
        if (t.is_write)
            return;
        if (!known) begin
            n_skipped++;
            return;
        end
        n_checked++;
        if (t.rdata !== exp) begin
            n_errors++;
            `uvm_error("APB_SB", $sformatf("%s: expected 0x%08h", t.convert2string(), exp))
        end
    endfunction

    function void report_phase(uvm_phase phase);
        string s = "";
        super.report_phase(phase);
        foreach (n_per_slave[k])
            s = {s, $sformatf(" %s=%0d", k, n_per_slave[k])};
        `uvm_info("APB_SB", $sformatf("transfers per block:%s", s), UVM_LOW)
        `uvm_info("APB_SB", $sformatf("%0d reads checked, %0d skipped, %0d PSLVERR seen, %0d errors",
                                      n_checked, n_skipped, n_slverr, n_errors), UVM_LOW)
        if (n_checked == 0)
            `uvm_error("APB_SB", "no read checked: the scoreboard checked nothing")
    endfunction
endclass
