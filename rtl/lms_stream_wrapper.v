`timescale 1ns/1ps

module lms_stream_wrapper #(
    parameter integer MU_SHIFT = 4
)(
    input  wire                    clk,
    input  wire                    rst,

    input  wire                    s_valid,
    output wire                    s_ready,
    input  wire signed [15:0]      s_reference,
    input  wire signed [15:0]      s_desired,

    output wire                    m_valid,
    input  wire                    m_ready,
    output wire signed [15:0]      m_noise_estimate,
    output wire signed [15:0]      m_error,
    output wire signed [15:0]      m_coeff0,
    output wire signed [15:0]      m_coeff1,
    output wire signed [15:0]      m_coeff2,
    output wire signed [15:0]      m_coeff3,

    output reg [31:0]              accepted_samples,
    output reg [31:0]              emitted_samples,
    output reg [31:0]              input_stall_cycles,
    output reg [31:0]              output_stall_cycles,
    output reg [31:0]              output_overflow_events
);

    // Four input entries absorb short producer bursts. Two output entries let
    // a downstream consumer stall without forcing the core result to be lost.
    reg signed [15:0] in_reference [0:3];
    reg signed [15:0] in_desired   [0:3];
    reg [1:0] in_wr_ptr;
    reg [1:0] in_rd_ptr;
    reg [2:0] in_count;

    reg signed [15:0] out_y  [0:1];
    reg signed [15:0] out_e  [0:1];
    reg signed [15:0] out_c0 [0:1];
    reg signed [15:0] out_c1 [0:1];
    reg signed [15:0] out_c2 [0:1];
    reg signed [15:0] out_c3 [0:1];
    reg out_wr_ptr;
    reg out_rd_ptr;
    reg [1:0] out_count;

    wire core_ready;
    wire core_out_valid;
    wire signed [15:0] core_y;
    wire signed [15:0] core_e;
    wire signed [15:0] core_c0, core_c1, core_c2, core_c3;

    wire pop_out = (out_count != 0) && m_ready;
    wire store_core_out =
        core_out_valid && ((out_count < 2) || pop_out);

    // The staged LMS has at most one sample in flight. When it becomes ready,
    // core_out_valid can still be presenting the result that completed on the
    // previous edge. Account for that pending FIFO write and a simultaneous
    // sink pop before reserving room for the next future result.
    wire [2:0] out_after_events =
        {1'b0, out_count}
        + (core_out_valid ? 3'd1 : 3'd0)
        - (pop_out ? 3'd1 : 3'd0);

    wire launch_room = (out_after_events < 3'd2);
    wire core_valid = (in_count != 0) && launch_room;
    wire launch = core_valid && core_ready;
    wire push_in = s_valid && s_ready;

    assign s_ready = (in_count < 4);

    assign m_valid = (out_count != 0);
    assign m_noise_estimate = m_valid ? out_y[out_rd_ptr] : 16'sd0;
    assign m_error = m_valid ? out_e[out_rd_ptr] : 16'sd0;
    assign m_coeff0 = m_valid ? out_c0[out_rd_ptr] : 16'sd0;
    assign m_coeff1 = m_valid ? out_c1[out_rd_ptr] : 16'sd0;
    assign m_coeff2 = m_valid ? out_c2[out_rd_ptr] : 16'sd0;
    assign m_coeff3 = m_valid ? out_c3[out_rd_ptr] : 16'sd0;

    lms_adaptive_filter_pipelined #(.MU_SHIFT(MU_SHIFT)) core (
        .clk(clk),
        .rst(rst),
        .sample_valid(core_valid),
        .sample_ready(core_ready),
        .reference_in(in_reference[in_rd_ptr]),
        .desired_in(in_desired[in_rd_ptr]),
        .out_valid(core_out_valid),
        .noise_estimate(core_y),
        .error_out(core_e),
        .coeff0(core_c0),
        .coeff1(core_c1),
        .coeff2(core_c2),
        .coeff3(core_c3)
    );

    always @(posedge clk) begin
        if (rst) begin
            in_wr_ptr <= 2'd0;
            in_rd_ptr <= 2'd0;
            in_count <= 3'd0;

            out_wr_ptr <= 1'b0;
            out_rd_ptr <= 1'b0;
            out_count <= 2'd0;

            accepted_samples <= 32'd0;
            emitted_samples <= 32'd0;
            input_stall_cycles <= 32'd0;
            output_stall_cycles <= 32'd0;
            output_overflow_events <= 32'd0;
        end else begin
            if (s_valid && !s_ready)
                input_stall_cycles <= input_stall_cycles + 1'b1;
            if (m_valid && !m_ready)
                output_stall_cycles <= output_stall_cycles + 1'b1;

            if (push_in) begin
                in_reference[in_wr_ptr] <= s_reference;
                in_desired[in_wr_ptr] <= s_desired;
                in_wr_ptr <= in_wr_ptr + 1'b1;
                accepted_samples <= accepted_samples + 1'b1;
            end

            if (launch)
                in_rd_ptr <= in_rd_ptr + 1'b1;

            case ({push_in, launch})
                2'b10: in_count <= in_count + 1'b1;
                2'b01: in_count <= in_count - 1'b1;
                default: in_count <= in_count;
            endcase

            if (store_core_out) begin
                out_y[out_wr_ptr] <= core_y;
                out_e[out_wr_ptr] <= core_e;
                out_c0[out_wr_ptr] <= core_c0;
                out_c1[out_wr_ptr] <= core_c1;
                out_c2[out_wr_ptr] <= core_c2;
                out_c3[out_wr_ptr] <= core_c3;
                out_wr_ptr <= out_wr_ptr + 1'b1;
            end else if (core_out_valid) begin
                // This should remain zero if launch_room is correct. Keeping a
                // visible counter makes an integration failure diagnosable.
                output_overflow_events <= output_overflow_events + 1'b1;
            end

            if (pop_out) begin
                out_rd_ptr <= out_rd_ptr + 1'b1;
                emitted_samples <= emitted_samples + 1'b1;
            end

            case ({store_core_out, pop_out})
                2'b10: out_count <= out_count + 1'b1;
                2'b01: out_count <= out_count - 1'b1;
                default: out_count <= out_count;
            endcase
        end
    end

endmodule
