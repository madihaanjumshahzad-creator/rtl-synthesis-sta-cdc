// mac_accel.v
// Near-memory int8 dot-product (multiply-accumulate) accelerator.
//
// The accelerator owns a small scratchpad memory. The CPU writes int8
// vectors into the scratchpad, programs the registers and starts the engine.
// The engine reads the operands from its own memory, so the data does not
// go over the CPU bus during the computation.
//
// Bus: PicoRV32 native memory interface (valid/ready handshake).
// Address map, relative to the accelerator base address:
//   0x0_0000  CTRL    W   bit0 = start (self-clearing)
//   0x0_0004  STATUS  R   bit0 = busy, bit1 = done, bit2 = error (misaligned)
//   0x0_0008  LEN     RW  number of int8 elements (0 .. 4*SPAD_WORDS)
//   0x0_000C  A_OFF   RW  byte offset of vector A in the scratchpad (word aligned)
//   0x0_0010  B_OFF   RW  byte offset of vector B in the scratchpad (word aligned)
//   0x0_0014  RESULT  R   signed 32-bit dot product
//   0x0_0018  CYCLES  R   engine cycles used by the last run
//   0x1_0000  scratchpad, SPAD_WORDS x 32 bit, 4 int8 values per word
//             (element i is in byte i%4 of word i/4, little endian)
//
// The engine processes 4 int8 lanes per clock cycle (one scratchpad word of
// A and one of B), pipelined, so a run of LEN elements takes about
// LEN/4 + 2 engine cycles.

`default_nettype none

module mac_accel #(
    parameter integer SPAD_WORDS = 1024   // 4 KiB scratchpad
) (
    input  wire        clk,
    input  wire        resetn,

    input  wire        bus_valid,
    output reg         bus_ready,
    /* verilator lint_off UNUSEDSIGNAL */
    input  wire [31:0] bus_addr,      // already decoded: only the low 17 bits are used
    /* verilator lint_on UNUSEDSIGNAL */
    input  wire [31:0] bus_wdata,
    input  wire [ 3:0] bus_wstrb,
    output reg  [31:0] bus_rdata
);
    localparam integer AW = $clog2(SPAD_WORDS);

    // ------------------------------------------------------------------
    // Registers
    // ------------------------------------------------------------------
    reg [31:0] len_r, a_off_r, b_off_r;
    reg [31:0] result_r, cycles_r;
    reg        busy, done, error;

    wire is_spad  = bus_addr[16];
    wire [4:0] reg_sel = bus_addr[6:2];
    wire [AW-1:0] cpu_word = bus_addr[AW+1:2];

    wire bus_write = bus_valid && !bus_ready && |bus_wstrb;
    wire bus_read  = bus_valid && !bus_ready && !(|bus_wstrb);

    wire start_req = bus_write && !is_spad && reg_sel == 5'd0 && bus_wdata[0] && !busy;

    // ------------------------------------------------------------------
    // Scratchpad: one CPU read/write port, two engine read ports.
    // Synchronous reads, so it maps onto FPGA block RAM (two copies).
    // ------------------------------------------------------------------
    reg [31:0] spad [0:SPAD_WORDS-1];
    reg [31:0] spad_rd_cpu, spad_rd_a, spad_rd_b;

    reg [AW-1:0] eng_a_addr, eng_b_addr;

    integer k;
    always @(posedge clk) begin
        if (bus_write && is_spad && !busy) begin
            for (k = 0; k < 4; k = k + 1)
                if (bus_wstrb[k]) spad[cpu_word][8*k +: 8] <= bus_wdata[8*k +: 8];
        end
        spad_rd_cpu <= spad[cpu_word];
        spad_rd_a   <= spad[eng_a_addr];
        spad_rd_b   <= spad[eng_b_addr];
    end

    // ------------------------------------------------------------------
    // Engine (2-stage pipeline)
    // Issue:      put the next word addresses on the scratchpad read ports
    // Accumulate: one cycle later the words arrive (data_v); 4 multiplies
    //             and an adder tree go into the 32-bit accumulator
    // ------------------------------------------------------------------
    reg [31:0] words_left;      // words still to issue
    reg [31:0] elems_left;      // elements still to accumulate (tail masking)
    reg        data_v;          // spad_rd_a / spad_rd_b hold valid operands
    reg [31:0] acc;

    // Number of valid lanes in the word being accumulated
    wire [2:0] lanes_valid = (elems_left >= 4) ? 3'd4 : elems_left[2:0];

    function signed [15:0] mul8;
        input [7:0] x, y;
        mul8 = $signed(x) * $signed(y);
    endfunction

    wire signed [15:0] p0 = mul8(spad_rd_a[ 7: 0], spad_rd_b[ 7: 0]);
    wire signed [15:0] p1 = mul8(spad_rd_a[15: 8], spad_rd_b[15: 8]);
    wire signed [15:0] p2 = mul8(spad_rd_a[23:16], spad_rd_b[23:16]);
    wire signed [15:0] p3 = mul8(spad_rd_a[31:24], spad_rd_b[31:24]);

    wire signed [17:0] word_sum =
          ((lanes_valid > 3'd0) ? {{2{p0[15]}}, p0} : 18'sd0)
        + ((lanes_valid > 3'd1) ? {{2{p1[15]}}, p1} : 18'sd0)
        + ((lanes_valid > 3'd2) ? {{2{p2[15]}}, p2} : 18'sd0)
        + ((lanes_valid > 3'd3) ? {{2{p3[15]}}, p3} : 18'sd0);

    wire misaligned = (|a_off_r[1:0]) || (|b_off_r[1:0]);
    wire too_long   = (len_r > 4*SPAD_WORDS);

    always @(posedge clk) begin
        if (!resetn) begin
            busy <= 1'b0; done <= 1'b0; error <= 1'b0;
            data_v <= 1'b0;
            acc <= 32'd0; result_r <= 32'd0; cycles_r <= 32'd0;
            words_left <= 32'd0; elems_left <= 32'd0;
            eng_a_addr <= {AW{1'b0}}; eng_b_addr <= {AW{1'b0}};
        end else if (start_req) begin
            done <= 1'b0;
            if (misaligned || too_long) begin
                error <= 1'b1;
                done  <= 1'b1;
            end else begin
                error      <= 1'b0;
                busy       <= 1'b1;
                acc        <= 32'd0;
                cycles_r   <= 32'd0;
                words_left <= (len_r + 32'd3) >> 2;
                elems_left <= len_r;
                eng_a_addr <= a_off_r[AW+1:2];
                eng_b_addr <= b_off_r[AW+1:2];
                data_v     <= 1'b0;
            end
        end else if (busy) begin
            cycles_r <= cycles_r + 32'd1;

            // issue: the RAM samples eng_*_addr on this edge
            data_v <= (words_left != 0);
            if (words_left != 0) begin
                words_left <= words_left - 32'd1;
                eng_a_addr <= eng_a_addr + 1'b1;
                eng_b_addr <= eng_b_addr + 1'b1;
            end

            // accumulate
            if (data_v) begin
                acc        <= acc + {{14{word_sum[17]}}, word_sum};
                elems_left <= (elems_left >= 4) ? elems_left - 32'd4 : 32'd0;
            end

            // finish once nothing is left to issue or accumulate
            if (words_left == 0 && !data_v) begin
                busy     <= 1'b0;
                done     <= 1'b1;
                result_r <= acc;
            end
        end
    end

    // ------------------------------------------------------------------
    // Bus side: registers and handshake (1 wait state for every access)
    // ------------------------------------------------------------------
    reg pending_read, pending_spad;
    reg [4:0] pending_sel;

    always @(posedge clk) begin
        if (!resetn) begin
            bus_ready <= 1'b0;
            len_r <= 32'd0; a_off_r <= 32'd0; b_off_r <= 32'd0;
            pending_read <= 1'b0;
        end else begin
            bus_ready <= 1'b0;
            if (bus_write) begin
                bus_ready <= 1'b1;
                if (!is_spad && !busy) begin
                    case (reg_sel)
                        5'd2: len_r   <= bus_wdata;
                        5'd3: a_off_r <= bus_wdata;
                        5'd4: b_off_r <= bus_wdata;
                        default: ;
                    endcase
                end
            end else if (bus_read && !pending_read) begin
                // wait one cycle for the synchronous scratchpad read
                pending_read <= 1'b1;
                pending_spad <= is_spad;
                pending_sel  <= reg_sel;
            end else if (pending_read) begin
                pending_read <= 1'b0;
                bus_ready    <= 1'b1;
            end
        end
    end

    always @(*) begin
        bus_rdata = 32'd0;
        if (pending_spad) begin
            bus_rdata = spad_rd_cpu;
        end else begin
            case (pending_sel)
                5'd1: bus_rdata = {29'd0, error, done, busy};
                5'd2: bus_rdata = len_r;
                5'd3: bus_rdata = a_off_r;
                5'd4: bus_rdata = b_off_r;
                5'd5: bus_rdata = result_r;
                5'd6: bus_rdata = cycles_r;
                default: bus_rdata = 32'd0;
            endcase
        end
    end

endmodule

`default_nettype wire
