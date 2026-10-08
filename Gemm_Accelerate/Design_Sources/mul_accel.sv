
import mul_accel_pkg::* ;

module BRAM #(
   parameter int DEPTH = 1024,
   parameter int DWIDTH = 256
)(
   input  logic clk,
   input  logic [$clog2(DEPTH)-1:0] address,
   input  logic wenable,
   input  logic renable,
   input  logic [DWIDTH:0] data_in,
   output logic [DWIDTH:0] data_out
);
   logic [DWIDTH-1:0] mem [DEPTH] ;
   always_ff @(posedge clk)
   begin
       if(wenable) mem[address] <= data_in ;
       if(renable) data_out <= mem[address] ;
   end
endmodule

// Top system
module mul_accel
#(
   parameter int N = 64,
   parameter int K = 768,
   parameter int M = 256
)(
   input  logic clk, rst_n,
   input  logic start,
   output logic done,

   // communicate with external memory
   input  logic a_wenable,
   input  logic [$clog2(N*(K/TILE))-1:0] a_wr_addr,
   input  logic [TILE*DTYPEIN-1:0] a_wdata,
   input  logic b_wenable,
   input  logic [$clog2(K*(M/TILE))-1:0] b_wr_addr,
   input  logic [TILE*DTYPEIN-1:0] b_wdata,
   input  logic c_renable,
   input  logic [$clog2(N*(M/TILE))-1:0] c_rd_addr,
   input  logic [TILE*DTYPEOUT-1:0] c_rdata
);
   localparam int N_TILE = N / TILE ;
   localparam int K_TILE = K / TILE ;
   localparam int M_TILE = M / TILE ;

   localparam int A_DEPTH = N * K_TILE ;
   localparam int B_DEPTH = K * M_TILE ;
   localparam int C_DEPTH = N * M_TILE ;

   state_t load_state ;

   // BRAM
   logic [$clog2(A_DEPTH)-1:0] a_rd_addr ;
   logic [$clog2(B_DEPTH)-1:0] b_rd_addr ;
   logic a_renable, b_renable ;
   logic c_wenable ;
   logic [TILE*DTYPEIN-1:0] a_rdata, b_rdata ;
   logic [TILE*DTYPEOUT-1:0] c_wdata ;

   BRAM #(
      .DEPTH(A_DEPTH),
      .DWIDTH(TILE*DTYPEIN)
   ) A_bram (
      .clk(clk),
      .address((load_state == IDLE)? a_wr_addr : a_rd_addr),
      .wenable((load_state == IDLE)? a_wenable : 'b0),
      .renable((load_state == IDLE)? 'b0 : a_renable),
      .data_in(a_wdata),
      .data_out(a_rdata)
   );

   BRAM #(
      .DEPTH(B_DEPTH),
      .DWIDTH(TILE*DTYPEIN)
   ) B_bram (
      .clk(clk),
      .address((load_state == IDLE)? b_wr_addr : b_rd_addr),
      .wenable((load_state == IDLE)? b_wenable : 'b0),
      .renable((load_state == IDLE)? 'b0 : b_renable),
      .data_in(b_wdata),
      .data_out(b_rdata)
   );

   // L0 registers
   // Load side of pipeline
   logic [DTYPEIN -1:0] l_locala [TILE][TILE] ;
   logic [DTYPEIN -1:0] l_localb [TILE][TILE] ;
   logic l_write_bram, l_cp_n, l_cp_m ;
   // Compute side of pipeline
   logic [DTYPEIN -1:0] c_locala [TILE][TILE] ;
   logic [DTYPEIN -1:0] c_localb [TILE][TILE] ;
   logic [DTYPEOUT-1:0] c_localc [TILE][TILE] ;
   logic c_write_bram, c_cp_n, c_cp_m ;
   logic gemm_busy, gemm_start, gemm_done ;
   // Writeback side of pipeline
   logic [DTYPEOUT-1:0] w_localc [TILE][TILE] ;
   logic w_write_bram, w_cp_n, w_cp_m ;
   logic wb_start, wb_ready ;
   fsm_t new_dotproduct_fsm ;

   // pipeline between Load and Compute
   logic pipeline_enable ;
   assign pipeline_enable = load_reg_tile_done & !gemm_busy & wb_ready;

   logic [$clog2(TILE)-1:0] reg_row_index ;
   logic load_reg_tile_done ;
   load_control #(
      .N_TILE(N_TILE),
      .M_TILE(M_TILE),
      .K_TILE(K_TILE),
      .A_DEPTH(A_DEPTH),
      .B_DEPTH(B_DEPTH)
   ) Load_control (
      .clk(clk),
      .rst_n(rst_n),
      .start(start),
      .waits(gemm_busy),
      .load_reg_tile_done(load_reg_tile_done),
      .write_bram(l_write_bram),
      .load_state(load_state),
      .addra(a_rd_addr),
      .addrb(b_rd_addr),
      .row_index(reg_row_index),
      .cp_n_out(l_cp_n),
      .cp_m_out(l_cp_m)
   );

   always_comb begin
      for(int i=0 ; i<TILE ; i++) begin
         l_locala[reg_row_index][i] = a_rdata[i*DTYPEIN +: DTYPEIN] ;
         l_localb[reg_row_index][i] = b_rdata[i*DTYPEIN +: DTYPEIN] ;
      end
   end

   always_ff @(posedge clk, negedge rst_n) begin
      if(!rst_n) begin
         for(int i=0 ; i<TILE ; i++) begin
            for(int j=0 ; j<TILE ; j++) begin
               c_locala[i][j] <= 'b0 ;
               c_localb[i][j] <= 'b0 ;
            end
         end
         c_write_bram <= 1'b0 ;
         c_cp_n <= 'b0 ;
         c_cp_m <= 'b0 ;
      end else begin
         if(pipeline_enable) begin
            for(int i=0 ; i<TILE ; i++) begin
               for(int j=0 ; j<TILE ; j++) begin
                  c_locala[i][j] <= l_locala[i][j] ;
                  c_localb[i][j] <= l_localb[i][j] ;
               end
            end
            gemm_start <= 1'b1 ;
            c_write_bram <= l_write_bram ;
            c_cp_n <= l_cp_n ;
            c_cp_m <= l_cp_m ;
         end
         else gemm_start <= 1'b0 ;
      end
   end

   Gemm gemm(
        .clk(clk),
        .rst_n(rst_n),
        .start(gemm_start),
        .locala(c_locala),
        .localb(c_localb),
        .localc(c_localc),
        .busy(gemm_busy),
        .done(gemm_done)
   );

   // pipeline between compute and writeback
   always_ff @(posedge clk) begin
      if(!rst_n) begin
         for(int i=0 ; i<TILE ; i++) begin
            for(int j=0 ; j<TILE ; j++) begin
               w_localc[i][j] <= 'b0 ;
            end
         end
         w_write_bram <= 1'b0 ;
         w_cp_n <= 'b0 ;
         w_cp_m <= 'b0 ;
      end else begin
         if(pipeline_enable) begin
            for(int i=0 ; i<TILE ; i++) begin
               for(int j=0 ; j<TILE ; j++) begin
                  w_localc[i][j] <= c_localc[i][j] ;
               end
            end
            w_write_bram <= c_write_bram ;
            w_cp_n <= c_cp_n ;
            w_cp_m <= c_cp_m ;

            // Control new_dotproduct signal
            unique case(new_dotproduct_fsm)
               IDLE:    new_dotproduct_fsm <= (c_write_bram)? PRE : IDLE ;
               PRE:     new_dotproduct_fsm <= ACTIVE ;
               ACTIVE:  new_dotproduct_fsm <= IDLE ;
            endcase
         end
      end
   end

   logic [DTYPEOUT-1:0] acc_localc [TILE][TILE] ;
   Accumulate_control Accumulate (
      .clk(clk), .rst_n(rst_n),
      .wb_start(wb_start),
      .new_dotproduct(new_dotproduct_fsm == ACTIVE),
      .new_localc(w_localc),
      .acc_localc(acc_localc),
      .wb_ready(wb_ready),
   );

endmodule
