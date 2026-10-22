// ============================================================================
// Thư viện sequence AXI4-Lite
// ============================================================================

// Lớp cơ sở: cung cấp write_word / read_word để các sequence dùng lại
class axi4_lite_base_seq extends uvm_sequence #(axi4_lite_item);
  `uvm_object_utils(axi4_lite_base_seq)

  function new(string name = "axi4_lite_base_seq");
    super.new(name);
  endfunction

  // Ghi 1 word (delay = 0 để giao dịch có định hướng chạy nhanh và dễ đọc waveform)
  task write_word(bit [31:0] a, bit [31:0] d, bit [3:0] s = 4'hF);
    axi4_lite_item t = axi4_lite_item::type_id::create("wr");
    start_item(t);
    if (!t.randomize() with { is_write == 1; addr == a; data == d; wstrb == s;
                              addr_delay == 0; data_delay == 0; resp_delay == 0; })
      `uvm_fatal("RAND", "randomize() that bai (write_word)")
    finish_item(t);
  endtask

  // Đọc 1 word, trả dữ liệu về d
  task read_word(bit [31:0] a, output bit [31:0] d);
    axi4_lite_item t = axi4_lite_item::type_id::create("rd");
    start_item(t);
    if (!t.randomize() with { is_write == 0; addr == a;
                              addr_delay == 0; data_delay == 0; resp_delay == 0; })
      `uvm_fatal("RAND", "randomize() that bai (read_word)")
    finish_item(t);
    d = t.rdata;
  endtask
endclass


// 1 giao dịch ghi + 1 giao dịch đọc lại (Mốc 2 của Tuần 5)
class axi4_lite_smoke_seq extends axi4_lite_base_seq;
  `uvm_object_utils(axi4_lite_smoke_seq)

  function new(string name = "axi4_lite_smoke_seq");
    super.new(name);
  endfunction

  task body();
    bit [31:0] rd;
    write_word(32'h0000_1000, 32'hDEADBEEF);
    read_word (32'h0000_1000, rd);
    if (rd !== 32'hDEADBEEF)
      `uvm_error("SMOKE", $sformatf("Doc lai sai: expected=0xDEADBEEF actual=0x%08h", rd))
    else
      `uvm_info("SMOKE", "Ghi 0xDEADBEEF @0x1000 va doc lai khop", UVM_LOW)
  endtask
endclass


// Kiểm tra WSTRB: ghi từng phần byte rồi đọc lại
class axi4_lite_wstrb_seq extends axi4_lite_base_seq;
  `uvm_object_utils(axi4_lite_wstrb_seq)

  function new(string name = "axi4_lite_wstrb_seq");
    super.new(name);
  endfunction

  task body();
    bit [31:0] rd;
    bit [31:0] a = 32'h0000_2000;

    write_word(a, 32'h11223344, 4'b1111);
    write_word(a, 32'hAABBCCDD, 4'b0101);   // byte0 và byte2
    read_word (a, rd);
    if (rd !== 32'h11BB33DD)
      `uvm_error("WSTRB", $sformatf("strb=0101: expected=0x11BB33DD actual=0x%08h", rd))

    write_word(a, 32'h99000000, 4'b1000);   // chỉ byte3
    read_word (a, rd);
    if (rd !== 32'h99BB33DD)
      `uvm_error("WSTRB", $sformatf("strb=1000: expected=0x99BB33DD actual=0x%08h", rd))

    write_word(a, 32'hFFFFFFFF, 4'b0000);   // không byte nào -> giữ nguyên
    read_word (a, rd);
    if (rd !== 32'h99BB33DD)
      `uvm_error("WSTRB", $sformatf("strb=0000: expected=0x99BB33DD actual=0x%08h", rd))
  endtask
endclass


// Ngẫu nhiên có ràng buộc: địa chỉ trong một cửa sổ nhỏ để có đọc-sau-ghi,
// WSTRB và độ trễ các kênh ngẫu nhiên để ép các thứ tự handshake khác nhau
class axi4_lite_rand_seq extends axi4_lite_base_seq;
  `uvm_object_utils(axi4_lite_rand_seq)

  int unsigned num_trans = 50;
  bit [31:0]   base_addr = 32'h0000_3000;
  int unsigned num_words = 16;

  function new(string name = "axi4_lite_rand_seq");
    super.new(name);
  endfunction

  task body();
    axi4_lite_item t;
    repeat (num_trans) begin
      t = axi4_lite_item::type_id::create("rnd");
      start_item(t);
      if (!t.randomize() with {
            addr inside {[base_addr : base_addr + 4 * (num_words - 1)]};
            is_write dist { 1 := 5, 0 := 5 };
            wstrb    dist { 4'hF := 6, [4'h0 : 4'hE] :/ 4 };
            addr_delay dist { 0 := 6, [1:3] := 3, [4:8] := 1 };
            data_delay dist { 0 := 6, [1:3] := 3, [4:8] := 1 };
            resp_delay dist { 0 := 6, [1:3] := 3, [4:8] := 1 };
          })
        `uvm_fatal("RAND", "randomize() that bai (rand_seq)")
      finish_item(t);
    end
  endtask
endclass