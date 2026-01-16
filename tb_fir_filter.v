`timescale 1ns/1ps

module tb_fir_filter;

    reg clk;
    reg rst;
    reg signed [15:0] sample_in;
    reg sample_valid;
    wire signed [15:0] y_out;

    fir_filter #(.TAPS(4)) dut (
        .clk(clk),
        .rst(rst),
        .sample_in(sample_in),
        .sample_valid(sample_valid),
        .y_out(y_out)
    );

    always #5 clk = ~clk;

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, tb_fir_filter);

        clk = 0;
        rst = 1;
        sample_in = 0;
        sample_valid = 0;

        #20;
        rst = 0;

        // Impulse
        #10;
        sample_valid = 1;
        sample_in = 16'sh7FFF;

        #10 sample_in = 16'sd0;
        #10 sample_in = 16'sd0;
        #10 sample_in = 16'sd0;

        #10 sample_valid = 0;

        #50;

        // Step
        sample_valid = 1;
        sample_in = 16'sh4000;

        #10 sample_in = 16'sh4000;
        #10 sample_in = 16'sh4000;
        #10 sample_in = 16'sh4000;

        #10 sample_valid = 0;

        #50;
        $stop;
    end

endmodule
