// reset_sync.v - reset goes on at once (async), goes off on a clk edge (sync)

`default_nettype none

module reset_sync (
    input  wire clk,
    input  wire arst_n,
    output wire rst_n
);
    (* ASYNC_REG = "TRUE" *) reg r1, r2;

    always @(posedge clk or negedge arst_n) begin
        if (!arst_n) begin
            r1 <= 1'b0;
            r2 <= 1'b0;
        end else begin
            r1 <= 1'b1;
            r2 <= r1;
        end
    end

    assign rst_n = r2;
endmodule

`default_nettype wire
