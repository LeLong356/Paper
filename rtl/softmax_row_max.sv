module softmax_row_max #(
    parameter int MAX_LENGTH = 32,
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

    typedef enum logic [2:0] {
        IDLE,
        RECEIVE, 
        READ_ROW,
        SUBTRACT,
        COMPLETE
    } state_t;
    state_t state, next_state;
    (* ram_style = "block" *) logic signed [31:0] row_buffer [0:MAX_LENGTH-1];
    logic signed [31:0] row_read_data;
    logic signed [31:0] current_max;
    logic [COUNT_WIDTH-1:0] last_index;
    localparam int ADDR_WIDTH = MAX_LENGTH > 1 ? $clog2(MAX_LENGTH) : 1;
    logic [ADDR_WIDTH-1:0] read_addr;
    logic [COUNT_WIDTH-1:0] received_count;
    logic [COUNT_WIDTH-1:0] subtract_count;

    wire read_row = state == READ_ROW ||
                    (state == SUBTRACT && subtract_count != last_index);
    always_ff @(posedge clk) begin
        if (state == RECEIVE)
            read_addr <= '0;
        else if (read_row)
            read_addr <= read_addr + 1'b1;
    end
    always_ff @(posedge clk) begin
        if (rst_n && in_valid && in_ready)
            row_buffer[ADDR_WIDTH'(received_count)] <= in_data;
        if (read_row)
            row_read_data <= row_buffer[read_addr];
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            last_index <= '0;
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
                    last_index <= '0;
                    received_count <= '0;
                    current_max <= '0;
                    subtract_count <= '0;
                    if (start && row_length >= 1 && row_length <= MAX_LENGTH)
                        last_index <= row_length - 1'b1;
                end
                RECEIVE: begin
                    if (in_valid && in_ready) begin
                        received_count <= received_count + 1'b1;
                        if (received_count == 0 || in_data > current_max)
                            current_max <= in_data;
                    end
                end
                READ_ROW: begin end
                SUBTRACT: begin
                    diff_data <= $signed({row_read_data[31], row_read_data}) - $signed({current_max[31], current_max});
                    diff_valid <= 1'b1;
                    if (subtract_count != last_index) begin
                        subtract_count <= subtract_count + 1'b1;
                    end
                end
                COMPLETE: begin
                end
                default: begin
                    last_index <= '0;
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
                if (in_valid && in_ready && received_count == last_index)
                    next_state = READ_ROW;
            end
            READ_ROW: next_state = SUBTRACT;
            SUBTRACT: begin
                if (subtract_count == last_index) begin
                    next_state = COMPLETE;
                end
            end
            COMPLETE: next_state = IDLE;
            default: next_state = IDLE;
        endcase
    end
endmodule
