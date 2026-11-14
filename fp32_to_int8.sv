module fp32_to_int8 (
    input  logic clk,
    input  logic rst_n,
    input  logic in_valid,
    input  logic [31:0] in_data,
    output logic signed [7:0] out_data,
    output logic out_valid
);
    // Stage 1: exact product by 127. The active (unclamped) inputs are normal.
    logic [30:0] mantissa_wide, product_q;
    logic [7:0] exponent, exponent_q;
    logic low_q, high_q;
    assign exponent = in_data[30:23];
    assign mantissa_wide = {7'b0, 1'b1, in_data[22:0]};

    // Stage 2: normalize and round the product to FP32, ties to even.
    // For a normalized 24-bit mantissa times 127 the leading bit is 29 or 30.
    logic [30:0] normalized;
    logic [24:0] rounded;
    logic [23:0] scaled_mantissa_q;
    logic [7:0] scaled_exp_q;
    logic scaled_low_q, scaled_high_q;
    assign normalized = product_q[30] ? product_q : product_q << 1;
    assign rounded = {1'b0, normalized[30:7]} +
                     (normalized[6] && ((|normalized[5:0]) || normalized[7]));

    always_ff @(posedge clk) begin
        product_q <= (mantissa_wide << 7) - mantissa_wide;
        exponent_q <= exponent;
        low_q <= in_data[31] || exponent < 119 ||
                 (exponent == 255 && |in_data[22:0]);
        high_q <= exponent >= 127;
        scaled_exp_q <= exponent_q + 8'd6 + product_q[30] + rounded[24];
        scaled_mantissa_q <= rounded[24] ? rounded[24:1] : rounded[23:0];
        scaled_low_q <= low_q;
        scaled_high_q <= high_q;
    end

    // Stage 3: round FP32 to an integer, then clamp to the INT8 range.
    logic [4:0] shift_amount;
    logic [7:0] integer_part;
    logic guard_bit, sticky_bit;
    logic [8:0] rounded_integer;
    assign shift_amount = 8'd150 - scaled_exp_q;
    assign integer_part = scaled_mantissa_q >> shift_amount;
    assign guard_bit = shift_amount <= 24 && scaled_mantissa_q[shift_amount-1'b1];
    always_comb begin
        sticky_bit = 1'b0;
        for (int i=0; i<24; i++)
            if (i+1 < shift_amount) sticky_bit |= scaled_mantissa_q[i];
    end
    assign rounded_integer = {1'b0, integer_part} +
                             (guard_bit && (sticky_bit || integer_part[0]));

    logic product_valid, scaled_valid;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            {product_valid, scaled_valid, out_valid} <= '0;
            out_data <= '0;
        end else begin
            product_valid <= in_valid;
            scaled_valid <= product_valid;
            out_valid <= scaled_valid;
            if (scaled_valid) begin
                if (scaled_low_q) out_data <= 8'sd0;
                else if (scaled_high_q || rounded_integer > 127) out_data <= 8'sd127;
                else out_data <= $signed(rounded_integer[7:0]);
            end
        end
    end
endmodule
