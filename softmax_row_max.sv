module softmax_row_max #(
    parameter int MAX_LENGTH = 2048,
    parameter int COUNT_WIDTH = $clog2(MAX_LENGTH + 1)
)(
    input  logic clk,
    input  logic rst_n,
    input  logic start,
    input  logic [COUNT_WIDTH-1:0] row_length,
    input  logic in_valid,
    output logic in_ready,
    input  logic signed [31:0] in_data,
    output logic done,
    output logic signed [31:0] max_value,
    output logic signed [32:0] diff_data,
    output logic diff_valid
);

    typedef enum logic [1:0] {
        IDLE,
        RECEIVE, 
        SUBTRACT,
        COMPLETE
    } state_t;
    state_t state, next_state;
    logic signed [31:0] row_buffer [0:MAX_LENGTH-1];
    logic signed [32:0] diff_buffer [0:MAX_LENGTH-1];
    logic signed [31:0] current_max;
    logic [COUNT_WIDTH-1:0] length_reg;
    logic [COUNT_WIDTH-1:0] received_count;
    logic [COUNT_WIDTH-1:0] subtract_count;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            length_reg <= '0;
            received_count <= '0;
            current_max <= '0;
            subtract_count <= '0;
            diff_data <= '0;
            diff_valid <= 1'b0;
        end 
        else begin
            state <= next_state;
            diff_valid <= 1'b0;
            case (state)
                IDLE: begin
                    length_reg <= '0;
                    received_count <= '0;
                    current_max <= '0;
                    subtract_count <= '0;
                    if (start && row_length >= 1 && row_length <= MAX_LENGTH)
                        length_reg <= row_length;
                end
                RECEIVE: begin
                    if (in_valid && in_ready) begin
                        row_buffer[received_count] <= in_data;
                        received_count <= received_count + 1'b1;
                        if (received_count == 0 || in_data > current_max)
                            current_max <= in_data;
                    end
                end
                SUBTRACT: begin
                    diff_buffer[subtract_count] <= $signed({row_buffer[subtract_count][31], row_buffer[subtract_count]}) - $signed({current_max[31], current_max});
                    diff_data <= $signed({row_buffer[subtract_count][31], row_buffer[subtract_count]}) - $signed({current_max[31], current_max});
                    diff_valid <= 1'b1;
                    if (subtract_count < length_reg - 1'b1) begin
                        subtract_count <= subtract_count + 1'b1;
                    end
                end
                COMPLETE: begin
                end
                default: begin
                    length_reg <= '0;
                    received_count <= '0;
                    current_max <= '0;
                end
            endcase
        end
    end

    always_comb begin
        next_state = state;
        in_ready = (state == RECEIVE);
        done = (state == COMPLETE);
        max_value = current_max;
        case (state)
            IDLE: begin
                if (start && row_length >= 1 && row_length <= MAX_LENGTH)
                    next_state = RECEIVE;
            end
            RECEIVE: begin
                if (in_valid && in_ready && received_count == length_reg - 1'b1)
                    next_state = SUBTRACT;
            end
            SUBTRACT: begin
                if (subtract_count == length_reg - 1'b1) begin
                    next_state = COMPLETE;
                end
            end
            COMPLETE: next_state = IDLE;
            default: next_state = IDLE;
        endcase
    end
endmodule
