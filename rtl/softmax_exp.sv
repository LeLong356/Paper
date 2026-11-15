module softmax_exp #(
    parameter int MAX_LENGTH = 32,
    parameter int COUNT_WIDTH = $clog2(MAX_LENGTH + 1)
)(
    input logic clk, rst_n, start,
    input logic [COUNT_WIDTH-1:0] row_length,
    input logic in_valid,
    output logic in_ready,
    input logic signed [31:0] in_data,
    output logic done,
    output logic signed [31:0] max_value,
    output logic [15:0] exp_data,
    output logic exp_valid
);
    logic signed [32:0] diff_data;
    logic diff_valid;
    logic [15:0] diff_bf16;

    logic bf_valid, bf_last, row_last;
    logic scaled_valid, scaled_last;
    logic [15:0] scaled_input_q;
    logic [23:0] scaled_mant, scaled_mant_q;
    logic signed [31:0] row_max, stream_max;
    logic [15:0] bf_q, exps, exps_q;
    logic nan_flag, inf_flag, zero_flag;
    logic nan_q, inf_q, zero_q, exp_is_zero_q;

    softmax_row_max #(
        .MAX_LENGTH(MAX_LENGTH), 
        .COUNT_WIDTH(COUNT_WIDTH)) 
        u_row (
        .clk(clk), 
        .rst_n(rst_n), 
        .start(start && !diff_valid && !bf_valid && !scaled_valid && !exp_valid),
        .row_length(row_length),
        .in_valid(in_valid), 
        .in_ready(in_ready), 
        .in_data(in_data),
        .done(row_last), 
        .max_value(row_max),
        .diff_data(diff_data), 
        .diff_valid(diff_valid)
    );
    int33_to_bf16 u_convert (
        .in_data(diff_data), 
        .out_bf16(diff_bf16)
    );
    vexp_scale u_scale (.x_in(bf_q), .scaled_mant(scaled_mant));
    vexp_shift_bias u_exps (
        .x_in(scaled_input_q), .scaled_mant(scaled_mant_q), .exps_out(exps), .is_nan(nan_flag),
        .is_inf(inf_flag), .is_zero(zero_flag)
    );
    vexp_finish u_finish (
        .exps_node(exps_q), .exp_is_zero(exp_is_zero_q),
        .is_nan(nan_q), .is_inf(inf_q), .is_zero(zero_q), .exp_out(exp_data)
    );

    always_ff @(posedge clk) begin
        bf_q <= diff_bf16;
        if (diff_valid) stream_max <= row_max;
        scaled_mant_q <= scaled_mant;
        scaled_input_q <= bf_q;
        exps_q <= exps;
        nan_q <= nan_flag;
        inf_q <= inf_flag;
        zero_q <= zero_flag;
        exp_is_zero_q <= (scaled_input_q[14:7] == 0);
    end
    assign max_value = exp_valid ? stream_max : row_max;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            {bf_valid, bf_last, scaled_valid, scaled_last, exp_valid, done} <= '0;
        end else begin
            bf_valid <= diff_valid;
            bf_last <= row_last;
            scaled_valid <= bf_valid;
            scaled_last <= bf_last;
            exp_valid <= scaled_valid;
            done <= scaled_last;
        end
    end
endmodule
