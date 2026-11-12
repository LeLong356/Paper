import mul_accel_pkg::* ;

module Accumulate_control #(
    parameter int TILE = DEFAULT_TILE,
    parameter int N_TILE = 2,
    parameter int M_TILE = 8,
    parameter int C_DEPTH = 1024
) (
    input clk, rst_n,
    input  logic wb_start,
    input  logic [DTYPEOUT-1:0] new_localc [TILE][TILE],
    output logic [DTYPEOUT-1:0] acc_localc [TILE][TILE],
    output logic wb_ready,
    // Ports for writeback into bram
    input  logic [$clog2(N_TILE)-1:0] cp_n,
    input  logic [$clog2(M_TILE)-1:0] cp_m,
    input  logic write_bram,
    output logic wen,
    output logic [$clog2(C_DEPTH)-1:0] addr,
    output logic [TILE*DTYPEOUT-1:0] wdata,
    output logic top_system_done
);

logic [$clog2(TILE)-1:0] k ;
logic running ;
logic pre_done ;
always_ff @(posedge clk, negedge rst_n)
    begin
        if(!rst_n)
        begin
            k <= 'b0 ;
            running <= 'b0 ;
            wen <= 1'b0 ;
            pre_done <= 1'b0 ;
        end
        else
        begin
            if(wb_start) begin
                k <= 'b0 ;
                running <= 1'b1 ;
                pre_done <= 1'b0 ;
            end
            else if(running) begin
                if(k == TILE - 1) begin
                    k <= 'b0 ;
                    running <= 1'b0 ;
                    if(write_bram && (cp_n == N_TILE-1) && (cp_m == M_TILE-1)) pre_done <= 1'b1 ;
                    else pre_done <= 1'b0 ;
                end
                else begin
                    k <= k+1 ;
                end
                wen <= write_bram ;
                addr <= ((cp_n * TILE) + k) * M_TILE + cp_m ;
            end
            else wen <= 1'b0 ;
        end
    end

    logic [DTYPEOUT-1:0] plus_value [TILE] ;
    generate;
        for(genvar i=0 ; i<TILE ; i++) begin : g_accumulate_adder
            assign plus_value[i] = new_localc[k][i] + acc_localc[k][i] ;
        end
    endgenerate

    always_ff @(posedge clk, negedge rst_n) begin
        if(!rst_n) begin
            for(int i=0 ; i<TILE ; i++) begin
                for(int j=0 ; j<TILE ; j++) acc_localc[i][j] <= 'b0 ;
            end
        end
        else begin
            for(int i=0 ; i<TILE ; i++) begin
                if(running) begin
                    acc_localc[k][i] <= (write_bram)? 'b0 : plus_value[i] ;
                    wdata[i*DTYPEOUT +: DTYPEOUT] <= plus_value[i] ;
                end
            end
        end
    end

    assign wb_ready = !running ;

    // Done signal is delayed 1 cycle by k reached TILE-1
    always_ff @(posedge clk, negedge rst_n) begin
        if(!rst_n) top_system_done <= 1'b0 ;
        else top_system_done <= pre_done ;
    end
endmodule
