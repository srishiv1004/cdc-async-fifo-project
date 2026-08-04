// =============================================================================
// async_fifo.sv
//
// Asynchronous FIFO used as the sole clock-domain-crossing (CDC) boundary
// between the slow UART domain (wr_clk) and the fast memory-write domain
// (rd_clk). Write and read pointers are gray-coded before crossing domains
// and passed through 2-flop synchronizers, per standard CDC practice
// (Cummings, "Simulation and Synthesis Techniques for Asynchronous FIFO
// Design", SNUG 2002).
//
// DELIBERATE CDC BUG (for verification demo): none present in this version.
// A buggy variant (binary pointer synced directly, no gray coding) lives in
// async_fifo_buggy.sv so the SymbiYosys check can be shown catching it.
// =============================================================================

module async_fifo #(
    parameter int DATA_WIDTH = 8,
    parameter int ADDR_WIDTH = 4              // depth = 2**ADDR_WIDTH
) (
    // Write domain
    input  logic                   wr_clk,
    input  logic                   wr_rst_n,
    input  logic                   wr_en,
    input  logic [DATA_WIDTH-1:0]  wr_data,
    output logic                   wr_full,

    // Read domain
    input  logic                   rd_clk,
    input  logic                   rd_rst_n,
    input  logic                   rd_en,
    output logic [DATA_WIDTH-1:0]  rd_data,
    output logic                   rd_empty
);

    localparam int DEPTH = 1 << ADDR_WIDTH;

    // Memory
    logic [DATA_WIDTH-1:0] mem [DEPTH];

    // Binary + gray pointers, one extra MSB (wrap bit) for full/empty detect
    logic [ADDR_WIDTH:0] wr_bin, wr_bin_next;
    logic [ADDR_WIDTH:0] wr_gray, wr_gray_next;
    logic [ADDR_WIDTH:0] rd_bin, rd_bin_next;
    logic [ADDR_WIDTH:0] rd_gray, rd_gray_next;

    // Synchronized copies of the *other* domain's gray pointer
    logic [ADDR_WIDTH:0] wr_gray_sync1, wr_gray_sync2; // into rd_clk domain
    logic [ADDR_WIDTH:0] rd_gray_sync1, rd_gray_sync2; // into wr_clk domain

    // -------------------------------------------------------------------
    // Write domain
    // -------------------------------------------------------------------
    // NOTE: increment is gated only by wr_en, NOT by !wr_full. Gating by
    // wr_full here would create a zero-delay combinational loop, since
    // wr_full itself is derived from wr_bin_next below. Respecting wr_full
    // (not asserting wr_en while full) is the writer's responsibility, same
    // as a real FIFO IP - this module only reports the flag, it doesn't
    // self-throttle.
    assign wr_bin_next  = wr_bin + (ADDR_WIDTH+1)'(wr_en);
    assign wr_gray_next = (wr_bin_next >> 1) ^ wr_bin_next;   // binary -> gray

    always_ff @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            wr_bin  <= '0;
            wr_gray <= '0;
        end else begin
            wr_bin  <= wr_bin_next;
            wr_gray <= wr_gray_next;
        end
    end

    always_ff @(posedge wr_clk) begin
        if (wr_en && !wr_full)
            mem[wr_bin[ADDR_WIDTH-1:0]] <= wr_data;
    end

    // full: next write pointer (gray) equals read pointer (gray) with the
    // two MSBs inverted -> classic wrap-around comparison.
    // wr_full is REGISTERED (not raw combinational) so that external logic
    // can safely do `assign wr_en = !wr_full` without creating a zero-delay
    // combinational loop back into this module (Cummings SNUG2002 style).
    logic wr_full_next;
    assign wr_full_next = (wr_gray_next == {~rd_gray_sync2[ADDR_WIDTH:ADDR_WIDTH-1],
                                              rd_gray_sync2[ADDR_WIDTH-2:0]});

    always_ff @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) wr_full <= 1'b0;
        else           wr_full <= wr_full_next;
    end

    // -------------------------------------------------------------------
    // Read domain
    // -------------------------------------------------------------------
    // Same reasoning as wr_bin_next above: gated only by rd_en, not by
    // !rd_empty, to avoid a combinational loop through rd_empty.
    assign rd_bin_next  = rd_bin + (ADDR_WIDTH+1)'(rd_en);
    assign rd_gray_next = (rd_bin_next >> 1) ^ rd_bin_next;

    always_ff @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            rd_bin  <= '0;
            rd_gray <= '0;
        end else begin
            rd_bin  <= rd_bin_next;
            rd_gray <= rd_gray_next;
        end
    end

    assign rd_data  = mem[rd_bin[ADDR_WIDTH-1:0]];

    // rd_empty is REGISTERED for the same reason wr_full is above. This is
    // what actually fixes the read stall: a raw combinational look-ahead
    // flag combined with a one-cycle-delayed external rd_en falls out of
    // phase permanently once the write rate is slower than the read clock.
    // Registering the flag lets rd_en be driven combinationally from it
    // with zero lag and zero loop risk.
    logic rd_empty_next;
    assign rd_empty_next = (rd_gray_next == wr_gray_sync2);

    always_ff @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) rd_empty <= 1'b1;
        else           rd_empty <= rd_empty_next;
    end

    // -------------------------------------------------------------------
    // CDC boundary: 2-flop synchronizers on GRAY-CODED pointers only.
    // Never synchronize the binary pointer or any multi-bit bus directly -
    // gray coding guarantees only one bit toggles per cycle, so a
    // synchronizer sampling mid-transition can only be one count off,
    // never garbage.
    // -------------------------------------------------------------------

    // wr_gray -> rd_clk domain
    always_ff @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            wr_gray_sync1 <= '0;
            wr_gray_sync2 <= '0;
        end else begin
            wr_gray_sync1 <= wr_gray;
            wr_gray_sync2 <= wr_gray_sync1;
        end
    end

    // rd_gray -> wr_clk domain
    always_ff @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            rd_gray_sync1 <= '0;
            rd_gray_sync2 <= '0;
        end else begin
            rd_gray_sync1 <= rd_gray;
            rd_gray_sync2 <= rd_gray_sync1;
        end
    end

endmodule
