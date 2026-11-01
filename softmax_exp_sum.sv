module softmax_exp_sum #(
    parameter int MAX_LENGTH=2048,
    parameter int COUNT_WIDTH=$clog2(MAX_LENGTH+1)
)(
    input logic clk, rst_n, start,
    input logic [COUNT_WIDTH-1:0] row_length,
    output logic ready,
    input logic in_valid,
    input logic signed [31:0] in_data,
    output logic in_ready,
    output logic [31:0] sum_fp32,
    output logic sum_valid,
    input logic [COUNT_WIDTH-1:0] read_index,
    output logic [15:0] read_data
);
    logic sum_ready, accepted_start;
    logic [15:0] exp_data;
    logic exp_valid, exp_last;
    logic signed [31:0] max_value;
    assign ready = rst_n && sum_ready;
    assign accepted_start = start && ready && row_length >= 1 && row_length <= MAX_LENGTH;
    softmax_exp #(
        .MAX_LENGTH(MAX_LENGTH), 
        .COUNT_WIDTH(COUNT_WIDTH)
    ) 
    u_exp (
        .clk(clk), 
        .rst_n(rst_n), 
        .start(accepted_start), 
        .row_length(row_length),
        .in_valid(in_valid), 
        .in_data(in_data), 
        .in_ready(in_ready),
        .done(exp_last), 
        .max_value(max_value), 
        .exp_data(exp_data), 
        .exp_valid(exp_valid)
    );
    softmax_sum #(
        .MAX_LENGTH(MAX_LENGTH), 
        .COUNT_WIDTH(COUNT_WIDTH)
    ) 
    u_sum (
        .clk(clk), 
        .rst_n(rst_n), 
        .start(accepted_start), 
        .row_length(row_length),
        .ready(sum_ready), 
        .exp_data(exp_data), 
        .exp_valid(exp_valid), 
        .exp_last(exp_last),
        .sum_fp32(sum_fp32), 
        .sum_valid(sum_valid),
        .read_index(read_index),
        .read_data(read_data)
    );
endmodule
