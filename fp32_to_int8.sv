module fp32_to_int8 (
    input  logic clk,
    input  logic rst_n,
    input  logic in_valid,
    input  logic [31:0] in_data,
    output logic signed [7:0] out_data,
    output logic out_valid
);
    logic sign_bit;
    logic [7:0] exponent;
    logic [22:0] fraction;
    logic is_zero, is_subnormal, is_nan, is_inf;
    logic [23:0] mantissa; 
    logic [30:0] mantissa_wide;
    logic [30:0] product;
    logic [4:0] leading_one_pos; 
    logic [30:0] normalized_product;
    logic signed [10:0] product_exponent;
    logic [23:0] product_mantissa;
    logic product_guard, product_round, product_sticky, product_round_up;
    logic [24:0] rounded_product_mantissa;
    logic [31:0] scaled_fp32;
    logic [23:0] scaled_mantissa;
    logic signed [10:0] integer_shift;
    logic [7:0] integer_part;
    logic integer_guard, integer_sticky, integer_round_up;
    logic [8:0] rounded_integer;
    logic clamp_low, clamp_high;
    logic signed [7:0] quantized_value;
    always_comb begin
        sign_bit = in_data[31];
        exponent = in_data[30:23];
        fraction = in_data[22:0];
        is_zero = (exponent == 0 && fraction == 0);
        is_subnormal = (exponent == 0 && fraction != 0);
        is_nan = (exponent == 255 && fraction != 0);
        is_inf = (exponent == 255 && fraction == 0);
        mantissa = {exponent != 0, fraction};
        mantissa_wide = {7'b0, mantissa};
        product = 0;
        leading_one_pos = 0;
        normalized_product = 0;
        product_exponent = 0;
        product_mantissa = 0;
        product_guard = 0;
        product_round = 0;
        product_sticky = 0;
        product_round_up = 0;
        rounded_product_mantissa = 0;
        scaled_fp32 = 0;
        scaled_mantissa = 0;
        integer_shift = 0;
        integer_part = 0;
        integer_guard = 0;
        integer_sticky = 0;
        integer_round_up = 0;
        rounded_integer = 0;
        quantized_value = 0;
        clamp_low = sign_bit || is_nan || exponent < 119;
        clamp_high = !sign_bit && !is_nan && exponent >= 127; 
        if (clamp_low) begin
            quantized_value = 8'sd0;
        end else if (clamp_high) begin
            quantized_value = 8'sd127;
        end else begin
            product = (mantissa_wide << 7) - mantissa_wide;
            for (int i=0; i<31; i=i+1)
                if (product[i]) leading_one_pos = i[4:0];
            normalized_product = product << (30-leading_one_pos);
            product_exponent = $signed({3'b0, exponent}) - 11'sd23
                             + $signed({6'b0, leading_one_pos});
            product_mantissa = normalized_product[30:7];
            product_guard = normalized_product[6];
            product_round = normalized_product[5];
            product_sticky = |normalized_product[4:0];
            product_round_up = product_guard &&
                              (product_round || product_sticky || product_mantissa[0]);
            rounded_product_mantissa = {1'b0, product_mantissa} + {24'b0, product_round_up};
            if (rounded_product_mantissa[24]) begin
                rounded_product_mantissa = rounded_product_mantissa >> 1;
                product_exponent = product_exponent + 11'sd1;
            end
            scaled_fp32 = {1'b0, product_exponent[7:0], rounded_product_mantissa[22:0]};
            scaled_mantissa = {1'b1, scaled_fp32[22:0]};
            integer_shift = 11'sd150 - $signed({3'b0, scaled_fp32[30:23]});
            integer_part = scaled_mantissa >> integer_shift;
            if (integer_shift <= 24)
                integer_guard = scaled_mantissa[integer_shift-1];
            for (int i=0; i<24; i=i+1)
                if (i < integer_shift-1) integer_sticky = integer_sticky | scaled_mantissa[i];
            integer_round_up = integer_guard && (integer_sticky || integer_part[0]);
            rounded_integer = {1'b0, integer_part} + {8'b0, integer_round_up};
            quantized_value = (rounded_integer > 127) ? 8'sd127 : $signed(rounded_integer[7:0]);
        end
    end
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_data <= 8'sd0;
            out_valid <= 1'b0;
        end else begin
            out_valid <= in_valid;
            if (in_valid) out_data <= quantized_value;
        end
    end
endmodule
