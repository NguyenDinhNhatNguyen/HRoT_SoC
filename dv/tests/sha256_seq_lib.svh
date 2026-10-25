// AXI4-Lite sequences for SHA256_Wrapper (P-08): hash messages with the same flow as the HAL, add random
// AXI delays and the corner cases of docs/verification/SHA256_UVM_TestPlan.md. Every sequence checks its
// results against sha256_ref (SV). The DPI SHA scoreboard is task P-17.
// Register map: docs/spec/SHA256_Register_Map.md, I-05 (empty offsets in 0x00-0xFF: OKAY, read 0).

class sha256_base_seq extends axi4_lite_base_seq;
    `uvm_object_utils(sha256_base_seq)

    localparam bit [31:0] BASE   = 32'h5000_0000;
    localparam bit [31:0] CTRL   = 32'h40;
    localparam bit [31:0] STATUS = 32'h44;
    localparam bit [31:0] HASH0  = 32'h50;
    localparam bit [31:0] START  = 32'h1;
    localparam bit [31:0] INIT   = 32'h2;

    bit          rand_delay = 1;      // random AXI delay of 0-8 cycles per channel
    int unsigned poll_limit = 500;    // max STATUS reads while waiting for DONE

    // Statistics (accumulated over every start in the same test)
    int unsigned n_msgs, n_blocks, n_checks, n_errors, n_restart;

    virtual axi4_lite_if vif;
    bit          aborted;             // a transaction of the current operation was aborted by reset
    string       pend_err[$];         // collected errors, reported only if no reset cut the operation

    function new(string name = "sha256_base_seq");
        super.new(name);
    endfunction

    task pre_body();
        if (vif == null && !uvm_config_db#(virtual axi4_lite_if)::get(null, get_full_name(), "vif", vif))
            `uvm_fatal("SHA_SEQ", "virtual interface 'vif' not found")
    endtask

    // One write/read at BASE + off. Records aborted and any non-OKAY response
    task axi_op(bit is_wr, bit [31:0] off, bit [31:0] wdata, output bit [31:0] rdata);
        axi4_lite_item t = axi4_lite_item::type_id::create("sha_item");
        start_item(t);
        if (!t.randomize() with {
                    is_write == is_wr;
                    addr == BASE + off;
                    data == wdata;
                    wstrb == 4'hF;
                    if (rand_delay) {
                        addr_delay dist { 0 := 6, [1:3] := 3, [4:8] := 1 };
                        data_delay dist { 0 := 6, [1:3] := 3, [4:8] := 1 };
                        resp_delay dist { 0 := 6, [1:3] := 3, [4:8] := 1 };
                    } else {
                        addr_delay == 0;
                        data_delay == 0;
                        resp_delay == 0;
                    } })
            `uvm_fatal("RAND", "randomize() failed (sha256 axi_op)")
        finish_item(t);
        rdata = t.rdata;
        if (t.aborted)
            aborted = 1;
        else
            check((is_wr ? t.bresp : t.rresp) == 2'b00,
                              $sformatf("%s off=0x%02h: response %0d, expected OKAY (I-05)",
                                                  is_wr ? "Write" : "Read", off, is_wr ? t.bresp : t.rresp));
    endtask

    task wr(bit [31:0] off, bit [31:0] data);
        bit [31:0] unused;
        axi_op(1'b1, off, data, unused);
    endtask

    task rd(bit [31:0] off, output bit [31:0] data);
        axi_op(1'b0, off, 32'h0, data);
    endtask

    function void check(bit ok, string msg);
        n_checks++;
        if (!ok)
            pend_err.push_back(msg);
    endfunction

    // Report the collected errors (discard = 1 when a reset cut the operation and the result means nothing)
    function void flush_checks(bit discard);
        if (!discard)
            foreach (pend_err[i]) begin
                n_errors++;
                `uvm_error("SHA_SEQ", pend_err[i])
            end
        pend_err.delete();
    endfunction

    // Read STATUS until DONE, check BUSY and DONE are never both 1
    task wait_done(output int unsigned polls);
        bit [31:0] st;
        polls = 0;
        do begin
            rd(STATUS, st);
            polls++;
            check(!(st[0] && st[1]), $sformatf("STATUS=0x%0h: DONE and BUSY both 1", st));
            if (aborted)
                return;
        end while (!st[0] && polls < poll_limit);
        check(st[0] == 1'b1, $sformatf("No DONE after %0d STATUS reads", polls));
    endtask

    // Wait until the DUT is not BUSY (no checks). Used before re-hashing a message cut by reset,
    // because the reset may land between two transactions while the old START is still running.
    task wait_idle();
        bit [31:0]   st;
        int unsigned polls = 0;
        do begin
            aborted = 0;
            rd(STATUS, st);
            polls++;
        end while ((aborted || st[1]) && polls < poll_limit);
        pend_err.delete();
    endtask

    // Write the 16 block words (in any order), START (+INIT), wait for DONE.
    // shuffle: write BLOCK in random order. interleave: read STATUS between the writes (F-AXI-03)
    task hash_block(bit [511:0] blk, bit init, bit shuffle, bit interleave);
        int unsigned order[$];
        bit [31:0]   st;
        int unsigned polls;
        rd(STATUS, st);
        check(st[1] == 1'b0, "BUSY = 1 before writing the block (the HAL checks BUSY first)");
        for (int i = 0; i < 16; i++)
            order.push_back(i);
        if (shuffle)
            order.shuffle();
        foreach (order[k]) begin
            wr(4 * order[k], blk[511 - 32*order[k] -: 32]);
            if (aborted)
                return; // cut by reset: stop writing, no START
            if (interleave && ($urandom_range(3, 0) == 0)) begin
                rd(STATUS, st);
                check(st[1] == 1'b0, "BUSY = 1 while writing BLOCK (before START)");
            end
        end
        if (aborted)
            return;
        wr(CTRL, init ? (START | INIT) : START);
        // START clears DONE and sets BUSY as soon as the write is accepted (HAL contract #3)
        rd(STATUS, st);
        check(st[1:0] == 2'b10, $sformatf("Right after START: STATUS=0x%0h, expected BUSY=1 DONE=0", st));
        wait_done(polls);
        n_blocks++;
    endtask

    task read_hash(output bit [255:0] hv, input bit shuffle);
        int unsigned order[$];
        bit [31:0]   w;
        for (int i = 0; i < 8; i++)
            order.push_back(i);
        if (shuffle)
            order.shuffle();
        foreach (order[k]) begin
            rd(HASH0 + 4 * order[k], w);
            hv[255 - 32*order[k] -: 32] = w;
        end
    endtask

    // Hash a whole message with the HAL flow and compare with the reference model.
    // ok = 0 if a reset cut it (call again). Corner cases are picked at random if rand_opts = 1.
    task hash_message(byte unsigned msg[$], output bit ok, input bit rand_opts = 1);
        bit [511:0]  blocks[$];
        bit [255:0]  got, exp;
        bit [31:0]   w;
        int unsigned rst0 = vif.reset_count;
        aborted = 0;
        sha256_ref::pad(msg, blocks);
        foreach (blocks[k]) begin
            bit sh = rand_opts && $urandom_range(1, 0);
            bit il = rand_opts && ($urandom_range(3, 0) == 0);
            hash_block(blocks[k], k == 0, sh, il);
            if (aborted)
                break;
            // Read HASH between blocks (not the final result yet): the bus must not hang (F-CTL-07)
            if (rand_opts && k + 1 < blocks.size() && $urandom_range(3, 0) == 0)
                rd(HASH0 + 4 * $urandom_range(7, 0), w);
        end
        if (!aborted)
            read_hash(got, rand_opts);
        exp = sha256_ref::digest(msg);
        ok = !aborted && vif.reset_count == rst0;
        if (ok)
            check(got == exp, $sformatf("Hash mismatch, len=%0d: got %h exp %h", msg.size(), got, exp));
        flush_checks(!ok);
        if (ok)
            n_msgs++;
        else
            n_restart++;
    endtask

    function void report(string name);
        `uvm_info("SHA_SEQ", $sformatf("%s: %0d messages, %0d blocks, %0d checks, %0d errors, %0d re-hashes after reset",
                                                                      name, n_msgs, n_blocks, n_checks, n_errors, n_restart), UVM_LOW)
    endfunction
endclass


// NIST vectors with hard-coded answers (independent of the SV model): empty, "abc", 56 bytes (2 blocks)
class sha256_kat_seq extends sha256_base_seq;
    `uvm_object_utils(sha256_kat_seq)

    function new(string name = "sha256_kat_seq");
        super.new(name);
    endfunction

    task run_kat(string s, bit [255:0] exp);
        byte unsigned msg[$];
        bit          ok;
        foreach (s[i])
            msg.push_back(s[i]);
        if (sha256_ref::digest(msg) != exp)
            `uvm_fatal("SHA_REF", $sformatf("SV model disagrees with the NIST vector len=%0d", msg.size()))
        hash_message(msg, ok, 0);
    endtask

    task body();
        run_kat("",    256'he3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855);
        run_kat("abc", 256'hba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad);
        run_kat("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq",
                                      256'h248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1);
        report("KAT");
    endtask
endclass


// Random messages: lengths weighted toward the padding edges (55/56/63/64/119/120...), random
// content, random AXI delays, random BLOCK write and HASH read order, interleaved STATUS reads.
// A message cut by reset (+RESET_AT_NS) is hashed again (F-RST-01).
class sha256_rand_seq extends sha256_base_seq;
    `uvm_object_utils(sha256_rand_seq)

    int unsigned num_msgs = 40;
    int unsigned max_len  = 600;

    function new(string name = "sha256_rand_seq");
        super.new(name);
    endfunction

    function int unsigned pick_len();
        int unsigned corners[$] = '{0, 1, 55, 56, 57, 63, 64, 65, 119, 120, 127, 128, 183, 184, 191, 192};
        randcase
            6:
                return corners[$urandom_range(corners.size() - 1, 0)];
            3:
                return $urandom_range(300, 1);
            1:
                return $urandom_range(max_len, 301);
        endcase
        return 0;
    endfunction

    task body();
        byte unsigned msg[$];
        bit           ok;
        int unsigned  len, tries;
        repeat (num_msgs) begin
            len = pick_len();
            msg.delete();
            repeat (len)
                msg.push_back(8'($urandom()));
            tries = 0;
            do begin
                if (tries > 0)
                    wait_idle();
                hash_message(msg, ok);
                tries++;
            end while (!ok && tries < 3);
            if (!ok)
                `uvm_error("SHA_SEQ", $sformatf("Message len=%0d cut by reset 3 times in a row", len))
        end
        report("RAND");
    endtask
endclass


// Control corner cases (F-CTL-01..07, F-HASH-04, F-REG-03/04) on random blocks.
// Method: START again WITHOUT rewriting BLOCK -> the DUT hashes the block it holds, which shows exactly
// whether a BLOCK write during BUSY was ignored and whether INIT reloads the IV.
class sha256_ctl_seq extends sha256_base_seq;
    `uvm_object_utils(sha256_ctl_seq)

    int unsigned num_iter = 8;

    function new(string name = "sha256_ctl_seq");
        super.new(name);
    endfunction

    task start_and_wait(bit [31:0] ctrl);
        bit [31:0]   st;
        int unsigned polls;
        wr(CTRL, ctrl);
        rd(STATUS, st);
        check(st[1:0] == 2'b10, $sformatf("Right after START: STATUS=0x%0h, expected BUSY=1 DONE=0", st));
        wait_done(polls);
    endtask

    task expect_hash(bit [255:0] exp, string what);
        bit [255:0] got;
        read_hash(got, 1);
        check(got == exp, $sformatf("%s: got %h exp %h", what, got, exp));
    endtask

    task body();
        bit [511:0] blk;
        bit [255:0] h1, h2;
        bit [31:0]  st, w;
        for (int it = 0; it < num_iter; it++) begin
            for (int i = 0; i < 16; i++)
                blk[511 - 32*i -: 32] = $urandom();
            h1 = sha256_ref::compress(SHA256_IV, blk);
            h2 = sha256_ref::compress(h1, blk);

            // 1. Block A + START|INIT. While BUSY: junk write to BLOCK, second START, early HASH read
            for (int i = 0; i < 16; i++)
                wr(4 * i, blk[511 - 32*i -: 32]);
            wr(CTRL, START | INIT);
            // The 3 transactions below must land while the DUT is BUSY (66 cycles): no delays, to be sure
            rand_delay = 0;
            wr(4 * $urandom_range(15, 0), $urandom());                       // F-CTL-06: must be ignored
            wr(CTRL, ($urandom_range(1, 0) ? START : (START | INIT)));      // F-CTL-05: must be ignored
            rd(HASH0 + 4 * $urandom_range(7, 0), w);                        // F-CTL-07: no hang
            rd(STATUS, st);
            check(st[1] == 1'b1, "DUT left BUSY before the BUSY corner cases finished (timing changed?)");
            rand_delay = 1;
            begin
                int unsigned p;
                wait_done(p);
            end
            expect_hash(h1, "Block A (junk/START during BUSY must be ignored)");

            // 2. DONE is sticky: repeated STATUS reads stay DONE=1 BUSY=0 (F-CTL-03)
            repeat ($urandom_range(4, 2)) begin
                rd(STATUS, st);
                check(st[1:0] == 2'b01, $sformatf("DONE must be sticky: STATUS=0x%0h", st));
            end

            // 3. CTRL write without START (INIT only, or 0): no run, no state change (F-CTL-01)
            wr(CTRL, $urandom_range(1, 0) ? INIT : 32'h0);
            rd(STATUS, st);
            check(st[1:0] == 2'b01, $sformatf("CTRL without START changed STATUS=0x%0h", st));
            expect_hash(h1, "After CTRL write without START");

            // 4. Writes to read-only registers (STATUS, HASH) and empty offsets 0x48/0x4C/0x70-0xFC:
            //    read 0, no side effects (F-REG-03/04, I-05)
            wr(STATUS, $urandom());
            wr(HASH0 + 4 * $urandom_range(7, 0), $urandom());
            begin
                bit [31:0] holes[$] = '{32'h48, 32'h4C};
                holes.push_back(32'h70 + 4 * $urandom_range(35, 0));         // 0x70 .. 0xFC
                foreach (holes[i]) begin
                    wr(holes[i], $urandom());
                    rd(holes[i], w);
                    check(w == 32'h0, $sformatf("Empty offset 0x%02h read 0x%08h, expected 0", holes[i], w));
                end
            end
            expect_hash(h1, "After writes to read-only registers / empty offsets");

            // 5. START without INIT, BLOCK not rewritten: chain from H1 on the same block
            start_and_wait(START);
            expect_hash(h2, "Chaining (START without INIT, same block)");

            // 6. START|INIT, BLOCK not rewritten: INIT reloads the IV -> H1 again (F-HASH-04)
            start_and_wait(START | INIT);
            expect_hash(h1, "INIT reloads the IV");
            flush_checks(0);
        end
        report("CTL");
    endtask
endclass


// Offsets >= 0x100 in the 64 KB SHA window on the Master bus (SoC_Top decodes [31:16]).
// I-05: they read 0 and writes are ignored. This found the addr[7:0]-only decode that aliased them
// onto real registers, fixed in RTL a968cce. Not part of make test.
class sha256_alias_seq extends sha256_ctl_seq;
    `uvm_object_utils(sha256_alias_seq)

    function new(string name = "sha256_alias_seq");
        super.new(name);
    endfunction

    task body();
        bit [511:0] blk;
        bit [255:0] h1;
        bit [31:0]  w;
        bit [31:0]  offs[$] = '{32'h100, 32'h13C, 32'h140, 32'h144, 32'h150, 32'h1000, 32'hFF44};
        for (int i = 0; i < 16; i++)
            blk[511 - 32*i -: 32] = $urandom();
        h1 = sha256_ref::compress(SHA256_IV, blk);
        for (int i = 0; i < 16; i++)
            wr(4 * i, blk[511 - 32*i -: 32]);
        start_and_wait(START | INIT);
        expect_hash(h1, "Original block");
        foreach (offs[i]) begin
            rd(offs[i], w);
            check(w == 32'h0, $sformatf("Offset 0x%04h read 0x%08h, expected 0 (I-05)", offs[i], w));
            wr(offs[i], 32'hDEAD_BEEF);
        end
        // If a write to 0x100/0x13C aliased onto BLOCK, or 0x140 onto CTRL, the hash below would be wrong
        start_and_wait(START | INIT);
        expect_hash(h1, "Writes to offsets >= 0x100 must not change BLOCK/CTRL");
        flush_checks(0);
        report("ALIAS");
    endtask
endclass
