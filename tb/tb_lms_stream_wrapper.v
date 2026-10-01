`timescale 1ns/1ps

module tb_lms_stream_wrapper;
    localparam integer N = 4096;

    reg clk = 1'b0;
    reg rst = 1'b1;

    reg s_valid = 1'b0;
    wire s_ready;
    reg signed [15:0] s_reference = 16'sd0;
    reg signed [15:0] s_desired = 16'sd0;

    wire m_valid;
    reg m_ready = 1'b0;
    wire signed [15:0] m_noise_estimate;
    wire signed [15:0] m_error;
    wire signed [15:0] m_coeff0, m_coeff1, m_coeff2, m_coeff3;

    wire [31:0] accepted_samples;
    wire [31:0] emitted_samples;
    wire [31:0] input_stall_cycles;
    wire [31:0] output_stall_cycles;
    wire [31:0] output_overflow_events;

    reg [15:0] reference_mem [0:N-1];
    reg [15:0] desired_mem [0:N-1];
    reg [15:0] expected_y [0:N-1];
    reg [15:0] expected_e [0:N-1];
    reg [15:0] expected_c0 [0:N-1];
    reg [15:0] expected_c1 [0:N-1];
    reg [15:0] expected_c2 [0:N-1];
    reg [15:0] expected_c3 [0:N-1];

    reg [15:0] source_lfsr = 16'h1d3f;
    reg [15:0] sink_lfsr = 16'ha671;
    integer cycle_count = 0;
    integer n;
    integer received = 0;
    integer failures = 0;
    integer timeout_cycles = 0;

    reg stalled_prev = 1'b0;
    reg signed [15:0] held_y, held_e, held_c0, held_c1, held_c2, held_c3;

    lms_stream_wrapper #(.MU_SHIFT(4)) dut (
        .clk(clk), .rst(rst),
        .s_valid(s_valid), .s_ready(s_ready),
        .s_reference(s_reference), .s_desired(s_desired),
        .m_valid(m_valid), .m_ready(m_ready),
        .m_noise_estimate(m_noise_estimate), .m_error(m_error),
        .m_coeff0(m_coeff0), .m_coeff1(m_coeff1),
        .m_coeff2(m_coeff2), .m_coeff3(m_coeff3),
        .accepted_samples(accepted_samples),
        .emitted_samples(emitted_samples),
        .input_stall_cycles(input_stall_cycles),
        .output_stall_cycles(output_stall_cycles),
        .output_overflow_events(output_overflow_events)
    );

    always #5 clk = ~clk;

    always @(negedge clk) begin
        if (rst) begin
            sink_lfsr <= 16'ha671;
            cycle_count <= 0;
            m_ready <= 1'b0;
        end else begin
            sink_lfsr <= {sink_lfsr[14:0],
                          sink_lfsr[15] ^ sink_lfsr[13] ^ sink_lfsr[12] ^ sink_lfsr[10]};
            cycle_count <= cycle_count + 1;

            // Pseudo-random consumer readiness plus a deterministic long stall
            // to force the two-entry output FIFO to fill.
            if ((cycle_count % 127) >= 80 && (cycle_count % 127) < 103)
                m_ready <= 1'b0;
            else
                m_ready <= sink_lfsr[0] | sink_lfsr[3];
        end
    end

    always @(posedge clk) begin
        if (!rst) begin
            if (stalled_prev) begin
                if (!m_valid ||
                    m_noise_estimate !== held_y ||
                    m_error !== held_e ||
                    m_coeff0 !== held_c0 ||
                    m_coeff1 !== held_c1 ||
                    m_coeff2 !== held_c2 ||
                    m_coeff3 !== held_c3) begin
                    $display("FAIL: output changed while backpressured at cycle %0d", cycle_count);
                    failures = failures + 1;
                end
            end

            stalled_prev <= m_valid && !m_ready;
            if (m_valid && !m_ready) begin
                held_y <= m_noise_estimate;
                held_e <= m_error;
                held_c0 <= m_coeff0;
                held_c1 <= m_coeff1;
                held_c2 <= m_coeff2;
                held_c3 <= m_coeff3;
            end

            if (m_valid && m_ready) begin
                if (received >= N) begin
                    $display("FAIL: received extra output");
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
                        $display("Mismatch n=%0d y=%0d/%0d e=%0d/%0d c=[%0d,%0d,%0d,%0d]",
                            received,
                            m_noise_estimate, $signed(expected_y[received]),
                            m_error, $signed(expected_e[received]),
                            m_coeff0, m_coeff1, m_coeff2, m_coeff3);
                    failures = failures + 1;
                end
                received = received + 1;
            end
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
            source_lfsr = {source_lfsr[14:0],
                           source_lfsr[15] ^ source_lfsr[13] ^ source_lfsr[12] ^ source_lfsr[10]};

            // Producer also has pseudo-random idle bubbles. Once valid is
            // asserted, data is held until the wrapper accepts it.
            if (source_lfsr[0] && source_lfsr[4]) begin
                @(negedge clk);
                s_valid = 1'b0;
            end

            @(negedge clk);
            s_reference = $signed(reference_mem[n]);
            s_desired = $signed(desired_mem[n]);
            s_valid = 1'b1;

            begin : wait_accept
                reg accepted;
                accepted = 1'b0;
                while (!accepted) begin
                    @(posedge clk);
                    if (s_ready)
                        accepted = 1'b1;
                end
            end

            @(negedge clk);
            s_valid = 1'b0;
        end

        while (received < N && timeout_cycles < 100000) begin
            @(posedge clk);
            timeout_cycles = timeout_cycles + 1;
        end

        repeat (3) @(posedge clk);

        if (received != N) begin
            $display("FAIL: received %0d/%0d outputs", received, N);
            failures = failures + 1;
        end
        if (accepted_samples != N) begin
            $display("FAIL: accepted counter %0d expected %0d", accepted_samples, N);
            failures = failures + 1;
        end
        if (emitted_samples != N) begin
            $display("FAIL: emitted counter %0d expected %0d", emitted_samples, N);
            failures = failures + 1;
        end
        if (input_stall_cycles == 0) begin
            $display("FAIL: stress run never exercised input backpressure");
            failures = failures + 1;
        end
        if (output_stall_cycles == 0) begin
            $display("FAIL: stress run never exercised output backpressure");
            failures = failures + 1;
        end
        if (output_overflow_events != 0) begin
            $display("FAIL: output overflow events=%0d", output_overflow_events);
            failures = failures + 1;
        end

        if (failures == 0) begin
            $display("PASS: stream wrapper matches 4096-sample bit-exact reference under producer/consumer stalls.");
            $display("accepted=%0d emitted=%0d input_stall_cycles=%0d output_stall_cycles=%0d overflow=%0d",
                accepted_samples, emitted_samples, input_stall_cycles,
                output_stall_cycles, output_overflow_events);
            $finish;
        end else begin
            $display("FAIL: %0d stream-wrapper error(s).", failures);
            $fatal(1);
        end
    end
endmodule
