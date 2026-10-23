// Cấu hình dùng chung cho agent / driver / monitor / scoreboard
class axi4_lite_agent_cfg extends uvm_object;
  `uvm_object_utils(axi4_lite_agent_cfg)

  virtual axi4_lite_if    vif;
  uvm_active_passive_enum is_active          = UVM_ACTIVE;
  int unsigned            timeout_cycles     = 2000;  // chờ tối đa mỗi handshake
  bit                     check_resp         = 1'b1;  // scoreboard yêu cầu BRESP/RRESP = OKAY
  bit [31:0]              default_read_value = 32'h0; // giá trị đọc của địa chỉ chưa ghi

  function new(string name = "axi4_lite_agent_cfg");
    super.new(name);
  endfunction
endclass
