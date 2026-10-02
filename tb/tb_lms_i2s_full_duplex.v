`timescale 1ns/1ps

module tb_lms_i2s_full_duplex;
    localparam integer CHECK_N = 128;
    localparam integer DRIVE_N = 136;

    reg sys_clk = 1'b0;
    reg rst = 1'b1;
    reg i2s_bclk = 1'b0;
    reg i2s_ws = 1'b1;
    reg i2s_sd_in = 1'b0;

    wire i2s_sd_out;

    wire [31:0] rx_frame_count;
    wire [31:0] rx_overrun_count;
    wire [31:0] rx_framing_error_count;
    wire [31:0] tx_loaded_frame_count;
    wire [31:0] tx_sent_frame_count;
    wire [31:0] tx_underrun_count;
    wire [31:0] tx_timing_error_count;
    wire [31:0] accepted_samples;
    wire [31:0] emitted_samples;
    wire [31:0] input_stall_cycles;
    wire [31:0] output_stall_cycles;
    wire [31:0] output_overflow_events;
    wire tx_completed_valid;

    wire mon_valid;
    wire signed [15:0] mon_left;
    wire signed [15:0] mon_right;
    wire [31:0] mon_frames, mon_overrun, mon_framing;

    reg [15:0] reference_mem [0:4095];
    reg [15:0] desired_mem [0:4095];
    reg [15:0] expected_y [0:4095];
    reg [15:0] expected_e [0:4095];

    integer n;
    integer bit_index;
    integer checked = 0;
    integer failures = 0;

    lms_i2s_full_duplex_bridge dut (
        .sys_clk(sys_clk),
        .rst(rst),
        .i2s_bclk(i2s_bclk),
        .i2s_ws(i2s_ws),
        .i2s_sd_in(i2s_sd_in),
        .i2s_sd_out(i2s_sd_out),

        .rx_frame_count(rx_frame_count),
        .rx_overrun_count(rx_overrun_count),
        .rx_framing_error_count(rx_framing_error_count),
        .tx_loaded_frame_count(tx_loaded_frame_count),
        .tx_sent_frame_count(tx_sent_frame_count),
        .tx_underrun_count(tx_underrun_count),
        .tx_timing_error_count(tx_timing_error_count),
        .accepted_samples(accepted_samples),
        .emitted_samples(emitted_samples),
        .input_stall_cycles(input_stall_cycles),
        .output_stall_cycles(output_stall_cycles),
        .output_overflow_events(output_overflow_events),
        .tx_completed_valid(tx_completed_valid)
    );

    i2s_stereo_rx16 output_monitor (
        .bclk(i2s_bclk),
        .rst(rst),
        .ws(i2s_ws),
        .sd(i2s_sd_out),
        .frame_valid(mon_valid),
        .frame_ready(1'b1),
        .left_sample(mon_left),
        .right_sample(mon_right),
        .frame_count(mon_frames),
        .overrun_count(mon_overrun),
        .framing_error_count(mon_framing)
    );

    always #10 sys_clk = ~sys_clk;
    always #325.520833 i2s_bclk = ~i2s_bclk;

    task send_stereo_frame;
        input [15:0] left_word;
        input [15:0] right_word;
        begin
            for (bit_index=15; bit_index>=1; bit_index=bit_index-1) begin
                @(negedge i2s_bclk);
                i2s_ws = 1'b0;
                i2s_sd_in = left_word[bit_index];
            end
            @(negedge i2s_bclk);
            i2s_ws = 1'b1;
            i2s_sd_in = left_word[0];

            for (bit_index=15; bit_index>=1; bit_index=bit_index-1) begin
                @(negedge i2s_bclk);
                i2s_ws = 1'b1;
                i2s_sd_in = right_word[bit_index];
            end
            @(negedge i2s_bclk);
            i2s_ws = 1'b0;
            i2s_sd_in = right_word[0];
        end
    endtask

    always @(posedge i2s_bclk) begin
        #1;
        if (!rst && mon_valid && tx_completed_valid && checked < CHECK_N) begin
            if (mon_left !== $signed(expected_e[checked]) ||
                mon_right !== $signed(expected_y[checked])) begin
                if (failures < 8)
                    $display("TX parity mismatch n=%0d left=%0d/%0d right=%0d/%0d",
                        checked,
                        mon_left, $signed(expected_e[checked]),
                        mon_right, $signed(expected_y[checked]));
                failures = failures + 1;
            end
            checked = checked + 1;
        end
    end

    initial begin
        $readmemh("build/parity/reference.mem", reference_mem);
        $readmemh("build/parity/desired.mem", desired_mem);
        $readmemh("build/parity/expected_y.mem", expected_y);
        $readmemh("build/parity/expected_e.mem", expected_e);

        repeat (8) @(posedge sys_clk);
        repeat (2) @(posedge i2s_bclk);
        rst = 1'b0;
        repeat (2) @(posedge i2s_bclk);

        // Initial synchronization boundary.
        @(negedge i2s_bclk);
        i2s_ws = 1'b0;
        i2s_sd_in = 1'b0;

        // Extra driven frames provide natural pipeline flush without stopping
        // the shared I2S clock. Only the first CHECK_N serialized LMS results
        // are compared.
        for (n=0; n<DRIVE_N; n=n+1)
            send_stereo_frame(reference_mem[n], desired_mem[n]);

        repeat (20) @(posedge sys_clk);

        if (checked != CHECK_N) begin
            $display("FAIL: checked %0d/%0d serialized LMS outputs", checked, CHECK_N);
            failures = failures + 1;
        end
        if (rx_overrun_count != 0 || rx_framing_error_count != 0) begin
            $display("FAIL: RX overrun=%0d framing=%0d",
                rx_overrun_count, rx_framing_error_count);
            failures = failures + 1;
        end
        if (tx_underrun_count != 0 || tx_timing_error_count != 0) begin
            $display("FAIL: TX underrun=%0d timing=%0d",
                tx_underrun_count, tx_timing_error_count);
            failures = failures + 1;
        end
        if (mon_framing != 0 || mon_overrun != 0) begin
            $display("FAIL: output monitor overrun=%0d framing=%0d",
                mon_overrun, mon_framing);
            failures = failures + 1;
        end
        if (input_stall_cycles != 0 || output_overflow_events != 0) begin
            $display("FAIL: LMS input stalls=%0d output overflow=%0d",
                input_stall_cycles, output_overflow_events);
            failures = failures + 1;
        end
        if (tx_sent_frame_count < CHECK_N) begin
            $display("FAIL: only %0d TX frames sent", tx_sent_frame_count);
            failures = failures + 1;
        end

        if (failures == 0) begin
            $display("PASS: full-duplex I2S -> LMS -> I2S path serialized %0d bit-exact cleaned/noise pairs.", CHECK_N);
            $display("rx_frames=%0d accepted=%0d emitted=%0d tx_loaded=%0d tx_sent=%0d",
                rx_frame_count, accepted_samples, emitted_samples,
                tx_loaded_frame_count, tx_sent_frame_count);
            $finish;
        end else begin
            $display("FAIL: %0d full-duplex I2S error(s).", failures);
            $fatal(1);
        end
    end
endmodule
