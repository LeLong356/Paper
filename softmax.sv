module softmax #(
    parameter int MAX_LENGTH=32,
    parameter int COUNT_WIDTH=$clog2(MAX_LENGTH+1)
)(
    input logic clk, rst_n, start,
    input logic [COUNT_WIDTH-1:0] row_length,
    output logic ready, // new row
    input logic in_valid,
    input logic signed [31:0] in_data,
    output logic in_ready,
    output logic signed [7:0] out_data,
    output logic out_valid,
    output logic out_last, 
    output logic done     
);
    typedef enum logic [2:0] {
        IDLE, 
        WAIT_SUM, 
        READ_NUMERATOR,
        DIV_REQUEST, 
        DIV_WAIT, 
        QUANTIZE_WAIT,
        COMPLETE
    } state_t;
    state_t state, next_state;
    logic [COUNT_WIDTH-1:0] length_reg, div_index;
    logic stage_start, stage_ready;
    logic [31:0] sum_fp32, sum_reg;
    logic sum_valid;
    logic [COUNT_WIDTH-1:0] read_index;
    logic [15:0] read_data;
    logic [31:0] div_numerator, div_denominator, div_result;
    logic div_in_valid, div_in_ready, div_out_valid;
    logic [31:0] probability_fp32;
    logic probability_valid, probability_last;



    fp32_to_int8 u_quantize (
        .clk(clk), 
        .rst_n(rst_n), 
        .in_valid(probability_valid),
        .in_data(probability_fp32), 
        .out_data(out_data), 
        .out_valid(out_valid)
    );
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) out_last <= 1'b0;
        else out_last <= probability_valid && probability_last;
    end
    assign done = out_valid && out_last;

    assign read_index = div_index;
    assign div_numerator = {read_data, 16'b0}; // BF16 -> FP32
    assign div_denominator = sum_reg;

    softmax_exp_sum #(
        .MAX_LENGTH(MAX_LENGTH), 
        .COUNT_WIDTH(COUNT_WIDTH)
        ) 
        u_front (
        .clk(clk), 
        .rst_n(rst_n), 
        .start(stage_start), 
        .row_length(row_length),
        .ready(stage_ready), 
        .in_valid(in_valid), 
        .in_data(in_data), 
        .in_ready(in_ready),
        .sum_fp32(sum_fp32), 
        .sum_valid(sum_valid),
        .read_index(read_index), 
        .read_data(read_data)
    );
    fp32_div_positive u_div (
        .clk(clk), 
        .rst_n(rst_n), 
        .in_valid(div_in_valid), 
        .in_ready(div_in_ready),
        .numerator(div_numerator), 
        .denominator(div_denominator),
        .result(div_result), 
        .out_valid(div_out_valid)
    );
    always_comb begin
        next_state = state;
        stage_start = 1'b0;
        ready = rst_n && (state == IDLE) && stage_ready;
        div_in_valid = 1'b0;
        case (state)
            IDLE: begin
                if (start && stage_ready && row_length >= 1 && row_length <= MAX_LENGTH) begin
                    stage_start = 1'b1;
                    next_state = WAIT_SUM;
                end
            end
            WAIT_SUM: begin
                if (sum_valid) begin
                    next_state = READ_NUMERATOR;
                end
            end
            READ_NUMERATOR: next_state = DIV_REQUEST;
            DIV_REQUEST: begin
                div_in_valid = 1'b1;
                if (div_in_ready) begin
                    next_state = DIV_WAIT;
                end
            end
            DIV_WAIT: begin
                if (div_out_valid) begin
                    if (div_index == length_reg - 1) begin
                        next_state = QUANTIZE_WAIT;
                    end
                    else begin
                        next_state = READ_NUMERATOR;
                    end
                end
            end
            QUANTIZE_WAIT: next_state = COMPLETE;
            COMPLETE: begin
                next_state = IDLE;
            end
            default: next_state = IDLE;
        endcase
    end
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            length_reg <= '0;
            state <= IDLE;
            sum_reg <= '0;
            div_index <= '0;
            probability_fp32 <= '0;
            probability_valid <= '0;
            probability_last <= '0;
        end
        else begin
            probability_valid <= '0;
            probability_last <= '0;
            state <= next_state;
            case(state)
                IDLE: begin
                    if (start && stage_ready && row_length >= 1 && row_length <= MAX_LENGTH) begin
                        length_reg <= row_length;
                        div_index <= '0;
                    end
                end
                WAIT_SUM: begin
                    if (sum_valid) begin
                        sum_reg <= sum_fp32;
                    end
                end
                READ_NUMERATOR: begin
                end
                DIV_REQUEST: begin
                end
                DIV_WAIT: begin
                    if (div_out_valid) begin
                        probability_fp32 <= div_result;
                        probability_valid <= 1'b1;
                        probability_last <= (div_index == length_reg - 1'b1);
                        if (div_index < length_reg - 1'b1) begin
                            div_index <= div_index + 1'b1;
                        end
                    end
                end
                QUANTIZE_WAIT: begin
                end
                COMPLETE: begin
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule

