`timescale 1ns/1ps

module lms_adaptive_filter_pipelined #(
    parameter integer MU_SHIFT = 4
)(
    input  wire                    clk,
    input  wire                    rst,
    input  wire                    sample_valid,
    output wire                    sample_ready,
    input  wire signed [15:0]      reference_in,
    input  wire signed [15:0]      desired_in,
    output reg                     out_valid,
    output reg  signed [15:0]      noise_estimate,
    output reg  signed [15:0]      error_out,
    output reg  signed [15:0]      coeff0,
    output reg  signed [15:0]      coeff1,
    output reg  signed [15:0]      coeff2,
    output reg  signed [15:0]      coeff3
);

    localparam integer UPDATE_SHIFT = 15 + MU_SHIFT;

    localparam [2:0] IDLE   = 3'd0;
    localparam [2:0] SUM    = 3'd1;
    localparam [2:0] ERROR  = 3'd2;
    localparam [2:0] CORR   = 3'd3;
    localparam [2:0] UPDATE = 3'd4;

    reg [2:0] state;

    reg signed [15:0] x1, x2, x3;
    reg signed [15:0] tap0, tap1, tap2, tap3;
    reg signed [15:0] desired_hold;
    reg signed [15:0] y_hold;
    reg signed [15:0] e_hold;

    reg signed [31:0] fir_prod0, fir_prod1, fir_prod2, fir_prod3;
    reg signed [39:0] acc_hold;
    reg signed [31:0] corr0, corr1, corr2, corr3;

    reg signed [15:0] mul_a0, mul_a1, mul_a2, mul_a3;
    reg signed [15:0] mul_b0, mul_b1, mul_b2, mul_b3;

    wire signed [31:0] mul_p0 = $signed(mul_a0) * $signed(mul_b0);
    wire signed [31:0] mul_p1 = $signed(mul_a1) * $signed(mul_b1);
    wire signed [31:0] mul_p2 = $signed(mul_a2) * $signed(mul_b2);
    wire signed [31:0] mul_p3 = $signed(mul_a3) * $signed(mul_b3);

    reg signed [39:0] sum01_calc;
    reg signed [39:0] sum23_calc;
    reg signed [15:0] y_calc;
    reg signed [16:0] err_wide;
    reg signed [15:0] e_calc;

    reg signed [31:0] delta0, delta1, delta2, delta3;
    reg signed [63:0] wide0, wide1, wide2, wide3;

    assign sample_ready = (state == IDLE);

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

    always @* begin
        mul_a0 = 16'sd0; mul_b0 = 16'sd0;
        mul_a1 = 16'sd0; mul_b1 = 16'sd0;
        mul_a2 = 16'sd0; mul_b2 = 16'sd0;
        mul_a3 = 16'sd0; mul_b3 = 16'sd0;

        if (state == IDLE) begin
            mul_a0 = reference_in; mul_b0 = coeff0;
            mul_a1 = x1;           mul_b1 = coeff1;
            mul_a2 = x2;           mul_b2 = coeff2;
            mul_a3 = x3;           mul_b3 = coeff3;
        end else if (state == CORR) begin
            mul_a0 = e_hold; mul_b0 = tap0;
            mul_a1 = e_hold; mul_b1 = tap1;
            mul_a2 = e_hold; mul_b2 = tap2;
            mul_a3 = e_hold; mul_b3 = tap3;
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            x1 <= 16'sd0;
            x2 <= 16'sd0;
            x3 <= 16'sd0;

            tap0 <= 16'sd0;
            tap1 <= 16'sd0;
            tap2 <= 16'sd0;
            tap3 <= 16'sd0;
            desired_hold <= 16'sd0;
            y_hold <= 16'sd0;
            e_hold <= 16'sd0;

            fir_prod0 <= 32'sd0;
            fir_prod1 <= 32'sd0;
            fir_prod2 <= 32'sd0;
            fir_prod3 <= 32'sd0;
            acc_hold <= 40'sd0;

            corr0 <= 32'sd0;
            corr1 <= 32'sd0;
            corr2 <= 32'sd0;
            corr3 <= 32'sd0;

            coeff0 <= 16'sd0;
            coeff1 <= 16'sd0;
            coeff2 <= 16'sd0;
            coeff3 <= 16'sd0;

            noise_estimate <= 16'sd0;
            error_out <= 16'sd0;
            out_valid <= 1'b0;
        end else begin
            out_valid <= 1'b0;

            case (state)
                IDLE: begin
                    if (sample_valid) begin
                        // Stage 1: capture the current reference vector and register
                        // the four FIR products. The same four multipliers are reused
                        // later for coefficient-correlation products.
                        tap0 <= reference_in;
                        tap1 <= x1;
                        tap2 <= x2;
                        tap3 <= x3;
                        desired_hold <= desired_in;

                        fir_prod0 <= mul_p0;
                        fir_prod1 <= mul_p1;
                        fir_prod2 <= mul_p2;
                        fir_prod3 <= mul_p3;

                        x3 <= x2;
                        x2 <= x1;
                        x1 <= reference_in;

                        state <= SUM;
                    end
                end

                SUM: begin
                    // Stage 2: balanced product accumulation. Sign extension keeps
                    // the same wide accumulation semantics as the original core.
                    sum01_calc = {{8{fir_prod0[31]}}, fir_prod0}
                               + {{8{fir_prod1[31]}}, fir_prod1};
                    sum23_calc = {{8{fir_prod2[31]}}, fir_prod2}
                               + {{8{fir_prod3[31]}}, fir_prod3};
                    acc_hold <= $signed(sum01_calc) + $signed(sum23_calc);
                    state <= ERROR;
                end

                ERROR: begin
                    // Stage 3: return Q2.30 FIR output to Q1.15 and compute e[n].
                    y_calc = sat16($signed(acc_hold) >>> 15);
                    err_wide = {desired_hold[15], desired_hold}
                             - {y_calc[15], y_calc};
                    e_calc = sat16(err_wide);

                    y_hold <= y_calc;
                    e_hold <= e_calc;
                    state <= CORR;
                end

                CORR: begin
                    // Stage 4: reuse the four multipliers for e[n] * x[n-i].
                    corr0 <= mul_p0;
                    corr1 <= mul_p1;
                    corr2 <= mul_p2;
                    corr3 <= mul_p3;
                    state <= UPDATE;
                end

                UPDATE: begin
                    // Stage 5: shift the Q2.30 correlations by mu and commit the
                    // coefficient update. No following sample is accepted until
                    // this state completes, preserving exact LMS update ordering.
                    delta0 = $signed(corr0) >>> UPDATE_SHIFT;
                    delta1 = $signed(corr1) >>> UPDATE_SHIFT;
                    delta2 = $signed(corr2) >>> UPDATE_SHIFT;
                    delta3 = $signed(corr3) >>> UPDATE_SHIFT;

                    wide0 = $signed(coeff0) + $signed(delta0);
                    wide1 = $signed(coeff1) + $signed(delta1);
                    wide2 = $signed(coeff2) + $signed(delta2);
                    wide3 = $signed(coeff3) + $signed(delta3);

                    coeff0 <= sat16(wide0);
                    coeff1 <= sat16(wide1);
                    coeff2 <= sat16(wide2);
                    coeff3 <= sat16(wide3);

                    noise_estimate <= y_hold;
                    error_out <= e_hold;
                    out_valid <= 1'b1;
                    state <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
