`timescale 1ns / 1ps

module tb_vexp_vivado();

    logic [15:0] x_in;
    logic [15:0] exp_out;
    logic [15:0] expected;
    integer sample;
    integer dump_file;
    string dump_path;

    vexp dut (
        .x_in(x_in),
        .exp_out(exp_out)
    );

    function automatic logic [15:0] reference_exp(input logic [15:0] bits);
        integer exponent, fraction, product, shift_amount, magnitude, encoded, corrected;
        begin
            exponent = (bits >> 7) & 255;
            fraction = bits & 127;
            if (exponent == 0)
                reference_exp = 16'h3F80;
            else if (exponent == 255 && fraction != 0)
                reference_exp = 16'h7FC0;
            else if (exponent > 133)
                reference_exp = bits[15] ? 16'h0000 : 16'h7F80;
            else begin
                product = (128 + fraction) * 23637;
                shift_amount = 141 - exponent;
                magnitude = (product >> shift_amount) + ((product >> (shift_amount - 1)) & 1);
                encoded = 16256 + (bits[15] ? -magnitude : magnitude);
                if (encoded < 128)
                    reference_exp = 16'h0000;
                else if (encoded >= 32640)
                    reference_exp = 16'h7F80;
                else begin
                    fraction = encoded & 127;
                    if (fraction < 64)
                        corrected = (7 * fraction * (fraction + 422)) / 4096;
                    else
                        corrected = 127 - (7 * (127 - fraction) * (fraction + 278)) / 2048;
                    reference_exp = (encoded & 65408) | corrected;
                end
            end
        end
    endfunction

    task automatic check_case(input logic [15:0] bits, input logic [15:0] wanted);
        begin
            x_in = bits;
            #20;
            if (exp_out !== wanted)
                $fatal(1, "Directed failure: input=%h expected=%h actual=%h", bits, wanted, exp_out);
            $display("Directed PASS: input=%h output=%h", bits, exp_out);
        end
    endtask

    initial begin
        dump_file = 0;
        if ($value$plusargs("DUMP=%s", dump_path)) begin
            dump_file = $fopen(dump_path, "w");
            if (dump_file == 0)
                $fatal(1, "Cannot open output dump: %s", dump_path);
        end
        check_case(16'h0000, 16'h3F80);
        check_case(16'h8000, 16'h3F80);
        check_case(16'h0001, 16'h3F80);
        check_case(16'h007F, 16'h3F80);
        check_case(16'h8001, 16'h3F80);
        check_case(16'h807F, 16'h3F80);
        check_case(16'h3F80, 16'h402E);
        check_case(16'hBF80, 16'h3EBD);
        check_case(16'h4000, 16'h40ED);
        check_case(16'hBF2A, 16'h3F03);
        check_case(16'h42B4, 16'h7F80);
        check_case(16'hC2B4, 16'h0000);
        check_case(16'h7F80, 16'h7F80);
        check_case(16'hFF80, 16'h0000);
        check_case(16'h7FC1, 16'h7FC0);
        check_case(16'hFFC1, 16'h7FC0);

        for (sample = 0; sample < 65536; sample = sample + 1) begin
            x_in = sample[15:0];
            #1;
            expected = reference_exp(x_in);
            if ((^exp_out) === 1'bx)
                $fatal(1, "Unknown output: input=%h output=%h", x_in, exp_out);
            if (exp_out !== expected)
                $fatal(1, "Reference mismatch: input=%h expected=%h actual=%h", x_in, expected, exp_out);
            if (x_in[14:7] == 0 && exp_out !== 16'h3F80)
                $fatal(1, "Zero/subnormal input must produce one: input=%h", x_in);
            if (x_in[15] && x_in[14:7] != 255 && exp_out > 16'h3F80)
                $fatal(1, "Negative finite input must produce output in [0,1]: input=%h", x_in);
            if (dump_file != 0)
                $fdisplay(dump_file, "%04h %04h", x_in, exp_out);
        end
        if (dump_file != 0)
            $fclose(dump_file);
        $display("PASS: all 65536 BF16 patterns match the bit-level reference; no X/Z outputs.");
        $finish;
    end

endmodule
