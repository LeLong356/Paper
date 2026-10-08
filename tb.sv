`timescale 1ns / 1ps

module tb_vexp_vivado();

    logic [15:0] x_in;
    logic [15:0] exp_out;

    vexp dut (
        .x_in(x_in),
        .exp_out(exp_out)
    );

    initial begin
        // [Test 1] x = 0.0 (Bfloat16: 16'h0000)
        // Kỳ vọng: e^0 = 1.0 (16'h3F80) -> Kết quả mới: 16'h3f80 (1.0)
        x_in = 16'h0000;
        #20; 
        $display("Test 1 [x =   0.0] | x_in = %h | exp_out = %h", x_in, exp_out);

        // [Test 2] x = 1.0 (Bfloat16: 16'h3F80)
        // Kỳ vọng: e^1 ~ 2.718 (16'h402E) -> Kết quả mới: 16'h402e (2.71875)
        x_in = 16'h3F80;
        #20;
        $display("Test 2 [x =   1.0] | x_in = %h | exp_out = %h", x_in, exp_out);

        // [Test 3] x = -1.0 (Bfloat16: 16'hBF80)
        // Kỳ vọng: e^-1 ~ 0.3678 (16'h3EBC) -> Kết quả mới: 16'h3ebc (0.3671875)
        x_in = 16'hBF80;
        #20;
        $display("Test 3 [x =  -1.0] | x_in = %h | exp_out = %h", x_in, exp_out);

        // [Test 4] x = 2.0 (Bfloat16: 16'h4000)
        // Kỳ vọng: e^2 ~ 7.389 (16'h40EC/40ED) -> Kết quả mới: 16'h40ed (7.40625)
        x_in = 16'h4000;
        #20;
        $display("Test 4 [x =   2.0] | x_in = %h | exp_out = %h", x_in, exp_out);

        // [Test 5] x = 90.0 (Bfloat16: 16'h42B4) -> Vượt ngưỡng tràn Bfloat16 (88.72)
        // Kỳ vọng: +Inf (16'h7F80) -> Kết quả mới: 16'h7f80
        x_in = 16'h42B4;
        #20;
        $display("Test 5 [Overflow+] | x_in = %h | exp_out = %h", x_in, exp_out);

        // [Test 6] x = -90.0 (Bfloat16: 16'hC2B4) -> Tràn âm (Underflow về 0)
        // Kỳ vọng: 0.0 (16'h0000) -> Kết quả mới: 16'h0000
        x_in = 16'hC2B4;
        #20;
        $display("Test 6 [Underflow] | x_in = %h | exp_out = %h", x_in, exp_out);

        // [Test 7] x = NaN (Bfloat16: 16'h7FC1)
        // Kỳ vọng: Canonical NaN (16'h7FC0) -> Kết quả mới: 16'h7fc0
        x_in = 16'h7FC1;
        #20;
        $display("Test 7 [NaN input] | x_in = %h | exp_out = %h", x_in, exp_out);

        $finish; 
    end

endmodule