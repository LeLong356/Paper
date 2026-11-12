
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
   parameter int TILE = DEFAULT_TILE,
   parameter int N = DEFAULT_N,
   parameter int K = DEFAULT_K,
   parameter int M = DEFAULT_M
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

   // A,B BRAM
   logic [$clog2(A_DEPTH)-1:0] a_rd_addr ;
   logic [$clog2(B_DEPTH)-1:0] b_rd_addr ;
   logic renable ;
   logic [TILE*DTYPEIN-1:0] a_rdata, b_rdata ;
   // C BRAM
   logic [$clog2(C_DEPTH)-1:0] c_wr_addr ;
   logic [TILE*DTYPEOUT-1:0] c_wdata ;
   logic c_wenable ;
   logic w_write_bram ;

   BRAM #(
      .DEPTH(A_DEPTH),
      .DWIDTH(TILE*DTYPEIN)
   ) A_bram (
      .clk(clk),
      .address((load_state == IDLE)? a_wr_addr : a_rd_addr),
      .wenable((load_state == IDLE)? a_wenable : 'b0),
      .renable((load_state == IDLE)? 'b0 : renable),
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
      .renable((load_state == IDLE)? 'b0 : renable),
      .data_in(b_wdata),
      .data_out(b_rdata)
   );

   BRAM #(
      .DEPTH(C_DEPTH),
      .DWIDTH(TILE*DTYPEOUT)
   ) C_bram (
      .clk(clk),
      .address((w_write_bram)? c_wr_addr : c_rd_addr),
      .wenable(c_wenable),
      .renable(c_renable),
      .data_in(c_wdata),
      .data_out(c_rdata)
   );

   // L0 registers
   // Load side of pipeline
   logic [DTYPEIN -1:0] l_locala [TILE][TILE] ;
   logic [DTYPEIN -1:0] l_localb [TILE][TILE] ;
   logic l_write_bram ;
   logic [$clog2(N_TILE)-1:0] l_cp_n ;
   logic [$clog2(M_TILE)-1:0] l_cp_m ;
   // Compute side of pipeline
   logic [DTYPEIN -1:0] c_locala [TILE][TILE] ;
   logic [DTYPEIN -1:0] c_localb [TILE][TILE] ;
   logic [DTYPEOUT-1:0] c_localc [TILE][TILE] ;
   logic c_write_bram ;
   logic [$clog2(N_TILE)-1:0]c_cp_n ;
   logic [$clog2(M_TILE)-1:0] c_cp_m ;
   logic gemm_busy, gemm_start, gemm_done ;
   // Writeback side of pipeline
   logic [DTYPEOUT-1:0] w_localc [TILE][TILE] ;
   logic [$clog2(N_TILE)-1:0] w_cp_n ;
   logic [$clog2(M_TILE)-1:0] w_cp_m ;
   logic wb_start, wb_ready ;

   // pipeline inside Load stage
   logic [$clog2(TILE)-1:0] row_index, row_index_reg ;
   logic load_local_valid ;

   // pipeline between Load and Compute
   logic load_reg_tile_done ;
   logic pipeline_enable ;
   assign pipeline_enable = load_reg_tile_done & !gemm_busy & wb_ready & !done ;

   Load_control #(
      .TILE(TILE),
      .N_TILE(N_TILE),
      .M_TILE(M_TILE),
      .K_TILE(K_TILE),
      .A_DEPTH(A_DEPTH),
      .B_DEPTH(B_DEPTH)
   ) Load_control (
      .clk(clk),
      .rst_n(rst_n),
      .start(start),
      .waits(!pipeline_enable),
      .done(done),
      .load_state(load_state),
      .addra(a_rd_addr),
      .addrb(b_rd_addr),
      .row_index(row_index_reg),
      .renable(renable),
      .cp_n_out(l_cp_n),
      .cp_m_out(l_cp_m),
      .write_bram(l_write_bram)
   );

// Pipeline inside Load stage
   always_ff @(posedge clk, negedge rst_n) begin
      if(!rst_n) begin
         load_reg_tile_done <= 1'b0 ;
         row_index <= 'b0 ;
         load_local_valid <= 1'b0 ;
      end
      else begin
         // pipeline to access bram
         row_index <= row_index_reg ;
         load_local_valid <= renable ;

         // pipeline to write L0 register
         for(int i=0 ; i<TILE ; i++) begin
            if(load_local_valid) begin
               l_locala[row_index][i] <= a_rdata[i*DTYPEIN +: DTYPEIN] ;
               l_localb[row_index][i] <= b_rdata[i*DTYPEIN +: DTYPEIN] ;
            end
         end
         unique case(load_reg_tile_done)
            1'b0: load_reg_tile_done <= (row_index == TILE-1) | (load_state == DONE) ;
            1'b1: load_reg_tile_done <= (pipeline_enable)? 1'b0 : 1'b1 ;
            default: ;
         endcase
      end
   end

// Pipeline between Load and Compute
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

   Gemm #(
        .TILE(TILE)
   ) gemm (
        .clk(clk),
        .rst_n(rst_n),
        .start(gemm_start),
        .locala(c_locala),
        .localb(c_localb),
        .localc(c_localc),
        .busy(gemm_busy),
        .done(gemm_done)
   );

// Pipeline between Compute and Writeback
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
            wb_start <= 1'b1 ;
            w_write_bram <= c_write_bram ;
            w_cp_n <= c_cp_n ;
            w_cp_m <= c_cp_m ;
         end
         else wb_start <= 1'b0 ;
      end
   end

   logic [DTYPEOUT-1:0] acc_localc [TILE][TILE] ;
   Accumulate_control #(
      .C_DEPTH(C_DEPTH),
      .N_TILE(N_TILE),
      .K_TILE(K_TILE),
      .M_TILE(M_TILE),
      .TILE(TILE)
   ) Accumulate (
      .clk(clk), .rst_n(rst_n),
      .wb_start(wb_start),
      .new_localc(w_localc),
      .acc_localc(acc_localc),
      .wb_ready(wb_ready),
      .cp_n(w_cp_n),
      .cp_m(w_cp_m),
      .write_bram(w_write_bram),
      .wen(c_wenable),
      .addr(c_wr_addr),
      .wdata(c_wdata),
      .top_system_done(done)
   );
endmodule
