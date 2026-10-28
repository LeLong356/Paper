module bram_pp #(
    parameter DATA_WIDTH = 256,
    parameter DEPTH      = 6144,
    parameter ADDR_WIDTH = $clog2(DEPTH)
) (
    input  logic          clk, rst_n,
    // DMA side
    input  logic          we,
    input  logic [AW-1:0] waddr,
    input  logic [DW-1:0] din,
    input  logic          wr_done,   // DMA ghi đủ 6144 từ -> pulse 1 cycle
    output logic          wr_ready,  // bank ghi đang rảnh
    // core side
    input  logic          re,
    input  logic [AW-1:0] raddr,
    output logic [DW-1:0] dout,
    input  logic          rd_done,   // core xong 1 phép nhân -> pulse
    output logic          rd_valid   // bank đọc đã đầy, được bắt đầu
);
    logic wr_bank, rd_bank, rd_bank_q;
    logic [1:0] full;
    logic [DATA_WIDTH - 1:0] q0,q1;

    bram #(DATA_WIDTH,DEPTH) u0 (.clk, .we(we & ~wr_bank), .waddr, .din, .re(re), .raddr, .dout(q0));
    bram #(DATA_WIDTH,DEPTH) u1 (.clk, .we(we & wr_bank), .waddr, .din, .re(re), .raddr, .dout(q1));

    always_ff @(posedge clk)
        rd_bank_q <= rd_bank;
            if(!rst_n) begin
                full <= '0; 
                wr_bank <= '0;
                rd_bank <= '0;
            end
        else begin
            if(wr_done) begin
                full[wr_bank] <= 1; 
                wr_bank <= ~wr_bank;
            end
            if(rd_done) begin
                full[rd_bank] <= 0; 
                rd_bank <= ~rd_bank;
            end
        end
    assign wr_ready = ~full[wr_bank] ;
    assign rd_valid = full[rd_bank] ;
    assign dout = rd_bank_q ? q1 : q0;
endmodule
