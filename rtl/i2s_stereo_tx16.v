`timescale 1ns/1ps

module i2s_stereo_tx16 (
    input  wire                    bclk,
    input  wire                    rst,
    input  wire                    ws,

    input  wire                    frame_valid,
    output reg                     frame_ready,
    input  wire signed [15:0]      left_sample,
    input  wire signed [15:0]      right_sample,

    output reg                     sd,
    output reg                     completed_valid,

    output reg [31:0]              loaded_frame_count,
    output reg [31:0]              sent_frame_count,
    output reg [31:0]              underrun_count,
    output reg [31:0]              timing_error_count
);

    reg have_ws;
    reg synced;
    reg ws_prev;
    reg channel;
    reg [4:0] bit_index;

    reg signed [15:0] active_left;
    reg signed [15:0] active_right;
    reg active_valid;
    reg started;

    wire active_bit =
        channel ? active_right[bit_index] : active_left[bit_index];

    always @(negedge bclk) begin
        if (rst) begin
            have_ws <= 1'b0;
            synced <= 1'b0;
            ws_prev <= 1'b0;
            channel <= 1'b0;
            bit_index <= 5'd15;

            active_left <= 16'sd0;
            active_right <= 16'sd0;
            active_valid <= 1'b0;
            started <= 1'b0;

            sd <= 1'b0;
            frame_ready <= 1'b0;
            completed_valid <= 1'b0;

            loaded_frame_count <= 32'd0;
            sent_frame_count <= 32'd0;
            underrun_count <= 32'd0;
            timing_error_count <= 32'd0;
        end else begin
            frame_ready <= 1'b0;
            completed_valid <= 1'b0;

            if (!have_ws) begin
                have_ws <= 1'b1;
                ws_prev <= ws;
                sd <= 1'b0;
            end else if (!synced) begin
                if (ws != ws_prev) begin
                    synced <= 1'b1;
                    channel <= ws;
                    bit_index <= 5'd15;
                    sd <= 1'b0;

                    // If synchronization is obtained on a right->left
                    // boundary, a pending pair may immediately become the
                    // first active output frame.
                    if (ws == 1'b0 && frame_valid) begin
                        active_left <= left_sample;
                        active_right <= right_sample;
                        active_valid <= 1'b1;
                        started <= 1'b1;
                        frame_ready <= 1'b1;
                        loaded_frame_count <= loaded_frame_count + 1'b1;
                    end
                end
                ws_prev <= ws;
            end else if (ws != channel) begin
                // In 16-bit I2S, the WS-transition edge carries bit 0 of the
                // channel that just ended. Bits 15..1 were launched on the
                // previous 15 falling BCLK edges.
                if (bit_index != 5'd0)
                    timing_error_count <= timing_error_count + 1'b1;

                if (active_valid)
                    sd <= channel ? active_right[0] : active_left[0];
                else
                    sd <= 1'b0;

                // Right -> left marks completion of one stereo output frame.
                if (channel == 1'b1 && ws == 1'b0) begin
                    completed_valid <= active_valid;
                    if (active_valid)
                        sent_frame_count <= sent_frame_count + 1'b1;

                    if (frame_valid) begin
                        active_left <= left_sample;
                        active_right <= right_sample;
                        active_valid <= 1'b1;
                        started <= 1'b1;
                        frame_ready <= 1'b1;
                        loaded_frame_count <= loaded_frame_count + 1'b1;
                    end else begin
                        active_valid <= 1'b0;
                        if (started)
                            underrun_count <= underrun_count + 1'b1;
                    end
                end

                channel <= ws;
                bit_index <= 5'd15;
                ws_prev <= ws;
            end else begin
                if (bit_index > 5'd0) begin
                    if (active_valid)
                        sd <= active_bit;
                    else
                        sd <= 1'b0;
                    bit_index <= bit_index - 1'b1;
                end else begin
                    // The next falling edge should have been a WS transition
                    // carrying bit 0. A same-channel edge here means the
                    // external slot is not the exact 16-bit format supported
                    // by this transmitter.
                    timing_error_count <= timing_error_count + 1'b1;
                    sd <= 1'b0;
                end
                ws_prev <= ws;
            end
        end
    end

endmodule
