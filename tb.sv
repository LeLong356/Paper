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
        // Kỳ vọng: e^0 = 1.0 (Bfloat16: 16'h3F80)
        // kết quả: 16'h3f80
        x_in = 16'h0000;
        #20; 
        $display("Test 1 [x =  0.0] | x_in = %h | exp_out = %h", x_in, exp_out);

        // [Test 2] x = 1.0 (Bfloat16: 16'h3F80)
        // Kỳ vọng: e^1 ~ 2.718 (Bfloat16: 16'h402D)
        // kết quả: 16'h402e = 2.71875
        x_in = 16'h3F80;
        #20;
        $display("Test 2 [x =  1.0] | x_in = %h | exp_out = %h", x_in, exp_out);

        // [Test 3] x = -1.0 (Bfloat16: 16'hBF80)
        // Kỳ vọng: e^-1 ~ 0.367 (Bfloat16: 16'h3EBC)
        // kết quả: 16'h3e98 = 0.297
        x_in = 16'hBF80;
        #20;
        $display("Test 3 [x = -1.0] | x_in = %h | exp_out = %h", x_in, exp_out);

        // [Test 4] x = 2.0 (Bfloat16: 16'h4000)
        // Kỳ vọng: e^2 ~ 7.389 (Bfloat16: 16'h40EC)
        // kết quả: 16'h40d2 = 6.5625   
        x_in = 16'h4000;
        #20;
        $display("Test 4 [x =  2.0] | x_in = %h | exp_out = %h", x_in, exp_out);

        // [Test 5] Test cờ chặn tràn số (Overflow threshold E >= 133)
        // x = 64.0 (Bfloat16: 16'h4280) 
        // kết quả: 16'h7f80, overflow
        x_in = 16'h4280;
        #20;
        $display("Test 5 [Overflow] | x_in = %h | exp_out = %h", x_in, exp_out);
        $finish; 
    end

endmodule