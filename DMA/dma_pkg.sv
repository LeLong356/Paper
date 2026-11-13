package dma_pkg;

  parameter int ADDR_W         = 32;
  parameter int DATA_W         = 32;                    
  parameter int WORD_W         = 256;                  
  parameter int MAX_BURST      = 16;
  parameter int MAX_OUT        = 1;                  

  parameter int BYTES_PER_BEAT = DATA_W / 8;          
  parameter int BEAT_SHIFT     = BYTES_PER_BEAT >> 2;// 2  -> thay ">> 2"
  parameter int BEATS_PER_WORD = WORD_W / DATA_W;       // 8
  parameter int IDX_W          = $clog2(BEATS_PER_WORD);// 3  (đếm idx u_wr)
  parameter int BEAT_CNT_W     = $clog2(MAX_BURST + 1); // 5  (bst_beats)
  parameter int TOTAL_BEATS_W  = 32 - BEAT_SHIFT;       // 30 (leg_total_beats)
  parameter int TO_4K_W        = 13 - BEAT_SHIFT;       // 11 (to_4k)
  parameter int PTR_W = (MAX_OUT > 1) ? $clog2(MAX_OUT) : 1;

  parameter logic [2:0] ARSIZE = 3'(BEAT_SHIFT);        // 3'b010

endpackage