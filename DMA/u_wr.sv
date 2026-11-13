module u_wr (
    input logic rst,clk,

    //WLD
    input logic wr_load,
    input logic [12 : 0] wr_dst,
    input logic [12:0] wr_len_words,
    output logic wr_bank_ready, wr_last_done,

    //BEAT
    input logic beat_valid,
    input logic [DATA_W - 1: 0] beat_data,
    input logic beat_last,
    output logic beat_ready,

    //BWR
    input logic wr_ready, wr_done,
    output logic we,
    output logic [12 : 0] waddr,
    output logic [255 : 0] din
);
    typedef enum logic { 
        W_IDLE = 'b0;
        W_PACK = 'b1;
    } u_wr;
    u_wr reg_stage, w_stage_nxt;

    always_comb begin
        case(reg_stage) 
            W_IDLE : begin  
                
            end

            W_PACK : begin

            end
        endcase
    end


    always_ff @( posedge clk) begin //ctrl
        if(rst) begin
            reg_stage <= W_IDLE;
            reg_idx <= 'd0;
            reg_we <= 'd0;
            reg_wr_last_done <= 'd0;
            reg_words_written <= 'd0;
        end
        else begin
            reg_stage <= w_stage_nxt;
            reg_idx <= w_idx_nxt;
            reg_we <= w_we_nxt;
            reg_wr_last_done <= w_wr_last_done_nxt;
            reg_words_written <= w_words_written_nxt;
        end
    end

    always_ff @(posedge clk) begin
        reg_cur_waddr <= w_cur_waddr_nxt;
        reg_wr_len_words <= w_wr_len_words_nxt;
        reg_buf <= w_reg_buf_nxt;
        reg_din <= w_din_nxt;
        reg_waddr <= w_waddr_nxt;
    end


endmodule