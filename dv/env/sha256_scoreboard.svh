// SHA-256 register model and passive scoreboard (P-17, test plan docs/verification/SHA256_UVM_TestPlan.md)
//
// The scoreboard listens to the AXI4-Lite monitor only. It rebuilds each block from the BLOCK writes,
// computes the digest with the C reference model through DPI (dv/env/sha256_ref_dpi.c, the same
// fw/hal/test/sha256_ref.c the HAL host test uses) and predicts every read: STATUS, HASH and the
// registers that read 0. It does not trust the sequences, so it also catches a sequence that checks
// against a wrong expectation.
//
// Timing, cycle exact, from SHA256_Wrapper / SHA256_Core (A2, A3 of the test plan). P = clock period,
// ts = edge where START was accepted, t = edge where a request was accepted (accept_time):
//   - a read returns the state after the edge before t, a write acts on edge t
//   - BUSY (and "writes ignored") for ts + P <= t <= ts + 65P
//   - DONE and the new digest visible for t >= ts + 66P
//   - START with INIT loads IV at ts, so HASH reads IV while that block runs
// After a reset the block words are unknown (the RTL does not clear them): a START before all 16 are
// written again makes that digest unpredictable, and the scoreboard skips it.

import "DPI-C" function void sha256_ref_compress_dpi(inout int unsigned h[8], input int unsigned w[16]);
import "DPI-C" function int unsigned sha256_ref_iv_dpi(input int i);

class sha256_reg_model extends uvm_object;
    `uvm_object_utils(sha256_reg_model)

    time         period;
    int unsigned block[16];
    bit          block_known[16];
    int unsigned h_prev[8];      // H before the last START
    int unsigned h_new[8];       // digest of the last START
    bit          h_new_known;
    bit          started;        // a START was accepted since reset
    bit          start_init;
    time         ts;

    function new(string name = "sha256_reg_model");
        super.new(name);
        reset();
    endfunction

    function void reset();
        for (int i = 0; i < 8; i++)
            h_prev[i] = sha256_ref_iv_dpi(i);
        foreach (block_known[i])
            block_known[i] = 1'b0;
        started     = 1'b0;
        h_new_known = 1'b1;
    endfunction

    function bit busy_at(time t);
        return started && t >= ts + period && t <= ts + 65 * period;
    endfunction

    function bit done_at(time t);
        return started && t >= ts + 66 * period;
    endfunction

    // Visible H word i for a read accepted at t. known = 0 when it cannot be predicted
    function int unsigned hash_at(time t, int i, output bit known);
        known = 1'b1;
        if (!started || t < ts + period)
            return h_prev[i];
        if (t < ts + 66 * period)
            return start_init ? sha256_ref_iv_dpi(i) : h_prev[i];
        known = h_new_known;
        return h_new[i];
    endfunction

    // Predicted read data for offset off (address bits [15:0]) accepted at t
    function bit [31:0] predict_read(bit [15:0] off, time t, output bit known);
        known = 1'b1;
        if (off[15:8] != 8'h00)
            return 32'h0;
        if (off[7:0] == 8'h44)
            return {30'b0, busy_at(t), done_at(t)};
        if (off[7:0] >= 8'h50 && off[7:0] <= 8'h6C)
            return hash_at(t, (off[7:0] - 8'h50) >> 2, known);   // H0 at 0x50 ... H7 at 0x6C
        return 32'h0;
    endfunction

    // Apply a write accepted at t. Returns 1 when it started a block
    function bit write(bit [15:0] off, bit [31:0] data, time t);
        int unsigned w[16];
        int unsigned h[8];
        bit          chain_known;
        if (off[15:8] != 8'h00 || busy_at(t))
            return 1'b0;
        if (off[7:6] == 2'b00) begin
            block[off[5:2]]       = data;
            block_known[off[5:2]] = 1'b1;
            return 1'b0;
        end
        if (off[7:0] != 8'h40 || !data[0])
            return 1'b0;
        // START: the previous block is done (not busy), so its digest is the chaining value
        chain_known = !started || h_new_known;
        if (started)
            h_prev = h_new;
        for (int i = 0; i < 8; i++)
            h[i] = data[1] ? sha256_ref_iv_dpi(i) : h_prev[i];
        foreach (block[i])
            w[i] = block[i];
        sha256_ref_compress_dpi(h, w);
        h_new       = h;
        h_new_known = block_known_all() && (data[1] || chain_known);
        started     = 1'b1;
        start_init  = data[1];
        ts          = t;
        return 1'b1;
    endfunction

    function bit block_known_all();
        foreach (block_known[i])
            if (!block_known[i])
                return 1'b0;
        return 1'b1;
    endfunction
endclass


class sha256_scoreboard extends uvm_component;
    `uvm_component_utils(sha256_scoreboard)

    uvm_analysis_imp #(axi4_lite_item, sha256_scoreboard) item_export;
    axi4_lite_agent_cfg cfg;
    sha256_reg_model    m;

    int unsigned n_reads, n_hash_reads, n_status_reads, n_writes, n_starts, n_skipped, n_errors;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        item_export = new("item_export", this);
        if (!uvm_config_db#(axi4_lite_agent_cfg)::get(this, "", "cfg", cfg))
            `uvm_fatal("NO_CFG", "sha256_scoreboard: cfg not found in config_db")
        m = sha256_reg_model::type_id::create("m");
    endfunction

    // Clock period from two rising edges, and a model reset on every reset of the DUT
    task run_phase(uvm_phase phase);
        time t0;
        @(posedge cfg.vif.clk);
        t0 = $time;
        @(posedge cfg.vif.clk);
        m.period = $time - t0;
        forever begin
            @(negedge cfg.vif.rst_n);
            m.reset();
            `uvm_info("SHA_SB", "DUT reset: model reset, block words unknown until written again", UVM_MEDIUM)
        end
    endtask

    function void write(axi4_lite_item t);
        bit [31:0] exp;
        bit        known;
        if (m.period == 0)
            `uvm_fatal("SHA_SB", "transaction seen before the clock period was measured")
        if (t.is_write) begin
            n_writes++;
            if (m.write(t.addr[15:0], t.data, t.accept_time))
                n_starts++;
            return;
        end
        n_reads++;
        exp = m.predict_read(t.addr[15:0], t.accept_time, known);
        if (!known) begin
            n_skipped++;
            return;
        end
        if (t.addr[15:0] == 16'h0044)
            n_status_reads++;
        if (t.addr[15:0] >= 16'h0050 && t.addr[15:0] <= 16'h006C)
            n_hash_reads++;
        if (t.rdata !== exp) begin
            n_errors++;
            `uvm_error("SHA_SB", $sformatf("read 0x%04h at %0t: DUT 0x%08h, model 0x%08h", t.addr[15:0],
                                           t.accept_time, t.rdata, exp))
        end
    endfunction

    function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info("SHA_SB", $sformatf("%0d writes, %0d STARTs, %0d reads checked (%0d STATUS, %0d HASH), %0d skipped, %0d errors",
                                      n_writes, n_starts, n_reads - n_skipped, n_status_reads, n_hash_reads,
                                      n_skipped, n_errors), UVM_LOW)
        if (n_starts == 0)
            `uvm_error("SHA_SB", "no START seen: the scoreboard checked nothing")
    endfunction
endclass
