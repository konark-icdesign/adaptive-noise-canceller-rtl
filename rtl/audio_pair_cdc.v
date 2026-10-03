`timescale 1ns/1ps

module audio_pair_cdc #(
    parameter integer WIDTH = 16
)(
    input  wire                         s_clk,
    input  wire                         s_rst,
    input  wire                         s_valid,
    output wire                         s_ready,
    input  wire signed [WIDTH-1:0]      s_left,
    input  wire signed [WIDTH-1:0]      s_right,

    input  wire                         d_clk,
    input  wire                         d_rst,
    output reg                          d_valid,
    input  wire                         d_ready,
    output reg signed [WIDTH-1:0]       d_left,
    output reg signed [WIDTH-1:0]       d_right
);

    reg req_toggle;
    reg ack_toggle;

    reg signed [WIDTH-1:0] source_left_hold;
    reg signed [WIDTH-1:0] source_right_hold;

    // These are intentional two-flop synchronizer chains. The async_reg
    // attributes document the CDC intent for synthesis/place-and-route tools.
    (* async_reg = "true" *) reg ack_sync1;
    (* async_reg = "true" *) reg ack_sync2;
    (* async_reg = "true" *) reg req_sync1;
    (* async_reg = "true" *) reg req_sync2;

    assign s_ready = (ack_sync2 == req_toggle);

    // Source-domain side. The bundled sample pair remains stable from the
    // request toggle until the acknowledgement returns.
    always @(posedge s_clk) begin
        if (s_rst) begin
            req_toggle <= 1'b0;
            source_left_hold <= {WIDTH{1'b0}};
            source_right_hold <= {WIDTH{1'b0}};
            ack_sync1 <= 1'b0;
            ack_sync2 <= 1'b0;
        end else begin
            ack_sync1 <= ack_toggle;
            ack_sync2 <= ack_sync1;

            if (s_valid && s_ready) begin
                source_left_hold <= s_left;
                source_right_hold <= s_right;
                req_toggle <= ~req_toggle;
            end
        end
    end

    // Destination-domain side. req_sync2 arrives only after the bundled data
    // has been stable for multiple destination clocks.
    always @(posedge d_clk) begin
        if (d_rst) begin
            req_sync1 <= 1'b0;
            req_sync2 <= 1'b0;
            ack_toggle <= 1'b0;
            d_valid <= 1'b0;
            d_left <= {WIDTH{1'b0}};
            d_right <= {WIDTH{1'b0}};
        end else begin
            req_sync1 <= req_toggle;
            req_sync2 <= req_sync1;

            if (!d_valid && (req_sync2 != ack_toggle)) begin
                d_left <= source_left_hold;
                d_right <= source_right_hold;
                d_valid <= 1'b1;
            end

            if (d_valid && d_ready) begin
                d_valid <= 1'b0;
                ack_toggle <= req_sync2;
            end
        end
    end

endmodule
