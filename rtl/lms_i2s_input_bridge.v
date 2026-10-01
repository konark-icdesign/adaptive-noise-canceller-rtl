`timescale 1ns/1ps

module lms_i2s_input_bridge #(
    parameter integer MU_SHIFT = 4
)(
    input  wire                    sys_clk,
    input  wire                    rst,

    input  wire                    i2s_bclk,
    input  wire                    i2s_ws,
    input  wire                    i2s_sd,

    output wire                    m_valid,
    input  wire                    m_ready,
    output wire signed [15:0]      m_noise_estimate,
    output wire signed [15:0]      m_error,
    output wire signed [15:0]      m_coeff0,
    output wire signed [15:0]      m_coeff1,
    output wire signed [15:0]      m_coeff2,
    output wire signed [15:0]      m_coeff3,

    output wire [31:0]             i2s_frame_count,
    output wire [31:0]             i2s_overrun_count,
    output wire [31:0]             i2s_framing_error_count,
    output wire [31:0]             accepted_samples,
    output wire [31:0]             emitted_samples,
    output wire [31:0]             input_stall_cycles,
    output wire [31:0]             output_stall_cycles,
    output wire [31:0]             output_overflow_events
);

    wire rx_valid;
    wire rx_ready;
    wire signed [15:0] rx_left;
    wire signed [15:0] rx_right;

    wire pair_valid;
    wire pair_ready;
    wire signed [15:0] pair_left;
    wire signed [15:0] pair_right;

    i2s_stereo_rx16 rx (
        .bclk(i2s_bclk),
        .rst(rst),
        .ws(i2s_ws),
        .sd(i2s_sd),
        .frame_valid(rx_valid),
        .frame_ready(rx_ready),
        .left_sample(rx_left),
        .right_sample(rx_right),
        .frame_count(i2s_frame_count),
        .overrun_count(i2s_overrun_count),
        .framing_error_count(i2s_framing_error_count)
    );

    audio_pair_cdc #(.WIDTH(16)) input_cdc (
        .s_clk(i2s_bclk),
        .s_rst(rst),
        .s_valid(rx_valid),
        .s_ready(rx_ready),
        .s_left(rx_left),
        .s_right(rx_right),

        .d_clk(sys_clk),
        .d_rst(rst),
        .d_valid(pair_valid),
        .d_ready(pair_ready),
        .d_left(pair_left),
        .d_right(pair_right)
    );

    // Stereo convention for this experiment:
    //   left  = LMS reference x[n]
    //   right = desired/primary d[n]
    lms_stream_wrapper #(.MU_SHIFT(MU_SHIFT)) lms_stream (
        .clk(sys_clk),
        .rst(rst),

        .s_valid(pair_valid),
        .s_ready(pair_ready),
        .s_reference(pair_left),
        .s_desired(pair_right),

        .m_valid(m_valid),
        .m_ready(m_ready),
        .m_noise_estimate(m_noise_estimate),
        .m_error(m_error),
        .m_coeff0(m_coeff0),
        .m_coeff1(m_coeff1),
        .m_coeff2(m_coeff2),
        .m_coeff3(m_coeff3),

        .accepted_samples(accepted_samples),
        .emitted_samples(emitted_samples),
        .input_stall_cycles(input_stall_cycles),
        .output_stall_cycles(output_stall_cycles),
        .output_overflow_events(output_overflow_events)
    );

endmodule
