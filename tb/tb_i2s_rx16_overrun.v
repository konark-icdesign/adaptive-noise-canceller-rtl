`timescale 1ns/1ps

module tb_i2s_rx16_overrun;
    reg bclk = 1'b0;
    reg rst = 1'b1;
    reg ws = 1'b1;
    reg sd = 1'b0;
    wire frame_valid;
    reg frame_ready = 1'b0;
    wire signed [15:0] left_sample, right_sample;
    wire [31:0] frame_count, overrun_count, framing_error_count;

    integer bit_index;

    i2s_stereo_rx16 dut (
        .bclk(bclk), .rst(rst), .ws(ws), .sd(sd),
        .frame_valid(frame_valid), .frame_ready(frame_ready),
        .left_sample(left_sample), .right_sample(right_sample),
        .frame_count(frame_count), .overrun_count(overrun_count),
        .framing_error_count(framing_error_count)
    );

    always #100 bclk = ~bclk;

    task send_frame;
        input [15:0] left_word;
        input [15:0] right_word;
        begin
            for (bit_index=15; bit_index>=1; bit_index=bit_index-1) begin
                @(negedge bclk); ws=1'b0; sd=left_word[bit_index];
            end
            @(negedge bclk); ws=1'b1; sd=left_word[0];
            for (bit_index=15; bit_index>=1; bit_index=bit_index-1) begin
                @(negedge bclk); ws=1'b1; sd=right_word[bit_index];
            end
            @(negedge bclk); ws=1'b0; sd=right_word[0];
        end
    endtask

    initial begin
        repeat (3) @(posedge bclk);
        rst = 1'b0;
        repeat (2) @(posedge bclk);
        @(negedge bclk); ws=1'b0; sd=1'b0;

        send_frame(16'h1234, 16'h5678);
        send_frame(16'h9abc, 16'hdef0);

        repeat (4) @(posedge bclk);

        if (!frame_valid) begin
            $display("FAIL: first frame was not retained while blocked");
            $fatal(1);
        end
        if (left_sample !== 16'h1234 || right_sample !== 16'h5678) begin
            $display("FAIL: retained frame corrupted left=%h right=%h",
                left_sample, right_sample);
            $fatal(1);
        end
        if (overrun_count != 1) begin
            $display("FAIL: expected one explicit overrun, got %0d", overrun_count);
            $fatal(1);
        end
        if (framing_error_count != 0) begin
            $display("FAIL: framing errors=%0d", framing_error_count);
            $fatal(1);
        end

        $display("PASS: blocked I2S consumer retains first frame and counts the dropped second frame.");
        $finish;
    end
endmodule
