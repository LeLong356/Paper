module softmax_sum #(
    parameter int MAX_LENGTH = 32,
    parameter int COUNT_WIDTH = $clog2(MAX_LENGTH + 1)
)(
    input logic clk, rst_n, start,
    input logic [COUNT_WIDTH-1:0] row_length,
    output logic ready,
    input logic [15:0] exp_data,
    input logic exp_valid,
    input logic exp_last,
    output logic [31:0] sum_fp32,
    output logic sum_valid,
    input logic [COUNT_WIDTH-1:0] read_index,
    output logic [15:0] read_data
);
    typedef enum logic [2:0] {
        IDLE, 
        RECEIVE, 
        ADD_READ,
        ADD_REQUEST, 
        ADD_WAIT, 
        COMPLETE
    } state_t;
    state_t state, next_state;
    (* ram_style = "block" *) logic [15:0] exp_buffer [0:MAX_LENGTH-1];
    logic [COUNT_WIDTH-1:0] length_reg, received_count, add_index;
    logic [31:0] term_fp32, accumulator;
    logic [31:0] add_a, add_b, add_result;
    logic add_in_valid, add_in_ready, add_out_valid;

    logic [15:0] ram_read_data;
    localparam int ADDR_WIDTH = MAX_LENGTH > 1 ? $clog2(MAX_LENGTH) : 1;
    logic [ADDR_WIDTH-1:0] ram_read_index;
    logic external_read, external_valid;
    logic read_valid_q;
    assign external_read = (state == IDLE || state == COMPLETE);
    assign external_valid = external_read && read_index < received_count;
    assign ram_read_index = external_read ? ADDR_WIDTH'(read_index) : ADDR_WIDTH'(add_index);
    always_ff @(posedge clk) begin
        if (rst_n && state == RECEIVE && exp_valid)
            exp_buffer[ADDR_WIDTH'(received_count)] <= exp_data;
        if (state == ADD_READ || external_read)
            ram_read_data <= exp_buffer[ram_read_index];
    end
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) read_valid_q <= 1'b0;
        else read_valid_q <= external_valid && !(state == IDLE && start);
    end
    assign term_fp32 = {ram_read_data, 16'b0};
    assign sum_fp32 = accumulator;
    assign sum_valid = (state == COMPLETE);
    assign ready = (state == IDLE);
    assign read_data = read_valid_q ? ram_read_data : 16'h0000;

    fp32_add_positive u_add (
        .clk(clk), 
        .rst_n(rst_n),
        .in_valid(add_in_valid), 
        .in_ready(add_in_ready),
        .a(add_a), 
        .b(add_b),
        .result(add_result), 
        .out_valid(add_out_valid)
    );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            length_reg <= '0;
            received_count <= '0;
            add_index <= '0;
            accumulator <= '0;
        end else begin
            state <= next_state;
            case (state)
                IDLE: begin
                    if (start && row_length >= 1 && row_length <= MAX_LENGTH) begin
                        length_reg <= row_length;
                        received_count <= '0;
                        add_index <= '0;
                        accumulator <= '0;
                    end
                end
                RECEIVE: begin
                    if (exp_valid) begin
                        received_count <= received_count + 1'b1;
                    end
                end
                ADD_WAIT: begin
                    if (add_out_valid) begin
                        accumulator <= add_result;
                        if (add_index < length_reg - 1'b1)
                            add_index <= add_index + 1'b1;
                    end
                end
                default: begin end
            endcase
        end
    end

    always_comb begin
        next_state = state;
        add_a = accumulator;
        add_b = term_fp32;
        add_in_valid = 1'b0;
        case (state)
            IDLE: begin
                if (start && row_length >= 1 && row_length <= MAX_LENGTH)
                    next_state = RECEIVE;
            end
            RECEIVE: begin
                if (exp_valid && received_count == length_reg - 1'b1)
                    next_state = ADD_READ;
            end
            ADD_READ: next_state = ADD_REQUEST;
            ADD_REQUEST: begin
                add_in_valid = 1'b1;
                if (add_in_ready) 
                    next_state = ADD_WAIT;
            end
            ADD_WAIT: begin
                if (add_out_valid) begin
                    if (add_index == length_reg - 1'b1)
                        next_state = COMPLETE;
                    else
                        next_state = ADD_READ;
                end
            end
            COMPLETE: next_state = IDLE;
            default: next_state = IDLE;
        endcase
    end

    // synthesis translate_off
    always @(posedge clk) begin
        if (rst_n && state == RECEIVE && exp_valid)
            assert (exp_last == (received_count == length_reg - 1'b1))
        else 
            $fatal(1, "exp_last does not match row_length");
    end
    // synthesis translate_on
endmodule
