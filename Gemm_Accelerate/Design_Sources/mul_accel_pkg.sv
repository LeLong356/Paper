package mul_accel_pkg;
    localparam int TILE = 32;
    localparam int DTYPEIN = 8;
    localparam int DTYPEOUT = 32;

    typedef enum logic[2:0] {
        IDLE = 3'b001,
        LOAD = 3'b010,
        WAIT = 3'b100
    } state_t;

    // FSM for new dot product signal
    typedef enum logic[2:0] {
        IDLE = 3'b001,
        PRE = 3'b010,
        ACTIVE = 3'b100
    } fsm_t;
endpackage
