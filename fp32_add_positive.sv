module fp32_add_positive (
    input logic clk, rst_n, in_valid,
    output logic in_ready,
    input logic [31:0] a, b,
    output logic [31:0] result,
    output logic out_valid
);
    logic [4:0] valid_pipe;
    logic [31:0] a_q, b_q;
    logic [7:0] exp_a, exp_b, shift_q, exp_q, aligned_exp;
    logic [26:0] mant_a, mant_b, big_q, small_q, big_aligned, small_aligned;
    logic [27:0] sum_q;
    logic [7:0] sum_exp;
    logic [26:0] normalized;
    logic [24:0] rounded_q;
    logic [8:0] round_exp, final_exp;
    logic [22:0] final_frac;

    typedef enum logic [1:0] {
        FINITE, 
        INF, 
        INVALID} kind_t;
    kind_t prep_kind, align_kind, sum_kind, round_kind;

    function automatic logic [26:0] shift_sticky(input logic [26:0] value,
                                                  input logic [7:0] amount);
        logic [26:0] shifted;
        shifted = value;
        for (int k = 0; k < 5; k++) begin
            if (amount[k])
                shifted = (shifted >> (1 << k)) |
                          {26'b0, |(shifted & ((27'd1 << (1 << k)) - 1'b1))};
        end
        return (|amount[7:5]) ? {26'b0, |value} : shifted;
    endfunction

    assign exp_a = a_q[30:23] == 0 ? 8'd1 : a_q[30:23];
    assign exp_b = b_q[30:23] == 0 ? 8'd1 : b_q[30:23];
    assign mant_a = {a_q[30:23] != 0, a_q[22:0], 3'b000};
    assign mant_b = {b_q[30:23] != 0, b_q[22:0], 3'b000};
    assign normalized = sum_q[27] ? {sum_q[27:2], |sum_q[1:0]} : sum_q[26:0];
    assign final_exp = round_exp + rounded_q[24];
    assign final_frac = rounded_q[24] ? rounded_q[23:1] : rounded_q[22:0];
    assign in_ready = rst_n;

    always_ff @(posedge clk) begin
        a_q <= a;
        b_q <= b;
        if (exp_a >= exp_b) begin
            exp_q <= exp_a;
            big_q <= mant_a;
            small_q <= mant_b;
            shift_q <= exp_a - exp_b;
        end else begin
            exp_q <= exp_b;
            big_q <= mant_b;
            small_q <= mant_a;
            shift_q <= exp_b - exp_a;
        end
        if (a_q[31] || b_q[31] || (&a_q[30:23] && |a_q[22:0]) ||
                                   (&b_q[30:23] && |b_q[22:0]))
            prep_kind <= INVALID;
        else if (&a_q[30:23] || &b_q[30:23])
            prep_kind <= INF;
        else
            prep_kind <= FINITE;

        big_aligned <= big_q;
        small_aligned <= shift_sticky(small_q, shift_q);
        aligned_exp <= exp_q;
        align_kind <= prep_kind;

        sum_q <= {1'b0, big_aligned} + {1'b0, small_aligned};
        sum_exp <= aligned_exp;
        sum_kind <= align_kind;

        rounded_q <= {1'b0, normalized[26:3]} +
                     (normalized[2] && (normalized[1] || normalized[0] || normalized[3]));
        round_exp <= {1'b0, sum_exp} + sum_q[27];
        round_kind <= sum_kind;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_pipe <= '0;
            out_valid <= 1'b0;
            result <= '0;
        end else begin
            valid_pipe <= {valid_pipe[3:0], in_valid};
            out_valid <= valid_pipe[4];
            if (valid_pipe[4]) begin
                if (round_kind == INVALID)
                    result <= 32'h7fc00000;
                else if (round_kind == INF || final_exp >= 255)
                    result <= 32'h7f800000;
                else if (final_exp == 1 && !rounded_q[23] && !rounded_q[24])
                    result <= {9'b0, final_frac};
                else
                    result <= {1'b0, final_exp[7:0], final_frac};
            end
        end
    end
endmodule
