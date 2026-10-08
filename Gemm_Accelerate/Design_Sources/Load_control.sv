import mul_accel_pkg::* ;

module load_control #(
    parameter int N_TILE = 2,
    parameter int K_TILE = 24,
    parameter int M_TILE = 8,
    parameter int A_DEPTH = 1024,
    parameter int B_DEPTH = 1024
)(
    input  logic clk, rst_n,
    input  logic start,
    input  logic waits, // define by busy signal of Gemm module
    output logic load_reg_tile_done,
    output state_t load_state,
    // Load registers signals
    output logic [$clog2(A_DEPTH)-1:0] addra,
    output logic [$clog2(B_DEPTH)-1:0] addrb,
    output logic [$clog2(TILE)-1:0] row_index,
    // Write back signals
    output logic cp_n_out,
    output logic cp_m_out,
    output logic write_bram
) ;

    logic [$clog2(N_TILE)-1:0] cp_n ; // check point N
    logic [$clog2(K_TILE)-1:0] cp_k ; // check point K
    logic [$clog2(M_TILE)-1:0] cp_m ; // check point M
    logic [$clog2(TILE)-1:0] cp_tile ; // check point TILE

    logic load_bram_tile_done ;
    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) begin
            cp_n <= 0 ;
            cp_k <= 0 ;
            cp_m <= 0 ;
            cp_tile <= 0 ;
            load_state <= IDLE ;
        end else begin
            unique case (load_state)
                IDLE: begin
                    cp_n <= 0 ;
                    cp_k <= 0 ;
                    cp_m <= 0 ;
                    cp_tile <= 0 ;
                    load_state <= (start)? LOAD : load_state ;
                    load_bram_tile_done <= 1'b0 ;
                end
                LOAD: begin
                    cp_tile <= (cp_tile == TILE-1)? 'b0 : cp_tile + 1 ;
                    if(cp_tile == TILE-1) begin
                        cp_k <= (cp_k == K_TILE-1)? 'b0 : cp_k +1 ;
                        if(cp_k == K_TILE-1) begin
                            cp_m <= (cp_m == M_TILE-1)? 'b0 : cp_m + 1 ;
                            if(cp_m == M_TILE-1) begin
                                cp_n <= (cp_n == N_TILE-1)? 'b0 : cp_n + 1 ;
                                if(cp_n == N_TILE-1) load_bram_tile_done <= 1'b1 ;
                            end
                        end
                        load_state <= (waits)? WAIT :
                            (cp_n == N_TILE-1 & cp_k == K_TILE-1 & cp_m == M_TILE-1)? IDLE : LOAD;
                    end
                    addra <= K_TILE * (cp_tile + (cp_n * TILE)) + cp_k ;
                    addrb <= M_TILE * (cp_tile + (cp_k * TILE)) + cp_m ;
                    row_index <= cp_tile ;
                    load_reg_tile_done <= (cp_tile == TILE-1)? 1'b1 : 1'b0 ;
                    write_bram <= (cp_tile == TILE-1) & (cp_k == K_TILE-1) ;
                    cp_n_out <= cp_n ;
                    cp_m_out <= cp_m ;
                end
                WAIT: begin
                    // Wait logic here
                    load_state <= (waits)? load_state : (load_bram_tile_done)? IDLE : LOAD ;
                end
                default: ;
            endcase
        end
    end
endmodule


