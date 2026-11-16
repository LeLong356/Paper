/*
 * Project      : DMA
 * Author       : Lê Nguyễn Huỳnh Long (user)
 * AI Flow      : VLSIT RTL Generator AI Automation Flow
 * AI Flow Page : https://github.com/nguyenquanicd/VLSIT_RTL_Generator_AI_Model
 * Date         : 2026-11-16
 * Description  : AR issuer u_ar: drives the AXI4 AR channel and pushes the last flag of each
 *                accepted burst into u_info.
 *                Design decisions: docs/dma/dma_v0_4block.md (section 4, decision table).
 * Deviations   : P11, TYP-05: imports dma_pkg (designer decision Q1).
 */
`timescale 1ns/1ps

module m_dma_ar
  import dma_pkg::*;
#(
  localparam logic [31:0] LPARA_LEN_W   = 8,
  localparam logic [31:0] LPARA_SIZE_W  = 3,
  localparam logic [31:0] LPARA_BURST_W = 2
) (
  input wire i_clk_core,
  input wire i_rst_n_core,
  // Control in
  input wire i_bst_valid,
  input wire i_bst_last,
  input wire i_full,
  input wire i_axi_arready,
  // Data in
  input wire [ADDR_W-1:0] i_bst_addr,
  input wire [BEAT_CNT_W-1:0] i_bst_beats,
  // Control out
  output logic o_bst_ready,
  output logic o_push,
  output logic o_push_last,
  output logic o_ar_done,
  output logic o_axi_arvalid,
  output logic o_axi_arid,
  // Data out
  output logic [ADDR_W-1:0] o_axi_araddr,
  output logic [LPARA_LEN_W-1:0] o_axi_arlen,
  output logic [LPARA_SIZE_W-1:0] o_axi_arsize,
  output logic [LPARA_BURST_W-1:0] o_axi_arburst
);

  // FSM states: IDLE waits for a burst and room in u_info, REQ holds ARVALID until ARREADY.
  // Both encodings of the 1-bit state are used; default recovers to ENUM_ST_IDLE.
  typedef enum logic [0:0] {
    ENUM_ST_IDLE = 1'b0,
    ENUM_ST_REQ  = 1'b1
  } ar_state_type_def;

  // AXI4 burst type encoding (IHI 0022H.c A3.4.1, Table A3-3); only INCR is used.
  typedef enum logic [LPARA_BURST_W-1:0] {
    ENUM_BURST_FIXED = 2'b00,
    ENUM_BURST_INCR  = 2'b01,
    ENUM_BURST_WRAP  = 2'b10
  } burst_type_def;

  // Internal signal declarations
  ar_state_type_def       reg_fsm_ar_current_state;
  ar_state_type_def       w_fsm_ar_nxt_state;
  logic [ADDR_W-1:0]      reg_araddr;
  logic [ADDR_W-1:0]      w_araddr_nxt;
  logic [LPARA_LEN_W-1:0] reg_arlen;
  logic [LPARA_LEN_W-1:0] w_arlen_nxt;
  logic                   reg_push_last;
  logic                   w_push_last_nxt;
  logic                   w_take;

  // AR channel. ARVALID is 1 exactly in REQ; it comes from a flop, so it does not depend on
  // ARREADY (IHI 0022H.c A3.2.1). Address and length are registered and stay stable until the
  // handshake (A3.2.1). Fixed fields: one ID, INCR, beat size = data bus width (A3.4.1).
  assign o_axi_arvalid = (reg_fsm_ar_current_state == ENUM_ST_REQ);
  assign o_axi_araddr  = reg_araddr;
  assign o_axi_arlen   = reg_arlen;
  assign o_axi_arsize  = ARSIZE;
  assign o_axi_arburst = ENUM_BURST_INCR;
  assign o_axi_arid    = 1'b0;

  // BST, PUSH and ar_done. A burst is taken in IDLE when one is offered and u_info has room.
  // The burst is pushed into u_info and released on BST at the AR handshake (spec section 4).
  assign w_take       = (reg_fsm_ar_current_state == ENUM_ST_IDLE) & i_bst_valid & ~i_full;
  assign o_push       = o_axi_arvalid & i_axi_arready;
  assign o_bst_ready  = o_push;
  assign o_push_last  = reg_push_last;
  assign o_ar_done    = (reg_fsm_ar_current_state == ENUM_ST_IDLE) & ~i_bst_valid;

  // Part 2, combinational: next state. IDLE -> REQ when a burst is taken; REQ -> IDLE on ARREADY.
  always_comb begin : p_com_fsm_nxt
    w_fsm_ar_nxt_state = reg_fsm_ar_current_state;
    case (reg_fsm_ar_current_state)
      ENUM_ST_IDLE: begin
        if (w_take)
          w_fsm_ar_nxt_state = ENUM_ST_REQ;
      end
      ENUM_ST_REQ: begin
        if (i_axi_arready)
          w_fsm_ar_nxt_state = ENUM_ST_IDLE;
      end
      default: w_fsm_ar_nxt_state = ENUM_ST_IDLE;
    endcase
  end

  // Burst capture: when a burst is taken, keep its address, ARLEN = beats - 1, and the last flag
  // for u_info; otherwise hold them.
  always_comb begin : p_com_capture
    w_araddr_nxt     = reg_araddr;
    w_arlen_nxt      = reg_arlen;
    w_push_last_nxt  = reg_push_last;
    if (w_take) begin
      w_araddr_nxt     = i_bst_addr;
      w_arlen_nxt      = LPARA_LEN_W'(i_bst_beats - BEAT_CNT_W'(1));
      w_push_last_nxt  = i_bst_last;
    end
  end

  // Part 1, sequential: state with synchronous active-low reset; reset leaves ARVALID low
  // (IHI 0022H.c A3.1.2).
  always_ff @(posedge i_clk_core) begin : p_ff_fsm_ar
    if (!i_rst_n_core)
      reg_fsm_ar_current_state <= ENUM_ST_IDLE;
    else
      reg_fsm_ar_current_state <= w_fsm_ar_nxt_state;
  end

  // Payload registers without reset (SEQ-04): written when a burst is taken, read only in REQ.
  always_ff @(posedge i_clk_core) begin : p_ff_payload
    reg_araddr     <= w_araddr_nxt;
    reg_arlen      <= w_arlen_nxt;
    reg_push_last  <= w_push_last_nxt;
  end

endmodule
