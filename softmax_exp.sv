module softmax_exp #(
    parameter int MAX_LENGTH = 2048,
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

    softmax_row_max #(
        .MAX_LENGTH(MAX_LENGTH), 
        .COUNT_WIDTH(COUNT_WIDTH)) 
        u_row (
        .clk(clk), 
        .rst_n(rst_n), 
        .start(start), 
        .row_length(row_length),
        .in_valid(in_valid), 
        .in_ready(in_ready), 
        .in_data(in_data),
        .done(done), 
        .max_value(max_value),
        .diff_data(diff_data), 
        .diff_valid(diff_valid)
    );
    int33_to_bf16 u_convert (
        .in_data(diff_data), 
        .out_bf16(diff_bf16)
    );
    vexp u_exp (
        .x_in(diff_bf16), 
        .exp_out(exp_data)
    );
    assign exp_valid = diff_valid;
endmodule
