/*
 * Project      : DMA
 * Author       : Lê Nguyễn Huỳnh Long (user)
 * AI Flow      : VLSIT RTL Generator AI Automation Flow
 * AI Flow Page : https://github.com/nguyenquanicd/VLSIT_RTL_Generator_AI_Model
 * Date         : 2026-11-16
 * Description  : Top of the read DMA (u_dma), structural only: Request FSM, u_legal, u_ar,
 *                u_info, u_r, u_wr. External buses: REQ, AXI4 AR/R (manager, read only), BWR.
 *                Design decisions: docs/dma/dma_v0_4block.md (section 1, decision table).
 * Deviations   : P11, TYP-05: imports dma_pkg (designer decision Q1).
 */
`timescale 1ns/1ps

module m_dma_rd
  import dma_pkg::*;
#(
  // Parameter Description: width of the byte length req_len of one command (bus REQ).
  // Parameter values: 6 to 32; default is 32.
  // Parameter unit: bit
  parameter logic [31:0] PARA_LEN_W = 32,
  // Parameter Description: width of a word address inside one bram_pp bank (BWR waddr, REQ
  // req_dst_waddr); it must hold PARA_BANK_DEPTH.
  // Parameter values: 1 to 31; default is 13.
  // Parameter unit: bit
  parameter logic [31:0] PARA_WADDR_W = 13,
  // Parameter Description: number of words in one bram_pp bank.
  // Parameter values: 1 to 2**PARA_WADDR_W - 1; default is 6144.
  // Parameter unit: count
  parameter logic [31:0] PARA_BANK_DEPTH = 6144,
  localparam logic [31:0] LPARA_ERR_CODE_W = 3,
  localparam logic [31:0] LPARA_RESP_W     = 2,
  localparam logic [31:0] LPARA_LEN_W      = 8,
  localparam logic [31:0] LPARA_SIZE_W     = 3,
  localparam logic [31:0] LPARA_BURST_W    = 2
) (
  input wire i_clk_core,
  input wire i_rst_n_core,
  // Control in
  input wire i_req_valid,
  input wire i_axi_arready,
  input wire i_axi_rvalid,
  input wire i_axi_rlast,
  input wire i_axi_rid,
  input wire i_wr_ready,
  // Data in
  input wire [ADDR_W-1:0] i_req_addr,
  input wire [PARA_LEN_W-1:0] i_req_len,
  input wire [PARA_WADDR_W-1:0] i_req_dst_waddr,
  input wire [DATA_W-1:0] i_axi_rdata,
  input wire [LPARA_RESP_W-1:0] i_axi_rresp,
  // Control out
  output logic o_req_ready,
  output logic o_dma_done,
  output logic o_dma_err,
  output logic o_axi_arvalid,
  output logic o_axi_arid,
  output logic o_axi_rready,
  output logic o_we,
  // Data out
  output logic [LPARA_ERR_CODE_W-1:0] o_dma_err_code,
  output logic [ADDR_W-1:0] o_axi_araddr,
  output logic [LPARA_LEN_W-1:0] o_axi_arlen,
  output logic [LPARA_SIZE_W-1:0] o_axi_arsize,
  output logic [LPARA_BURST_W-1:0] o_axi_arburst,
  output logic [PARA_WADDR_W-1:0] o_waddr,
  output logic [WORD_W-1:0] o_din
);

  // Internal buses
  logic                        w_leg_load;
  logic                        w_leg_abort;
  logic [ADDR_W-1:0]           w_leg_addr;
  logic [TOTAL_BEATS_W-1:0]    w_leg_total_beats;
  logic                        w_bst_valid;
  logic                        w_bst_ready;
  logic                        w_bst_last;
  logic [ADDR_W-1:0]           w_bst_addr;
  logic [BEAT_CNT_W-1:0]       w_bst_beats;
  logic                        w_push;
  logic                        w_push_last;
  logic                        w_full;
  logic                        w_ar_done;
  logic                        w_pop;
  logic                        w_empty;
  logic                        w_head_last;
  logic                        w_beat_valid;
  logic                        w_beat_ready;
  logic                        w_beat_last;
  logic [DATA_W-1:0]           w_beat_data;
  logic                        w_r_idle;
  logic                        w_r_err;
  logic [LPARA_ERR_CODE_W-1:0] w_r_err_code;
  logic                        w_wr_load;
  logic                        w_wr_abort;
  logic [PARA_WADDR_W-1:0]     w_wr_dst;
  logic                        w_wr_bank_ready;
  logic                        w_wr_last_done;

  // Request FSM: accepts REQ, checks it, loads u_legal (LOAD) and u_wr (WLD), reports the result.
  m_dma_fsm #(
    .PARA_LEN_W      (PARA_LEN_W),
    .PARA_WADDR_W    (PARA_WADDR_W),
    .PARA_BANK_DEPTH (PARA_BANK_DEPTH)
  ) u_dma_fsm (
    .i_clk_core        (i_clk_core),
    .i_rst_n_core      (i_rst_n_core),
    .i_req_valid       (i_req_valid),
    .i_ar_done         (w_ar_done),
    .i_r_idle          (w_r_idle),
    .i_r_err           (w_r_err),
    .i_wr_bank_ready   (w_wr_bank_ready),
    .i_wr_last_done    (w_wr_last_done),
    .i_req_addr        (i_req_addr),
    .i_req_len         (i_req_len),
    .i_req_dst_waddr   (i_req_dst_waddr),
    .i_r_err_code      (w_r_err_code),
    .o_req_ready       (o_req_ready),
    .o_dma_done        (o_dma_done),
    .o_dma_err         (o_dma_err),
    .o_leg_load        (w_leg_load),
    .o_leg_abort       (w_leg_abort),
    .o_wr_load         (w_wr_load),
    .o_wr_abort        (w_wr_abort),
    .o_dma_err_code    (o_dma_err_code),
    .o_leg_addr        (w_leg_addr),
    .o_leg_total_beats (w_leg_total_beats),
    .o_wr_dst          (w_wr_dst)
  );

  // Burst legalizer: splits the command into bursts of at most MAX_BURST beats inside 4 KB (BST).
  m_dma_legal u_dma_legal (
    .i_clk_core        (i_clk_core),
    .i_rst_n_core      (i_rst_n_core),
    .i_leg_load        (w_leg_load),
    .i_leg_abort       (w_leg_abort),
    .i_bst_ready       (w_bst_ready),
    .i_leg_addr        (w_leg_addr),
    .i_leg_total_beats (w_leg_total_beats),
    .o_bst_valid       (w_bst_valid),
    .o_bst_last        (w_bst_last),
    .o_bst_addr        (w_bst_addr),
    .o_bst_beats       (w_bst_beats)
  );

  // AR issuer: drives the AXI4 AR channel and pushes each accepted burst into u_info (PUSH).
  m_dma_ar u_dma_ar (
    .i_clk_core    (i_clk_core),
    .i_rst_n_core  (i_rst_n_core),
    .i_bst_valid   (w_bst_valid),
    .i_bst_last    (w_bst_last),
    .i_full        (w_full),
    .i_axi_arready (i_axi_arready),
    .i_bst_addr    (w_bst_addr),
    .i_bst_beats   (w_bst_beats),
    .o_bst_ready   (w_bst_ready),
    .o_push        (w_push),
    .o_push_last   (w_push_last),
    .o_ar_done     (w_ar_done),
    .o_axi_arvalid (o_axi_arvalid),
    .o_axi_arid    (o_axi_arid),
    .o_axi_araddr  (o_axi_araddr),
    .o_axi_arlen   (o_axi_arlen),
    .o_axi_arsize  (o_axi_arsize),
    .o_axi_arburst (o_axi_arburst)
  );

  // Burst info FIFO: one entry per burst in flight, popped by u_r at the end of each burst (POP).
  m_dma_info u_dma_info (
    .i_clk_core   (i_clk_core),
    .i_rst_n_core (i_rst_n_core),
    .i_push       (w_push),
    .i_push_last  (w_push_last),
    .i_pop        (w_pop),
    .o_full       (w_full),
    .o_empty      (w_empty),
    .o_head_last  (w_head_last)
  );

  // R receiver: takes the AXI4 R beats, checks them and forwards good beats on BEAT (RST status).
  m_dma_r u_dma_r (
    .i_clk_core   (i_clk_core),
    .i_rst_n_core (i_rst_n_core),
    .i_axi_rvalid (i_axi_rvalid),
    .i_axi_rlast  (i_axi_rlast),
    .i_axi_rid    (i_axi_rid),
    .i_empty      (w_empty),
    .i_head_last  (w_head_last),
    .i_beat_ready (w_beat_ready),
    .i_axi_rdata  (i_axi_rdata),
    .i_axi_rresp  (i_axi_rresp),
    .o_axi_rready (o_axi_rready),
    .o_pop        (w_pop),
    .o_beat_valid (w_beat_valid),
    .o_beat_last  (w_beat_last),
    .o_r_idle     (w_r_idle),
    .o_r_err      (w_r_err),
    .o_beat_data  (w_beat_data),
    .o_r_err_code (w_r_err_code)
  );

  // BRAM writer: packs the beats into WORD_W-bit words and writes them to bram_pp (BWR).
  m_dma_wr #(
    .PARA_WADDR_W (PARA_WADDR_W)
  ) u_dma_wr (
    .i_clk_core      (i_clk_core),
    .i_rst_n_core    (i_rst_n_core),
    .i_wr_load       (w_wr_load),
    .i_wr_abort      (w_wr_abort),
    .i_beat_valid    (w_beat_valid),
    .i_beat_last     (w_beat_last),
    .i_wr_ready      (i_wr_ready),
    .i_wr_dst        (w_wr_dst),
    .i_beat_data     (w_beat_data),
    .o_wr_bank_ready (w_wr_bank_ready),
    .o_wr_last_done  (w_wr_last_done),
    .o_beat_ready    (w_beat_ready),
    .o_we            (o_we),
    .o_waddr         (o_waddr),
    .o_din           (o_din)
  );

endmodule
