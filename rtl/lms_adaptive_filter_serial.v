`timescale 1ns/1ps

module lms_adaptive_filter_serial #(
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
    localparam [1:0] IDLE = 2'd0, FIR = 2'd1, UPDATE = 2'd2;

    reg [1:0] state;
    reg [1:0] index;

    reg signed [15:0] x1, x2, x3;
    reg signed [15:0] tap0, tap1, tap2, tap3;
    reg signed [15:0] desired_hold;
    reg signed [15:0] error_hold;
    reg signed [63:0] accumulator;

    reg signed [15:0] mult_a;
    reg signed [15:0] mult_b;
    wire signed [31:0] mult_product = $signed(mult_a) * $signed(mult_b);

    reg signed [63:0] fir_total;
    reg signed [63:0] delta_wide;
    reg signed [63:0] coeff_sum;
    reg signed [16:0] err_wide;
    reg signed [15:0] y_work;
    reg signed [15:0] e_work;

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
        mult_a = 16'sd0;
        mult_b = 16'sd0;

        if (state == FIR) begin
            case (index)
                2'd0: begin mult_a = tap0; mult_b = coeff0; end
                2'd1: begin mult_a = tap1; mult_b = coeff1; end
                2'd2: begin mult_a = tap2; mult_b = coeff2; end
                default: begin mult_a = tap3; mult_b = coeff3; end
            endcase
        end else if (state == UPDATE) begin
            mult_a = error_hold;
            case (index)
                2'd0: mult_b = tap0;
                2'd1: mult_b = tap1;
                2'd2: mult_b = tap2;
                default: mult_b = tap3;
            endcase
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            index <= 2'd0;
            x1 <= 16'sd0;
            x2 <= 16'sd0;
            x3 <= 16'sd0;
            tap0 <= 16'sd0;
            tap1 <= 16'sd0;
            tap2 <= 16'sd0;
            tap3 <= 16'sd0;
            desired_hold <= 16'sd0;
            error_hold <= 16'sd0;
            accumulator <= 64'sd0;
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
                        tap0 <= reference_in;
                        tap1 <= x1;
                        tap2 <= x2;
                        tap3 <= x3;
                        desired_hold <= desired_in;

                        x3 <= x2;
                        x2 <= x1;
                        x1 <= reference_in;

                        accumulator <= 64'sd0;
                        index <= 2'd0;
                        state <= FIR;
                    end
                end

                FIR: begin
                    if (index == 2'd3) begin
                        fir_total = $signed(accumulator) + $signed(mult_product);
                        y_work = sat16($signed(fir_total) >>> 15);
                        err_wide = {desired_hold[15], desired_hold} - {y_work[15], y_work};
                        e_work = sat16(err_wide);

                        noise_estimate <= y_work;
                        error_out <= e_work;
                        error_hold <= e_work;
                        index <= 2'd0;
                        state <= UPDATE;
                    end else begin
                        accumulator <= $signed(accumulator) + $signed(mult_product);
                        index <= index + 2'd1;
                    end
                end

                UPDATE: begin
                    delta_wide = $signed(mult_product);
                    delta_wide = $signed(delta_wide) >>> UPDATE_SHIFT;

                    case (index)
                        2'd0: begin
                            coeff_sum = $signed(coeff0) + $signed(delta_wide);
                            coeff0 <= sat16(coeff_sum);
                        end
                        2'd1: begin
                            coeff_sum = $signed(coeff1) + $signed(delta_wide);
                            coeff1 <= sat16(coeff_sum);
                        end
                        2'd2: begin
                            coeff_sum = $signed(coeff2) + $signed(delta_wide);
                            coeff2 <= sat16(coeff_sum);
                        end
                        default: begin
                            coeff_sum = $signed(coeff3) + $signed(delta_wide);
                            coeff3 <= sat16(coeff_sum);
                        end
                    endcase

                    if (index == 2'd3) begin
                        index <= 2'd0;
                        state <= IDLE;
                        out_valid <= 1'b1;
                    end else begin
                        index <= index + 2'd1;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
