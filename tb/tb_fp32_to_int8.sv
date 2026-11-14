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
    always #2.5 clk=~clk;
    reg [2:0] expected_valid;
    reg [7:0] expected_data[0:2];
    integer checked=0;
    always @(posedge clk) begin
        held_data=out_data;
        if (!rst_n) expected_valid=0;
        else begin
            expected_valid={expected_valid[1:0],in_valid};
            expected_data[2]=expected_data[1];
            expected_data[1]=expected_data[0];
            expected_data[0]=expected[7:0];
            #1;
            if(out_valid !== expected_valid[2]) $fatal(1,"Quantizer valid misaligned");
            if(out_valid) begin
                if(out_data !== expected_data[2])
                    $fatal(1,"INT8 got %h expected %h",out_data,expected_data[2]);
                checked++;
            end else if(out_data !== held_data) $fatal(1,"Output changed during bubble");
        end
    end
    task reset_dut;
        @(negedge clk); rst_n=0; in_valid=0;
        #1;
        if(out_data !== 0 || out_valid !== 0) $fatal(1,"Reset failed");
        @(negedge clk); rst_n=1;
    endtask
    initial begin
        if(!$value$plusargs("VECTORS=%s",path)) $fatal(1,"Missing vectors");
        reset_dut();
        // Reset with both internal valid bits set, before either input retires.
        in_valid=1; in_data=32'h3f800000; expected=127;
        repeat(2) @(posedge clk);
        reset_dut();
        fd=$fopen(path,"r"); if(!fd) $fatal(1,"Cannot open vectors");
        while(!$feof(fd)) begin
            status=$fscanf(fd,"%h %d",value,expected);
            if(status==2) begin
                @(negedge clk);
                // Insert bubbles and verify output data holds its last value.
                if(count%7==3) begin
                    in_valid=0;
                    @(negedge clk);
                end
                in_valid=1; in_data=value;
                @(posedge clk); #1;
                count=count+1;
            end else if(!$feof(fd)) $fatal(1,"Malformed vector");
        end
        @(negedge clk); in_valid=0;
        repeat(4) @(negedge clk);
        if(out_valid !== 0 || checked!=count) $fatal(1,"Stale valid or missing output");
        $fclose(fd);
        if(count==0) $fatal(1,"No vectors");
        $display("PASS: %0d FP32-to-INT8 conversions match Python; clock, valid, bubbles and reset checked",count);
        $finish;
    end
    initial begin #3000000; $fatal(1,"Timeout"); end
endmodule
