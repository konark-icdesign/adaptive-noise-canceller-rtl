`timescale 1ns/1ps

module tb_lms_stream_48k;
    localparam integer N = 256;

    reg clk = 1'b0;
    reg rst = 1'b1;
    reg s_valid = 1'b0;
    wire s_ready;
    reg signed [15:0] s_reference = 16'sd0;
    reg signed [15:0] s_desired = 16'sd0;
    wire m_valid;
    reg m_ready = 1'b1;
    wire signed [15:0] m_noise_estimate, m_error;
    wire signed [15:0] m_coeff0, m_coeff1, m_coeff2, m_coeff3;
    wire [31:0] accepted_samples, emitted_samples;
    wire [31:0] input_stall_cycles, output_stall_cycles, output_overflow_events;

    reg [15:0] reference_mem [0:4095];
    reg [15:0] desired_mem [0:4095];
    reg [15:0] expected_y [0:4095];
    reg [15:0] expected_e [0:4095];
    reg [15:0] expected_c0 [0:4095];
    reg [15:0] expected_c1 [0:4095];
    reg [15:0] expected_c2 [0:4095];
    reg [15:0] expected_c3 [0:4095];

    integer n;
    integer received = 0;
    integer failures = 0;
    integer gap_clocks;

    lms_stream_wrapper #(.MU_SHIFT(4)) dut (
        .clk(clk), .rst(rst),
        .s_valid(s_valid), .s_ready(s_ready),
        .s_reference(s_reference), .s_desired(s_desired),
        .m_valid(m_valid), .m_ready(m_ready),
        .m_noise_estimate(m_noise_estimate), .m_error(m_error),
        .m_coeff0(m_coeff0), .m_coeff1(m_coeff1),
        .m_coeff2(m_coeff2), .m_coeff3(m_coeff3),
        .accepted_samples(accepted_samples), .emitted_samples(emitted_samples),
        .input_stall_cycles(input_stall_cycles),
        .output_stall_cycles(output_stall_cycles),
        .output_overflow_events(output_overflow_events)
    );

    // 50 MHz reference clock.
    always #10 clk = ~clk;

    always @(posedge clk) begin
        if (!rst && m_valid && m_ready) begin
            if (m_noise_estimate !== $signed(expected_y[received]) ||
                m_error !== $signed(expected_e[received]) ||
                m_coeff0 !== $signed(expected_c0[received]) ||
                m_coeff1 !== $signed(expected_c1[received]) ||
                m_coeff2 !== $signed(expected_c2[received]) ||
                m_coeff3 !== $signed(expected_c3[received])) begin
                if (failures < 8)
                    $display("48k mismatch n=%0d", received);
                failures = failures + 1;
            end
            received = received + 1;
        end
    end

    initial begin
        $readmemh("build/parity/reference.mem", reference_mem);
        $readmemh("build/parity/desired.mem", desired_mem);
        $readmemh("build/parity/expected_y.mem", expected_y);
        $readmemh("build/parity/expected_e.mem", expected_e);
        $readmemh("build/parity/expected_c0.mem", expected_c0);
        $readmemh("build/parity/expected_c1.mem", expected_c1);
        $readmemh("build/parity/expected_c2.mem", expected_c2);
        $readmemh("build/parity/expected_c3.mem", expected_c3);

        repeat (4) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;

        for (n = 0; n < N; n = n + 1) begin
            // 50 MHz / 48 kHz = 1041.666... clocks/sample. The repeating
            // 1042,1042,1041 pattern has exactly that three-sample average.
            case (n % 3)
                0, 1: gap_clocks = 1042;
                default: gap_clocks = 1041;
            endcase

            repeat (gap_clocks - 1) @(posedge clk);
            @(negedge clk);
            s_reference = $signed(reference_mem[n]);
            s_desired = $signed(desired_mem[n]);
            s_valid = 1'b1;
            @(posedge clk);
            if (!s_ready) begin
                $display("FAIL: 48 kHz source backpressured at sample %0d", n);
                failures = failures + 1;
            end
            @(negedge clk);
            s_valid = 1'b0;
        end

        while (received < N)
            @(posedge clk);

        repeat (3) @(posedge clk);

        if (accepted_samples != N || emitted_samples != N) begin
            $display("FAIL: counters accepted=%0d emitted=%0d", accepted_samples, emitted_samples);
            failures = failures + 1;
        end
        if (input_stall_cycles != 0) begin
            $display("FAIL: 48 kHz input saw %0d backpressure cycles", input_stall_cycles);
            failures = failures + 1;
        end
        if (output_overflow_events != 0) begin
            $display("FAIL: 48 kHz overflow=%0d", output_overflow_events);
            failures = failures + 1;
        end

        if (failures == 0) begin
            $display("PASS: 256-sample 48 kHz stream at 50 MHz is bit-exact with zero source backpressure.");
            $finish;
        end else begin
            $display("FAIL: %0d 48 kHz stream error(s).", failures);
            $fatal(1);
        end
    end
endmodule
