// async_fifo.v - FIFO between two unrelated clocks (wclk, rclk)
// Based on Cummings, SNUG 2002. Binary pointers address the memory and Gray
// copies of them cross to the other clock through 2-flop synchronizers.
// wfull is made in the wclk domain and rempty in the rclk domain. They can
// stay set a few cycles too long, but the FIFO never overflows or underflows.

`default_nettype none

module async_fifo #(
    parameter integer DW = 32,
    parameter integer AW = 4     // depth = 2**AW
) (
    input  wire          wclk,
    input  wire          wrst_n,
    input  wire          winc,
    input  wire [DW-1:0] wdata,
    output reg           wfull,
    input  wire          rclk,
    input  wire          rrst_n,
    input  wire          rinc,
    output wire [DW-1:0] rdata,
    output reg           rempty
);
    localparam integer DEPTH = 1 << AW;

    reg [DW-1:0] mem [0:DEPTH-1];

    // one extra bit to tell full from empty
    reg  [AW:0] wbin, wgray;
    reg  [AW:0] rbin, rgray;
    wire [AW:0] rgray_w;   // rgray after sync to wclk
    wire [AW:0] wgray_r;   // wgray after sync to rclk

    // write side (wclk)
    wire [AW:0] wbin_next  = wbin + {{AW{1'b0}}, (winc & ~wfull)};
    wire [AW:0] wgray_next = (wbin_next >> 1) ^ wbin_next;

    always @(posedge wclk) begin
        if (winc && !wfull)
            mem[wbin[AW-1:0]] <= wdata;
    end

    always @(posedge wclk or negedge wrst_n) begin
        if (!wrst_n) begin
            wbin  <= {(AW+1){1'b0}};
            wgray <= {(AW+1){1'b0}};
            wfull <= 1'b0;
        end else begin
            wbin  <= wbin_next;
            wgray <= wgray_next;
            // full when write ptr is one lap ahead: top 2 bits inverted
            wfull <= (wgray_next == {~rgray_w[AW:AW-1], rgray_w[AW-2:0]});
        end
    end

    sync_2ff #(.W(AW+1)) u_sync_r2w (
        .clk(wclk), .rst_n(wrst_n), .d(rgray), .q(rgray_w)
    );

    // read side (rclk)
    wire [AW:0] rbin_next  = rbin + {{AW{1'b0}}, (rinc & ~rempty)};
    wire [AW:0] rgray_next = (rbin_next >> 1) ^ rbin_next;

    assign rdata = mem[rbin[AW-1:0]];

    always @(posedge rclk or negedge rrst_n) begin
        if (!rrst_n) begin
            rbin   <= {(AW+1){1'b0}};
            rgray  <= {(AW+1){1'b0}};
            rempty <= 1'b1;
        end else begin
            rbin   <= rbin_next;
            rgray  <= rgray_next;
            rempty <= (rgray_next == wgray_r);
        end
    end

    sync_2ff #(.W(AW+1)) u_sync_w2r (
        .clk(rclk), .rst_n(rrst_n), .d(wgray), .q(wgray_r)
    );
endmodule

`default_nettype wire
