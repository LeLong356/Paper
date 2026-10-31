module fp32_add_positive (
    input logic clk, rst_n, in_valid,
    output logic in_ready,
    input logic [31:0] a, b,
    output logic [31:0] result,
    output logic out_valid
);
    logic [31:0] result_next;
    logic [26:0] mant_a, mant_b, aligned_a, aligned_b, normalized;
    logic [27:0] sum_ext;
    logic [24:0] rounded;
    integer exp_a, exp_b, common_exp;
    function automatic [26:0] shift_sticky(input logic [26:0] value, input integer amount);
        logic [26:0] shifted;
        logic sticky;
        begin
            shifted = value >> amount;
            sticky = 1'b0;
            for (int i=0; i<27; i=i+1)
                if (i < amount) sticky = sticky | value[i];
            shifted[0] = shifted[0] | sticky;
            shift_sticky = shifted;
        end
    endfunction

    always_comb begin
        exp_a = (a[30:23] == 0) ? 1 : int'(a[30:23]);
        exp_b = (b[30:23] == 0) ? 1 : int'(b[30:23]);
        mant_a = {a[30:23] != 0, a[22:0], 3'b000};
        mant_b = {b[30:23] != 0, b[22:0], 3'b000};
        common_exp = (exp_a > exp_b) ? exp_a : exp_b;
        aligned_a = shift_sticky(mant_a, common_exp-exp_a);
        aligned_b = shift_sticky(mant_b, common_exp-exp_b);
        sum_ext = {1'b0, aligned_a} + {1'b0, aligned_b};
        normalized = sum_ext[26:0];
        if (sum_ext[27]) begin
            normalized = sum_ext[27:1];
            normalized[0] = normalized[0] | sum_ext[0];
            common_exp = common_exp + 1;
        end
        rounded = {1'b0, normalized[26:3]};
        if (normalized[2] && (normalized[1] || normalized[0] || normalized[3]))
            rounded = rounded + 25'd1;
        if (rounded[24]) begin
            rounded = rounded >> 1;
            common_exp = common_exp + 1;
        end
        if (common_exp == 1 && !rounded[23]) common_exp = 0;
        result_next = {1'b0, common_exp[7:0], rounded[22:0]};
        if (common_exp >= 255) result_next = 32'h7f800000;
        if (a[30:0] == 31'h7f800000 || b[30:0] == 31'h7f800000)
            result_next = 32'h7f800000;
        if (a[31] || b[31] || (a[30:23] == 255 && a[22:0] != 0) || (b[30:23] == 255 && b[22:0] != 0))
            result_next = 32'h7fc00000;
    end

    assign in_ready = rst_n;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            result <= '0;
            out_valid <= 1'b0;
        end else begin
            out_valid <= in_valid && in_ready;
            if (in_valid && in_ready) 
                result <= result_next;
        end
    end
endmodule
