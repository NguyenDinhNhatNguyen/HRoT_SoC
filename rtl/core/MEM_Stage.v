`timescale 1ns / 1ps

module MEM_Stage(
    input         clk,
    //Inputs tu EX_MEM_Reg
    input         RegWrite_MEM,
    input         MemWrite_MEM,
    input         MemRead_MEM,
    input  [1:0]  ResultSrc_MEM,

    input  [31:0] ALUResult_MEM,
    input  [31:0] WriteData_MEM,
    input  [31:0] PC_Plus_4_MEM,
    input  [31:0] PCTarget_MEM,
    input  [4:0]  Rd_MEM,
    input  [2:0]  funct3_MEM,     // 000 B, 001 H, 010 W, 100 BU, 101 HU
    //AXI interface
    input  [31:0] data_rdata,     // Word 32-bit can le chua dia chi data_addr

    output [31:0] data_addr,
    output [31:0] data_wdata,
    output [3:0]  data_wstrb,     // Byte lane duoc ghi (bit i <-> data_wdata[8*i+7:8*i])
    output        data_we,
    output        data_re,
    //Outputs den MEM_WB_Reg
    output        RegWrite_MEM_out,
    output [1:0]  ResultSrc_MEM_out,
    output [31:0] ALUResult_MEM_out,
    output [31:0] ReadData_MEM_out,
    output [31:0] PC_Plus_4_MEM_out,
    output [31:0] PCTarget_MEM_out,
    output [4:0]  Rd_MEM_out
);

//MEM -> MEM/WB pass-through
assign RegWrite_MEM_out  = RegWrite_MEM;
assign ResultSrc_MEM_out = ResultSrc_MEM;
assign ALUResult_MEM_out = ALUResult_MEM;
assign PC_Plus_4_MEM_out = PC_Plus_4_MEM;
assign PCTarget_MEM_out  = PCTarget_MEM;
assign Rd_MEM_out        = Rd_MEM;

//Data Memory interface
// Truy cap lech le (LH/SH o dia chi le, LW/SW khong chia het cho 4) khong duoc ho tro:
// khong co trap, ket qua khong xac dinh. Compiler khong sinh truy cap lech le cho du lieu can le.
wire [1:0] byte_off = ALUResult_MEM[1:0];

assign data_addr  = ALUResult_MEM;
assign data_we    = MemWrite_MEM;
assign data_re    = MemRead_MEM;

// Store: lap byte/half len moi lane, WSTRB chon lane theo dia chi
assign data_wdata = (funct3_MEM[1:0] == 2'b00) ? {4{WriteData_MEM[7:0]}}  : // SB
                    (funct3_MEM[1:0] == 2'b01) ? {2{WriteData_MEM[15:0]}} : // SH
                                                 WriteData_MEM;             // SW

assign data_wstrb = (funct3_MEM[1:0] == 2'b00) ? (4'b0001 << byte_off)          : // SB
                    (funct3_MEM[1:0] == 2'b01) ? (byte_off[1] ? 4'b1100 : 4'b0011) : // SH
                                                 4'b1111;                          // SW

// Load: dich byte/half can doc ve bit [7:0]/[15:0] roi mo rong dau hoac mo rong 0
wire [31:0] rdata_shifted = data_rdata >> {byte_off, 3'b000};
reg  [31:0] load_data;

always @(*) begin
    case (funct3_MEM)
        3'b000:  load_data = {{24{rdata_shifted[7]}},  rdata_shifted[7:0]};  // LB
        3'b001:  load_data = {{16{rdata_shifted[15]}}, rdata_shifted[15:0]}; // LH
        3'b100:  load_data = {24'b0, rdata_shifted[7:0]};                    // LBU
        3'b101:  load_data = {16'b0, rdata_shifted[15:0]};                   // LHU
        default: load_data = data_rdata;                                     // LW
    endcase
end

assign ReadData_MEM_out = load_data;

endmodule
