module axi4_lite_master #(
    parameter int ADDR_WIDTH = 32
)(
    axi4_lite_if.axi4_lite_master bus,
    input logic        write_req,
    input logic [ADDR_WIDTH - 1 : 0] write_addr,
    input logic [31:0] write_data,
    input logic [3:0]  write_strb,
    output logic       write_done,
    output logic [1:0] write_resp
);
    typedef enum logic [1:0] { 
        IDLE,
        SETUP,
        WAIT,
        OK
    } state_t;
    state_t state, next_state;
    always_ff @(posedge bus.aclk or negedge bus.arst_n) begin
        if (!bus.arst_n) begin
            bus.awaddr  <= '0;
            bus.awprot  <= 3'b010;
            bus.awvalid <= 1'b0;
            bus.wdata   <= '0;
            bus.wstrb   <= '0;
            bus.wvalid  <= 1'b0;
            bus.bready  <= 1'b0;
            bus.araddr  <= '0;
            bus.arprot  <= 3'b010;
            bus.arvalid <= 1'b0;
            bus.rready  <= 1'b0;
            write_done  <= 1'b0;
            write_resp  <= '0;
            state       <= IDLE;
        end
        else begin
            state <= next_state;
            write_done <= 1'b0;
            case (state)
                IDLE: begin
                    if (write_req) begin
                        bus.awaddr <= write_addr;
                        bus.wdata  <= write_data;
                        bus.wstrb  <= write_strb;
                    end
                end
                SETUP: begin
                    bus.awvalid <= 1'b1;
                    bus.wvalid  <= 1'b1;
                end
                WAIT: begin
                    if (bus.awvalid && bus.awready)
                        bus.awvalid <= 1'b0;
                    if (bus.wvalid && bus.wready)
                        bus.wvalid <= 1'b0;
                end
                OK: begin
                    bus.bready <= 1'b1;
                    if (bus.bvalid && bus.bready) begin
                        bus.bready <= 1'b0;
                        write_resp <= bus.bresp;
                        write_done <= 1'b1;
                    end
                end
            endcase
        end
    end

    always_comb begin
        next_state = state;
        case (state)
            IDLE:  if (write_req) next_state = SETUP;
            SETUP: next_state = WAIT;
            WAIT:  if (!bus.awvalid && !bus.wvalid) next_state = OK;
            OK:    if (bus.bvalid && bus.bready) next_state = IDLE;
        endcase
    end
endmodule
