`timescale 1ns/1ps

module Load_control_tb();

localparam int TILE = 32 ;
localparam int DTYPEIN = 8 ;
localparam int DTYPEOUT = 32 ;

localparam int N = 64 ;
localparam int K = 768 ;
localparam int M = 256 ;
localparam int N_TILE = N/TILE ;
localparam int K_TILE = K/TILE ;
localparam int M_TILE = M/TILE ;
localparam int A_DEPTH = N * K_TILE ;
localparam int B_DEPTH = K * M_TILE ;
localparam int C_DEPTH = N * M_TILE ;

logic clk, rst_n ;
logic start, busy ;

logic l_write_bram ;
logic l_cp_n ;
logic l_cp_m ;
logic [$clog2(A_DEPTH)-1:0] a_rd_addr ;
logic [$clog2(B_DEPTH)-1:0] b_rd_addr ;
logic [$clog2(TILE)-1:0] row_index ;

state_t load_state ;

Load_control #(
      .N_TILE(N_TILE),
      .M_TILE(M_TILE),
      .K_TILE(K_TILE),
      .A_DEPTH(A_DEPTH),
      .B_DEPTH(B_DEPTH)
   ) Load_control (
      .clk(clk),
      .rst_n(rst_n),
      .start(start),
      .waits(busy),
      .load_state(load_state),
      .addra(a_rd_addr),
      .addrb(b_rd_addr),
      .row_index(row_index),
      .cp_n_out(l_cp_n),
      .cp_m_out(l_cp_m),
      .write_bram(l_write_bram)
   );

task automatic clock(input int number) ;
    repeat(number) begin
        clk = 1 ; #5 ;
        clk = 0 ; #5 ;
    end
endtask
task automatic reset() ;
    rst_n = 1'b0 ; clock(2) ;
    rst_n = 1'b1 ; clock(1) ;
endtask

task automatic load_control_test() ;
    start = 1'b0 ;
    reset() ;
    start <= 1'b1 ;
    clock(1) ; start <= 1'b0 ; busy = 1'b1 ;
    clock(31) ;
    repeat(34) begin
        busy <= 1'b0 ; clock(1) ; busy <= 1'b1 ;
        clock(34) ;
    end
endtask

initial begin
    load_control_test() ;
    $finish ;
end
endmodule

