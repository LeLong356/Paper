`timescale 1ns/1ps
// Run with python3 verify_fp32_to_int8.py.
module tb_fp32_to_int8;
    logic clk=0, rst_n=0, in_valid=0;
    logic [31:0] in_data=0;
    wire signed [7:0] out_data;
    wire out_valid;
    reg [31:0] value;
    reg signed [7:0] held_data;
    integer fd,status,expected,count=0;
    string path;
    fp32_to_int8 dut(.*);
    always #5 clk=~clk;
    task reset_dut;
        @(negedge clk); rst_n=0; in_valid=0;
        #1;
        if(out_data !== 0 || out_valid !== 0) $fatal(1,"Reset failed");
        @(negedge clk); rst_n=1;
    endtask
    initial begin
        if(!$value$plusargs("VECTORS=%s",path)) $fatal(1,"Missing vectors");
        reset_dut();
        fd=$fopen(path,"r"); if(!fd) $fatal(1,"Cannot open vectors");
        while(!$feof(fd)) begin
            status=$fscanf(fd,"%h %d",value,expected);
            if(status==2) begin
                @(negedge clk);
                // Insert bubbles and verify output data holds its last value.
                if(count%7==3) begin
                    held_data=out_data; in_valid=0; in_data=32'h7fc00000;
                    @(posedge clk); #1;
                    if(out_valid !== 0 || out_data !== held_data) $fatal(1,"Invalid input accepted");
                    @(negedge clk);
                end
                held_data=out_data;
                in_valid=1; in_data=value;
                #1; if(out_data !== held_data) $fatal(1,"Output changed before clock");
                @(posedge clk); #1;
                if(out_valid !== 1 || out_data !== expected[7:0])
                    $fatal(1,"FP32 %h -> %0d expected %0d",value,out_data,expected);
                if(out_data < 0) $fatal(1,"Output outside 0..127");
                count=count+1;
                if(count==25) reset_dut();
            end else if(!$feof(fd)) $fatal(1,"Malformed vector");
        end
        @(negedge clk); in_valid=0;
        @(posedge clk); #1; if(out_valid !== 0) $fatal(1,"Stale valid");
        $fclose(fd);
        if(count==0) $fatal(1,"No vectors");
        $display("PASS: %0d FP32-to-INT8 conversions match Python; clock, valid, bubbles and reset checked",count);
        $finish;
    end
    initial begin #3000000; $fatal(1,"Timeout"); end
endmodule
