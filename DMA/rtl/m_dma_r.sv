/*
 * Project      : DMA
 * Author       : Lê Nguyễn Huỳnh Long (user)
 * AI Flow      : VLSIT RTL Generator AI Automation Flow
 * AI Flow Page : https://github.com/nguyenquanicd/VLSIT_RTL_Generator_AI_Model
 * Date         : 2026-11-16
 * Description  : R receiver u_r: forwards AXI4 R beats on BEAT, ends a burst on RLAST, drains
 *                after an RRESP error, reports r_idle and r_err.
 *                Design decisions: docs/dma/dma_v0_4block.md (section 6, decision table).
 * Deviations   : P11, TYP-05: imports dma_pkg (designer decision Q1).
 */
`timescale 1ns/1ps

module m_dma_r
  import dma_pkg::*;
#(
  localparam logic [31:0] LPARA_RESP_W     = 2,
  localparam logic [31:0] LPARA_ERR_CODE_W = 3
) (
  input wire i_clk_core,
  input wire i_rst_n_core,
  // Control in
  input wire i_axi_rvalid,
  input wire i_axi_rlast,
  input wire i_axi_rid,
  input wire i_empty,
  input wire i_head_last,
  input wire i_beat_ready,
  // Data in
  input wire [DATA_W-1:0] i_axi_rdata,
  input wire [LPARA_RESP_W-1:0] i_axi_rresp,
  // Control out
  output logic o_axi_rready,
  output logic o_pop,
  output logic o_beat_valid,
  output logic o_beat_last,
  output logic o_r_idle,
  output logic o_r_err,
  // Data out
  output logic [DATA_W-1:0] o_beat_data,
  output logic [LPARA_ERR_CODE_W-1:0] o_r_err_code
);

  // FSM states: RECV receives and forwards the beats of the bursts in u_info (and is idle when
  // u_info is empty); DRAIN accepts and drops every remaining beat after an error until u_info
  // is empty. Both encodings of the 1-bit state are used; default recovers to ENUM_ST_RECV.
  typedef enum logic [0:0] {
    ENUM_ST_RECV  = 1'b0,
    ENUM_ST_DRAIN = 1'b1
  } r_state_type_def;

  // AXI4 RRESP encodings (IHI 0022H.c A3.4.5, Table A3-5).
  typedef enum logic [LPARA_RESP_W-1:0] {
    ENUM_RESP_OKAY   = 2'b00,
    ENUM_RESP_EXOKAY = 2'b01,
    ENUM_RESP_SLVERR = 2'b10,
    ENUM_RESP_DECERR = 2'b11
  } axi_resp_type_def;

  // Error codes of bus RST and REQ (dma_v0_4block.md section 2). The same encoding is defined in
  // m_dma_fsm; both must stay equal.
  typedef enum logic [LPARA_ERR_CODE_W-1:0] {
    ENUM_ERR_OKAY   = 3'd0,
    ENUM_ERR_CFG    = 3'd1,
    ENUM_ERR_SLVERR = 3'd2,
    ENUM_ERR_DECERR = 3'd3
  } err_code_type_def;

  // Internal signal declarations
  r_state_type_def             reg_fsm_r_current_state;
  r_state_type_def             w_fsm_r_nxt_state;
  logic [LPARA_ERR_CODE_W-1:0] reg_r_err_code;
  logic [LPARA_ERR_CODE_W-1:0] w_r_err_code_nxt;
  logic [LPARA_ERR_CODE_W-1:0] w_err_code;
  logic                        w_r_hs;
  logic                        w_burst_end;
  logic                        w_resp_err;

  // Beat decode. A burst ends on any handshake with RLAST = 1 (decision R2). A beat is faulty
  // when RRESP is not OKAY. RID is not used (answer Q8-d).
  assign w_r_hs      = i_axi_rvalid & o_axi_rready;
  assign w_burst_end = w_r_hs & i_axi_rlast;
  assign w_resp_err  = (i_axi_rresp != ENUM_RESP_OKAY);

  // BEAT payload and error code output. beat_data is RDATA without a register (as in the wave).
  // beat_last marks the last beat (RLAST) of the last burst of the transfer (u_info head_last).
  // The error code output shows the new code in the cycle of the r_err pulse and the registered
  // code afterwards, so the Request FSM can capture it together with the combinational r_err
  // (answers Q7-A, Q8-e).
  assign o_beat_data  = i_axi_rdata;
  assign o_beat_last  = i_head_last & i_axi_rlast;
  assign o_r_err_code = o_r_err ? w_err_code : reg_r_err_code;

  // Error code of the beat, by RRESP: ENUM_ERR_OKAY (0) for a good beat; SLVERR and EXOKAY
  // report SLVERR (answer Q8-c); DECERR reports DECERR.
  always_comb begin : p_com_err_code
    w_err_code = ENUM_ERR_OKAY;
    case (i_axi_rresp)
      ENUM_RESP_OKAY:   w_err_code = ENUM_ERR_OKAY;
      ENUM_RESP_EXOKAY: w_err_code = ENUM_ERR_SLVERR;
      ENUM_RESP_SLVERR: w_err_code = ENUM_ERR_SLVERR;
      ENUM_RESP_DECERR: w_err_code = ENUM_ERR_DECERR;
      default:          w_err_code = ENUM_ERR_OKAY;
    endcase
  end

  // Part 2, combinational: next state. RECV -> DRAIN on a faulty beat; DRAIN -> RECV when u_info
  // is empty (a pop in DRAIN takes effect on i_empty one cycle later).
  // Default first (COM-02) and a default in the case (COM-03), so no latch (COM-07).
  always_comb begin : p_com_fsm_nxt
    w_fsm_r_nxt_state = reg_fsm_r_current_state;
    case (reg_fsm_r_current_state)
      ENUM_ST_RECV: begin
        if (w_r_hs & w_resp_err)
          w_fsm_r_nxt_state = ENUM_ST_DRAIN;
      end
      ENUM_ST_DRAIN: begin
        if (i_empty)
          w_fsm_r_nxt_state = ENUM_ST_RECV;
      end
      default: w_fsm_r_nxt_state = ENUM_ST_RECV;
    endcase
  end

  // Part 3, combinational: Mealy outputs (they depend on the state and on the R channel inputs).
  // RECV : RREADY = beat_ready while u_info holds a burst, else 0; a beat is forwarded only when
  //        its RRESP is OKAY (answer Q8-a); r_err pulses on a faulty beat; pop at each RLAST;
  //        r_idle = u_info empty (spec section 6).
  // DRAIN: RREADY = 1 while u_info holds a burst, beats are dropped, pop at each RLAST.
  // beat_valid depends on RVALID and RRESP, never on beat_ready (valid/ready rule).
  always_comb begin : p_com_fsm_out
    o_axi_rready = 1'b0;
    o_beat_valid = 1'b0;
    o_pop        = 1'b0;
    o_r_idle     = 1'b0;
    o_r_err      = 1'b0;
    case (reg_fsm_r_current_state)
      ENUM_ST_RECV: begin
        o_axi_rready = i_beat_ready & ~i_empty;
        o_beat_valid = i_axi_rvalid & ~i_empty & ~w_resp_err;
        o_r_err      = w_r_hs & w_resp_err;
        o_pop        = w_burst_end;
        o_r_idle     = i_empty;
      end
      ENUM_ST_DRAIN: begin
        o_axi_rready = ~i_empty;
        o_pop        = w_burst_end;
      end
      default: begin
        // Unused encoding: all outputs stay at their default value.
      end
    endcase
  end

  // The error code register takes the code of each r_err pulse and holds it (answer Q8-e).
  assign w_r_err_code_nxt = o_r_err ? w_err_code : reg_r_err_code;

  // Part 1, sequential: control state with synchronous active-low reset (answer Q2-B). Reset
  // puts the receiver in RECV with no error code.
  always_ff @(posedge i_clk_core) begin : p_ff_ctrl
    if (!i_rst_n_core) begin
      reg_fsm_r_current_state <= ENUM_ST_RECV;
      reg_r_err_code          <= ENUM_ERR_OKAY;
    end else begin
      reg_fsm_r_current_state <= w_fsm_r_nxt_state;
      reg_r_err_code          <= w_r_err_code_nxt;
    end
  end

endmodule
