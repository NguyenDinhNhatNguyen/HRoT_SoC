// SHA-256 functional coverage (P-19, test plan docs/verification/SHA256_UVM_TestPlan.md section 6)
//
// Passive: it listens to the AXI4-Lite monitor only, like sha256_scoreboard, and rebuilds what it needs
// from the bus (BUSY/DONE phase, block chains, message length). Compiled only with +define+HROT_COV
// (sim/cov.sh), so the normal Questa and Verilator builds do not change.
//
// Covergroups:
//   cg_reg_access  register class x read/write, WSTRB of the writes
//   cg_msg         message length and block count. A message is a chain of STARTs that begins with INIT.
//                  Its length is read back from the padding of the last block (bit length in words 14/15),
//                  and it is sampled only when the block count matches that length, so the raw blocks of
//                  sha256_ctl_seq never count as messages
//   cg_ctrl        INIT x START x phase (IDLE/BUSY/DONE) on CTRL writes, BLOCK writes x phase
//   cg_status      transitions between STATUS values seen by reads (IDLE 0, BUSY 2, DONE 1)
//   cg_axi         AW/W order, response latency and the gap before a request, measured on the bus
//   cg_reset       phase of the block when a reset comes (IDLE, BUSY early/mid/late, DONE)
//   cg_poll        STATUS reads after a START until the first one that sees DONE
// Phases follow sha256_scoreboard: P = clock period, ts = START edge, BUSY for ts+P..ts+65P, DONE from ts+66P.
`ifdef HROT_COV
class sha256_coverage extends uvm_subscriber #(axi4_lite_item);
    `uvm_component_utils(sha256_coverage)

    typedef enum {IDLE, BUSY, DONE} phase_e;
    typedef enum {R_BLOCK, R_CTRL, R_STATUS, R_HASH, R_RESERVED, R_OUT_OF_MAP} reg_e;
    typedef enum {RST_IDLE, RST_BUSY_EARLY, RST_BUSY_MID, RST_BUSY_LATE, RST_DONE} rst_e;
    typedef enum {AW_FIRST, W_FIRST, AW_W_SAME} order_e;

    axi4_lite_agent_cfg cfg;
    time                period;
    bit                 started;      // a START was accepted since reset
    time                ts;
    bit [31:0]          blk[16];      // BLOCK words as the DUT holds them
    bit [31:0]          last_blk[16]; // block of the last START
    int unsigned        chain_blocks; // STARTs since the last START with INIT
    bit                 polling;
    int unsigned        polls;
    bit [1:0]           last_status;
    time                last_resp;

    // Sample values
    reg_e        s_reg;
    bit          s_wr;
    bit [3:0]    s_strb;
    int unsigned s_len, s_blocks;
    bit          s_init, s_start;
    phase_e      s_phase;
    bit [1:0]    s_status;
    order_e      s_order;
    int unsigned s_lat, s_gap;
    rst_e        s_rst;
    int unsigned s_polls;

    covergroup cg_reg_access;
        cp_reg: coverpoint s_reg;
        cp_dir: coverpoint s_wr;
        reg_x_dir: cross cp_reg, cp_dir;
        cp_strb: coverpoint s_strb iff (s_wr) {
            bins full   = {4'hF};
            bins none   = {4'h0};
            bins lane[] = {4'h1, 4'h2, 4'h4, 4'h8};
            bins other  = default;
        }
    endgroup

    covergroup cg_msg;
        cp_len: coverpoint s_len {
            bins len_0       = {0};
            bins len_1_54    = {[1:54]};
            bins len_55      = {55};
            bins len_56      = {56};
            bins len_57_62   = {[57:62]};
            bins len_63      = {63};
            bins len_64      = {64};
            bins len_65_118  = {[65:118]};
            bins len_119     = {119};
            bins len_120     = {120};
            bins len_121_127 = {[121:127]};
            bins len_128     = {128};
            bins len_big     = {[129:$]};
        }
        cp_blocks: coverpoint s_blocks {
            bins one   = {1};
            bins two   = {2};
            bins three = {3};
            bins more  = {[4:$]};
        }
    endgroup

    covergroup cg_ctrl;
        cp_init:  coverpoint s_init;
        cp_start: coverpoint s_start;
        cp_phase: coverpoint s_phase;
        ctrl_x_phase: cross cp_init, cp_start, cp_phase;
    endgroup

    covergroup cg_block_write;
        cp_phase: coverpoint s_phase;          // BUSY = a BLOCK write the DUT must ignore (F-CTL-06)
    endgroup

    covergroup cg_status;
        cp_trans: coverpoint s_status {
            bins idle_to_busy = (2'd0 => 2'd2);
            bins busy_to_done = (2'd2 => 2'd1);
            bins done_to_busy = (2'd1 => 2'd2);
            bins busy_hold    = (2'd2 => 2'd2);
            bins done_hold    = (2'd1 => 2'd1);
            bins idle_hold    = (2'd0 => 2'd0);
        }
    endgroup

    covergroup cg_axi with function sample(bit is_wr);
        cp_order: coverpoint s_order iff (is_wr);
        cp_lat: coverpoint s_lat {
            bins lat_0_1  = {[0:1]};
            bins lat_2_4  = {[2:4]};
            bins lat_5_up = {[5:$]};
        }
        cp_gap: coverpoint s_gap {
            bins gap_0_1  = {[0:1]};
            bins gap_2_4  = {[2:4]};
            bins gap_5_up = {[5:$]};
        }
        cp_dir: coverpoint is_wr;
        lat_x_dir: cross cp_lat, cp_dir;
    endgroup

    covergroup cg_reset;
        cp_phase: coverpoint s_rst;
    endgroup

    covergroup cg_poll;
        cp_polls: coverpoint s_polls {
            bins one      = {1};
            bins two_ten  = {[2:10]};
            bins many     = {[11:$]};
        }
    endgroup

    function new(string name, uvm_component parent);
        super.new(name, parent);
        cg_reg_access  = new();
        cg_msg         = new();
        cg_ctrl        = new();
        cg_block_write = new();
        cg_status      = new();
        cg_axi         = new();
        cg_reset       = new();
        cg_poll        = new();
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(axi4_lite_agent_cfg)::get(this, "", "cfg", cfg))
            `uvm_fatal("NO_CFG", "sha256_coverage: cfg not found in config_db")
    endfunction

    function void clear_state();
        started      = 1'b0;
        chain_blocks = 0;
        polling      = 1'b0;
        foreach (blk[i])
            blk[i] = 32'h0;
    endfunction

    function phase_e phase_at(time t);
        if (!started || t < ts + period)
            return started ? BUSY : IDLE;   // t == ts cannot happen: one request per edge
        if (t <= ts + 65 * period)
            return BUSY;
        return DONE;
    endfunction

    // Clock period, then one reset sample per reset of the DUT
    task run_phase(uvm_phase phase);
        time t0;
        @(posedge cfg.vif.clk);
        t0 = $time;
        @(posedge cfg.vif.clk);
        period = $time - t0;
        clear_state();
        forever begin
            @(negedge cfg.vif.rst_n);
            if (!started)
                s_rst = RST_IDLE;
            else if ($time > ts + 65 * period)
                s_rst = RST_DONE;
            else if ($time <= ts + 22 * period)
                s_rst = RST_BUSY_EARLY;
            else if ($time <= ts + 44 * period)
                s_rst = RST_BUSY_MID;
            else
                s_rst = RST_BUSY_LATE;
            cg_reset.sample();
            finish_chain();                 // a chain cut by reset is not a message
            chain_blocks = 0;
            clear_state();
        end
    endtask

    // The chain that ended is a message when its last block carries a length that needs exactly that
    // many blocks (pad: 0x80, zeros, 64-bit bit length in words 14 and 15)
    function void finish_chain();
        bit [63:0]   bits;
        int unsigned len;
        if (chain_blocks == 0)
            return;
        bits = {last_blk[14], last_blk[15]};
        len  = bits / 8;
        if (bits[2:0] == 3'b0 && bits < 64'd1_000_000 && (len + 9 + 63) / 64 == chain_blocks) begin
            s_len    = len;
            s_blocks = chain_blocks;
            cg_msg.sample();
        end
    endfunction

    function reg_e reg_of(bit [15:0] off);
        if (off >= 16'h0100)
            return R_OUT_OF_MAP;
        if (off <= 16'h003C)
            return R_BLOCK;
        if (off == 16'h0040)
            return R_CTRL;
        if (off == 16'h0044)
            return R_STATUS;
        if (off >= 16'h0050 && off <= 16'h006C)
            return R_HASH;
        return R_RESERVED;
    endfunction

    function void write(axi4_lite_item t);
        bit [15:0] off = t.addr[15:0];
        time       req;
        if (period == 0)
            return;

        // Register access and bus timing
        s_reg  = reg_of(off);
        s_wr   = t.is_write;
        s_strb = t.wstrb;
        cg_reg_access.sample();
        if (t.is_write)
            s_order = (t.a_time < t.w_time) ? AW_FIRST : (t.a_time > t.w_time) ? W_FIRST : AW_W_SAME;
        req   = (t.is_write && t.w_time < t.a_time) ? t.w_time : t.a_time;
        s_lat = (t.resp_time - t.accept_time) / period;
        s_gap = (last_resp == 0 || req < last_resp) ? 0 : (req - last_resp) / period;
        cg_axi.sample(t.is_write);
        last_resp = t.resp_time;

        if (off[15:8] != 8'h00)
            return;
        s_phase = phase_at(t.accept_time);
        if (t.is_write) begin
            if (off[7:6] == 2'b00) begin
                cg_block_write.sample();
                if (s_phase != BUSY)
                    blk[off[5:2]] = t.data;
            end else if (off[7:0] == 8'h40) begin
                s_init  = t.data[1];
                s_start = t.data[0];
                cg_ctrl.sample();
                if (t.data[0] && s_phase != BUSY) begin
                    if (t.data[1]) begin
                        finish_chain();
                        chain_blocks = 0;
                    end
                    chain_blocks++;
                    last_blk = blk;
                    started  = 1'b1;
                    ts       = t.accept_time;
                    polling  = 1'b1;
                    polls    = 0;
                end
            end
        end else if (off[7:0] == 8'h44) begin
            s_status = t.rdata[1:0];
            cg_status.sample();
            if (polling) begin
                polls++;
                if (t.rdata[0]) begin
                    s_polls = polls;
                    cg_poll.sample();
                    polling = 1'b0;
                end
            end
        end
    endfunction

    function void report_phase(uvm_phase phase);
        finish_chain();
        `uvm_info("SHA_COV", $sformatf("reg %0.1f%%, msg %0.1f%%, ctrl %0.1f%%, block write %0.1f%%, status %0.1f%%, axi %0.1f%%, reset %0.1f%%, poll %0.1f%%",
                                       cg_reg_access.get_coverage(), cg_msg.get_coverage(), cg_ctrl.get_coverage(),
                                       cg_block_write.get_coverage(), cg_status.get_coverage(), cg_axi.get_coverage(),
                                       cg_reset.get_coverage(), cg_poll.get_coverage()), UVM_LOW)
    endfunction
endclass
`endif
