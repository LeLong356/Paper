`timescale 1ns/1ps

module Gemm_tb();

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
logic start, busy, done ;
logic valid_in, valid_out ;
logic [DTYPEIN-1:0] locala [TILE][TILE] ;
logic [DTYPEIN-1:0] localb [TILE][TILE] ;
logic [DTYPEOUT-1:0] localc[TILE][TILE] ;
logic [DTYPEOUT-1:0] expected_c [TILE][TILE] ;

logic [DTYPEIN-1:0]  load_A [TILE*TILE];
logic [DTYPEIN-1:0]  load_B [TILE*TILE];
logic [DTYPEOUT-1:0] load_C [TILE*TILE];

logic [DTYPEIN-1:0] small_a [TILE] ;
logic [DTYPEIN-1:0] small_b [TILE] ;
logic [DTYPEOUT-1:0] small_c [TILE][TILE] ;
logic [DTYPEOUT-1:0] expected_small_c [TILE][TILE] ;

logic [DTYPEOUT-1:0] load_expected_small_c [TILE*TILE];

grid_mac mac_dut(
    .clk(clk),
    .rst_n(rst_n),
    .valid_in(valid_in),
    .A(small_a),
    .B(small_b),
    .C_out(small_c),
    .valid_out(valid_out)
);

Gemm gemm_dut (
    .clk(clk),
    .rst_n(rst_n),
    .start(start),
    .locala(locala),
    .localb(localb),
    .localc(localc),
    .busy(busy),
    .done(done)
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

task automatic small_matrix_test() ;
    reset() ;
    valid_in <= 1'b1 ;
    $readmemh("small_a.hex", small_a) ;
    $readmemh("small_b.hex", small_b) ;
    $readmemh("small_c.hex", load_expected_small_c) ;

    for(int i=0 ; i<TILE ; i++) begin
        for(int j=0 ; j<TILE ; j++) begin
            expected_small_c[i][j] = load_expected_small_c[i*TILE + j] ;
        end
    end

    clock(1) ; valid_in <= 1'b0 ;
    clock(5) ;

    check_32x32: assert (small_c == expected_small_c)
        $display("SUCCESS") ;
    else $error("Multiplication error!");
endtask

task automatic Gemm_test() ;
    $readmemh("matrix_A.hex", load_A) ;
    $readmemh("matrix_B.hex", load_B) ;
    $readmemh("matrix_C.hex", load_C) ;

    for(int i=0 ; i<TILE ; i++) begin
        for(int j=0 ; j<TILE ; j++) begin
            locala[i][j] = load_A[i*TILE + j] ;
            localb[i][j] = load_B[i*TILE + j] ;
            expected_c[i][j] = load_C[i*TILE + j] ;
        end
    end

    reset() ;
    start <= 1'b1 ; clock(1) ; start <= 1'b0 ;
    clock(40) ;

    check_32x32: assert (localc == expected_c)
        $display("SUCCESS") ;
    else $error("Multiplication error!");

    $display("Clock cycles: %d", gemm_dut.cycles_counter) ;
endtask

initial begin
    small_matrix_test() ;
    Gemm_test() ;

    $finish ;
end

endmodule
