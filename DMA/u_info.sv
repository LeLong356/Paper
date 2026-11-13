module u_info_fifo
import dma_pkg::*;
(
    input  logic clk,rst,
    input  logic push,push_last,
    input  logic [BEAT_CNT_W - 1 : 0] push_beats,
    output logic full,
    input  logic pop,
    output logic empty,
    output logic [BEAT_CNT_W - 1 : 0] head_beats,
    output logic head_last

);
    logic [ BEAT_CNT_W  : 0] mem[MAX_OUT];
    logic [PTR_W - 1 : 0] rd_ptr, wr_ptr;
    logic [PTR_W - 1 : 0] count;

    assign empty = (count == 0);
    assign full = (count == MAX_OUT) && !pop;
    assign {head_beats , head_last} = mem[rd_ptr];

    always_ff @( posedge clk ) begin 
        if(rst) begin
            count <= 'd0;
            rd_ptr <= 'd0;
            wr_ptr <= 'd0;
        end
        else begin
            if(push && !full) begin
                mem[wr_ptr] <= {push_beats , push_last};
                wr_ptr <= (wr_ptr == MAX_OUT - 1 ) ? '0 : wr_ptr + 'd1;
            end
            if(pop && !empty) begin
                rd_ptr <= (rd_ptr == MAX_OUT - 1) ? '0 : rd_ptr + 'd1;
            end
            count <= count + (push && !full) - (pop && !empty);
        end
    end

endmodule