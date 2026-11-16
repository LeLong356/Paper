/*
 * Project      : DMA
 * Author       : Lê Nguyễn Huỳnh Long (user)
 * AI Flow      : VLSIT RTL Generator AI Automation Flow
 * AI Flow Page : https://github.com/nguyenquanicd/VLSIT_RTL_Generator_AI_Model
 * Date         : 2026-11-16
 * Description  : Request FSM: accepts a command on REQ, checks it, loads u_legal and u_wr,
 *                waits for the end of the transfer, reports done or error (codes 1-3).
 *                Design decisions: docs/dma/dma_v0_4block.md (section 2, decision table).
 * Deviations   : P11, TYP-05: imports dma_pkg (designer decision Q1).
 */
`timescale 1ns/1ps

module m_dma_fsm
  import dma_pkg::*;
#(
  // Parameter Description: width of the byte length req_len of one command (bus REQ).
  // Parameter values: LPARA_WORD_SHIFT + 1 to 32; default is 32.
  // Parameter unit: bit
  parameter logic [31:0] PARA_LEN_W = 32,
  // Parameter Description: width of a word address inside one bram_pp bank (req_dst_waddr,
  // wr_dst); it must hold PARA_BANK_DEPTH.
  // Parameter values: 1 to 31; default is 13.
  // Parameter unit: bit
  parameter logic [31:0] PARA_WADDR_W = 13,
  // Parameter Description: number of words in one bram_pp bank; the last word written by a
  // command must lie inside the bank (CHECK state).
  // Parameter values: 1 to 2**PARA_WADDR_W - 1; default is 6144.
  // Parameter unit: count
  parameter logic [31:0] PARA_BANK_DEPTH = 6144,
  localparam logic [31:0] LPARA_ERR_CODE_W = 3,
  localparam logic [31:0] LPARA_WORD_SHIFT = BEAT_SHIFT + IDX_W
) (
  input wire i_clk_core,
  input wire i_rst_n_core,
  // Control in
  input wire i_req_valid,
  input wire i_ar_done,
  input wire i_r_idle,
  input wire i_r_err,
  input wire i_wr_bank_ready,
  input wire i_wr_last_done,
  // Data in
  input wire [ADDR_W-1:0] i_req_addr,
  input wire [PARA_LEN_W-1:0] i_req_len,
  input wire [PARA_WADDR_W-1:0] i_req_dst_waddr,
  input wire [LPARA_ERR_CODE_W-1:0] i_r_err_code,
  // Control out
  output logic o_req_ready,
  output logic o_dma_done,
  output logic o_dma_err,
  output logic o_leg_load,
  output logic o_leg_abort,
  output logic o_wr_load,
  output logic o_wr_abort,
  // Data out
  output logic [LPARA_ERR_CODE_W-1:0] o_dma_err_code,
  output logic [ADDR_W-1:0] o_leg_addr,
  output logic [TOTAL_BEATS_W-1:0] o_leg_total_beats,
  output logic [PARA_WADDR_W-1:0] o_wr_dst
);

  // FSM states: IDLE accepts a command; CHECK validates it; WAIT_RDY waits for a free bank;
  // RUN waits for the last word or an error; FLUSH waits until no burst is in flight; DONE and
  // ERR report the result for one cycle. Unused encoding 3'b111 recovers to ENUM_ST_IDLE.
  typedef enum logic [2:0] {
    ENUM_ST_IDLE     = 3'b000,
    ENUM_ST_CHECK    = 3'b001,
    ENUM_ST_WAIT_RDY = 3'b010,
    ENUM_ST_RUN      = 3'b011,
    ENUM_ST_FLUSH    = 3'b100,
    ENUM_ST_DONE     = 3'b101,
    ENUM_ST_ERR      = 3'b110
  } req_state_type_def;

  // Error codes of bus RST and REQ (dma_v0_4block.md section 2). The same encoding is defined in
  // m_dma_r; both must stay equal.
  typedef enum logic [LPARA_ERR_CODE_W-1:0] {
    ENUM_ERR_OKAY   = 3'd0,
    ENUM_ERR_CFG    = 3'd1,
    ENUM_ERR_SLVERR = 3'd2,
    ENUM_ERR_DECERR = 3'd3
  } err_code_type_def;

  // Internal signal declarations
  req_state_type_def             reg_fsm_req_current_state;
  req_state_type_def             w_fsm_req_nxt_state;
  logic [ADDR_W-1:0]             reg_req_addr;
  logic [ADDR_W-1:0]             w_req_addr_nxt;
  logic [PARA_LEN_W-1:0]         reg_req_len;
  logic [PARA_LEN_W-1:0]         w_req_len_nxt;
  logic [PARA_WADDR_W-1:0]       reg_req_dst;
  logic [PARA_WADDR_W-1:0]       w_req_dst_nxt;
  logic [LPARA_ERR_CODE_W-1:0]   reg_dma_err_code;
  logic [LPARA_ERR_CODE_W-1:0]   w_dma_err_code_nxt;
  logic                          reg_leg_load;
  logic                          reg_wr_load;
  logic                          w_load_nxt;
  logic                          w_req_hs;
  logic [PARA_LEN_W-1:0]         w_words;
  logic [PARA_LEN_W:0]           w_end_waddr;
  logic                          w_addr_ok;
  logic                          w_len_ok;
  logic                          w_cfg_ok;

  // Command check (CHECK state, answer Q9-d), computed from the captured command.
  // w_words is the number of WORD_W-bit words; the end address is computed one bit wider than
  // req_len so that a large length cannot wrap around and pass the bank-depth comparison.
  assign w_req_hs    = i_req_valid & o_req_ready;
  assign w_words     = reg_req_len >> LPARA_WORD_SHIFT;
  assign w_end_waddr = $bits(w_end_waddr)'(w_words) + $bits(w_end_waddr)'(reg_req_dst);
  assign w_addr_ok   = (reg_req_addr[BEAT_SHIFT-1:0] == '0); // ARSIZE = 4 byte
  // 1 word == 32 byte
  assign w_len_ok    = (reg_req_len[LPARA_WORD_SHIFT-1:0] == '0) & (reg_req_len != '0);
  assign w_cfg_ok    = w_addr_ok & w_len_ok & (w_end_waddr <= $bits(w_end_waddr)'(PARA_BANK_DEPTH));

  // LOAD and WLD payload. They come from the command captured at the REQ handshake, so they are
  // stable from the load pulse to the end of the transfer.
  assign o_leg_addr        = reg_req_addr;
  assign o_leg_total_beats = $bits(o_leg_total_beats)'(reg_req_len >> BEAT_SHIFT);
  assign o_wr_dst          = reg_req_dst;

  // Registered outputs: load pulses (answer Q9-a) and the error code that holds until the next
  // accepted command.
  assign o_leg_load     = reg_leg_load;
  assign o_wr_load      = reg_wr_load;
  assign o_dma_err_code = reg_dma_err_code;

  // Part 2, combinational: next state.
  // IDLE -> CHECK on the REQ handshake. CHECK -> WAIT_RDY when the command is valid, else ERR.
  // WAIT_RDY -> RUN when bram_pp has a free bank. RUN -> FLUSH on r_err or on wr_last_done.
  // FLUSH waits for ar_done and r_idle, then goes to ERR when an error code was stored, else
  // to DONE. DONE and ERR -> IDLE.
  // Default first (COM-02) and a default in every case (COM-03), so no latch (COM-07).
  always_comb begin : p_com_fsm_nxt
    w_fsm_req_nxt_state = reg_fsm_req_current_state;
    case (reg_fsm_req_current_state)
      ENUM_ST_IDLE: begin
        if (w_req_hs)
          w_fsm_req_nxt_state = ENUM_ST_CHECK;
      end
      ENUM_ST_CHECK: begin
        if (w_cfg_ok)
          w_fsm_req_nxt_state = ENUM_ST_WAIT_RDY;
        else
          w_fsm_req_nxt_state = ENUM_ST_ERR;
      end
      ENUM_ST_WAIT_RDY: begin
        if (i_wr_bank_ready)
          w_fsm_req_nxt_state = ENUM_ST_RUN;
      end
      ENUM_ST_RUN: begin
        if (i_r_err | i_wr_last_done)
          w_fsm_req_nxt_state = ENUM_ST_FLUSH;
      end
      ENUM_ST_FLUSH: begin
        if (i_ar_done & i_r_idle) begin
          if (reg_dma_err_code != ENUM_ERR_OKAY)
            w_fsm_req_nxt_state = ENUM_ST_ERR;
          else
            w_fsm_req_nxt_state = ENUM_ST_DONE;
        end
      end
      ENUM_ST_DONE: w_fsm_req_nxt_state = ENUM_ST_IDLE;
      ENUM_ST_ERR:  w_fsm_req_nxt_state = ENUM_ST_IDLE;
      default:      w_fsm_req_nxt_state = ENUM_ST_IDLE;
    endcase
  end

  // Part 3, combinational: Mealy outputs. req_ready, dma_done and dma_err depend on the state
  // only (dma_done and dma_err are one-cycle pulses because DONE and ERR last one cycle).
  // leg_abort and wr_abort follow r_err in RUN in the same cycle (answers Q4-A, Q7-A).
  always_comb begin : p_com_fsm_out
    o_req_ready = 1'b0;
    o_dma_done  = 1'b0;
    o_dma_err   = 1'b0;
    o_leg_abort = 1'b0;
    o_wr_abort  = 1'b0;
    case (reg_fsm_req_current_state)
      ENUM_ST_IDLE: o_req_ready = 1'b1;
      ENUM_ST_RUN: begin
        o_leg_abort = i_r_err;
        o_wr_abort  = i_r_err;
      end
      ENUM_ST_DONE: o_dma_done = 1'b1;
      ENUM_ST_ERR:  o_dma_err  = 1'b1;
      default: begin
        // CHECK, WAIT_RDY, FLUSH and the unused encoding: all outputs stay at their default.
      end
    endcase
  end

  // Command capture, error code and load pulse.
  // IDLE: the REQ handshake captures the command (the requester may change req_* afterwards) and
  // clears the error code. CHECK: a rejected command stores the configuration code. RUN: r_err
  // stores the code of the read error. The load pulse is set when WAIT_RDY sees a free bank, so
  // it appears in the first RUN cycle.
  always_comb begin : p_com_cmd
    w_req_addr_nxt     = reg_req_addr;
    w_req_len_nxt      = reg_req_len;
    w_req_dst_nxt      = reg_req_dst;
    w_dma_err_code_nxt = reg_dma_err_code;
    w_load_nxt         = 1'b0;
    case (reg_fsm_req_current_state)
      ENUM_ST_IDLE: begin
        if (w_req_hs) begin
          w_req_addr_nxt     = i_req_addr;
          w_req_len_nxt      = i_req_len;
          w_req_dst_nxt      = i_req_dst_waddr;
          w_dma_err_code_nxt = ENUM_ERR_OKAY;
        end
      end
      ENUM_ST_CHECK: begin
        if (!w_cfg_ok)
          w_dma_err_code_nxt = ENUM_ERR_CFG;
      end
      ENUM_ST_WAIT_RDY: begin
        w_load_nxt = i_wr_bank_ready;
      end
      ENUM_ST_RUN: begin
        if (i_r_err)
          w_dma_err_code_nxt = i_r_err_code;
      end
      default: begin
        // Other states keep the command and the error code.
      end
    endcase
  end

  // Part 1, sequential: control state with synchronous active-low reset (answer Q2-B). Reset
  // puts the FSM in IDLE with no load pulse and no error code.
  always_ff @(posedge i_clk_core) begin : p_ff_ctrl
    if (!i_rst_n_core) begin
      reg_fsm_req_current_state <= ENUM_ST_IDLE;
      reg_dma_err_code          <= ENUM_ERR_OKAY;
      reg_leg_load              <= 1'b0;
      reg_wr_load               <= 1'b0;
    end else begin
      reg_fsm_req_current_state <= w_fsm_req_nxt_state;
      reg_dma_err_code          <= w_dma_err_code_nxt;
      reg_leg_load              <= w_load_nxt;
      reg_wr_load               <= w_load_nxt;
    end
  end

  // Command registers without reset (SEQ-04): they are written at the REQ handshake, and CHECK
  // and the LOAD / WLD consumers read them only after that.
  always_ff @(posedge i_clk_core) begin : p_ff_cmd
    reg_req_addr <= w_req_addr_nxt;
    reg_req_len  <= w_req_len_nxt;
    reg_req_dst  <= w_req_dst_nxt;
  end

endmodule
