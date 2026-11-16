/*
 * Project      : DMA
 * Author       : Lê Nguyễn Huỳnh Long (user)
 * AI Flow      : VLSIT RTL Generator AI Automation Flow
 * AI Flow Page : https://github.com/nguyenquanicd/VLSIT_RTL_Generator_AI_Model
 * Date         : 2026-11-16
 * Description  : Burst info FIFO u_info: depth MAX_OUT, one last flag per burst in flight.
 *                Design decisions: docs/dma/dma_v0_4block.md (section 5, decision table).
 * Deviations   : P11, TYP-05: imports dma_pkg (designer decision Q1).
 */
`timescale 1ns/1ps

module m_dma_info
  import dma_pkg::*;
#(
  localparam logic [31:0] LPARA_CNT_W = $clog2(MAX_OUT + 1)
) (
  input wire i_clk_core,
  input wire i_rst_n_core,
  // Control in
  input wire i_push,
  input wire i_push_last,
  input wire i_pop,
  // Control out
  output logic o_full,
  output logic o_empty,
  output logic o_head_last
);

  // Internal signal declarations
  logic                   reg_mem [MAX_OUT];
  logic [PTR_W-1:0]       reg_rd_ptr;
  logic [PTR_W-1:0]       w_rd_ptr_nxt;
  logic [PTR_W-1:0]       reg_wr_ptr;
  logic [PTR_W-1:0]       w_wr_ptr_nxt;
  logic [LPARA_CNT_W-1:0] reg_cnt;
  logic [LPARA_CNT_W-1:0] w_cnt_nxt;
  logic                   w_wr;
  logic                   w_rd;

  // Status and head entry. full is released by a pop in the same cycle (spec section 5).
  assign o_empty     = (reg_cnt == '0);
  assign o_full      = (reg_cnt == LPARA_CNT_W'(MAX_OUT)) & ~i_pop;
  assign o_head_last = reg_mem[reg_rd_ptr];
  assign w_wr        = i_push & ~o_full;
  assign w_rd        = i_pop & ~o_empty;

  // Pointers wrap at MAX_OUT - 1; the counter follows the accepted pushes and pops.
  always_comb begin : p_com_ptr
    w_wr_ptr_nxt = reg_wr_ptr;
    w_rd_ptr_nxt = reg_rd_ptr;
    if (w_wr)
      w_wr_ptr_nxt = (reg_wr_ptr == PTR_W'(MAX_OUT - 1)) ? '0 : reg_wr_ptr + PTR_W'(1);
    if (w_rd)
      w_rd_ptr_nxt = (reg_rd_ptr == PTR_W'(MAX_OUT - 1)) ? '0 : reg_rd_ptr + PTR_W'(1);
    w_cnt_nxt = reg_cnt + LPARA_CNT_W'(w_wr) - LPARA_CNT_W'(w_rd);
  end

  // Pointers and counter with synchronous active-low reset: empty after reset.
  always_ff @(posedge i_clk_core) begin : p_ff_ctrl
    if (!i_rst_n_core) begin
      reg_rd_ptr <= '0;
      reg_wr_ptr <= '0;
      reg_cnt    <= '0;
    end else begin
      reg_rd_ptr <= w_rd_ptr_nxt;
      reg_wr_ptr <= w_wr_ptr_nxt;
      reg_cnt    <= w_cnt_nxt;
    end
  end

  // Entry storage without reset (SEQ-04): an entry is read only after it was pushed (not empty).
  always_ff @(posedge i_clk_core) begin : p_ff_mem
    if (w_wr)
      reg_mem[reg_wr_ptr] <= i_push_last;
  end

endmodule
