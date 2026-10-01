`timescale 1ns/1ps

module tb_lms_i2s_input_bridge;
    localparam integer N = 256;

    reg sys_clk = 1'b0;
    reg rst = 1'b1;
    reg i2s_bclk = 1'b0;
    reg i2s_ws = 1'b1;
    reg i2s_sd = 1'b0;

    wire m_valid;
    reg m_ready = 1'b1;
    wire signed [15:0] m_noise_estimate;
    wire signed [15:0] m_error;
    wire signed [15:0] m_coeff0, m_coeff1, m_coeff2, m_coeff3;

    wire [31:0] i2s_frame_count;
    wire [31:0] i2s_overrun_count;
    wire [31:0] i2s_framing_error_count;
    wire [31:0] accepted_samples;
    wire [31:0] emitted_samples;
    wire [31:0] input_stall_cycles;
    wire [31:0] output_stall_cycles;
    wire [31:0] output_overflow_events;

    reg [15:0] reference_mem [0:4095];
    reg [15:0] desired_mem [0:4095];
    reg [15:0] expected_y [0:4095];
    reg [15:0] expected_e [0:4095];
    reg [15:0] expected_c0 [0:4095];
    reg [15:0] expected_c1 [0:4095];
    reg [15:0] expected_c2 [0:4095];
    reg [15:0] expected_c3 [0:4095];

    integer n;
    integer bit_index;
    integer received = 0;
    integer failures = 0;
    integer timeout = 0;

    lms_i2s_input_bridge dut (
        .sys_clk(sys_clk),
        .rst(rst),
        .i2s_bclk(i2s_bclk),
        .i2s_ws(i2s_ws),
        .i2s_sd(i2s_sd),

        .m_valid(m_valid),
        .m_ready(m_ready),
        .m_noise_estimate(m_noise_estimate),
        .m_error(m_error),
        .m_coeff0(m_coeff0),
        .m_coeff1(m_coeff1),
        .m_coeff2(m_coeff2),
        .m_coeff3(m_coeff3),

        .i2s_frame_count(i2s_frame_count),
        .i2s_overrun_count(i2s_overrun_count),
        .i2s_framing_error_count(i2s_framing_error_count),
        .accepted_samples(accepted_samples),
        .emitted_samples(emitted_samples),
        .input_stall_cycles(input_stall_cycles),
        .output_stall_cycles(output_stall_cycles),
        .output_overflow_events(output_overflow_events)
    );

    // 50 MHz LMS/system clock.
    always #10 sys_clk = ~sys_clk;

    // 48 kHz * 32 bit clocks/frame = 1.536 MHz BCLK.
    // Full BCLK period = 651.041666... ns.
    always #325.520833 i2s_bclk = ~i2s_bclk;

    always @(posedge sys_clk) begin
        if (!rst && m_valid && m_ready) begin
            if (received >= N) begin
                $display("FAIL: extra LMS output");
                failures = failures + 1;
            end else if (
                m_noise_estimate !== $signed(expected_y[received]) ||
                m_error !== $signed(expected_e[received]) ||
                m_coeff0 !== $signed(expected_c0[received]) ||
                m_coeff1 !== $signed(expected_c1[received]) ||
                m_coeff2 !== $signed(expected_c2[received]) ||
                m_coeff3 !== $signed(expected_c3[received])
            ) begin
                if (failures < 8)
                    $display("I2S/LMS mismatch n=%0d y=%0d/%0d e=%0d/%0d",
                        received,
                        m_noise_estimate, $signed(expected_y[received]),
                        m_error, $signed(expected_e[received]));
                failures = failures + 1;
            end
            received = received + 1;
        end
    end

    task send_stereo_frame;
        input [15:0] left_word;
        input [15:0] right_word;
        begin
            // WS is already low at the start of a normal frame because the
            // preceding right-channel LSB edge changed it one BCLK early.
            for (bit_index = 15; bit_index >= 1; bit_index = bit_index - 1) begin
                @(negedge i2s_bclk);
                i2s_ws = 1'b0;
                i2s_sd = left_word[bit_index];
            end

            // Left LSB is launched on the same falling edge that changes WS.
            @(negedge i2s_bclk);
            i2s_ws = 1'b1;
            i2s_sd = left_word[0];

            for (bit_index = 15; bit_index >= 1; bit_index = bit_index - 1) begin
                @(negedge i2s_bclk);
                i2s_ws = 1'b1;
                i2s_sd = right_word[bit_index];
            end

            // Right LSB plus WS transition back to left.
            @(negedge i2s_bclk);
            i2s_ws = 1'b0;
            i2s_sd = right_word[0];
        end
    endtask

    initial begin
        $readmemh("build/parity/reference.mem", reference_mem);
        $readmemh("build/parity/desired.mem", desired_mem);
        $readmemh("build/parity/expected_y.mem", expected_y);
        $readmemh("build/parity/expected_e.mem", expected_e);
        $readmemh("build/parity/expected_c0.mem", expected_c0);
        $readmemh("build/parity/expected_c1.mem", expected_c1);
        $readmemh("build/parity/expected_c2.mem", expected_c2);
        $readmemh("build/parity/expected_c3.mem", expected_c3);

        // Let both clock domains see reset and learn the initial WS=1 level.
        repeat (8) @(posedge sys_clk);
        repeat (2) @(posedge i2s_bclk);
        rst = 1'b0;
        repeat (2) @(posedge i2s_bclk);

        // Initial I2S synchronization transition. This edge represents the
        // unknown previous right-channel LSB; the first left MSB follows one
        // full bit clock later.
        @(negedge i2s_bclk);
        i2s_ws = 1'b0;
        i2s_sd = 1'b0;

        for (n = 0; n < N; n = n + 1)
            send_stereo_frame(reference_mem[n], desired_mem[n]);

        while (received < N && timeout < 2000000) begin
            @(posedge sys_clk);
            timeout = timeout + 1;
        end

        repeat (10) @(posedge sys_clk);

        if (received != N) begin
            $display("FAIL: received %0d/%0d LMS outputs", received, N);
            failures = failures + 1;
        end
        if (i2s_frame_count != N) begin
            $display("FAIL: I2S frame count=%0d expected=%0d", i2s_frame_count, N);
            failures = failures + 1;
        end
        if (accepted_samples != N || emitted_samples != N) begin
            $display("FAIL: accepted=%0d emitted=%0d expected=%0d",
                accepted_samples, emitted_samples, N);
            failures = failures + 1;
        end
        if (i2s_overrun_count != 0) begin
            $display("FAIL: I2S overrun count=%0d", i2s_overrun_count);
            failures = failures + 1;
        end
        if (i2s_framing_error_count != 0) begin
            $display("FAIL: I2S framing errors=%0d", i2s_framing_error_count);
            failures = failures + 1;
        end
        if (input_stall_cycles != 0) begin
            $display("FAIL: LMS source backpressure at 48 kHz: %0d cycles",
                input_stall_cycles);
            failures = failures + 1;
        end
        if (output_overflow_events != 0) begin
            $display("FAIL: LMS output overflow=%0d", output_overflow_events);
            failures = failures + 1;
        end

        if (failures == 0) begin
            $display("PASS: 256 standard-I2S stereo frames crossed into 50 MHz LMS domain bit-exactly.");
            $display("frames=%0d accepted=%0d emitted=%0d i2s_overrun=%0d framing_errors=%0d",
                i2s_frame_count, accepted_samples, emitted_samples,
                i2s_overrun_count, i2s_framing_error_count);
            $finish;
        end else begin
            $display("FAIL: %0d I2S-ingress error(s).", failures);
            $fatal(1);
        end
    end

endmodule
