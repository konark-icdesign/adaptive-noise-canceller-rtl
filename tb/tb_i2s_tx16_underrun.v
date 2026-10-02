`timescale 1ns/1ps

module tb_i2s_tx16_underrun;
    reg bclk = 1'b0;
    reg rst = 1'b1;
    reg ws = 1'b1;

    reg frame_valid = 1'b0;
    wire frame_ready;
    reg signed [15:0] left_sample = 16'sh1234;
    reg signed [15:0] right_sample = 16'sh5678;

    wire sd;
    wire completed_valid;
    wire [31:0] loaded_frame_count;
    wire [31:0] sent_frame_count;
    wire [31:0] underrun_count;
    wire [31:0] timing_error_count;

    wire mon_valid;
    wire signed [15:0] mon_left;
    wire signed [15:0] mon_right;
    wire [31:0] mon_frames, mon_overrun, mon_framing;

    integer bit_index;
    integer seen_valid = 0;
    integer failures = 0;

    i2s_stereo_tx16 dut (
        .bclk(bclk), .rst(rst), .ws(ws),
        .frame_valid(frame_valid), .frame_ready(frame_ready),
        .left_sample(left_sample), .right_sample(right_sample),
        .sd(sd), .completed_valid(completed_valid),
        .loaded_frame_count(loaded_frame_count),
        .sent_frame_count(sent_frame_count),
        .underrun_count(underrun_count),
        .timing_error_count(timing_error_count)
    );

    i2s_stereo_rx16 monitor (
        .bclk(bclk), .rst(rst), .ws(ws), .sd(sd),
        .frame_valid(mon_valid), .frame_ready(1'b1),
        .left_sample(mon_left), .right_sample(mon_right),
        .frame_count(mon_frames), .overrun_count(mon_overrun),
        .framing_error_count(mon_framing)
    );

    always #100 bclk = ~bclk;

    task set_ws_before_negedge;
        input next_ws;
        begin
            @(posedge bclk);
            #80;
            ws = next_ws;
        end
    endtask

    task clock_frame;
        begin
            for (bit_index=15; bit_index>=1; bit_index=bit_index-1)
                set_ws_before_negedge(1'b0);
            set_ws_before_negedge(1'b1);
            for (bit_index=15; bit_index>=1; bit_index=bit_index-1)
                set_ws_before_negedge(1'b1);
            set_ws_before_negedge(1'b0);
        end
    endtask

    always @(posedge bclk) begin
        #1;
        if (!rst && mon_valid && completed_valid) begin
            seen_valid = seen_valid + 1;
            if (mon_left !== 16'sh1234 || mon_right !== 16'sh5678) begin
                $display("FAIL: TX serial data mismatch left=%h right=%h",
                    mon_left, mon_right);
                failures = failures + 1;
            end
        end
    end

    initial begin
        repeat (3) @(posedge bclk);
        rst = 1'b0;
        repeat (2) @(posedge bclk);

        // Initial right->left synchronization boundary. Keep one frame pending
        // so it becomes the first active serialized pair.
        frame_valid = 1'b1;
        set_ws_before_negedge(1'b0);

        wait (frame_ready);
        #1;
        frame_valid = 1'b0;

        // Serializing this first valid frame ends on the next right->left
        // boundary. Because no replacement pair is pending at that boundary,
        // exactly one underrun is recorded for the frame that starts there.
        clock_frame();
        repeat (4) @(posedge bclk);

        if (seen_valid != 1) begin
            $display("FAIL: expected exactly one valid decoded output, got %0d", seen_valid);
            failures = failures + 1;
        end
        if (loaded_frame_count != 1 || sent_frame_count != 1) begin
            $display("FAIL: loaded=%0d sent=%0d", loaded_frame_count, sent_frame_count);
            failures = failures + 1;
        end
        if (underrun_count != 1) begin
            $display("FAIL: expected one TX underrun, got %0d", underrun_count);
            failures = failures + 1;
        end
        if (timing_error_count != 0 || mon_framing != 0) begin
            $display("FAIL: tx_timing=%0d monitor_framing=%0d",
                timing_error_count, mon_framing);
            failures = failures + 1;
        end

        if (failures == 0) begin
            $display("PASS: I2S TX serialized one frame exactly and counted the following missing frame as one underrun.");
            $finish;
        end else begin
            $display("FAIL: %0d I2S TX error(s).", failures);
            $fatal(1);
        end
    end
endmodule
