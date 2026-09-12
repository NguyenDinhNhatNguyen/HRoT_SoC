`timescale 1ns / 1ps

module Result_Mux(
    input   [31:0] ALUResult,
    input   [31:0] ReadData,
    input   [31:0] PC_Plus_4,
    input   [31:0] PCTarget,
    input   [1:0]  ResultSrc,

    output  [31:0] Result
);

assign Result = (ResultSrc == 2'b00) ? ALUResult :
                (ResultSrc == 2'b01) ? ReadData :
                (ResultSrc == 2'b10) ? PC_Plus_4 : 
                                       PCTarget; // ResultSrc == 2'b11

endmodule