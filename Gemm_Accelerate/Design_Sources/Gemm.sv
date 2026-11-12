import mul_accel_pkg::* ;

module grid_mac
#(parameter int TILE = DEFAULT_TILE)(
    input  logic clk, rst_n,
    input  logic valid_in,
    input  logic signed [DTYPEIN -1:0] A [TILE],
    input  logic signed [DTYPEIN -1:0] B [TILE],
    output logic valid_out,
    output logic signed [DTYPEOUT-1:0] C_out [TILE][TILE]
);
    logic                   r1_sign [TILE] ;
    logic [DTYPEIN-1:0]     r1_abs  [TILE] ;
    logic                   r2_sign [TILE] ;
    logic [DTYPEIN-1:0]     r2_abs  [TILE] ;

    genvar j, k ;
    generate
        for (j = 0; j < TILE; j++) begin : g_row
            logic                     c_sign ;
            logic signed [DTYPEIN:0] c_ext, c_neg ;   // 9 bit: -(-128) = +128 must fit
            logic [DTYPEIN-1:0]      c_abs ;
            always_comb begin
                c_sign = A[j][DTYPEIN-1] ;
                c_ext  = {A[j][DTYPEIN-1], A[j]} ;
                c_neg  = -c_ext ;
                c_abs  = c_sign ? c_neg[DTYPEIN-1:0] : A[j] ;
            end
            always_ff @(posedge clk) begin
                r1_sign[j] <= c_sign ;
                r1_abs[j]  <= c_abs ;
                r2_sign[j] <= r1_sign[j] ;
                r2_abs[j]  <= r1_abs[j] ;
            end
        end
    endgenerate

    // bias +128 on an 8-bit two's-complement value is just an MSB flip.
    logic [2*DTYPEIN-1:0] c1_pack [TILE/2] ;   // {Bk1_b, Bk_b}; the 8'b0 guard
    logic [3*DTYPEIN-1:0] pack24 [TILE/2] ;   // {Bk1_b, 8'b0, Bk_b}
    generate
        for (k = 0; k < TILE; k = k + 2) begin : g_col
            assign c1_pack[k/2] = { ~B[k+1][DTYPEIN-1], B[k+1][DTYPEIN-2:0],
                                  ~B[k  ][DTYPEIN-1], B[k  ][DTYPEIN-2:0] } ;
            always_ff @(posedge clk) begin
                pack24[k/2] <= { c1_pack[k/2][2*DTYPEIN-1:DTYPEIN], {DTYPEIN{1'b0}},
                         c1_pack[k/2][DTYPEIN-1:0] } ;
            end
        end
    endgenerate

    // ---------------- per-slice: multiply (stage 2) and fix-up (stage 3) ----------------
    generate
        for (j = 0; j < TILE; j++) begin : g_slice_row
            for (k = 0; k < TILE; k = k + 2) begin : g_slice
                // stage 2: unsigned x unsigned packed multiply (the DSP op)
                logic [DTYPEOUT-1:0] dsp_out ;
                always_ff @(posedge clk) begin
                    dsp_out <= r1_abs[j] * pack24[k/2] ;
                end

                // stage 3: lanes -> single subtract with operand swap
                logic [2*DTYPEIN:0] lane0, lane1, corr ;
                logic signed [2*DTYPEIN:0] x0, y0, x1, y1 ; // extend 1 bit for overflow
                always_comb begin
                    lane0 = {1'b0, dsp_out[2*DTYPEIN-1:0]} ;
                    lane1 = {1'b0, dsp_out[4*DTYPEIN-1:2*DTYPEIN]} ;
                    corr  = {2'b0, r2_abs[j], 7'b0} ;          // |A| * 128
                    x0 = r2_sign[j] ? corr  : lane0 ;
                    y0 = r2_sign[j] ? lane0 : corr ;
                    x1 = r2_sign[j] ? corr  : lane1 ;
                    y1 = r2_sign[j] ? lane1 : corr ;
                end
                assign C_out[j][k]   = x0 - y0 ;
                assign C_out[j][k+1] = x1 - y1 ;
            end
        end
    endgenerate

    // valid_out: valid_in delayed by exactly 3 cycles (shared control).
    logic vo_d1 ;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            vo_d1 <= 1'b0 ; valid_out <= 1'b0 ;
        end else begin
            vo_d1 <= valid_in ; valid_out <= vo_d1 ;
        end
    end
endmodule

module Gemm
#(parameter int TILE = DEFAULT_TILE)(
    input  logic clk, rst_n,
    input  logic start,
    input  logic signed [DTYPEIN -1:0] locala [TILE][TILE],
    input  logic signed [DTYPEIN -1:0] localb [TILE][TILE],
    output logic signed [DTYPEOUT-1:0] localc[TILE][TILE],
    output logic busy,
    output logic done
);
    logic signed [DTYPEOUT-1:0] prev_c [TILE][TILE] ;
    logic signed [DTYPEOUT-1:0] prev_c_next [TILE][TILE] ;
    logic signed [DTYPEIN-1:0] A [TILE] ;
    logic signed [DTYPEIN-1:0] B [TILE] ;
    logic signed [DTYPEOUT-1:0] C_out [TILE][TILE] ;
    logic running, issuing ;
    logic mac_valid_in, mac_valid_out ;
    logic [$clog2(TILE)-1:0] k, k_acc ;

    grid_mac #(
        .TILE(TILE)
    ) PE (
        .clk(clk), .rst_n(rst_n),
        .valid_in(mac_valid_in),
        .A(A), .B(B),
        .valid_out(mac_valid_out),
        .C_out(C_out)
    );

    logic signed [DTYPEOUT-1:0] zero_c [TILE][TILE] ;
    always_comb begin
        for (int i = 0; i < TILE; i++)
            for (int j = 0; j < TILE; j++) zero_c[i][j] = '0 ;
    end

    // The only feedback loop in the whole compute path: one 32-bit add.
    always_comb begin
        for (int i = 0; i < TILE; i++)
            for (int j = 0; j < TILE; j++)
                prev_c_next[i][j] = prev_c[i][j] + C_out[i][j] ;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            k <= '0 ;
            k_acc <= '0 ;
            issuing <= 1'b0 ;
            running <= 1'b0 ;
            done <= 1'b0 ;
            mac_valid_in <= 1'b0 ;
            for (int i = 0; i < TILE; i++) begin A[i] <= '0 ; B[i] <= '0 ; end
            prev_c <= zero_c ;
        end else begin
            done         <= 1'b0 ;
            mac_valid_in <= 1'b0 ;

            if (start) begin
                k       <= 'b0 ;
                k_acc   <= 'b0 ;
                running <= 1'b1 ;
                issuing <= 1'b1 ;
                for (int i = 0; i < TILE; i++) begin
                    A[i] <= locala[i][0] ;
                    B[i] <= localb[0][i] ;
                end
                mac_valid_in <= 1'b1 ;       // issue k=0
                prev_c       <= zero_c ;     // clear once here, so the loop below is a bare add
            end
            else if (running) begin
                // issue a NEW column/row EVERY cycle until all TILE are in flight
                if (issuing) begin
                    if (k < TILE-1) begin
                        k <= k + 1'b1 ;
                        for (int i = 0; i < TILE; i++) begin
                            A[i] <= locala[i][k+1] ;
                            B[i] <= localb[k+1][i] ;
                        end
                        mac_valid_in <= 1'b1 ;
                    end else begin
                        issuing <= 1'b0 ;
                    end
                end

                // accumulate each result the cycle it lands
                if (mac_valid_out) begin
                    prev_c <= prev_c_next ;
                    k_acc  <= k_acc + 1'b1 ;
                    if (k_acc == TILE-1) begin
                        running <= 1'b0 ;
                        done    <= 1'b1 ;
                    end
                end
            end
        end
    end
    assign localc = prev_c ;
    assign busy   = running ;

    logic [5:0] cycles_counter ;
    always_ff @(posedge clk, negedge rst_n) begin
        if(!rst_n) cycles_counter <= 'b0 ;
        else if(start | running) cycles_counter <= cycles_counter + 1 ;
    end
endmodule

