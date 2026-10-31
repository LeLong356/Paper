`timescale 1ns/1ps
// Run with verify_fp32_div_positive.py to generate exact Python references.
module tb_fp32_div_positive;
    logic clk=0, rst_n=0, in_valid=0;
    logic [31:0] numerator=0, denominator=0;
    wire in_ready, out_valid;
    wire [31:0] result;
    reg [31:0] a,b,expected;
    integer fd,status,cycles,count=0;
    string path;
    fp32_div_positive dut(.*);
    always #5 clk=~clk;
    task reset_dut;
        @(negedge clk); rst_n=0; in_valid=0;
        #1;
        if(in_ready !== 0 || out_valid !== 0 || result !== 0) $fatal(1,"Reset failed");
        @(negedge clk); rst_n=1;
    endtask
    initial begin
        if(!$value$plusargs("VECTORS=%s",path)) $fatal(1,"Missing vectors");
        reset_dut();
        // Reset aborts an in-progress long division.
        @(negedge clk); in_valid=1; numerator=32'h3f800000; denominator=32'h40400000;
        @(posedge clk); #1;
        @(negedge clk); in_valid=0;
        repeat(8) @(posedge clk);
        reset_dut();
        repeat(35) begin
            @(posedge clk); #1;
            if(out_valid !== 0 || in_ready !== 1) $fatal(1,"Stale completion after reset");
        end
        fd=$fopen(path,"r"); if(!fd) $fatal(1,"Cannot open vectors");
        while(!$feof(fd)) begin
            status=$fscanf(fd,"%h %h %h",a,b,expected);
            if(status==3) begin
                @(negedge clk);
                if(in_ready !== 1) $fatal(1,"Not ready");
                numerator=a; denominator=b; in_valid=1;
                @(posedge clk); #1;
                if(in_ready !== 0 || out_valid !== 0) $fatal(1,"Bad acceptance");
                // Change inputs while busy: the saved operands must be used.
                @(negedge clk); numerator=32'hdeadbeef; denominator=0;
                cycles=0;
                while(out_valid !== 1 && cycles<40) begin
                    @(posedge clk); #1; cycles=cycles+1;
                    if(in_ready !== 0) $fatal(1,"Ready while busy");
                end
                if(out_valid !== 1 || result !== expected)
                    $fatal(1,"%h / %h = %h, expected %h; cycles=%0d",a,b,result,expected,cycles);
                if(count<4) $display("Example %h / %h = %h (%0d clocks after accept)",a,b,result,cycles);
                @(negedge clk); in_valid=0;
                @(posedge clk); #1;
                if(out_valid !== 0 || in_ready !== 1 || result !== expected)
                    $fatal(1,"Output pulse/hold failed");
                count=count+1;
            end else if(!$feof(fd)) $fatal(1,"Malformed vector");
        end
        if(count==0) $fatal(1,"Empty test");
        $display("PASS: %0d divisions match exact Python reference; handshake, busy inputs and reset passed",count);
        $finish;
    end
    initial begin #20000000; $fatal(1,"Timeout"); end
endmodule
