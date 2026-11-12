import mul_accel_pkg::* ;

module Load_control #(
    parameter int TILE = DEFAULT_TILE,
    parameter int N_TILE = 2,
    parameter int K_TILE = 24,
    parameter int M_TILE = 8,
    parameter int A_DEPTH = 1024,
    parameter int B_DEPTH = 1024
)(
    input  logic clk, rst_n,
    input  logic start,
    input  logic waits, // define by enable to pass data to Gemm
    input  logic done,  // define by done of whole mul accelerator
    output state_t load_state,
    // Load registers signals
    output logic [$clog2(A_DEPTH)-1:0] addra,
    output logic [$clog2(B_DEPTH)-1:0] addrb,
    output logic [$clog2(TILE)-1:0] row_index,
    output logic renable,
    // Write back signals
    output logic [$clog2(N_TILE)-1:0] cp_n_out,
    output logic [$clog2(M_TILE)-1:0] cp_m_out,
    output logic write_bram
) ;

    logic [$clog2(N_TILE)-1:0] cp_n ; // check point N
    logic [$clog2(K_TILE)-1:0] cp_k ; // check point K
    logic [$clog2(M_TILE)-1:0] cp_m ; // check point M
    logic [$clog2(TILE)-1:0] cp_tile ; // check point TILE

    logic [$clog2(N_TILE)-1:0] cp_n_cur ; // save current check point when in WAIT state
    logic [$clog2(M_TILE)-1:0] cp_m_cur ; // save current check point when in WAIT state

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
                end
                LOAD: begin
                    cp_tile <= (cp_tile == TILE-1)? 'b0 : cp_tile + 1 ;
                    if(cp_tile == TILE-1) begin
                        cp_k <= (cp_k == K_TILE-1)? 'b0 : cp_k +1 ;
                        if(cp_k == K_TILE-1) begin
                            cp_m <= (cp_m == M_TILE-1)? 'b0 : cp_m + 1 ;
                            if(cp_m == M_TILE-1) begin
                                cp_n <= (cp_n == N_TILE-1)? 'b0 : cp_n + 1 ;
                            end
                        end
                        load_state <= ((cp_n == N_TILE-1) & (cp_k == K_TILE-1) &
                                        (cp_m == M_TILE-1))? DONE : (waits)? WAIT : LOAD ;
                        cp_n_cur <= cp_n ;
                        cp_m_cur <= cp_m ;
                    end
                    write_bram <= (cp_tile == TILE-1) & (cp_k == K_TILE-1) ;
                end
                WAIT: begin
                    load_state <= (waits)? load_state : LOAD ;
                end
                DONE: begin
                    load_state <= (done)? IDLE : load_state ;
                end
                default: ;
            endcase
        end
    end

    assign addra = K_TILE * (cp_tile + (cp_n * TILE)) + cp_k ;
    assign addrb = M_TILE * (cp_tile + (cp_k * TILE)) + cp_m ;
    assign renable = (load_state == LOAD) ;
    assign cp_n_out = cp_n_cur ;
    assign cp_m_out = cp_m_cur ;
    assign row_index = cp_tile ;
endmodule


