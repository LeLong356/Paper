module exps_stage (
    input  logic [15:0] x_in,
    output logic [15:0] exps_out,
    output logic        is_nan,
    output logic        is_inf,
    output logic        is_zero
);
    logic       sign_bit;
    logic [7:0] exp_in;
    logic [6:0] mant_in;
    logic in_is_nan, in_is_inf;
    localparam logic [15:0] LOG2E = 16'd23637;
    logic [7:0]  mant_full;
    logic [23:0] scaled_mant; // Q2.21
    logic pre_overflow;
    logic [23:0] shifted_val;
    logic [7:0]  shift_right_amount;
    logic        guard_bit;
    logic [15:0] rounded_val; // Q8.7
    logic signed [17:0] bias_s, sel_val_s, biased_val;
    logic signed [10:0] exp_field_s;
    assign sign_bit = x_in[15];
    assign exp_in   = x_in[14:7];
    assign mant_in  = x_in[6:0];
    assign in_is_nan = (exp_in == 8'hFF) && (mant_in != 7'd0);
    assign in_is_inf = (exp_in == 8'hFF) && (mant_in == 7'd0);
    assign mant_full = (exp_in == 8'd0) ? 8'd0 : {1'b1, mant_in};
    assign scaled_mant = mant_full * LOG2E;
    assign pre_overflow = (exp_in > 8'd133);
    assign shift_right_amount = 8'd133 - exp_in;
    assign shifted_val = pre_overflow ? 24'd0 : (scaled_mant >> shift_right_amount);
    assign guard_bit   = shifted_val[7];
    assign rounded_val = {1'b0, shifted_val[22:8]} + guard_bit;
    assign bias_s     = 18'sd16256;
    assign sel_val_s  = sign_bit ? -$signed({2'b00, rounded_val}) : $signed({2'b00, rounded_val});
    assign biased_val = bias_s + sel_val_s;
    assign exp_field_s = biased_val[17:7];

    assign is_nan  = in_is_nan;
    assign is_inf  = (~is_nan) && (in_is_inf ? (~sign_bit) : (pre_overflow ? (~sign_bit) : (exp_field_s >= 11'sd255)));
    assign is_zero = (~is_nan) && (in_is_inf ? ( sign_bit) : (pre_overflow ? ( sign_bit) : (exp_field_s <= 11'sd0)));

    assign exps_out = biased_val[15:0];
endmodule

module px (
    input  logic [6:0] exps_in,
    output logic [6:0] p_out
);
    localparam logic [8:0] GAMMA_1 = 9'd422;
    localparam logic [8:0] GAMMA_2 = 9'd278;

    logic       select;
    logic [8:0] x_aligned;
    logic [5:0] x_frac;
    logic [5:0] frac_sel;
    logic [8:0] ab;
    logic [8:0] gamma, sum_val;
    logic [17:0] mul_val, p_temp;
    assign select    = exps_in[6];
    assign x_aligned = {2'b00, exps_in};
    assign x_frac    = exps_in[5:0];
    assign frac_sel = select ? (~x_frac) : x_frac;
    assign ab = frac_sel * 3'd7;
    assign gamma   = select ? GAMMA_2 : GAMMA_1;
    assign sum_val = x_aligned + gamma;
    assign mul_val = ab * sum_val;
    assign p_temp  = select ? (mul_val >> 4) : (mul_val >> 5); // beta = 7/16, alpha = 7/32
    assign p_out = select ? ~(p_temp[13:7]) : p_temp[13:7];
endmodule

module vexp (
    input  logic [15:0] x_in,
    output logic [15:0] exp_out
);
    logic [15:0] exps_node;
    logic        is_nan, is_inf, is_zero;
    exps_stage u_exps (
        .x_in     (x_in),
        .exps_out (exps_node),
        .is_nan   (is_nan),
        .is_inf   (is_inf),
        .is_zero  (is_zero)
    );

    vexp_finish u_finish (
        .exps_node(exps_node), .exp_is_zero(x_in[14:7] == 0),
        .is_nan(is_nan), .is_inf(is_inf), .is_zero(is_zero), .exp_out(exp_out)
    );
endmodule

module vexp_finish (
    input logic [15:0] exps_node,
    input logic exp_is_zero, is_nan, is_inf, is_zero,
    output logic [15:0] exp_out
);
    logic [6:0] p_node;
    px u_px (
        .exps_in  (exps_node[6:0]),
        .p_out    (p_node)
    );
    assign exp_out = exp_is_zero ? 16'h3F80 :
                     is_nan  ? 16'h7FC0 :
                     is_inf  ? 16'h7F80 :
                     is_zero ? 16'h0000 :
                               {exps_node[15:7], p_node};
endmodule
