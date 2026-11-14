module int33_to_bf16 (
    input  logic signed [32:0] in_data,
    output logic        [15:0] out_bf16
);
    logic sign_bit;
    logic is_zero;
    logic [32:0] magnitude;
    logic [5:0] leading_one_pos;
    logic [7:0] exponent;
    logic [32:0] normalized_magnitude;
    logic [6:0] fraction;
    logic guard_bit;
    logic round_bit;
    logic sticky_bit;
    logic round_up;
    logic [8:0] rounded_significand;
    logic [7:0] final_exponent;
    logic [6:0] final_fraction;

    always_comb begin
        sign_bit = in_data[32];
        is_zero = (in_data == 0);
        magnitude = sign_bit ? (~in_data + 33'd1) : in_data;
        leading_one_pos = 0;
        for (int i = 0; i < 33; i = i + 1) begin
            if (magnitude[i])
                leading_one_pos = i[5:0];
        end
        exponent = 8'd127 + {2'b00, leading_one_pos};
        normalized_magnitude = magnitude << (32 - leading_one_pos);
        fraction = normalized_magnitude[31:25];
        guard_bit = normalized_magnitude[24];
        round_bit = normalized_magnitude[23];
        sticky_bit = |normalized_magnitude[22:0];
        round_up = guard_bit && (round_bit || sticky_bit || fraction[0]);
        rounded_significand = {1'b0, 1'b1, fraction} + {8'b0, round_up};
        final_exponent = exponent;
        final_fraction = rounded_significand[6:0];
        if (rounded_significand[8]) begin
            final_exponent = exponent + 8'd1;
            final_fraction = 7'd0;
        end
        out_bf16 = is_zero ? 16'h0000 : {sign_bit, final_exponent, final_fraction};
    end
endmodule
