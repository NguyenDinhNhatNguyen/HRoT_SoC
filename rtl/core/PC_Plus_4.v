`timescale 1ns / 1ps

module PC_Plus_4(
	input wire [31:0]  PC,
	output wire [31:0] PCPlus4 
);

assign PCPlus4 = PC + 32'd4;

endmodule