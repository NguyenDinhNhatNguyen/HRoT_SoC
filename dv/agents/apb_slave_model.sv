`timescale 1ns/1ps
// Behavioural APB4 slave with wait states (P-17): 1 KB of RAM (256 words, PADDR[9:2]) with byte strobes.
// The real APB peripherals all answer with zero wait states, so this slave on the APB bus of
// tb_apb_top is what exercises PREADY low in the driver, the monitor and the decoder.
// PREADY waits 0..+APB_MAX_WAIT=<n> cycles at random (default 3). The write lands on the completing edge.
module apb_slave_model (
    input  logic        clk,
    input  logic        reset,
    input  logic [11:0] PADDR,
    input  logic        PSEL,
    input  logic        PENABLE,
    input  logic        PWRITE,
    input  logic [31:0] PWDATA,
    input  logic [3:0]  PSTRB,
    output logic [31:0] PRDATA,
    output logic        PREADY,
    output logic        PSLVERR
);
    logic [31:0] mem [0:255];
    int unsigned max_wait = 3;
    int unsigned left;

    initial begin
        void'($value$plusargs("APB_MAX_WAIT=%d", max_wait));
        foreach (mem[i])
            mem[i] = 32'h0;
    end

    assign PSLVERR = 1'b0;
    assign PRDATA  = (PSEL && PENABLE && PREADY && !PWRITE) ? mem[PADDR[9:2]] : 32'h0;

    // A wait count is drawn at the setup phase and counted down in the access phase
    always_ff @(posedge clk) begin
        if (reset) begin
            left <= 0;
        end else if (PSEL && !PENABLE) begin
            left <= $urandom_range(max_wait, 0);
        end else if (PSEL && PENABLE && left != 0) begin
            left <= left - 1;
        end else if (PSEL && PENABLE) begin
            if (PWRITE)
                for (int b = 0; b < 4; b++)
                    if (PSTRB[b])
                        mem[PADDR[9:2]][8*b +: 8] <= PWDATA[8*b +: 8];
        end
    end

    assign PREADY = PSEL && PENABLE && left == 0;
endmodule
