// APB functional coverage for tb_apb_top (P-19). Passive, next to apb_scoreboard: it listens to both
// APB monitors and to the pins in apb_sb_if. Compiled only with +define+HROT_COV (sim/cov.sh).
//
// Covergroups:
//   cg_secure    window (GPIO, TIMER, Mailbox, RAM model, no slave) x read/write, PSLVERR, wait states
//                of the RAM model, PSTRB of the writes
//   cg_regs      register x read/write in GPIO, TIMER and the Secure side of the Mailbox
//   cg_app       register x read/write on the App side of the Mailbox
//   cg_same_edge both buses finish a Mailbox transfer on the same edge (the scoreboard's hardest case)
//   cg_irq       rise and fall of the GPIO, TIMER and both Mailbox interrupt lines
// Window decode as in tb_apb_top: Secure PADDR[15:12] 0 GPIO, 1 TIMER, 2 Mailbox, 3 RAM model, 4..15 none.
`ifdef HROT_COV
class apb_coverage extends uvm_component;
    `uvm_component_utils(apb_coverage)

    typedef enum {W_GPIO, W_TIMER, W_MBOX, W_RAM, W_NONE} win_e;
    typedef enum {OFF_0, OFF_4, OFF_8, OFF_C, OFF_OTHER} off_e;

    uvm_analysis_imp_secure #(apb_item, apb_coverage) secure_export;
    uvm_analysis_imp_app    #(apb_item, apb_coverage) app_export;
    virtual apb_sb_if sb_vif;

    win_e        s_win;
    off_e        s_off;
    bit          s_wr, s_err;
    bit [3:0]    s_strb;
    int unsigned s_waits;
    bit          s_s_wr, s_a_wr;
    time         last_mbox_s = -1;
    time         last_mbox_a = -1;
    bit          last_mbox_s_wr, last_mbox_a_wr;
    bit          s_gpio_irq, s_timer_irq, s_mbox_irq_s, s_mbox_irq_a;

    covergroup cg_secure;
        cp_win: coverpoint s_win;
        cp_dir: coverpoint s_wr;
        win_x_dir: cross cp_win, cp_dir;
        cp_err: coverpoint s_err;
        win_x_err: cross cp_win, cp_err {
            ignore_bins slave_ok   = binsof(cp_win) intersect {W_GPIO, W_TIMER, W_MBOX, W_RAM} && binsof(cp_err) intersect {1};
            ignore_bins none_error = binsof(cp_win) intersect {W_NONE} && binsof(cp_err) intersect {0};
        }
        cp_waits: coverpoint s_waits iff (s_win == W_RAM) {
            bins zero  = {0};
            bins few   = {[1:3]};
            bins many  = {[4:$]};
        }
        cp_strb: coverpoint s_strb iff (s_wr) {
            bins full    = {4'hF};
            bins none    = {4'h0};
            bins lane0   = {4'h1};
            bins partial = default;
        }
        win_x_strb: cross cp_win, cp_strb {
            ignore_bins no_slave = binsof(cp_win) intersect {W_NONE};
        }
    endgroup

    covergroup cg_regs;
        cp_win: coverpoint s_win {
            bins gpio  = {W_GPIO};
            bins timer = {W_TIMER};
            bins mbox  = {W_MBOX};
        }
        cp_off: coverpoint s_off;
        cp_dir: coverpoint s_wr;
        reg_x_dir: cross cp_win, cp_off, cp_dir;
    endgroup

    covergroup cg_app;
        cp_off: coverpoint s_off;
        cp_dir: coverpoint s_wr;
        off_x_dir: cross cp_off, cp_dir;
    endgroup

    covergroup cg_same_edge;
        cp_s: coverpoint s_s_wr;
        cp_a: coverpoint s_a_wr;
        s_x_a: cross cp_s, cp_a;
    endgroup

    // Sampled on every clock by run_phase (a class covergroup must be built in new(), before sb_vif exists)
    covergroup cg_irq;
        cp_gpio:   coverpoint s_gpio_irq   { bins rise = (0 => 1); bins fall = (1 => 0); }
        cp_timer:  coverpoint s_timer_irq  { bins rise = (0 => 1); bins fall = (1 => 0); }
        cp_mbox_s: coverpoint s_mbox_irq_s { bins rise = (0 => 1); bins fall = (1 => 0); }
        cp_mbox_a: coverpoint s_mbox_irq_a { bins rise = (0 => 1); bins fall = (1 => 0); }
    endgroup

    function new(string name, uvm_component parent);
        super.new(name, parent);
        cg_secure    = new();
        cg_regs      = new();
        cg_app       = new();
        cg_same_edge = new();
        cg_irq       = new();
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        secure_export = new("secure_export", this);
        app_export    = new("app_export", this);
        if (!uvm_config_db#(virtual apb_sb_if)::get(this, "", "sb_vif", sb_vif))
            `uvm_fatal("NO_VIF", "apb_coverage: sb_vif not found")
    endfunction

    task run_phase(uvm_phase phase);
        forever begin
            @(posedge sb_vif.clk);
            s_gpio_irq   = sb_vif.gpio_irq;
            s_timer_irq  = sb_vif.timer_irq;
            s_mbox_irq_s = sb_vif.mbox_irq_s;
            s_mbox_irq_a = sb_vif.mbox_irq_a;
            cg_irq.sample();
        end
    endtask

    function off_e off_of(bit [11:0] off);
        case (off)
            12'h000:
                return OFF_0;
            12'h004:
                return OFF_4;
            12'h008:
                return OFF_8;
            12'h00C:
                return OFF_C;
            default:
                return OFF_OTHER;
        endcase
    endfunction

    // Mailbox transfers of both buses that complete on one edge
    function void check_same_edge();
        if (last_mbox_s == last_mbox_a && last_mbox_s != -1) begin
            s_s_wr = last_mbox_s_wr;
            s_a_wr = last_mbox_a_wr;
            cg_same_edge.sample();
            last_mbox_a = -1;
        end
    endfunction

    function void write_secure(apb_item t);
        if (t.aborted)
            return;
        case (t.addr[15:12])
            4'h0:
                s_win = W_GPIO;
            4'h1:
                s_win = W_TIMER;
            4'h2:
                s_win = W_MBOX;
            4'h3:
                s_win = W_RAM;
            default:
                s_win = W_NONE;
        endcase
        s_off   = off_of(t.addr[11:0]);
        s_wr    = t.is_write;
        s_err   = t.slverr;
        s_strb  = t.strb;
        s_waits = t.waits;
        cg_secure.sample();
        if (s_win != W_RAM && s_win != W_NONE)
            cg_regs.sample();
        if (s_win == W_MBOX) begin
            last_mbox_s    = t.done_time;
            last_mbox_s_wr = t.is_write;
            check_same_edge();
        end
    endfunction

    function void write_app(apb_item t);
        if (t.aborted)
            return;
        s_off = off_of(t.addr[11:0]);
        s_wr  = t.is_write;
        cg_app.sample();
        last_mbox_a    = t.done_time;
        last_mbox_a_wr = t.is_write;
        check_same_edge();
    endfunction

    function void report_phase(uvm_phase phase);
        `uvm_info("APB_COV", $sformatf("secure %0.1f%%, regs %0.1f%%, app %0.1f%%, same edge %0.1f%%, irq %0.1f%%",
                                       cg_secure.get_coverage(), cg_regs.get_coverage(), cg_app.get_coverage(),
                                       cg_same_edge.get_coverage(), cg_irq.get_coverage()), UVM_LOW)
    endfunction
endclass
`endif
