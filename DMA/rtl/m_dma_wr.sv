/*
 * Project      : DMA
 * Author       : Lê Nguyễn Huỳnh Long (user)
 * AI Flow      : VLSIT RTL Generator AI Automation Flow
 * AI Flow Page : https://github.com/nguyenquanicd/VLSIT_RTL_Generator_AI_Model
 * Date         : 2026-11-16
 * Description  : BRAM writer u_wr: packs 8 beats into one 256-bit word, writes bram_pp from
 *                wr_dst, ends on beat_last.
 *                Design decisions: docs/dma/dma_v0_4block.md (section 7, decision table).
 * Deviations   : P11, TYP-05: imports dma_pkg (designer decision Q1).
 */
`timescale 1ns/1ps

module m_dma_wr
  import dma_pkg::*;
#(
  // Parameter Description: width of a word address inside one bram_pp bank (WLD wr_dst, BWR
  // waddr), as in section 7 of the spec.
  // Parameter values: 1 to 31; default is 13 (one bank holds 6144 words).
  // Parameter unit: bit
  parameter logic [31:0] PARA_WADDR_W = 13,
  localparam logic [31:0] LPARA_BUF_W = WORD_W - DATA_W
) (
  input wire i_clk_core,
  input wire i_rst_n_core,
  // Control in
  input wire i_wr_load,
  input wire i_wr_abort,
  input wire i_beat_valid,
  input wire i_beat_last,
  input wire i_wr_ready,
  // Data in
  input wire [PARA_WADDR_W-1:0] i_wr_dst,
  input wire [DATA_W-1:0] i_beat_data,
  // Control out
  output logic o_wr_bank_ready,
  output logic o_wr_last_done,
  output logic o_beat_ready,
  output logic o_we,
  // Data out
  output logic [PARA_WADDR_W-1:0] o_waddr,
  output logic [WORD_W-1:0] o_din
);

  // FSM states: IDLE waits for wr_load, PACK collects beats and writes words until the beat with
  // beat_last or an abort. Both encodings of the 1-bit state are used; default recovers to
  // ENUM_ST_IDLE.
  typedef enum logic [0:0] {
    ENUM_ST_IDLE = 1'b0,
    ENUM_ST_PACK = 1'b1
  } wr_state_type_def;

  // Internal signal declarations
  wr_state_type_def        reg_fsm_wr_current_state;
  wr_state_type_def        w_fsm_wr_nxt_state;
  logic [IDX_W-1:0]        reg_idx;
  logic [IDX_W-1:0]        w_idx_nxt;
  logic [PARA_WADDR_W-1:0] reg_cur_waddr;
  logic [PARA_WADDR_W-1:0] w_cur_waddr_nxt;
  logic [LPARA_BUF_W-1:0]  reg_buf;
  logic [LPARA_BUF_W-1:0]  w_buf_nxt;
  logic                    reg_we;
  logic                    w_we_nxt;
  logic                    reg_wr_last_done;
  logic                    w_wr_last_done_nxt;
  logic [PARA_WADDR_W-1:0] reg_waddr;
  logic [PARA_WADDR_W-1:0] w_waddr_nxt;
  logic [WORD_W-1:0]       reg_din;
  logic [WORD_W-1:0]       w_din_nxt;
  logic                    w_load;
  logic                    w_beat_acc;
  logic                    w_word_done;
  logic                    w_end;

  // Interface mapping. wr_bank_ready forwards the bram_pp wr_ready level to the Request FSM
  // (assumption A10). beat_ready is constant 1 (answer Q5-A). The BWR outputs come straight from
  // registers (answer Q3-B), so o_we and wr_last_done are one-cycle pulses.
  assign o_wr_bank_ready = i_wr_ready;
  assign o_beat_ready    = 1'b1;
  assign o_we            = reg_we;
  assign o_waddr         = reg_waddr;
  assign o_din           = reg_din;
  assign o_wr_last_done  = reg_wr_last_done;

  // Event decode. A load is taken in IDLE only, and an abort in the same cycle cancels it.
  // A beat is accepted only in PACK without an abort. The beat with index BEATS_PER_WORD-1
  // completes a word. The accepted beat with beat_last ends the transfer (answer Q6).
  assign w_load      = i_wr_load & ~i_wr_abort;
  assign w_beat_acc  = i_beat_valid & ~i_wr_abort & (reg_fsm_wr_current_state == ENUM_ST_PACK);
  assign w_word_done = w_beat_acc & (reg_idx == IDX_W'(BEATS_PER_WORD - 1));
  assign w_end       = w_beat_acc & i_beat_last;

  // Part 2, combinational: next state. IDLE -> PACK on a load; PACK -> IDLE on an abort or on
  // the beat with beat_last. The default is assigned first (COM-02) and the case has a default
  // (COM-03), so no latch is inferred (COM-07).
  always_comb begin : p_com_fsm_nxt
    w_fsm_wr_nxt_state = reg_fsm_wr_current_state;
    case (reg_fsm_wr_current_state)
      ENUM_ST_IDLE: begin
        if (w_load)
          w_fsm_wr_nxt_state = ENUM_ST_PACK;
      end
      ENUM_ST_PACK: begin
        if (i_wr_abort | w_end)
          w_fsm_wr_nxt_state = ENUM_ST_IDLE;
      end
      default: w_fsm_wr_nxt_state = ENUM_ST_IDLE;
    endcase
  end

  // Part 3, combinational: packer datapath and registered BWR outputs.
  // IDLE: a load captures wr_dst and clears the beat index.
  // PACK, priority casez on {abort, word completed, beat accepted}:
  //   abort         -> nothing is written; the partial word is dropped (answer Q4-A).
  //   word complete -> write {current beat, buffer} to cur_waddr in the next cycle, then
  //                    increment cur_waddr and restart the beat index; wr_last_done comes with
  //                    the word whose last beat has beat_last (answer Q6).
  //   other beat    -> store the beat in the buffer slot of its index, increment the index.
  // we and wr_last_done default to 0 so they are one-cycle pulses; waddr, din and the buffer
  // hold their value. Every output of the process gets its default first (COM-02, COM-07).
  always_comb begin : p_com_pack
    w_idx_nxt          = reg_idx;
    w_cur_waddr_nxt    = reg_cur_waddr;
    w_buf_nxt          = reg_buf;
    w_we_nxt           = 1'b0;
    w_wr_last_done_nxt = 1'b0;
    w_waddr_nxt        = reg_waddr;
    w_din_nxt          = reg_din;
    case (reg_fsm_wr_current_state)
      ENUM_ST_IDLE: begin
        if (w_load) begin
          w_idx_nxt       = '0;
          w_cur_waddr_nxt = i_wr_dst;
        end
      end
      ENUM_ST_PACK: begin
        casez ({i_wr_abort, w_word_done, w_beat_acc})
          3'b1??: begin
            w_idx_nxt = '0;
          end
          3'b01?: begin
            w_we_nxt           = 1'b1;
            w_wr_last_done_nxt = i_beat_last;
            w_waddr_nxt        = reg_cur_waddr;
            w_din_nxt          = {i_beat_data, reg_buf};
            w_cur_waddr_nxt    = reg_cur_waddr + PARA_WADDR_W'(1);
            w_idx_nxt          = '0;
          end
          3'b001: begin
            // reg_idx < BEATS_PER_WORD-1 here: index BEATS_PER_WORD-1 completes the word
            // (branch 3'b01?), so the slot is always inside the buffer. A beat_last here (not
            // possible by design) ends PACK through w_end; the next load clears the index.
            w_buf_nxt[reg_idx*DATA_W +: DATA_W] = i_beat_data;
            w_idx_nxt = reg_idx + IDX_W'(1);
          end
          default: begin
            // No beat accepted: every register keeps its value.
          end
        endcase
      end
      default: begin
        // Unused encoding: same as IDLE without a load.
      end
    endcase
  end

  // Part 1, sequential: control and validity state with synchronous active-low reset
  // (answer Q2-B). Reset puts the writer in IDLE with no write pending.
  always_ff @(posedge i_clk_core) begin : p_ff_ctrl
    if (!i_rst_n_core) begin
      reg_fsm_wr_current_state <= ENUM_ST_IDLE;
      reg_idx                  <= '0;
      reg_we                   <= 1'b0;
      reg_wr_last_done         <= 1'b0;
    end else begin
      reg_fsm_wr_current_state <= w_fsm_wr_nxt_state;
      reg_idx                  <= w_idx_nxt;
      reg_we                   <= w_we_nxt;
      reg_wr_last_done         <= w_wr_last_done_nxt;
    end
  end

  // Payload registers without reset (SEQ-04). cur_waddr is written by every load before PACK
  // reads it; the buffer slots are written before the word that uses them; waddr and din are
  // read by bram_pp only while o_we is 1.
  always_ff @(posedge i_clk_core) begin : p_ff_payload
    reg_cur_waddr <= w_cur_waddr_nxt;
    reg_buf       <= w_buf_nxt;
    reg_waddr     <= w_waddr_nxt;
    reg_din       <= w_din_nxt;
  end

endmodule
