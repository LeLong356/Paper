module bram #(
    parameter DATA_WIDTH = 256,
    parameter DEPTH      = 6144,
    parameter ADDR_WIDTH = $clog2(DEPTH)
) (
    input  logic                    clk,
    // write port
    input  logic                    we,
    input  logic [ADDR_WIDTH-1:0]   waddr,
    input  logic [DATA_WIDTH-1:0]   din,
    // read port
    input  logic                    re,
    input  logic [ADDR_WIDTH-1:0]   raddr,
    output logic [DATA_WIDTH-1:0]   dout
);
    logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    always_ff @(posedge clk) begin
        if (we) mem[waddr] <= din;
        if (re) dout <= mem[raddr];
    end
endmodule