import mul_accel_pkg::* ;

module Accumulate_control (
    input clk, rst_n,
    input  logic wb_start,
    input  logic new_dotproduct,
    input  logic [DTYPEOUT-1:0] new_localc [TILE][TILE],
    output logic [DTYPEOUT-1:0] acc_localc [TILE][TILE],
    output logic wb_ready
);

logic [DTYPEOUT-1:0] row_nlc [TILE] ;
logic [DTYPEOUT-1:0] row_alc [TILE] ;
logic [$clog2(TILE)-1:0] k ;
logic [$clog2(TILE)-1:0] row_index ;
logic running ;
always_ff @(posedge clk, negedge rst_n)
    begin
        if(!rst_n)
        begin
            row_nlc <= '{default: '0} ;
            row_alc <= '{default: '0} ;
            k <= 'b0 ;
            running <= 'b0 ;
        end
        else
        begin
            if(wb_start) begin
                k <= 'b1 ;
                running <= 1'b1 ;
                for(int i=0 ; i<TILE ; i++) begin
                    row_nlc[i] <= new_localc[0][i] ;
                    row_alc[i] <= acc_localc[0][i] ;
                end
                row_index <= 'b0 ;
            end
            else if(running) begin
                if(k == TILE - 1) begin
                    k <= 'b0 ;
                    running <= 1'b0 ;
                end
                else begin
                    k <= k+1 ;
                end
                for(int i=0 ; i<TILE ; i++) begin
                    row_nlc[i] <= new_localc[k][i] ;
                    row_alc[i] <= acc_localc[k][i] ;
                end
                row_index <= k ;
            end
        end
    end

    genvar i ;
    logic [DTYPEOUT-1:0] plus_value [TILE] ;
    generate;
        for(i=0 ; i<TILE ; i++) begin : g_accumulate_adder
            assign plus_value[i] = row_nlc[i] + row_alc[i] ;
        end
    endgenerate

    always_ff @(posedge clk) begin
        for(int i=0 ; i<TILE ; i++) begin
            acc_localc[row_index][i] <= (new_dotproduct)? row_nlc[i] : plus_value[i] ;
        end
    end

    assign wb_ready = !running ;
endmodule
