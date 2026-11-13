module u_r
import dma_pkg::*;
(
    input  logic rst, clk,

    //AXR
    input  logic [DATA_W - 1: 0] RDATA,
    input  logic [1:0] RRESP,
    input  logic RLAST,
    input  logic RID,
    input  logic RVALID,
    output logic RREADY,

    //POP
    output logic pop,
    input  logic empty,
    input  logic [BEAT_CNT_W - 1 : 0] head_beats,
    input  logic head_last,

    //BEAT
    input  logic beat_ready,
    output logic beat_valid,
    output logic [DATA_W - 1 : 0] beat_data,
    output logic beat_last,

    //RST
    output logic r_idle,
    output logic r_err,
    output logic [2 : 0] r_err_code

);
    typedef enum logic [1:0] { 
        R_IDLE = 'b00;
        R_RECV = 'b01;
        R_DRAIN = 'b10;
    } r_fsm;
    r_fsm stage;

    always_ff @(posedge clk) begin
        if(rst) begin

        end
        else begin

        end
    end
endmodule