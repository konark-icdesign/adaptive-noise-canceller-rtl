`timescale 1ns/1ps

module lms_stream_ecp5_top #(
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
    output wire [4:0]              debug_status
);

    wire [31:0] accepted_samples;
    wire [31:0] emitted_samples;
    wire [31:0] input_stall_cycles;
    wire [31:0] output_stall_cycles;
    wire [31:0] output_overflow_events;

    lms_stream_wrapper #(.MU_SHIFT(MU_SHIFT)) wrapped (
        .clk(clk),
        .rst(rst),
        .s_valid(s_valid),
        .s_ready(s_ready),
        .s_reference(s_reference),
        .s_desired(s_desired),
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

    // Preserve all counter bits in the implementation study without mapping
    // 160 diagnostic bits to package pins. A real integration would read these
    // counters through a register bus or debug interface, not dedicated I/O.
    assign debug_status[0] = ^accepted_samples;
    assign debug_status[1] = ^emitted_samples;
    assign debug_status[2] = ^input_stall_cycles;
    assign debug_status[3] = ^output_stall_cycles;
    assign debug_status[4] = ^output_overflow_events;

endmodule
