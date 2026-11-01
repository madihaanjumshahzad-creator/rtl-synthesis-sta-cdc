// sync_2ff.v - 2 flop synchronizer (1 bit or a Gray coded bus)
// meta can go metastable, it gets one clock period to settle before sync.

`default_nettype none

module sync_2ff #(
    parameter integer W = 1
) (
    input  wire         clk,
    input  wire         rst_n,
    input  wire [W-1:0] d,
    output wire [W-1:0] q
);
    (* ASYNC_REG = "TRUE" *) reg [W-1:0] meta, sync;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            meta <= {W{1'b0}};
            sync <= {W{1'b0}};
        end else begin
            meta <= d;
            sync <= meta;
        end
    end

    assign q = sync;
endmodule

`default_nettype wire
