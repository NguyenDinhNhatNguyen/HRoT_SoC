`timescale 1ns / 1ps

module PC (	
		input 	        clk, rst,
        // Pipeline control 
        input           stall,          // Dong bang PC (Load-Use Hazard / Bus stall)
        input           flush,          // Ep nhay PC (Branch/Jalr resolve o EX)
		input   [31:0]  PCNext,
        input   [31:0]  PCflush_target, // Dia chi dung khi flush (tu tang EX)
		output  [31:0]  PC
);
   
reg [31:0] PCReg;

always@(posedge clk or posedge rst) begin
	if (rst) begin
        PCReg <= 32'h0000_0000;
    end
	else if (flush) begin 
        PCReg <= PCflush_target;            // Uu tien 1: Correct Branch/Jump Target
    end
    else if (!stall) begin
        PCReg <= PCNext;                    // Uu tien 2: Cap nhat luong lenh tiep theo
    end
    // else: Giu nguyen PCReg khi stall = 1
end

assign PC = PCReg;

endmodule