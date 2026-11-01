// cdc_top.v - async FIFO + one reset synchronizer per clock
// This is the top for simulation, synthesis and STA.

`default_nettype none

module cdc_top #(
    parameter integer DW = 32,
    parameter integer AW = 4
) (
    input  wire          arst_n,
    input  wire          wclk,
    input  wire          winc,
    input  wire [DW-1:0] wdata,
    output wire          wfull,
    input  wire          rclk,
    input  wire          rinc,
    output wire [DW-1:0] rdata,
    output wire          rempty
);
    wire wrst_n, rrst_n;

    reset_sync u_wrst (.clk(wclk), .arst_n(arst_n), .rst_n(wrst_n));
    reset_sync u_rrst (.clk(rclk), .arst_n(arst_n), .rst_n(rrst_n));

    async_fifo #(.DW(DW), .AW(AW)) u_fifo (
        .wclk(wclk), .wrst_n(wrst_n), .winc(winc), .wdata(wdata), .wfull(wfull),
        .rclk(rclk), .rrst_n(rrst_n), .rinc(rinc), .rdata(rdata), .rempty(rempty)
    );
endmodule

`default_nettype wire
