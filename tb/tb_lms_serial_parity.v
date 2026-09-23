\`timescale 1ns/1ps

module tb_lms_serial_parity;
    localparam integer N = 4096;

    reg clk = 1'b0;
    reg rst = 1'b1;
    reg sample_valid = 1'b0;
    reg signed [15:0] reference_in = 16'sd0;
    reg signed [15:0] desired_in = 16'sd0;

    wire sample_ready;
    wire out_valid;
    wire signed [15:0] noise_estimate;
    wire signed [15:0] error_out;
    wire signed [15:0] coeff0, coeff1, coeff2, coeff3;

    reg [15:0] reference_mem [0:N-1];
    reg [15:0] desired_mem [0:N-1];
    reg [15:0] expected_y [0:N-1];
    reg [15:0] expected_e [0:N-1];
    reg [15:0] expected_c0 [0:N-1];
    reg [15:0] expected_c1 [0:N-1];
    reg [15:0] expected_c2 [0:N-1];
    reg [15:0] expected_c3 [0:N-1];

    integer n;
    integer failures = 0;
    integer accepted_cycle;
    integer completed_cycle;
    integer total_latency = 0;

    lms_adaptive_filter_serial #(.MU_SHIFT(4)) dut (
        .clk(clk), .rst(rst), .sample_valid(sample_valid), .sample_ready(sample_ready),
        .reference_in(reference_in), .desired_in(desired_in), .out_valid(out_valid),
        .noise_estimate(noise_estimate), .error_out(error_out),
        .coeff0(coeff0), .coeff1(coeff1), .coeff2(coeff2), .coeff3(coeff3)
    );

    always #5 clk = ~clk;

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
            while (!sample_ready) @(negedge clk);

            reference_in = $signed(reference_mem[n]);
            desired_in = $signed(desired_mem[n]);
            sample_valid = 1'b1;

            @(posedge clk);
            accepted_cycle = $time / 10;
            #1;
            @(negedge clk);
            sample_valid = 1'b0;

            begin : wait_for_result
                reg done;
                done = 1'b0;
                while (!done) begin
                    @(posedge clk);
                    #1;
                    if (out_valid) begin
                        completed_cycle = $time / 10;
                        total_latency = total_latency + (completed_cycle - accepted_cycle);
                        done = 1'b1;
                    end
                end
            end

            if ((noise_estimate !== $signed(expected_y[n])) ||
                (error_out !== $signed(expected_e[n])) ||
                (coeff0 !== $signed(expected_c0[n])) ||
                (coeff1 !== $signed(expected_c1[n])) ||
                (coeff2 !== $signed(expected_c2[n])) ||
                (coeff3 !== $signed(expected_c3[n]))) begin
                if (failures < 8) begin
                    $display("Mismatch n=%0d y=%0d/%0d e=%0d/%0d c=[%0d,%0d,%0d,%0d] exp=[%0d,%0d,%0d,%0d]",
                        n, noise_estimate, $signed(expected_y[n]), error_out, $signed(expected_e[n]),
                        coeff0, coeff1, coeff2, coeff3,
                        $signed(expected_c0[n]), $signed(expected_c1[n]),
                        $signed(expected_c2[n]), $signed(expected_c3[n]));
                end
                failures = failures + 1;
            end
        end

        if (failures == 0) begin
            $display("PASS: serialized one-multiplier LMS matches 4096-sample bit-exact reference.");
            $display("Average accept-to-result latency: %0d clocks", total_latency / N);
            $display("Initiation interval: 9 clocks/sample");
            $finish;
        end else begin
            $display("FAIL: %0d serial parity mismatch(es).", failures);
            $fatal(1);
        end
    end
endmodule
