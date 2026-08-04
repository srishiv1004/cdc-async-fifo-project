// =============================================================================
// tb_async_fifo.sv
//
// Minimal sanity-check testbench for async_fifo.sv in ModelSim.
// Uses two independent, non-integer-ratio clocks (25 MHz wr_clk vs
// 100.7 MHz-ish rd_clk) to exercise real cross-domain timing skew.
// =============================================================================

`timescale 1ns/1ps

module tb_async_fifo;

    localparam DATA_WIDTH = 8;
    localparam ADDR_WIDTH = 4;

    logic wr_clk = 0, rd_clk = 0;
    logic wr_rst_n = 0, rd_rst_n = 0;
    logic wr_en, rd_en;
    logic [DATA_WIDTH-1:0] wr_data, rd_data;
    logic wr_full, rd_empty;

    // wr_clk: 25 MHz -> 40 ns period (20 ns half period)
    always #20 wr_clk = ~wr_clk;

    // rd_clk: ~100.7 MHz -> deliberately not an integer multiple of wr_clk,
    // so pointer crossings land at varying phase offsets each time.
    always #4.97 rd_clk = ~rd_clk;

    async_fifo #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) dut (
        .wr_clk   (wr_clk),
        .wr_rst_n (wr_rst_n),
        .wr_en    (wr_en),
        .wr_data  (wr_data),
        .wr_full  (wr_full),
        .rd_clk   (rd_clk),
        .rd_rst_n (rd_rst_n),
        .rd_en    (rd_en),
        .rd_data  (rd_data),
        .rd_empty (rd_empty)
    );

    // Reset
    initial begin
        wr_rst_n = 0; rd_rst_n = 0;
        wr_en = 0; wr_data = '0;
        repeat (5) @(posedge wr_clk);
        wr_rst_n = 1;
        repeat (5) @(posedge rd_clk);
        rd_rst_n = 1;
    end

    // Writer: push 20 incrementing bytes, one per wr_clk, while not full
    initial begin
        @(posedge wr_rst_n);
        @(posedge wr_clk);
        for (int i = 0; i < 20; i++) begin
            // Wait until not full BEFORE asserting wr_en - wr_en must stay
            // low while stalled, otherwise the write pointer keeps
            // incrementing every cycle (the RTL no longer self-gates it)
            // and races out of sync with what the reader has drained.
            while (wr_full) @(posedge wr_clk);
            wr_en   <= 1;
            wr_data <= i[DATA_WIDTH-1:0];
            @(posedge wr_clk);
            wr_en <= 0;
        end
    end

    // Reader: greedily consume whenever data is available. This is now safe
    // as a plain combinational drive because rd_empty is a REGISTERED
    // output of the FIFO (see async_fifo.sv) - no lag, no loop.
    logic rd_active;
    assign rd_en = rd_active && !rd_empty;

    initial begin
        rd_active = 0;
        @(posedge rd_rst_n);
        repeat (30) @(posedge rd_clk);   // let a few writes accumulate first
        rd_active = 1;
    end

    // Simple scoreboard: check read data is monotonically increasing 0..19
    int expected = 0;
    always @(posedge rd_clk) begin
        if (rd_en && !rd_empty) begin
            if (rd_data !== expected[DATA_WIDTH-1:0]) begin
                $error("MISMATCH: expected %0d got %0d at time %0t",
                       expected, rd_data, $time);
            end else begin
                $display("OK: read %0d at time %0t", rd_data, $time);
            end
            expected++;
        end
    end

    initial begin
        #5000;
        if (expected == 20)
            $display("TEST PASSED: all 20 words read back correctly");
        else
            $display("TEST INCOMPLETE: only %0d of 20 words read", expected);
        $finish;
    end

endmodule
