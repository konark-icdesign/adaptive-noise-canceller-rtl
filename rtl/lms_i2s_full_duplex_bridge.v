`timescale 1ns/1ps

module lms_i2s_full_duplex_bridge #(
    parameter integer MU_SHIFT = 4
)(
    input  wire                    sys_clk,
    input  wire                    rst,

    input  wire                    i2s_bclk,
    input  wire                    i2s_ws,
    input  wire                    i2s_sd_in,
    output wire                    i2s_sd_out,

    output wire [31:0]             rx_frame_count,
    output wire [31:0]             rx_overrun_count,
    output wire [31:0]             rx_framing_error_count,

    output wire [31:0]             tx_loaded_frame_count,
    output wire [31:0]             tx_sent_frame_count,
    output wire [31:0]             tx_underrun_count,
    output wire [31:0]             tx_timing_error_count,

    output wire [31:0]             accepted_samples,
    output wire [31:0]             emitted_samples,
    output wire [31:0]             input_stall_cycles,
    output wire [31:0]             output_stall_cycles,
    output wire [31:0]             output_overflow_events,

    output wire                    tx_completed_valid
);

    wire lms_valid;
    wire lms_ready;
    wire signed [15:0] lms_noise;
    wire signed [15:0] lms_error;
    wire signed [15:0] lms_c0, lms_c1, lms_c2, lms_c3;

    wire tx_pair_valid;
    wire tx_pair_ready;
    wire signed [15:0] tx_left;
    wire signed [15:0] tx_right;

    lms_i2s_input_bridge #(.MU_SHIFT(MU_SHIFT)) ingress (
        .sys_clk(sys_clk),
        .rst(rst),
        .i2s_bclk(i2s_bclk),
        .i2s_ws(i2s_ws),
        .i2s_sd(i2s_sd_in),

        .m_valid(lms_valid),
        .m_ready(lms_ready),
        .m_noise_estimate(lms_noise),
        .m_error(lms_error),
        .m_coeff0(lms_c0),
        .m_coeff1(lms_c1),
        .m_coeff2(lms_c2),
        .m_coeff3(lms_c3),

        .i2s_frame_count(rx_frame_count),
        .i2s_overrun_count(rx_overrun_count),
        .i2s_framing_error_count(rx_framing_error_count),
        .accepted_samples(accepted_samples),
        .emitted_samples(emitted_samples),
        .input_stall_cycles(input_stall_cycles),
        .output_stall_cycles(output_stall_cycles),
        .output_overflow_events(output_overflow_events)
    );

    // Return complete LMS results to the I2S BCLK domain. The cleaned/error
    // signal is placed on the left output channel and the estimated noise on
    // the right output channel for observability.
    audio_pair_cdc #(.WIDTH(16)) result_cdc (
        .s_clk(sys_clk),
        .s_rst(rst),
        .s_valid(lms_valid),
        .s_ready(lms_ready),
        .s_left(lms_error),
        .s_right(lms_noise),

        .d_clk(i2s_bclk),
        .d_rst(rst),
        .d_valid(tx_pair_valid),
        .d_ready(tx_pair_ready),
        .d_left(tx_left),
        .d_right(tx_right)
    );

    i2s_stereo_tx16 tx (
        .bclk(i2s_bclk),
        .rst(rst),
        .ws(i2s_ws),
        .frame_valid(tx_pair_valid),
        .frame_ready(tx_pair_ready),
        .left_sample(tx_left),
        .right_sample(tx_right),
        .sd(i2s_sd_out),
        .completed_valid(tx_completed_valid),
        .loaded_frame_count(tx_loaded_frame_count),
        .sent_frame_count(tx_sent_frame_count),
        .underrun_count(tx_underrun_count),
        .timing_error_count(tx_timing_error_count)
    );

endmodule
