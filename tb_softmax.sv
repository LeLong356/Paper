`timescale 1ns/1ps
// Run using python3 verify_softmax.py. Outputs are sampled after clock updates.
module tb_softmax;
    logic clk=0, rst_n=0, start=0, in_valid=0;
    logic [11:0] row_length=0;
    logic signed [31:0] in_data=0;
    wire ready, in_ready, out_valid, out_last, done;
    wire signed [7:0] out_data;
    reg signed [31:0] samples[0:2047];
    reg [31:0] expected[0:2047], expected_sum;
    reg [7:0] expected_int8[0:2047];
    integer fp32_received;
    reg previous_valid, previous_last;
    integer fd, dump_fd, status, n, cycles, received;
    integer rows=0, elements=0;
    string vector_path, output_path;
    softmax dut(.*);
    always #5 clk=~clk;
    // Check exact one-cycle valid/last alignment through the quantizer.
    always @(posedge clk) begin
        previous_valid = rst_n && dut.probability_valid;
        previous_last = rst_n && dut.probability_valid && dut.probability_last;
        #1;
        if(out_valid !== previous_valid || out_last !== previous_last ||
           done !== (out_valid && out_last))
            $fatal(1,"Quantizer valid/last/done alignment failed");
    end

    task reset_dut;
        @(negedge clk); rst_n=0; start=0; in_valid=0;
        #1;
        if(ready !== 0 || in_ready !== 0 || out_valid !== 0 || out_last !== 0 || done !== 0)
            $fatal(1,"Reset did not clear control outputs");
        @(negedge clk); rst_n=1;
    endtask

    task begin_row(input integer length);
        @(negedge clk);
        if(ready !== 1) $fatal(1,"Not ready for new row");
        start=1; row_length=length; in_valid=0;
        @(posedge clk); #1;
        if(ready !== 0 || in_ready !== 1 || out_valid !== 0 || done !== 0)
            $fatal(1,"Row start failed");
        @(negedge clk); start=0; row_length=0;
    endtask

    task check_idle;
        repeat(40) begin
            @(posedge clk); #1;
            if(ready !== 1 || in_ready !== 0 || out_valid !== 0 || out_last !== 0 || done !== 0)
                $fatal(1,"Stale output after reset/idle");
        end
    endtask

    initial begin
        if(!$value$plusargs("VECTORS=%s",vector_path) || !$value$plusargs("OUTPUT=%s",output_path))
            $fatal(1,"Missing VECTORS or OUTPUT argument");
        fd=$fopen(vector_path,"r"); dump_fd=$fopen(output_path,"w");
        if(!fd || !dump_fd) $fatal(1,"Cannot open test files");
        reset_dut(); check_idle();
        // Reject invalid lengths and in_valid without start.
        @(negedge clk); in_valid=1;
        @(posedge clk); #1;
        if(in_ready !== 0 || ready !== 1) $fatal(1,"Accepted unsolicited input");
        @(negedge clk); in_valid=0; start=1; row_length=0;
        @(posedge clk); #1;
        if(ready !== 1 || in_ready !== 0) $fatal(1,"Accepted zero length");
        @(negedge clk); row_length=2049;
        @(posedge clk); #1;
        if(ready !== 1 || in_ready !== 0) $fatal(1,"Accepted oversized row");
        @(negedge clk); start=0;

        // Abort while receiving.
        begin_row(3); in_valid=1; in_data=42;
        @(posedge clk); #1;
        reset_dut(); check_idle();
        // Abort after the summation adder has accepted a request.
        begin_row(1); in_valid=1; in_data=7;
        @(posedge clk); #1;
        @(negedge clk); in_valid=0;
        cycles=0;
        while(dut.u_front.u_sum.add_in_valid !== 1 && cycles<20) begin
            @(posedge clk); #1; cycles=cycles+1;
        end
        if(cycles==20) $fatal(1,"Sum phase timeout");
        @(posedge clk); #1;
        reset_dut(); check_idle();
        // Abort during long division.
        begin_row(1); in_valid=1; in_data=7;
        @(posedge clk); #1;
        @(negedge clk); in_valid=0;
        cycles=0;
        while(dut.div_in_valid !== 1 && cycles<30) begin
            @(posedge clk); #1; cycles=cycles+1;
        end
        if(cycles==30) $fatal(1,"Divide phase timeout");
        repeat(5) begin @(posedge clk); #1; end
        reset_dut(); check_idle();

        // Reset with the last FP32 result pending at the quantizer input.
        begin_row(1); in_valid=1; in_data=7;
        @(posedge clk); #1;
        @(negedge clk); in_valid=0;
        cycles=0;
        while(dut.probability_valid !== 1 && cycles<60) begin
            @(posedge clk); #1; cycles=cycles+1;
        end
        if(cycles==60) $fatal(1,"Quantizer pending phase timeout");
        reset_dut(); check_idle();

        while(!$feof(fd)) begin
            status=$fscanf(fd,"%d %h",n,expected_sum);
            if(status==2) begin
                if(n<1 || n>2048) $fatal(1,"Bad vector length");
                for(integer i=0;i<n;i=i+1) begin
                    status=$fscanf(fd,"%h %h %h",samples[i],expected[i],expected_int8[i]);
                    if(status!=3) $fatal(1,"Malformed vector");
                end
                begin_row(n);
                for(integer i=0;i<n;i=i+1) begin
                    if(i%3==1) begin
                        in_valid=0; in_data=32'sh7fffffff;
                        @(posedge clk); #1;
                        if(out_valid !== 0 || done !== 0 || ready !== 0) $fatal(1,"Early output");
                        @(negedge clk);
                    end
                    if(in_ready !== 1) $fatal(1,"Input not ready");
                    in_valid=1; in_data=samples[i];
                    @(posedge clk); #1;
                    if(out_valid !== 0 || out_last !== 0 || done !== 0) $fatal(1,"Output during input");
                    @(negedge clk);
                end
                // Assert start throughout busy time: buffer must NOT be overwritten.
                start=1; row_length=1; in_valid=1; in_data=999;
                received=0; fp32_received=0; cycles=0;
                while(received<n && cycles<40*n+100) begin
                    @(posedge clk); #1; cycles=cycles+1;
                    if(ready !== 0 || in_ready !== 0) $fatal(1,"New row accepted while busy");
                    if(dut.probability_valid === 1) begin
                        if(fp32_received>=n) $fatal(1,"Extra internal FP32 output");
                        if(dut.probability_fp32 !== expected[fp32_received])
                            $fatal(1,"Internal FP32 mismatch row %0d index %0d",rows,fp32_received);
                        fp32_received=fp32_received+1;
                    end
                    if(out_valid === 1) begin
                        if(out_data !== expected_int8[received] || dut.sum_reg !== expected_sum)
                            $fatal(1,"Row %0d index %0d got %h expected %h (sum %h/%h)",
                                   rows,received,out_data,expected_int8[received],dut.sum_reg,expected_sum);
                        if(out_last !== (received==n-1) || done !== (received==n-1))
                            $fatal(1,"Wrong last/done position");
                        $fdisplay(dump_fd,"%0d %0d %h",rows,received,out_data);
                        received=received+1;
                    end else if(out_valid !== 0 || out_last !== 0 || done !== 0)
                        $fatal(1,"Invalid control signal or stray completion");
                    @(negedge clk);
                end
                if(received!=n || fp32_received!=n) $fatal(1,"Output count/timeout mismatch");
                start=0; in_valid=0;
                @(posedge clk); #1;
                if(ready !== 1 || out_valid !== 0 || out_last !== 0 || done !== 0)
                    $fatal(1,"Completion pulse did not clear");
                rows=rows+1; elements=elements+n;
            end else if(!$feof(fd)) $fatal(1,"Malformed row header");
        end
        check_idle();
        if(rows==0) $fatal(1,"No test rows");
        $fclose(fd); $fclose(dump_fd);
        $display("PASS: %0d rows, %0d INT8 outputs and internal FP32 results match Python; valid/last/done/reset checks passed",rows,elements);
        $finish;
    end
    initial begin #20000000; $fatal(1,"Global timeout"); end
endmodule
