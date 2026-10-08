import mul_accel_pkg::* ;

module grid_mac(
    input  logic signed [DTYPEIN -1:0] A [TILE],
    input  logic signed [DTYPEIN -1:0] B [TILE],
    input  logic signed [DTYPEOUT-1:0] C_in [TILE][TILE],
    output logic signed [DTYPEOUT-1:0] C_out [TILE][TILE]
);
    logic signed [DTYPEOUT-1:0] mul_val [TILE][TILE] ;
    genvar j, k ;
    // generate
    //     for(j=0 ; j<TILE ; j++)
    //     begin : g_loop_row_A // -> locala[j][i]
    //         for(k=0 ; k<TILE ; k=k+2)
    //         begin : g_loop_col_b // -> localb[i][k]
    //             logic [DTYPEOUT-1:0] dsp_out ;
    //             always_comb
    //             begin
    //                 dsp_out = A[j] * {'b0, B[k+1], 8'b0, B[k]} ;
    //                 mul_val[j][k] = dsp_out[15:0] ;
    //                 mul_val[j][k+1] = dsp_out[31:16] ;
    //                 C_out[j][k] = C_in[j][k] + mul_val[j][k] ;
    //                 C_out[j][k+1] = C_in[j][k+1] + mul_val[j][k+1] ;
    //             end
    //         end
    //     end
    // endgenerate

    generate
        for(j=0 ; j<TILE ; j++)
        begin : g_loop_row_A
            for(k=0 ; k<TILE ; k++)
            begin : g_loop_col_b
                always_comb
                begin
                    mul_val[j][k] = DTYPEOUT'(A[j]) * DTYPEOUT'(B[k]) ;
                    C_out[j][k]   = C_in[j][k] + mul_val[j][k] ;
                end
            end
        end
    endgenerate
endmodule

module Gemm(
    input  logic clk, rst_n,
    input  logic start,
    input  logic signed [DTYPEIN -1:0] locala [TILE][TILE],
    input  logic signed [DTYPEIN -1:0] localb [TILE][TILE],
    output logic signed [DTYPEOUT-1:0] localc[TILE][TILE],
    output logic busy,
    output logic done
);
    logic signed [DTYPEOUT-1:0] prev_c [TILE][TILE] ;
    logic signed [DTYPEOUT-1:0] cur_c [TILE][TILE] ;
    logic signed [DTYPEIN-1:0] A [TILE] ;
    logic signed [DTYPEIN-1:0] B [TILE] ;
    logic running ;
    logic [$clog2(TILE)-1:0] k ;

    // cycles counter use for testbench
    logic [$clog2(TILE):0] cycles_counter ;
    always_ff @(posedge clk) begin
        if(!rst_n) cycles_counter <= 'b0 ;
        else if(start) cycles_counter <= 'b1 ;
        else if(running) cycles_counter <= cycles_counter + 1 ;
    end

    always_ff @(posedge clk, negedge rst_n)
    begin
        if(!rst_n)
        begin
            A <= '{default: '0} ;
            B <= '{default: '0} ;
            prev_c <= '{default: '0} ;
            running <= 1'b0 ;
            k <= 0 ;
            done <= 1'b0 ;
        end
        else
        begin
            if(start) begin
                k <= 'b0 ;
                running <= 1'b1 ;
                done <= 1'b0 ;
                for(int i=0 ; i<TILE ; i++) begin
                    A[i] <= locala[i][0] ;
                    B[i] <= localb[0][i] ;
                end
                prev_c <= '{default: '0} ;
            end
            else if(running) begin
                prev_c <= cur_c ;
                if(k == TILE - 1) begin
                    k <= 'b0 ;
                    running <= 1'b0 ;
                    done <= 1'b1 ;
                end
                else begin
                    k <= k+1 ;
                    for(int i=0 ; i<TILE ; i++) begin
                        A[i] <= locala[i][k+1] ;
                        B[i] <= localb[k+1][i] ;
                    end
                end
            end
        end
    end

    grid_mac PE(
        .A(A),
        .B(B),
        .C_in(prev_c),
        .C_out(cur_c)
    );

    assign localc = prev_c ;
    assign busy = running ;
endmodule


