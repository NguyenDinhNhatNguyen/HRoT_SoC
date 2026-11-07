// Pin walk test for the KV260 Pmod (J2). Drives one of the 8 Pmod pins high at a time, 2 s each,
// in the order HDA11 to HDA18, then all low for 2 s, and repeats. Use it with an LED or a multimeter
// on J2 to find which connector pin follows which FPGA pin.
// pl_clk0 is 50 MHz (kv260_bd.tcl), so 100_000_000 cycles is 2 s.
module PinWalk_Top (
    output wire [7:0] pmod
);
    wire pl_clk0, pl_resetn0;

    kv260_ps_wrapper ps (
        .pl_clk0(pl_clk0),
        .pl_resetn0(pl_resetn0)
    );

    reg [26:0] tick = 27'd0;
    reg [3:0]  step = 4'd0;

    always @(posedge pl_clk0) begin
        if (tick == 27'd99_999_999) begin
            tick <= 27'd0;
            step <= (step == 4'd8) ? 4'd0 : step + 4'd1;
        end else begin
            tick <= tick + 27'd1;
        end
    end

    // step 0 to 7 raises pmod[step], step 8 leaves every pin low
    assign pmod = (step < 4'd8) ? (8'd1 << step[2:0]) : 8'd0;
endmodule
