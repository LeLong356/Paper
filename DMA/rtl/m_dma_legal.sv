/*
 * Project      : DMA
 * Author       : Lê Nguyễn Huỳnh Long (user)
 * AI Flow      : VLSIT RTL Generator AI Automation Flow
 * AI Flow Page : https://github.com/nguyenquanicd/VLSIT_RTL_Generator_AI_Model
 * Date         : 2026-11-16
 * Description  : Burst legalizer u_legal: splits a command into bursts of at most MAX_BURST
 *                beats that do not cross 4 KB, offered on BST.
 *                Design decisions: docs/dma/dma_v0_4block.md (section 3, decision table).
 * Deviations   : P11, TYP-05: imports dma_pkg (designer decision Q1).
 */
`timescale 1ns/1ps

module m_dma_legal
  import dma_pkg::*;
#(
  localparam logic [31:0] LPARA_4K_BYTES = 4096,
  localparam logic [31:0] LPARA_4K_W     = $clog2(LPARA_4K_BYTES)
) (
  input wire i_clk_core,
  input wire i_rst_n_core,
  // Control in
  input wire i_leg_load,
  input wire i_leg_abort,
  input wire i_bst_ready,
  // Data in
  input wire [ADDR_W-1:0] i_leg_addr,
  input wire [TOTAL_BEATS_W-1:0] i_leg_total_beats,
  // Control out
  output logic o_bst_valid,
  output logic o_bst_last,
  // Data out
  output logic [ADDR_W-1:0] o_bst_addr,
  output logic [BEAT_CNT_W-1:0] o_bst_beats
);

  // Internal signal declarations
  logic [ADDR_W-1:0]        reg_addr;
  logic [ADDR_W-1:0]        w_addr_nxt;
  logic [TOTAL_BEATS_W-1:0] reg_beats_left;
  logic [TOTAL_BEATS_W-1:0] w_beats_left_nxt;
  logic [TO_4K_W-1:0]       w_to_4k;
  logic [BEAT_CNT_W-1:0]    w_beats;
  logic                     w_bst_hs;

  // BST outputs. A burst is offered while beats are left and no abort is pending (an abort drops
  // bst_valid in the same cycle, answers A9 and Q7-A). bst_last marks the burst that uses up all
  // remaining beats.
  assign o_bst_valid = (reg_beats_left != '0) & ~i_leg_abort;
  assign o_bst_addr  = reg_addr;
  assign o_bst_beats = w_beats;
  assign o_bst_last  = ({{(TOTAL_BEATS_W-BEAT_CNT_W){1'b0}}, w_beats} == reg_beats_left);
  assign w_bst_hs    = o_bst_valid & i_bst_ready;

  // Burst size: beats = min(MAX_BURST, beats_left, beats to the next 4 KB boundary).
  // to_4k is 1 .. 4096 / BYTES_PER_BEAT, so it needs TO_4K_W bits; the subtraction is done one
  // bit wider than the 4 KB offset so that the constant 4096 does not wrap to 0.
  always_comb begin : p_com_beats
    w_to_4k = TO_4K_W'(((LPARA_4K_W+1)'(LPARA_4K_BYTES)
                        - (LPARA_4K_W+1)'(reg_addr[LPARA_4K_W-1:0])) >> BEAT_SHIFT);
    w_beats = BEAT_CNT_W'(MAX_BURST);
    if (reg_beats_left < TOTAL_BEATS_W'(w_beats))
      w_beats = BEAT_CNT_W'(reg_beats_left);
    if (TOTAL_BEATS_W'(w_to_4k) < TOTAL_BEATS_W'(w_beats))
      w_beats = BEAT_CNT_W'(w_to_4k);
  end

  // Next address and beat count. A load takes the new command; otherwise each accepted burst
  // moves the address by beats * BYTES_PER_BEAT and reduces the beats left. An abort clears the
  // beats left in any case, so no further burst is offered.
  always_comb begin : p_com_nxt
    w_addr_nxt       = reg_addr;
    w_beats_left_nxt = reg_beats_left;
    if (i_leg_load) begin
      w_addr_nxt       = i_leg_addr;
      w_beats_left_nxt = i_leg_total_beats;
    end else if (w_bst_hs) begin
      w_addr_nxt       = reg_addr + (ADDR_W'(w_beats) << BEAT_SHIFT);
      w_beats_left_nxt = reg_beats_left - TOTAL_BEATS_W'(w_beats);
    end
    if (i_leg_abort)
      w_beats_left_nxt = '0;
  end

  // Address and beat count with synchronous active-low reset: no burst after reset.
  always_ff @(posedge i_clk_core) begin : p_ff_ctrl
    if (!i_rst_n_core) begin
      reg_addr       <= '0;
      reg_beats_left <= '0;
    end else begin
      reg_addr       <= w_addr_nxt;
      reg_beats_left <= w_beats_left_nxt;
    end
  end

endmodule
