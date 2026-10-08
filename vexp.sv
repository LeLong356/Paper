module exps_stage (
    input logic [15:0] x_in,
    output logic [15:0] exps_out,
    output logic is_overflow
);
    logic sign_bit;
    logic [7:0] exp_in;
    logic [6:0] mant_in;
    assign sign_bit = x_in[15];
    assign exp_in = x_in[14:7];
    assign mant_in = x_in[6:0];
    localparam logic [15:0] LOG2E = 16'd23637; //q-format
    logic [7:0] mant_full;
    assign mant_full = {1'b1, mant_in};
    logic [23:0] scaled_mant;
    assign scaled_mant = mant_full * LOG2E;
    assign is_overflow = (exp_in >= 8'd133);
    logic [7:0] shift_right_amount;
    assign shift_right_amount = 8'd133 - exp_in;
    logic [23:0] shifted_val;
    assign shifted_val = is_overflow ? 24'd0 : (scaled_mant >> shift_right_amount);
    logic guard_bit;
    assign guard_bit = shifted_val[7];
    logic [15:0] rounded_val;
    assign rounded_val = shifted_val[23:8] + guard_bit;
    logic [15:0] sel_val;
    assign sel_val = sign_bit ? ~rounded_val : rounded_val;
    assign exps_out = sel_val + (127 << 7);
endmodule

module px (
    input logic [6:0] exps_in,
    output logic [6:0] p_out
);
    localparam logic [8:0] GAMMA_1 = 9'd422;
    localparam logic [8:0] GAMMA_2 = 9'd278;
    logic select;
    assign select = exps_in[6];
    logic [8:0] x_aligned;
    assign x_aligned = {2'b00, exps_in};
    logic [5:0] x_frac;
    assign x_frac = exps_in[5:0];
    logic [8:0] sum_val;
    logic [14:0] mul_val;
    logic [14:0] p_temp;
    assign sum_val = select ? (x_aligned + GAMMA_2) : (x_aligned + GAMMA_1);
    assign mul_val = select ? ((~x_frac) * sum_val) : (x_frac * sum_val); // x(x+gamma1) || x(x+gamma2)
    assign p_temp = select
                  ? ((mul_val >> 1) - (mul_val >> 4)) // beta = 0.4375 = 1/2 - 1/16
                  : ((mul_val >> 2) - (mul_val >> 5)); // alpha = 0.21875 = 1/4 - 1/32
    assign p_out = select ? ~(p_temp[13:7]) : p_temp[13:7];
endmodule

module vexp(
    input logic [15:0] x_in,
    output logic [15:0] exp_out
);
    logic [15:0] exps_node;
    logic [6:0] p_node;
    logic overflow_flag; 

    exps_stage block_d (
        .x_in(x_in),
        .exps_out(exps_node),
        .is_overflow(overflow_flag)
    );

    px block_e (
        .exps_in(exps_node[6:0]),
        .p_out(p_node)
    ); 
    logic [15:0] calc_out;
    assign calc_out = {exps_node[15:7], p_node};
    assign exp_out = overflow_flag ? 16'h7F80 : calc_out;
    
endmodule