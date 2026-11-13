module u_fsm (
    input logic rst, clk,

    //REQ
    input logic req_valid,
    output logic req_ready,
    input logic [ADDR_W - 1 : 0] req_addr,
    input logic [31 : 0] req_len,
    input logic [12 : 0] req_dst_waddr,
    output logic dma_done, dma_err,
    output logic [2 : 0]dma_err_code,

    //LOAD
    output logic leg_load,leg_abort,
    output logic [ADDR_W - 1 : 0] leg_addr,
    output logic [TOTAL_BEATS_W - 1 : 0] leg_total_beats,

    input logic ar_done,
    //RST
    input logic r_idle,
    input logic r_err,
    input logic [2 : 0] r_err_code,

    //WLD
    output logic wr_load,
    output logic [12 : 0] wr_dst,
    output logic [12 : 0] wr_len_words,
    input logic wr_bank_ready, wr_last_done

);
    
endmodule