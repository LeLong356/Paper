`timescale 1ns/1ps

// Run from the repository directory:
// iverilog -g2012 -s tb_softmax_row_max -o /tmp/row_max.vvp softmax_row_max.sv tb_softmax_row_max.sv
// vvp /tmp/row_max.vvp
module tb_softmax_row_max;
    localparam int MAX_LENGTH = 32;
    localparam int COUNT_WIDTH = $clog2(MAX_LENGTH + 1);
    logic clk = 0;
    logic rst_n = 0;
    logic start = 0;
    logic [COUNT_WIDTH-1:0] row_length = 0;
    logic in_valid = 0;
    logic signed [31:0] in_data = 0;
    wire in_ready, done;
    wire signed [31:0] max_value;
    wire signed [32:0] diff_data;
    wire diff_valid;
    logic signed [31:0] samples [0:MAX_LENGTH-1];
    logic [31:0] random_state = 32'h20261026;
    integer passed = 0;
    integer checked_elements = 0;
    softmax_row_max #(.MAX_LENGTH(MAX_LENGTH)) dut (.*);
    always #5 clk = ~clk;

    // Drive on falling edges; check after rising-edge nonblocking updates.
    task automatic reset_dut;
        @(negedge clk);
        rst_n = 0; start = 0; in_valid = 0;
        #1;
        if (done !== 0 || in_ready !== 0 || max_value !== 0 ||
            diff_valid !== 0 || diff_data !== 0 ||
            dut.received_count !== 0 || dut.subtract_count !== 0)
            $fatal(1, "Reset did not clear control state");
        @(negedge clk); rst_n = 1;
    endtask

    task automatic begin_row(input integer n);
        @(negedge clk);
        start = 1; row_length = n; in_valid = 0;
        @(posedge clk); #1;
        if (in_ready !== 1 || done !== 0 || diff_valid !== 0 || dut.last_index !== n - 1)
            $fatal(1, "Failed to start row of length %0d", n);
        @(negedge clk);
        start = 0;
        row_length = 0; // The latched length must survive changes at the input.
    endtask

    task automatic run_row(input string label_text, input integer n, input bit bubbles);
        longint signed expected_max, expected_diff, value64, running_max;
        expected_max = samples[0];
        for (integer j = 1; j < n; j = j + 1)
            if (samples[j] > expected_max) expected_max = samples[j];
        begin_row(n);
        running_max = samples[0];
        for (integer j = 0; j < n; j = j + 1) begin
            if (bubbles && j % 3 == 1) begin
                in_valid = 0; in_data = 32'sh7fffffff;
                @(posedge clk); #1;
                if (dut.received_count !== j || done !== 0 || diff_valid !== 0 || max_value !== running_max[31:0])
                    $fatal(1, "%s: invalid input changed state", label_text);
                @(negedge clk);
            end
            in_valid = 1; in_data = samples[j];
            if (samples[j] > running_max) running_max = samples[j];
            @(posedge clk); #1;
            if (dut.row_buffer[j] !== samples[j] || dut.received_count !== j + 1 ||
                max_value !== running_max[31:0] || done !== 0 || diff_valid !== 0)
                $fatal(1, "%s: receive mismatch at %0d", label_text, j);
            @(negedge clk);
        end
        // Keep valid asserted to prove that SUBTRACT does not receive extra data.
        in_valid = 1; in_data = 32'sh7fffffff;
        @(posedge clk); #1; if (diff_valid || done) $fatal(1,"Early output during RAM read");
        for (integer j = 0; j < n; j = j + 1) begin
            if (in_ready !== 0 || dut.subtract_count !== j)
                $fatal(1, "%s: wrong subtract index %0d", label_text, j);
            @(posedge clk); #1;
            value64 = samples[j];
            expected_diff = value64 - expected_max; // Independent 64-bit reference.
            // Check the public stream, not just the internal buffer.
            if (diff_valid !== 1 || diff_data !== expected_diff[32:0])
                $fatal(1, "%s[%0d]: stream valid=%b, data=%0d, expected=%0d",
                       label_text, j, diff_valid, diff_data, expected_diff);
            if (done !== (j == n - 1) || max_value !== expected_max[31:0] ||
                dut.received_count !== n)
                $fatal(1, "%s: completion/max/count mismatch", label_text);
            checked_elements = checked_elements + 1;
            @(negedge clk);
        end
        in_valid = 0;
        @(posedge clk); #1;
        if (done !== 0 || in_ready !== 0 || diff_valid !== 0)
            $fatal(1, "%s: done pulse must last one cycle", label_text);
        passed = passed + 1;
        $display("PASS %s: length=%0d, max=%0d", label_text, n, expected_max);
    endtask

    initial begin
        reset_dut();
        // Neither valid alone nor an invalid length may start a row.
        @(negedge clk); in_valid = 1;
        @(posedge clk); #1;
        if (in_ready !== 0 || done !== 0 || diff_valid !== 0) $fatal(1, "Started without start");
        @(negedge clk); in_valid = 0; start = 1; row_length = 0;
        @(posedge clk); #1;
        if (in_ready !== 0 || diff_valid !== 0) $fatal(1, "Accepted zero length");
        @(negedge clk); row_length = MAX_LENGTH + 1;
        @(posedge clk); #1;
        if (in_ready !== 0 || diff_valid !== 0) $fatal(1, "Accepted oversized length");
        @(negedge clk); start = 0;

        samples[0]=10; samples[1]=25; samples[2]=-3;
        run_row("example: differences -15, 0, -28", 3, 0);
        samples[0]=-5; samples[1]=-8; samples[2]=-2;
        run_row("negative row, final max, bubbles", 3, 1);
        samples[0]=32'sh80000000;
        run_row("singleton INT32_MIN", 1, 0);
        samples[0]=32'sh80000000; samples[1]=32'sh7fffffff;
        run_row("INT32 extremes: difference -4294967295", 2, 0);
        for (integer j=0; j<8; j=j+1) samples[j]=-7;
        run_row("all equal", 8, 1);
        samples[0]=99; samples[1]=1; samples[2]=-99;
        run_row("first element is max", 3, 0);
        for (integer j=0; j<MAX_LENGTH; j=j+1) samples[j]=j-MAX_LENGTH/2;
        run_row("maximum length", MAX_LENGTH, 1);
        for (integer r=0; r<20; r=r+1) begin
            for (integer j=0; j<1+(r*7)%MAX_LENGTH; j=j+1) begin
                random_state = random_state * 32'd1664525 + 32'd1013904223;
                samples[j] = random_state;
            end
            run_row($sformatf("deterministic random %0d",r), 1+(r*7)%MAX_LENGTH, 1);
        end

        // Abort RECEIVE, then ensure the next row starts cleanly.
        begin_row(3); in_valid=1; in_data=42;
        @(posedge clk); #1;
        reset_dut();
        samples[0]=7; run_row("after reset during receive",1,0);

        // Abort SUBTRACT with its first RAM read pending, then process a different row.
        begin_row(3);
        for (integer j=0; j<3; j=j+1) begin
            in_valid=1; in_data=j;
            @(posedge clk); #1; @(negedge clk);
        end
        in_valid=0;
        @(posedge clk); #1;
        reset_dut();
        samples[0]=-9; samples[1]=-4;
        run_row("after reset during subtract",2,0);
        $display("ALL PASS: %0d rows, %0d stream differences; invalid lengths and reset checks passed",
                 passed, checked_elements);
        $finish;
    end
    initial begin
        #1000000;
        $fatal(1, "Simulation timeout");
    end
endmodule
