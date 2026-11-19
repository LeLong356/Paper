interface axi4_lite_if #(
    parameter int ADDR_WIDTH = 32
)(
    input logic aclk,
    input logic arst_n
);
    // AW: write address
    logic [ADDR_WIDTH - 1: 0] awaddr;
    logic [2:0]               awprot;
    logic                     awvalid;
    logic                     awready;
    // W: write data
    logic [31:0]              wdata;
    logic [3:0]               wstrb;
    logic                     wvalid;
    logic                     wready;
    // B: write response
    logic                     bready;
    logic                     bvalid;
    logic [1:0]               bresp;
    // AR: read address
    logic [ADDR_WIDTH - 1: 0] araddr;
    logic [2:0]               arprot;
    logic                     arvalid;
    logic                     arready;
    // R: read data
    logic                     rready;
    logic                     rvalid;
    logic [31:0]              rdata;
    logic [1:0]               rresp; 
    modport axi4_lite_master (
    input awready, wready, bvalid, bresp, arready, rvalid, rdata, rresp, aclk, arst_n,
    output awaddr, awprot, awvalid, wdata, wstrb, wvalid, bready, araddr, arprot, arvalid, rready
    );
    modport axi4_lite_slave (
    input awaddr, awprot, awvalid, wdata, wstrb, wvalid, bready, araddr, arprot, arvalid, rready, aclk, arst_n,
    output awready, wready, bvalid, bresp, arready, rvalid, rdata, rresp
    );
endinterface