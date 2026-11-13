module ar_fsm
  import dma_pkg::*;
(
  input  logic                      clk, rst,

  input  logic                      bst_valid,
  output logic                      bst_ready,
  input  logic [ADDR_W-1:0]         bst_addr,
  input  logic [BEAT_CNT_W-1:0]     bst_beats,
  input  logic                      bst_last,

  output logic                      push, push_last,
  output logic [BEAT_CNT_W-1:0]     push_beats,
  input  logic                      full,

  output logic                      ar_done,

  output logic [ADDR_W-1:0]         ARADDR,
  output logic [7:0]                ARLEN,
  output logic [2:0]                ARSIZE,
  output logic [1:0]                ARBURST,
  output logic                      ARID,
  output logic                      ARVALID,
  input  logic                      ARREADY
);
  typedef enum logic {AR_IDLE, AR_REQ} ar_state_t;
  ar_state_t stage;

  assign ARID    = 1'b0;
  assign ARBURST = 2'b01;
  assign ARSIZE  = 3'(BEAT_SHIFT);

  assign ar_done    = (stage == AR_IDLE) && !bst_valid;
  assign push       = ARVALID && ARREADY; 
  assign bst_ready  = push;

  always_ff @(posedge clk) begin
    if (rst) begin
      stage   <= AR_IDLE;
      ARVALID <= 1'b0;
    end else begin
      case (stage)
        AR_IDLE: if (bst_valid && !full) begin
          ARADDR  <= bst_addr;
          ARLEN   <= 8'(bst_beats - 1'b1);
          push_beats <= bst_beats;
          push_last  <= bst_last;
          ARVALID <= 1'b1;                   
          stage   <= AR_REQ;
        end
        AR_REQ: if (ARREADY) begin
          ARVALID <= 1'b0;                 
          stage   <= AR_IDLE;
        end
      endcase
    end
  end
endmodule