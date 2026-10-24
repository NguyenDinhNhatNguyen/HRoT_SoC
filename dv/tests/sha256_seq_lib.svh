// Sequence AXI4-Lite cho SHA256_Wrapper (P-08): bam message theo dung luong cua HAL, them do tre
// AXI ngau nhien va cac corner case trong docs/verification/SHA256_UVM_TestPlan.md. Moi sequence tu kiem tra
// ket qua bang sha256_ref (SV); scoreboard SHA dung DPI la viec P-17.
// Ban do thanh ghi: docs/spec/SHA256_Register_Map.md, I-05 (offset trong trong 0x00-0xFF: OKAY, doc 0).

class sha256_base_seq extends axi4_lite_base_seq;
  `uvm_object_utils(sha256_base_seq)

  localparam bit [31:0] BASE   = 32'h5000_0000;
  localparam bit [31:0] CTRL   = 32'h40;
  localparam bit [31:0] STATUS = 32'h44;
  localparam bit [31:0] HASH0  = 32'h50;
  localparam bit [31:0] START  = 32'h1;
  localparam bit [31:0] INIT   = 32'h2;

  bit          rand_delay = 1;      // do tre AXI ngau nhien 0-8 chu ky moi kenh
  int unsigned poll_limit = 500;    // so lan doc STATUS toi da khi cho DONE

  // Thong ke (cong don qua cac lan start trong cung test)
  int unsigned n_msgs, n_blocks, n_checks, n_errors, n_restart;

  virtual axi4_lite_if vif;
  bit          aborted;             // co giao dich bi driver huy do reset trong thao tac hien tai
  string       pend_err[$];         // loi gom lai, chi bao khi thao tac khong bi reset cat ngang

  function new(string name = "sha256_base_seq");
    super.new(name);
  endfunction

  task pre_body();
    if (vif == null && !uvm_config_db#(virtual axi4_lite_if)::get(null, get_full_name(), "vif", vif))
      `uvm_fatal("SHA_SEQ", "Khong tim thay virtual interface 'vif'")
  endtask

  // Mot giao dich ghi/doc tai BASE + off; ghi nhan aborted va response khac OKAY
  task axi_op(bit is_wr, bit [31:0] off, bit [31:0] wdata, output bit [31:0] rdata);
    axi4_lite_item t = axi4_lite_item::type_id::create("sha_item");
    start_item(t);
    if (!t.randomize() with {
          is_write == is_wr; addr == BASE + off; data == wdata; wstrb == 4'hF;
          if (rand_delay) {
            addr_delay dist { 0 := 6, [1:3] := 3, [4:8] := 1 };
            data_delay dist { 0 := 6, [1:3] := 3, [4:8] := 1 };
            resp_delay dist { 0 := 6, [1:3] := 3, [4:8] := 1 };
          } else {
            addr_delay == 0; data_delay == 0; resp_delay == 0;
          } })
      `uvm_fatal("RAND", "randomize() that bai (sha256 axi_op)")
    finish_item(t);
    rdata = t.rdata;
    if (t.aborted) aborted = 1;
    else check((is_wr ? t.bresp : t.rresp) == 2'b00,
               $sformatf("%s off=0x%02h: response %0d, mong doi OKAY (I-05)",
                         is_wr ? "Ghi" : "Doc", off, is_wr ? t.bresp : t.rresp));
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
    if (!ok) pend_err.push_back(msg);
  endfunction

  // Bao cac loi da gom (discard = 1 khi thao tac bi reset cat ngang, ket qua khong co nghia)
  function void flush_checks(bit discard);
    if (!discard)
      foreach (pend_err[i]) begin
        n_errors++;
        `uvm_error("SHA_SEQ", pend_err[i])
      end
    pend_err.delete();
  endfunction

  // Doc STATUS den khi DONE; kiem BUSY va DONE khong cung bang 1
  task wait_done(output int unsigned polls);
    bit [31:0] st;
    polls = 0;
    do begin
      rd(STATUS, st);
      polls++;
      check(!(st[0] && st[1]), $sformatf("STATUS=0x%0h: DONE va BUSY cung bang 1", st));
      if (aborted) return;
    end while (!st[0] && polls < poll_limit);
    check(st[0] == 1'b1, $sformatf("Khong thay DONE sau %0d lan doc STATUS", polls));
  endtask

  // Cho DUT het BUSY (khong kiem tra gi): dung truoc khi bam lai message bi reset cat ngang,
  // vi reset co the roi vao giua hai giao dich va START cu van dang chay.
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

  // Ghi 16 word cua block (thu tu tuy chon), START (+INIT), cho DONE.
  // shuffle: ghi BLOCK theo thu tu ngau nhien; interleave: chen doc STATUS giua cac lan ghi (F-AXI-03)
  task hash_block(bit [511:0] blk, bit init, bit shuffle, bit interleave);
    int unsigned order[$];
    bit [31:0]   st;
    int unsigned polls;
    rd(STATUS, st);
    check(st[1] == 1'b0, "BUSY = 1 truoc khi ghi block (HAL kiem BUSY truoc)");
    for (int i = 0; i < 16; i++) order.push_back(i);
    if (shuffle) order.shuffle();
    foreach (order[k]) begin
      wr(4 * order[k], blk[511 - 32*order[k] -: 32]);
      if (aborted) return;                     // reset cat ngang: khong ghi tiep, khong START
      if (interleave && ($urandom_range(3, 0) == 0)) begin
        rd(STATUS, st);
        check(st[1] == 1'b0, "BUSY = 1 khi dang ghi BLOCK (chua START)");
      end
    end
    if (aborted) return;
    wr(CTRL, init ? (START | INIT) : START);
    // START xoa DONE va dat BUSY ngay khi ghi duoc chap nhan (hop dong HAL #3)
    rd(STATUS, st);
    check(st[1:0] == 2'b10, $sformatf("Ngay sau START: STATUS=0x%0h, mong doi BUSY=1 DONE=0", st));
    wait_done(polls);
    n_blocks++;
  endtask

  task read_hash(output bit [255:0] hv, input bit shuffle);
    int unsigned order[$];
    bit [31:0]   w;
    for (int i = 0; i < 8; i++) order.push_back(i);
    if (shuffle) order.shuffle();
    foreach (order[k]) begin
      rd(HASH0 + 4 * order[k], w);
      hv[255 - 32*order[k] -: 32] = w;
    end
  endtask

  // Bam ca message theo luong cua HAL va so voi mo hinh tham chieu.
  // ok = 0 neu bi reset cat ngang (goi lai). Corner case chon ngau nhien neu rand_opts = 1.
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
      if (aborted) break;
      // Doc HASH giua cac block (chua phai ket qua cuoi): khong duoc treo bus (F-CTL-07)
      if (rand_opts && k + 1 < blocks.size() && $urandom_range(3, 0) == 0)
        rd(HASH0 + 4 * $urandom_range(7, 0), w);
    end
    if (!aborted) read_hash(got, rand_opts);
    exp = sha256_ref::digest(msg);
    ok = !aborted && vif.reset_count == rst0;
    if (ok) check(got == exp, $sformatf("Hash sai, len=%0d: got %h exp %h", msg.size(), got, exp));
    flush_checks(!ok);
    if (ok) n_msgs++;
    else    n_restart++;
  endtask

  function void report(string name);
    `uvm_info("SHA_SEQ", $sformatf("%s: %0d message, %0d block, %0d check, %0d loi, %0d lan bam lai do reset",
                                   name, n_msgs, n_blocks, n_checks, n_errors, n_restart), UVM_LOW)
  endfunction
endclass


// Vector NIST co dap an cung (khong phu thuoc mo hinh SV): rong, "abc", 56 byte (2 block)
class sha256_kat_seq extends sha256_base_seq;
  `uvm_object_utils(sha256_kat_seq)

  function new(string name = "sha256_kat_seq");
    super.new(name);
  endfunction

  task run_kat(string s, bit [255:0] exp);
    byte unsigned msg[$];
    bit          ok;
    foreach (s[i]) msg.push_back(s[i]);
    if (sha256_ref::digest(msg) != exp)
      `uvm_fatal("SHA_REF", $sformatf("Mo hinh SV sai voi vector NIST len=%0d", msg.size()))
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


// Message ngau nhien: do dai co trong so vao bien padding (55/56/63/64/119/120...), noi dung
// ngau nhien, do tre AXI ngau nhien, thu tu ghi BLOCK/doc HASH ngau nhien, doc STATUS xen ke.
// Bi reset giua chung (+RESET_AT_NS) thi bam lai message do (F-RST-01).
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
      6: return corners[$urandom_range(corners.size() - 1, 0)];
      3: return $urandom_range(300, 1);
      1: return $urandom_range(max_len, 301);
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
      repeat (len) msg.push_back(8'($urandom()));
      tries = 0;
      do begin
        if (tries > 0) wait_idle();
        hash_message(msg, ok);
        tries++;
      end while (!ok && tries < 3);
      if (!ok) `uvm_error("SHA_SEQ", $sformatf("Message len=%0d bi reset cat ngang 3 lan lien tiep", len))
    end
    report("RAND");
  endtask
endclass


// Corner case dieu khien (F-CTL-01..07, F-HASH-04, F-REG-03/04) tren block ngau nhien.
// Ky thuat: START lai ma KHONG ghi lai BLOCK -> DUT bam lai noi dung block dang giu, nen biet chinh
// xac lan ghi BLOCK luc BUSY co bi bo qua khong, va INIT co nap lai IV khong.
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
    check(st[1:0] == 2'b10, $sformatf("Ngay sau START: STATUS=0x%0h, mong doi BUSY=1 DONE=0", st));
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
      for (int i = 0; i < 16; i++) blk[511 - 32*i -: 32] = $urandom();
      h1 = sha256_ref::compress(SHA256_IV, blk);
      h2 = sha256_ref::compress(h1, blk);

      // 1. Block A + START|INIT; trong luc BUSY: ghi rac vao BLOCK, START lan 2, doc HASH som
      for (int i = 0; i < 16; i++) wr(4 * i, blk[511 - 32*i -: 32]);
      wr(CTRL, START | INIT);
      // 3 giao dich duoi phai roi vao luc DUT con BUSY (66 chu ky): tat do tre de chac chan
      rand_delay = 0;
      wr(4 * $urandom_range(15, 0), $urandom());                       // F-CTL-06: phai bi bo qua
      wr(CTRL, ($urandom_range(1, 0) ? START : (START | INIT)));      // F-CTL-05: phai bi bo qua
      rd(HASH0 + 4 * $urandom_range(7, 0), w);                        // F-CTL-07: khong treo
      rd(STATUS, st);
      check(st[1] == 1'b1, "DUT da het BUSY truoc khi kiem xong corner case luc BUSY (tang thoi gian?)");
      rand_delay = 1;
      begin int unsigned p; wait_done(p); end
      expect_hash(h1, "Block A (rac/START khi BUSY phai bi bo qua)");

      // 2. DONE sticky: doc STATUS nhieu lan van DONE=1 BUSY=0 (F-CTL-03)
      repeat ($urandom_range(4, 2)) begin
        rd(STATUS, st);
        check(st[1:0] == 2'b01, $sformatf("DONE phai sticky: STATUS=0x%0h", st));
      end

      // 3. Ghi CTRL khong co START (chi INIT, hoac 0): khong chay, khong doi trang thai (F-CTL-01)
      wr(CTRL, $urandom_range(1, 0) ? INIT : 32'h0);
      rd(STATUS, st);
      check(st[1:0] == 2'b01, $sformatf("CTRL khong START lam doi STATUS=0x%0h", st));
      expect_hash(h1, "Sau ghi CTRL khong START");

      // 4. Ghi vao thanh ghi chi doc (STATUS, HASH) va offset trong 0x48/0x4C/0x70-0xFC:
      //    doc ra 0, khong tac dung phu (F-REG-03/04, I-05)
      wr(STATUS, $urandom());
      wr(HASH0 + 4 * $urandom_range(7, 0), $urandom());
      begin
        bit [31:0] holes[$] = '{32'h48, 32'h4C};
        holes.push_back(32'h70 + 4 * $urandom_range(35, 0));         // 0x70 .. 0xFC
        foreach (holes[i]) begin
          wr(holes[i], $urandom());
          rd(holes[i], w);
          check(w == 32'h0, $sformatf("Offset trong 0x%02h doc ra 0x%08h, mong doi 0", holes[i], w));
        end
      end
      expect_hash(h1, "Sau ghi vao thanh ghi chi doc / offset trong");

      // 5. START khong INIT, khong ghi lai BLOCK: noi tiep tu H1 tren cung block (chaining)
      start_and_wait(START);
      expect_hash(h2, "Chaining (START khong INIT, block giu nguyen)");

      // 6. START|INIT, khong ghi lai BLOCK: INIT nap lai IV -> lai ra H1 (F-HASH-04)
      start_and_wait(START | INIT);
      expect_hash(h1, "INIT nap lai IV");
      flush_checks(0);
    end
    report("CTL");
  endtask
endclass


// Offset >= 0x100 trong cua so 64 KB cua SHA tren bus Master (SoC_Top giai ma [31:16]).
// Theo I-05 phai doc 0 va ghi bi bo qua. Wrapper hien chi giai ma addr[7:0] nen cac offset nay
// bi aliasing vao thanh ghi that -> test nay dang FAIL, cho Nguyen sua RTL (khong nam trong make test).
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
    for (int i = 0; i < 16; i++) blk[511 - 32*i -: 32] = $urandom();
    h1 = sha256_ref::compress(SHA256_IV, blk);
    for (int i = 0; i < 16; i++) wr(4 * i, blk[511 - 32*i -: 32]);
    start_and_wait(START | INIT);
    expect_hash(h1, "Block goc");
    foreach (offs[i]) begin
      rd(offs[i], w);
      check(w == 32'h0, $sformatf("Offset 0x%04h doc ra 0x%08h, mong doi 0 (I-05)", offs[i], w));
      wr(offs[i], 32'hDEAD_BEEF);
    end
    // Neu ghi 0x100/0x13C bi alias vao BLOCK hoac 0x140 vao CTRL thi hash duoi day se sai
    start_and_wait(START | INIT);
    expect_hash(h1, "Ghi offset >= 0x100 khong duoc doi BLOCK/CTRL");
    flush_checks(0);
    report("ALIAS");
  endtask
endclass
