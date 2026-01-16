module fir_filter #(
    parameter TAPS = 4
)(
    input  wire               clk,
    input  wire               rst,
    input  wire signed [15:0] sample_in,
    input  wire               sample_valid,
    output reg  signed [15:0] y_out
);

    reg signed [15:0] shift_reg [0:TAPS-1];
    reg signed [15:0] coeff     [0:TAPS-1];
    reg signed [31:0] acc;
    integer i;

    initial begin
        for (i = 0; i < TAPS; i = i + 1)
            coeff[i] = 16'sh2000; // 0.25 in Q1.15
    end

    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < TAPS; i = i + 1)
                shift_reg[i] <= 16'sd0;
            y_out <= 16'sd0;
        end else if (sample_valid) begin

            for (i = TAPS-1; i > 0; i = i - 1)
                shift_reg[i] <= shift_reg[i-1];

            shift_reg[0] <= sample_in;

            acc = 32'sd0;
            for (i = 0; i < TAPS; i = i + 1)
                acc = acc + (shift_reg[i] * coeff[i]);

            y_out <= acc[30:15];
        end
    end

endmodule
