`timescale 1ns/1ps

`ifndef S_HALF
`define S_HALF 10.0
`endif

`ifndef D_HALF
`define D_HALF 13.0
`endif

`ifndef D_PHASE
`define D_PHASE 3.0
`endif

module tb_audio_pair_cdc_stress;
    localparam integer N = 512;
    localparam realtime S_HALF_NS = `S_HALF;
    localparam realtime D_HALF_NS = `D_HALF;
    localparam realtime D_PHASE_NS = `D_PHASE;

    reg s_clk = 1'b0;
    reg d_clk = 1'b0;
    reg s_rst = 1'b1;
    reg d_rst = 1'b1;

    reg s_valid = 1'b0;
    wire s_ready;
    reg signed [15:0] s_left = 16'sd0;
    reg signed [15:0] s_right = 16'sd0;

    wire d_valid;
    reg d_ready = 1'b0;
    wire signed [15:0] d_left;
    wire signed [15:0] d_right;

    reg [15:0] s_lfsr = 16'h1ace;
    reg [15:0] d_lfsr = 16'hb4d3;

    integer sent = 0;
    integer received = 0;
    integer failures = 0;
    integer source_stall_cycles = 0;
    integer destination_stall_cycles = 0;

    reg stalled_prev = 1'b0;
    reg signed [15:0] held_left = 16'sd0;
    reg signed [15:0] held_right = 16'sd0;

    audio_pair_cdc dut (
        .s_clk(s_clk),
        .s_rst(s_rst),
        .s_valid(s_valid),
        .s_ready(s_ready),
        .s_left(s_left),
        .s_right(s_right),

        .d_clk(d_clk),
        .d_rst(d_rst),
        .d_valid(d_valid),
        .d_ready(d_ready),
        .d_left(d_left),
        .d_right(d_right)
    );

    initial forever #(S_HALF_NS) s_clk = ~s_clk;
    initial begin
        #(D_PHASE_NS);
        forever #(D_HALF_NS) d_clk = ~d_clk;
    end

    // Source produces deterministic ordered pairs with pseudo-random bubbles.
    // Once valid is asserted, the pair is held until the source handshake.
    always @(negedge s_clk) begin
        if (s_rst) begin
            s_valid <= 1'b0;
            s_left <= 16'sd0;
            s_right <= 16'sd0;
            s_lfsr <= 16'h1ace;
        end else if (s_valid && !s_ready) begin
            s_valid <= s_valid;
            s_left <= s_left;
            s_right <= s_right;
        end else if (sent < N) begin
            s_lfsr <= {s_lfsr[14:0],
                       s_lfsr[15] ^ s_lfsr[13] ^ s_lfsr[12] ^ s_lfsr[10]};
            if (s_lfsr[0] | s_lfsr[5]) begin
                s_valid <= 1'b1;
                s_left <= $signed(sent);
                s_right <= $signed((sent ^ 16'h5a5a) & 16'hffff);
            end else begin
                s_valid <= 1'b0;
            end
        end else begin
            s_valid <= 1'b0;
        end
    end

    always @(posedge s_clk) begin
        if (!s_rst) begin
            if (s_valid && !s_ready)
                source_stall_cycles = source_stall_cycles + 1;
            if (s_valid && s_ready)
                sent = sent + 1;
        end
    end

    // Destination adds pseudo-random backpressure plus a recurring forced
    // stall. This exercises d_valid hold behavior and delays acknowledgements.
    integer d_cycle = 0;
    always @(negedge d_clk) begin
        if (d_rst) begin
            d_ready <= 1'b0;
            d_lfsr <= 16'hb4d3;
            d_cycle <= 0;
        end else begin
            d_lfsr <= {d_lfsr[14:0],
                       d_lfsr[15] ^ d_lfsr[14] ^ d_lfsr[12] ^ d_lfsr[3]};
            d_cycle <= d_cycle + 1;
            if ((d_cycle % 61) >= 37 && (d_cycle % 61) < 44)
                d_ready <= 1'b0;
            else
                d_ready <= d_lfsr[0] | d_lfsr[2];
        end
    end

    always @(posedge d_clk) begin
        if (!d_rst) begin
            if (stalled_prev) begin
                if (!d_valid || d_left !== held_left || d_right !== held_right) begin
                    $display("FAIL: destination data changed while stalled at received=%0d", received);
                    failures = failures + 1;
                end
            end

            stalled_prev <= d_valid && !d_ready;
            if (d_valid && !d_ready) begin
                held_left <= d_left;
                held_right <= d_right;
                destination_stall_cycles = destination_stall_cycles + 1;
            end

            if (d_valid && d_ready) begin
                if (d_left !== $signed(received) ||
                    d_right !== $signed((received ^ 16'h5a5a) & 16'hffff)) begin
                    if (failures < 8)
                        $display("FAIL: CDC order/data mismatch n=%0d left=%h right=%h",
                            received, d_left, d_right);
                    failures = failures + 1;
                end
                received = received + 1;
            end
        end
    end

    initial begin
        // Both synchronous resets are held long enough to be sampled by both
        // unrelated clocks before traffic begins.
        #5000;
        @(negedge s_clk);
        s_rst = 1'b0;
        @(negedge d_clk);
        d_rst = 1'b0;
    end

    initial begin
        fork
            begin
                wait (received == N);
                repeat (6) @(posedge d_clk);

                if (sent != N) begin
                    $display("FAIL: source sent=%0d expected=%0d", sent, N);
                    failures = failures + 1;
                end
                if (d_valid) begin
                    $display("FAIL: destination valid remained asserted after final consume");
                    failures = failures + 1;
                end
                if (source_stall_cycles == 0 && S_HALF_NS < D_HALF_NS) begin
                    $display("FAIL: slower destination case never backpressured source");
                    failures = failures + 1;
                end
                if (destination_stall_cycles == 0) begin
                    $display("FAIL: destination stall path was not exercised");
                    failures = failures + 1;
                end

                if (failures == 0) begin
                    $display("PASS: CDC transferred %0d ordered pairs; s_half=%0.6fns d_half=%0.6fns phase=%0.6fns source_stall=%0d dest_stall=%0d",
                        N, S_HALF_NS, D_HALF_NS, D_PHASE_NS,
                        source_stall_cycles, destination_stall_cycles);
                    $finish;
                end else begin
                    $display("FAIL: %0d CDC stress error(s).", failures);
                    $fatal(1);
                end
            end
            begin
                #50000000;
                $display("FAIL: CDC stress timeout sent=%0d received=%0d", sent, received);
                $fatal(1);
            end
        join_any
        disable fork;
    end

endmodule
