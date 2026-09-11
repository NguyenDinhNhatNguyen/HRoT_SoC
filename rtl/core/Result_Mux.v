`timescale 1ns / 1ps

module Result_Mux(
    input  wire [31:0] ALUResult,
    input  wire [31:0] ReadData,
    input  wire [31:0] PC_Plus_4,
    input  wire [31:0] ResultSrc,

    output wire [31:0] Result
);

assign Result = ResultSrc[1] ? PC_Plus_4 : (ResultSrc[0] ? ReadData : ALUResult);

endmodule