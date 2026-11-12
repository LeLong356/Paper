package mul_accel_pkg;
    localparam int DTYPEIN = 8;
    localparam int DTYPEOUT = 32;

    localparam int DEFAULT_TILE = 32 ;
    localparam int DEFAULT_N = 64;
    localparam int DEFAULT_K = 768;
    localparam int DEFAULT_M = 256;

    // FSM for load control
    typedef enum logic[3:0] {
        IDLE = 4'b0001,
        LOAD = 4'b0010,
        WAIT = 4'b0100,
        DONE = 4'b1000
    } state_t;

    // FSM for new dot product signal
    typedef enum logic[2:0] {
        OFF = 3'b001,
        PRE = 3'b010,
        ACTIVE = 3'b100
    } fsm_t;
endpackage
