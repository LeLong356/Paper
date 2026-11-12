`timescale 1ns/1ps

module mul_accel_tb() ;
localparam int DTYPEIN = 8 ;
localparam int DTYPEOUT = 32 ;

// Custom parameters for test
localparam int TILE = 16 ;
localparam int N = 32 ;
localparam int K = 64 ;
localparam int M = 48 ;
localparam int C_ROWS_SMALL = N * (M / TILE);

// Default matrix sizes for test
localparam int DTILE = 32 ;
localparam int DN = 64 ;
localparam int DK = 768 ;
localparam int DM = 256 ;
localparam int C_ROWS_DEF = DN * (DM / DTILE); // 64 * 8 = 512 rows

// Shared clock and reset
logic clk, rst_n;

// Control & status signals for each DUT
logic start_small, done_small;
logic start_def,   done_def;

// -------------------------------------------------------------------------
// DUT 1: Small Matrix Instance (N=32, K=64, M=48, TILE=16)
// -------------------------------------------------------------------------
mul_accel #(
    .TILE(TILE),
    .N(N),
    .K(K),
    .M(M)
) dut_small (
    .clk       (clk),
    .rst_n     (rst_n),
    .start     (start_small),
    .done      (done_small),
    .a_wenable (1'b0),
    .a_wr_addr ('0),
    .a_wdata   ('0),
    .b_wenable (1'b0),
    .b_wr_addr ('0),
    .b_wdata   ('0),
    .c_renable (1'b0),
    .c_rd_addr ('0),
    .c_rdata   ()
);

BRAM #(
    .DEPTH (C_ROWS_SMALL),
    .DWIDTH(TILE * DTYPEOUT)
) expected_c_small (
    .clk     (clk),
    .address ('0),
    .wenable (1'b0),
    .renable (1'b0),
    .data_in ('0),
    .data_out()
);

// -------------------------------------------------------------------------
// DUT 2: Default Matrix Instance (DN=64, DK=768, DM=256, DTILE=32)
// -------------------------------------------------------------------------
mul_accel #(
    .TILE(DTILE),
    .N(DN),
    .K(DK),
    .M(DM)
) dut_default (
    .clk       (clk),
    .rst_n     (rst_n),
    .start     (start_def),
    .done      (done_def),
    .a_wenable (1'b0),
    .a_wr_addr ('0),
    .a_wdata   ('0),
    .b_wenable (1'b0),
    .b_wr_addr ('0),
    .b_wdata   ('0),
    .c_renable (1'b0),
    .c_rd_addr ('0),
    .c_rdata   ()
);

BRAM #(
    .DEPTH (C_ROWS_DEF),
    .DWIDTH(DTILE * DTYPEOUT)
) expected_c_default (
    .clk     (clk),
    .address ('0),
    .wenable (1'b0),
    .renable (1'b0),
    .data_in ('0),
    .data_out()
);

// -------------------------------------------------------------------------
// Helper Tasks
// -------------------------------------------------------------------------
task automatic clock(input int num);
    repeat(num) begin
        clk = 1'b0; #2;
        clk = 1'b1; #2;
    end
endtask

task automatic reset();
    rst_n       = 1'b0;
    start_small = 1'b0;
    start_def   = 1'b0;
    clock(2);
    rst_n       = 1'b1;
    clock(1);
endtask
// -------------------------------------------------------------------------
// Test 1: Small Matrix Test (dut_small)
// -------------------------------------------------------------------------
int error_count1 = 0;
int cycle_count1 = 0;
task automatic small_test();
    logic [DTYPEIN-1:0]  raw_a [N*K];
    logic [DTYPEIN-1:0]  raw_b [K*M];
    logic [DTYPEOUT-1:0] raw_c [N*M];

    $readmemh("small_bram_a.hex", raw_a);
    $readmemh("small_bram_b.hex", raw_b);
    $readmemh("small_bram_c.hex", raw_c);

    for (int i = 0; i < N*(K/TILE); i++) begin
        for (int j = 0; j < TILE; j++) begin
            dut_small.A_bram.mem[i][j*DTYPEIN +: DTYPEIN] = raw_a[i*TILE + j];
        end
    end
    for (int i = 0; i < K*(M/TILE); i++) begin
        for (int j = 0; j < TILE; j++) begin
            dut_small.B_bram.mem[i][j*DTYPEIN +: DTYPEIN] = raw_b[i*TILE + j];
        end
    end
    for (int i = 0; i < C_ROWS_SMALL; i++) begin
        for (int j = 0; j < TILE; j++) begin
            expected_c_small.mem[i][j*DTYPEOUT +: DTYPEOUT] = raw_c[i*TILE + j];
        end
    end

    reset();
    start_small = 1'b1;
    clock(1);
    start_small = 1'b0;

    fork
        begin : wait_until_done_small
            while (done_small !== 1'b1) begin
                clock(1);
                cycle_count1 = cycle_count1 + 1;
            end
            $display("INFO: dut_small asserted done!");
        end
        begin : timeout_small
            // 2 * 4 * 3 = 24 tiles * ~19 cycles = ~456 cycles + writeback
            clock(1500);
            $display("ERROR: Timeout waiting for done_small!");
            $finish;
        end
    join_any
    disable fork;

    clock(1);

    for (int addr = 0; addr < C_ROWS_SMALL; addr++) begin
        if (dut_small.C_bram.mem[addr] !== expected_c_small.mem[addr]) begin
            error_count1++;
        end
    end
endtask

// -------------------------------------------------------------------------
// Test 2: Default Matrix Test (dut_default)
// -------------------------------------------------------------------------
int error_count2 = 0;
int cycle_count2 = 0;
task automatic default_size_test();
    logic [DTYPEIN-1:0]  raw_a [DN*DK];
    logic [DTYPEIN-1:0]  raw_b [DK*DM];
    logic [DTYPEOUT-1:0] raw_c [DN*DM];

    $readmemh("bram_a.hex", raw_a);
    $readmemh("bram_b.hex", raw_b);
    $readmemh("bram_c.hex", raw_c);

    for (int i = 0; i < DN*(DK/DTILE); i++) begin
        for (int j = 0; j < DTILE; j++) begin
            dut_default.A_bram.mem[i][j*DTYPEIN +: DTYPEIN] = raw_a[i*DTILE + j];
        end
    end
    for (int i = 0; i < DK*(DM/DTILE); i++) begin
        for (int j = 0; j < DTILE; j++) begin
            dut_default.B_bram.mem[i][j*DTYPEIN +: DTYPEIN] = raw_b[i*DTILE + j];
        end
    end
    for (int i = 0; i < C_ROWS_DEF; i++) begin
        for (int j = 0; j < DTILE; j++) begin
            expected_c_default.mem[i][j*DTYPEOUT +: DTYPEOUT] = raw_c[i*DTILE + j];
        end
    end

    reset();
    start_def = 1'b1;
    clock(1);
    start_def = 1'b0;

    fork
        begin : wait_until_done_def
            while (done_def !== 1'b1) begin
                clock(1);
                cycle_count2 = cycle_count2 + 1;
            end
            $display("INFO: dut_default asserted done!");
        end
        begin : timeout_def
            // 2 * 24 * 8 = 384 tiles * ~35 cycles = ~13,440 cycles + writeback
            clock(15000);
            $display("ERROR: Timeout waiting for done_def!");
            $finish;
        end
    join_any
    disable fork;

    clock(1);

    for (int addr = 0; addr < C_ROWS_DEF; addr++) begin
        if (dut_default.C_bram.mem[addr] !== expected_c_default.mem[addr]) begin
            error_count2++;
        end
    end
endtask

initial begin
    $display("\n============================================================");
    $display("STARTING TEST 1: SMALL MATRIX TEST");
    $display("  -> Matrix Dimensions    : A(%0dx%0d) * B(%0dx%0d) = C(%0dx%0d)", N, K, K, M, N, M);
    $display("  -> Hardware Tile Size   : %0dx%0d (%0d parallel MACs)", TILE, TILE, TILE*TILE);
    $display("  -> Total Tile Operations: %0d (N_tile=%0d, K_tile=%0d, M_tile=%0d)",
            (N/TILE)*(K/TILE)*(M/TILE), N/TILE, K/TILE, M/TILE);
    $display("  -> Loading hex files : small_bram_a.hex, small_bram_b.hex, small_bram_c.hex");
    $display("============================================================");
    small_test();

    $display("\n============================================================");
    $display("STARTING TEST 2: DEFAULT MATRIX TEST");
    $display("  -> Matrix Dimensions    : A(%0dx%0d) * B(%0dx%0d) = C(%0dx%0d)",
                                            DN, DK, DK, DM, DN, DM);
    $display("  -> Hardware Tile Size   : %0dx%0d (%0d parallel MACs)", DTILE, DTILE, DTILE*DTILE);
    $display("  -> Total Tile Operations: %0d (N_tile=%0d, K_tile=%0d, M_tile=%0d)",
             (DN/DTILE)*(DK/DTILE)*(DM/DTILE), DN/DTILE, DK/DTILE, DM/DTILE);
    $display("  -> Loading hex files : bram_a.hex, bram_b.hex, bram_c.hex");
    $display("============================================================");
    default_size_test();

    $display("\n************************************************************");
    $display("*                   FINAL TEST SUMMARY                     *");
    $display("*  Test 1 (Small   %2dx%2dx%2d)   :   %s (Errors: %0d)    :   Total Cycles: %0d",
             N, K, M, (error_count1 == 0) ? "PASSED" : "FAILED", error_count1, cycle_count1);
    $display("*  Test 2 (Default %2dx%3dx%3d)   :   %s (Errors: %0d)    :   Total Cycles: %0d",
             DN, DK, DM, (error_count2 == 0) ? "PASSED" : "FAILED", error_count2, cycle_count2);
    $display("************************************************************\n");
    $finish;
end

endmodule
