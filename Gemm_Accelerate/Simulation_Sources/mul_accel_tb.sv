`timescale 1ns/1ps

module mul_accel_tb() ;
localparam int TILE = 16 ;
localparam int N = 32 ;
localparam int K = 64 ;
localparam int M = 48 ;
localparam int DTYPEIN = 8 ;
localparam int DTYPEOUT = 32 ;

logic clk, rst_n ;
logic start ;
logic done ;
logic a_wenable ;
logic [$clog2(N*(K/TILE))-1:0] a_wr_addr ;
logic [TILE*DTYPEIN-1:0] a_wdata ;
logic b_wenable ;
logic [$clog2(K*(M/TILE))-1:0] b_wr_addr ;
logic [TILE*DTYPEIN-1:0] b_wdata ;
logic c_renable ;
logic [$clog2(N*(M/TILE))-1:0] c_rd_addr ;
logic [TILE*DTYPEOUT-1:0] c_rdata ;

mul_accel #(.TILE(TILE),.N(N), .K(K), .M(M)) dut (.*);

logic [$clog2(N*(M/TILE))-1:0] address ;
logic wenable ;
logic renable ;
logic [TILE*DTYPEIN-1:0] data_in ;
logic [TILE*DTYPEOUT-1:0] data_out ;
BRAM #(.DEPTH(N*(M/TILE)), .DWIDTH(TILE*DTYPEOUT)) expected_c (.*);

task automatic clock(input int num) ;
    repeat(num) begin
        clk = 1'b0 ; #2 ;
        clk = 1'b1 ; #2 ;
    end
endtask
task automatic reset() ;
    rst_n = 1'b0 ; clock(2) ;
    rst_n = 1'b1 ; clock(1) ;
endtask

int error_count = 0 ;
task automatic small_test() ;
    // 1. Declare temporary unpacked arrays sized for individual elements
    logic [DTYPEIN-1:0]  raw_a [N*K];
    logic [DTYPEIN-1:0]  raw_b [K*M];
    logic [DTYPEOUT-1:0] raw_c [N*M];

    // 2. Load the 1-element-per-line hex files into the temporary arrays
    $readmemh("small_bram_a.hex", raw_a);
    $readmemh("small_bram_b.hex", raw_b);
    $readmemh("small_bram_c.hex", raw_c);

    for(int i=0 ; i < N*(K/TILE) ; i++) begin
        for(int j=0 ; j < TILE ; j++) begin
            dut.A_bram.mem[i][j*DTYPEIN +: DTYPEIN] = raw_a[i*TILE+j];
        end
    end
    for(int i=0 ; i < K*(M/TILE) ; i++) begin
        for(int j=0 ; j < TILE ; j++) begin
            dut.B_bram.mem[i][j*DTYPEIN +: DTYPEIN] = raw_b[i*TILE+j];
        end
    end
    for(int i=0 ; i < N*(M/TILE) ; i++) begin
        for(int j=0 ; j < TILE ; j++) begin
            expected_c.mem[i][j*DTYPEOUT +: DTYPEOUT] = raw_c[i*TILE+j];
        end
    end

    start = 1'b0 ;
    reset() ;
    start = 1'b1 ; clock(1); start = 1'b0 ;

    fork
        begin : wait_until_done
            while(!done) clock(1) ;
            $display("[%0t] INFO: Accelerator asserted done!", $time) ;
        end
        begin : Timeout
            // gemm consume (TILE+4) cycles.
            // We need N_TILE*K_TILE*M_TILE gemm operations
            // -> 20*2*3*4 = 480 cycles
            clock(600) ;
            $display("[%0t] ERROR: Timeout waiting for done signal!", $time) ;
            $finish ;
        end
    join_any
    disable fork ; // Need to delete the timeout threads when done is asserted

    clock(1);

    // Compare dut.C_bram.mem against expected_c.mem
    for (int addr = 0; addr < (N*(M/TILE)); addr++) begin
        if (dut.C_bram.mem[addr] !== expected_c.mem[addr]) begin
            $display("------------------------------------------------------------");
            $display("[MISMATCH] C_bram row address %0d:", addr);
            error_count++;
        end
    end

    if (error_count == 0) begin
        $display("============================================================");
        $display("[PASS] All %0d rows in C_bram match expected_c.mem!", N*(M/TILE));
        $display("============================================================");
    end else begin
        $display("============================================================");
        $display("[FAIL] Found %0d mismatched rows out of %0d in C_bram.", error_count,N*(M/TILE));
        $display("============================================================");
    end
    $finish ;
endtask

//task automatic run_test();
//    logic [DTYPEOUT-1:0] expected_c [TILE][TILE] ;
//    $readmemh("bram_a.hex", dut.A_bram.mem) ;
//    $readmemh("bram_b.hex", dut.B_bram.mem) ;
//endtask

initial begin
    small_test() ;
end
endmodule
