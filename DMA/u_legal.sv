module u_legal 
import dma_pkg::*;
(
    input clk, rst,
    input  logic leg_load, leg_abort,
    input  logic [ADDR_W - 1 : 0] leg_addr;
    input  logic [TOTAL_BEATS_W - 1 : 0] leg_total_beats,
    output logic bst_valid,
    input  logic bst_ready,
    output logic [ADRR_W - 1 : 0] bst_addr,
    output logic [BEAT_CNT_W - 1 : 0] bst_beats,
    output logic bst_last
);  
    logic [TO_4K_W - 1 : 0] to_4k;
    logic [TOTAL_BEATS_W - 1 : 0] beats_left;
    logic [ADDR_W - 1 : 0] addr;
    logic [BEAT_CNT_W - 1 : 0] beats;

    always_comb begin
        to_4k = TO_4K_W'(('d4096 - {1'b0 , addr[11:0]}) >> BEAT_SHIFT);
        beats = BEAT_CNT_W'(MAX_BURST);
        if(beats_left < beats) beats = BEAT_CNT_W'(beats_left);
        if(to_4k < beats) beats = BEAT_CNT_W'(to_4k);
    end
    assign bst_valid = (beats_left != 0) && !leg_abort;
    assign bst_addr = addr;
    assign bst_beats = beats;
    assign bst_last = (beats == beats_left);

    always_ff @( posedge clk ) begin
        if(rst) begin
            addr <= 'd0;
            beats_left <= 'd0;
        end 
        else begin
                if(leg_load) begin
                addr <= leg_addr;
                beats_left <= leg_total_beats;
            end
                else if(bst_valid && bst_ready) begin
                    addr <= addr + (ADDR_W'(beats) << BEAT_SHIFT);
                    beats_left <= beats_left - beats;
                end
                if(leg_abort) begin
                    beats_left <= TOTAL_BEATS_W'd0;
                end
        end
    end
    
endmodule 