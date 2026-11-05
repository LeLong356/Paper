`timescale 1ns/1ps
// Run via python3 verify_softmax_exp_sum.py.
module tb_softmax_exp_sum;
    localparam int MAX_LENGTH = 32;
    logic clk=0, rst_n=0, start=0, in_valid=0;
    logic [$clog2(MAX_LENGTH+1)-1:0] row_length=0;
    logic signed [31:0] in_data=0;
    wire ready, in_ready, sum_valid;
    wire [31:0] sum_fp32;
    logic [$clog2(MAX_LENGTH+1)-1:0] read_index=0;
    wire [15:0] read_data;
    reg [15:0] expected_exp[0:MAX_LENGTH-1];
    reg signed [31:0] samples[0:MAX_LENGTH-1];
    reg [31:0] expected;
    integer fd,status,n,cycles,rows=0,elements=0;
    string path;
    softmax_exp_sum dut(.*);
    always #2.5 clk=~clk; // 5 ns period (200 MHz)
    task reset_dut;
        @(negedge clk); rst_n=0; start=0; in_valid=0;
        #1;
        if(ready !== 0 || sum_valid !== 0 || in_ready !== 0 || read_data !== 0) $fatal(1,"Reset failed");
        @(negedge clk); rst_n=1;
    endtask
    task begin_row(input integer length);
        @(negedge clk);
        if(ready !== 1) $fatal(1,"Not ready for new row");
        start=1; row_length=length;
        @(posedge clk); #1;
        if(ready !== 0 || in_ready !== 1 || sum_valid !== 0) $fatal(1,"Start failed");
        @(negedge clk); start=0; row_length=0;
    endtask
    initial begin
        if(!$value$plusargs("VECTORS=%s",path)) $fatal(1,"Missing vectors");
        fd=$fopen(path,"r"); if(!fd) $fatal(1,"Cannot open vectors");
        reset_dut();
        @(negedge clk); start=1; row_length=0;
        @(posedge clk); #1;
        if(ready !== 1 || in_ready !== 0) $fatal(1,"Zero length accepted");
        @(negedge clk); row_length=MAX_LENGTH+1;
        @(posedge clk); #1;
        if(ready !== 1 || in_ready !== 0) $fatal(1,"Oversized row accepted");
        @(negedge clk); start=0;
        // Reset while receiving an unfinished row.
        begin_row(3); in_valid=1; in_data=42;
        @(posedge clk); #1; reset_dut();
        // Reset while the FP32 addition is pending.
        begin_row(1); in_valid=1; in_data=7;
        @(posedge clk); #1;
        @(negedge clk); in_valid=0;
        repeat(3) begin @(posedge clk); #1; end
        reset_dut();
        while(!$feof(fd)) begin
            status=$fscanf(fd,"%d %h",n,expected);
            if(status==2) begin
                for(integer i=0;i<n;i=i+1) begin
                    status=$fscanf(fd,"%h %h",samples[i],expected_exp[i]);
                    if(status!=2) $fatal(1,"Malformed sample");
                end
                begin_row(n);
                for(integer i=0;i<n;i=i+1) begin
                    if(i%3==1) begin
                        in_valid=0; in_data=32'sh7fffffff;
                        @(posedge clk); #1;
                        if(sum_valid !== 0 || ready !== 0) $fatal(1,"Premature completion");
                        @(negedge clk);
                    end
                    in_valid=1; in_data=samples[i];
                    if(in_ready !== 1) $fatal(1,"Missing input ready");
                    @(posedge clk); #1;
                    if(sum_valid !== 0) $fatal(1,"Sum before receiving all inputs");
                    @(negedge clk);
                end
                // Deliberately request another row while busy: it must be ignored.
                start=1; row_length=1; in_valid=1; in_data=999;
                cycles=0;
                while(sum_valid !== 1 && cycles<10*n+15) begin
                    @(posedge clk); #1; cycles=cycles+1;
                    if(ready !== 0 || in_ready !== 0) $fatal(1,"Accepted row while summing");
                end
                if(sum_valid !== 1 || sum_fp32 !== expected)
                    $fatal(1,"Row %0d n=%0d got %h expected %h",rows,n,sum_fp32,expected);
                if(rows==0) $display("[2,1,0]: sum_fp32=%h",sum_fp32);
                @(negedge clk); start=0; in_valid=0;
                @(posedge clk); #1;
                if(sum_valid !== 0 || ready !== 1) $fatal(1,"Bad done pulse or readiness");
                // Read every stored numerator through the PUBLIC wrapper port.
                for(integer i=0;i<n;i=i+1) begin
                    @(negedge clk); read_index=i;
                    @(posedge clk); #1;
                    if(read_data !== expected_exp[i])
                        $fatal(1,"Row %0d read[%0d]=%h expected %h",rows,i,read_data,expected_exp[i]);
                end
                @(negedge clk); read_index=n;
                @(posedge clk); #1; if(read_data !== 0) $fatal(1,"Out-of-row read not guarded");
                @(negedge clk); read_index=MAX_LENGTH;
                @(posedge clk); #1; if(read_data !== 0) $fatal(1,"Out-of-buffer read not guarded");
                rows=rows+1; elements=elements+n;
            end else if(!$feof(fd)) $fatal(1,"Malformed header");
        end
        if(rows==0) $fatal(1,"No tests");
        $fclose(fd);
        $display("PASS: %0d rows, %0d inputs/readbacks; FP32 sums and BF16 read port match Python; control checks passed",rows,elements);
        $finish;
    end
    initial begin #3000000; $fatal(1,"Timeout"); end
endmodule
