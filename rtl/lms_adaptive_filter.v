`timescale 1ns/1ps

module lms_adaptive_filter #(
    parameter integer MU_SHIFT = 4  // mu = 2^-MU_SHIFT; default = 1/16
)(
    input  wire                    clk,
    input  wire                    rst,
    input  wire                    sample_valid,
    input  wire signed [15:0]      reference_in,   // x[n], Q1.15
    input  wire signed [15:0]      desired_in,     // d[n], Q1.15
    output reg  signed [15:0]      noise_estimate, // y[n], Q1.15
    output reg  signed [15:0]      error_out,      // e[n], Q1.15
    output reg  signed [15:0]      coeff0,
    output reg  signed [15:0]      coeff1,
    output reg  signed [15:0]      coeff2,
    output reg  signed [15:0]      coeff3
);

    localparam integer UPDATE_SHIFT = 15 + MU_SHIFT;

    // Delayed reference samples x[n-1], x[n-2], x[n-3]
    reg signed [15:0] x1;
    reg signed [15:0] x2;
    reg signed [15:0] x3;

    // Procedural temporaries. Wider than the Q1.15 datapath to preserve precision.
    reg signed [39:0] acc_calc;
    reg signed [15:0] y_calc;
    reg signed [15:0] e_calc;
    reg signed [16:0] err_wide;
    reg signed [31:0] corr0;
    reg signed [31:0] corr1;
    reg signed [31:0] corr2;
    reg signed [31:0] corr3;
    reg signed [31:0] delta0;
    reg signed [31:0] delta1;
    reg signed [31:0] delta2;
    reg signed [31:0] delta3;
    reg signed [63:0] wide_calc;

    // Saturate a wider signed value to the Q1.15 16-bit range.
    function signed [15:0] sat16;
        input signed [63:0] value;
        begin
            if (value > 64'sd32767)
                sat16 = 16'sh7fff;
            else if (value < -64'sd32768)
                sat16 = 16'sh8000;
            else
                sat16 = value[15:0];
        end
    endfunction

    always @(posedge clk) begin
        if (rst) begin
            x1 <= 16'sd0;
            x2 <= 16'sd0;
            x3 <= 16'sd0;

            coeff0 <= 16'sd0;
            coeff1 <= 16'sd0;
            coeff2 <= 16'sd0;
            coeff3 <= 16'sd0;

            noise_estimate <= 16'sd0;
            error_out <= 16'sd0;
        end else if (sample_valid) begin
            // FIR estimate y[n] = sum(w_i[n] * x[n-i]).
            // Products are Q2.30. Accumulation stays wide, then returns to Q1.15.
            acc_calc = 40'sd0;
            acc_calc = acc_calc + ($signed(reference_in) * $signed(coeff0));
            acc_calc = acc_calc + ($signed(x1)          * $signed(coeff1));
            acc_calc = acc_calc + ($signed(x2)          * $signed(coeff2));
            acc_calc = acc_calc + ($signed(x3)          * $signed(coeff3));

            y_calc = sat16($signed(acc_calc) >>> 15);

            // Error e[n] = d[n] - y[n]. Widen first so subtraction cannot wrap.
            err_wide = {desired_in[15], desired_in} - {y_calc[15], y_calc};
            e_calc = sat16(err_wide);

            noise_estimate <= y_calc;
            error_out <= e_calc;

            // LMS coefficient update:
            // w_i[n+1] = w_i[n] + mu * e[n] * x[n-i]
            // e*x is Q2.30. Shifting by (15 + MU_SHIFT) returns a Q1.15 delta.
            corr0 = $signed(e_calc) * $signed(reference_in);
            corr1 = $signed(e_calc) * $signed(x1);
            corr2 = $signed(e_calc) * $signed(x2);
            corr3 = $signed(e_calc) * $signed(x3);

            delta0 = $signed(corr0) >>> UPDATE_SHIFT;
            delta1 = $signed(corr1) >>> UPDATE_SHIFT;
            delta2 = $signed(corr2) >>> UPDATE_SHIFT;
            delta3 = $signed(corr3) >>> UPDATE_SHIFT;

            wide_calc = $signed(coeff0) + $signed(delta0);
            coeff0 <= sat16(wide_calc);

            wide_calc = $signed(coeff1) + $signed(delta1);
            coeff1 <= sat16(wide_calc);

            wide_calc = $signed(coeff2) + $signed(delta2);
            coeff2 <= sat16(wide_calc);

            wide_calc = $signed(coeff3) + $signed(delta3);
            coeff3 <= sat16(wide_calc);

            // Advance the reference delay line after using the current vector.
            x3 <= x2;
            x2 <= x1;
            x1 <= reference_in;
        end
    end

endmodule
