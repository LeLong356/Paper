module fp32_div_positive (
    input logic clk, rst_n, in_valid,
    output logic in_ready,
    input logic [31:0] numerator, denominator,
    output logic [31:0] result,
    output logic out_valid
);
    typedef enum logic [2:0] {
        IDLE, 
        UNPACK, 
        NORMALIZE, 
        DIVIDE, 
        ROUND, 
        PACK, 
        COMPLETE
    } state_t;
    state_t state, next_state;
    logic [31:0] numerator_reg, denominator_reg, result_reg;
    logic numerator_zero, denominator_zero, numerator_inf, denominator_inf;
    logic invalid_input, special_case;
    logic [31:0] special_result;
    logic [23:0] numerator_mantissa, denominator_mantissa;
    integer numerator_exp, denominator_exp, initial_exp;
    logic [24:0] normalized_numerator;
    logic signed [10:0] quotient_exp;
    logic [23:0] divisor;
    logic [25:0] remainder, quotient, remainder_after_subtract;
    logic [5:0] bit_count;
    logic next_quotient_bit;
    logic [26:0] round_input;
    logic guard_bit, round_bit, sticky_bit, round_up;
    logic [24:0] rounded_mantissa;
    integer rounded_exp;
    logic [7:0] final_exponent, packed_exponent;
    logic [22:0] final_fraction, packed_fraction;

    assign in_ready = rst_n && (state == IDLE);
    assign out_valid = rst_n && (state == COMPLETE);
    assign result = result_reg;
    function automatic [26:0] shift_sticky(input logic [26:0] value, input integer amount);
        logic [26:0] shifted;
        logic lost;
        begin
            shifted = value >> amount;
            lost = 1'b0;
            for (int i=0; i<27; i=i+1)
                if (i < amount) lost = lost | value[i];
            shifted[0] = shifted[0] | lost;
            shift_sticky = shifted;
        end
    endfunction

    always_comb begin
        numerator_zero = (numerator_reg[30:0] == 0);
        denominator_zero = (denominator_reg[30:0] == 0);
        numerator_inf = (numerator_reg[30:0] == 31'h7f800000);
        denominator_inf = (denominator_reg[30:0] == 31'h7f800000);
        invalid_input = (numerator_reg[31] && !numerator_zero) ||
                        (denominator_reg[31] && !denominator_zero) ||
                        (numerator_reg[30:23] == 255 && numerator_reg[22:0] != 0) ||
                        (denominator_reg[30:23] == 255 && denominator_reg[22:0] != 0);
        special_case = 1'b1;
        special_result = 32'h00000000;
        if (invalid_input || (numerator_zero && denominator_zero) ||
            (numerator_inf && denominator_inf)) special_result = 32'h7fc00000;
        else if (denominator_zero || numerator_inf) special_result = 32'h7f800000;
        else if (numerator_zero || denominator_inf) special_result = 32'h00000000;
        else special_case = 1'b0;
    end

    always_comb begin
        numerator_exp = (numerator_reg[30:23] == 0) ? 1 : int'(numerator_reg[30:23]);
        denominator_exp = (denominator_reg[30:23] == 0) ? 1 : int'(denominator_reg[30:23]);
        numerator_mantissa = {numerator_reg[30:23] != 0, numerator_reg[22:0]};
        denominator_mantissa = {denominator_reg[30:23] != 0, denominator_reg[22:0]};
        for (int i=0; i<23; i=i+1) begin
            if (!numerator_mantissa[23]) begin
                numerator_mantissa = numerator_mantissa << 1;
                numerator_exp = numerator_exp - 1;
            end
            if (!denominator_mantissa[23]) begin
                denominator_mantissa = denominator_mantissa << 1;
                denominator_exp = denominator_exp - 1;
            end
        end
        initial_exp = numerator_exp - denominator_exp + 127;
        normalized_numerator = {1'b0, numerator_mantissa};
        if (numerator_mantissa < denominator_mantissa) begin
            normalized_numerator = normalized_numerator << 1;
            initial_exp = initial_exp - 1;
        end
    end
    always_comb begin
        next_quotient_bit = (remainder >= {2'b00, divisor});
        remainder_after_subtract = remainder;
        if (next_quotient_bit)
            remainder_after_subtract = remainder - {2'b00, divisor};
    end
    
    always_comb begin
        round_input = {quotient, (remainder != 0)};
        rounded_exp = int'($signed(quotient_exp));
        if (rounded_exp <= 0) begin
            round_input = shift_sticky(round_input, 1-rounded_exp);
            rounded_exp = 1;
        end
        guard_bit = round_input[2];
        round_bit = round_input[1];
        sticky_bit = round_input[0];
        round_up = guard_bit && (round_bit || sticky_bit || round_input[3]);
        rounded_mantissa = {1'b0, round_input[26:3]} + {24'b0, round_up};
        if (rounded_mantissa[24]) begin
            rounded_mantissa = rounded_mantissa >> 1;
            rounded_exp = rounded_exp + 1;
        end
        if (rounded_exp == 1 && !rounded_mantissa[23]) rounded_exp = 0;
        packed_exponent = rounded_exp[7:0];
        packed_fraction = rounded_mantissa[22:0];
        if (rounded_exp >= 255) begin
            packed_exponent = 8'hff;
            packed_fraction = 0;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            numerator_reg <= 0; denominator_reg <= 0; result_reg <= 0;
            quotient_exp <= 0; divisor <= 0; remainder <= 0;
            quotient <= 0; bit_count <= 0;
            final_exponent <= 0; final_fraction <= 0;
        end else begin
            state <= next_state;
            case (state)
                IDLE: if (in_valid && in_ready) begin
                    numerator_reg <= numerator;
                    denominator_reg <= denominator;
                end
                UNPACK: if (special_case) result_reg <= special_result;
                NORMALIZE: begin
                    quotient_exp <= initial_exp[10:0];
                    divisor <= denominator_mantissa;
                    remainder <= {1'b0, normalized_numerator};
                    quotient <= 0;
                    bit_count <= 0;
                end
                DIVIDE: begin
                    quotient <= {quotient[24:0], next_quotient_bit};
                    remainder <= remainder_after_subtract << 1;
                    bit_count <= bit_count + 1'b1;
                end
                ROUND: begin
                    final_exponent <= packed_exponent;
                    final_fraction <= packed_fraction;
                end
                PACK: result_reg <= {1'b0, final_exponent, final_fraction};
                default: begin end
            endcase
        end
    end

    always_comb begin
        next_state = state;
        case (state)
            IDLE: if (in_valid && in_ready) next_state = UNPACK;
            UNPACK: begin
                if (special_case) next_state = COMPLETE;
                else next_state = NORMALIZE;
            end
            NORMALIZE: next_state = DIVIDE;
            DIVIDE: if (bit_count == 25) next_state = ROUND;
            ROUND: next_state = PACK;
            PACK: next_state = COMPLETE;
            COMPLETE: next_state = IDLE;
            default: next_state = IDLE;
        endcase
    end
endmodule
