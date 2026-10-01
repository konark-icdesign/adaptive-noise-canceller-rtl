`timescale 1ns/1ps

module i2s_stereo_rx16 (
    input  wire                    bclk,
    input  wire                    rst,
    input  wire                    ws,
    input  wire                    sd,

    output reg                     frame_valid,
    input  wire                    frame_ready,
    output reg signed [15:0]       left_sample,
    output reg signed [15:0]       right_sample,

    output reg [31:0]              frame_count,
    output reg [31:0]              overrun_count,
    output reg [31:0]              framing_error_count
);

    reg have_ws;
    reg synced;
    reg ws_prev;
    reg channel;
    reg [4:0] bit_count;
    reg [15:0] shift_reg;
    reg [15:0] left_hold;
    reg left_seen;

    wire consume = frame_valid && frame_ready;
    wire [15:0] completed_word = {shift_reg[14:0], sd};

    always @(posedge bclk) begin
        if (rst) begin
            have_ws <= 1'b0;
            synced <= 1'b0;
            ws_prev <= 1'b0;
            channel <= 1'b0;
            bit_count <= 5'd0;
            shift_reg <= 16'd0;
            left_hold <= 16'd0;
            left_seen <= 1'b0;

            frame_valid <= 1'b0;
            left_sample <= 16'sd0;
            right_sample <= 16'sd0;

            frame_count <= 32'd0;
            overrun_count <= 32'd0;
            framing_error_count <= 32'd0;
        end else begin
            if (consume)
                frame_valid <= 1'b0;

            if (!have_ws) begin
                // Learn the idle/current WS level first. A real I2S word
                // boundary is established only after the first WS transition.
                have_ws <= 1'b1;
                ws_prev <= ws;
            end else if (!synced) begin
                if (ws != ws_prev) begin
                    // I2S changes WS one bit clock before the next MSB. The
                    // transition edge therefore carries the previous channel's
                    // LSB and is ignored only for this initial synchronization.
                    synced <= 1'b1;
                    channel <= ws;
                    bit_count <= 5'd0;
                    shift_reg <= 16'd0;
                    left_seen <= 1'b0;
                end
                ws_prev <= ws;
            end else if (ws != channel) begin
                // At a normal WS transition, the serial bit on this edge is
                // the LSB of the channel that just ended.
                if (bit_count == 5'd15) begin
                    if (channel == 1'b0) begin
                        left_hold <= completed_word;
                        left_seen <= 1'b1;
                    end else begin
                        if (left_seen) begin
                            if (!frame_valid || consume) begin
                                left_sample <= $signed(left_hold);
                                right_sample <= $signed(completed_word);
                                frame_valid <= 1'b1;
                                frame_count <= frame_count + 1'b1;
                            end else begin
                                // I2S cannot be backpressured electrically.
                                // If the previous pair has not moved into the
                                // CDC bridge, this complete stereo frame is lost
                                // and the loss is made explicit.
                                overrun_count <= overrun_count + 1'b1;
                            end
                        end else begin
                            framing_error_count <= framing_error_count + 1'b1;
                        end
                        left_seen <= 1'b0;
                    end
                end else begin
                    framing_error_count <= framing_error_count + 1'b1;
                    if (channel == 1'b1)
                        left_seen <= 1'b0;
                end

                channel <= ws;
                bit_count <= 5'd0;
                shift_reg <= 16'd0;
                ws_prev <= ws;
            end else begin
                // Between WS transitions capture bits 15 down through 1.
                // Bit 0 is captured on the following WS-transition edge.
                if (bit_count < 5'd15) begin
                    shift_reg <= {shift_reg[14:0], sd};
                    bit_count <= bit_count + 1'b1;
                end else begin
                    // More than 15 non-transition bits means the slot is not
                    // the 16-bit I2S format this receiver implements.
                    framing_error_count <= framing_error_count + 1'b1;
                end
                ws_prev <= ws;
            end
        end
    end

endmodule
