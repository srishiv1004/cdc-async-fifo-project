`timescale 1ns/1ps

module tb_top_sram;

    localparam CLKS_PER_BIT = 20;   // small divisor, fast test

    logic wr_clk = 0;
    logic wr_rst_n = 0;
    logic [15:0] clks_per_bit = CLKS_PER_BIT;
    logic rx_serial = 1;

    logic rd_clk = 0;
    logic rd_rst_n = 0;

    logic [7:0] mem_rd_addr;
    logic [7:0] mem_rd_data;
    logic uart_framing_error;
    logic fifo_wr_full;

    
    always #20   wr_clk = ~wr_clk;    // 25 MHz
    always #4.97 rd_clk = ~rd_clk;    // ~100.7 MHz

    top_sram #(
        .DATA_WIDTH(8), .FIFO_ADDR_WIDTH(4), .MEM_ADDR_WIDTH(8)
    ) dut (
        .wr_clk(wr_clk), .wr_rst_n(wr_rst_n),
        .clks_per_bit(clks_per_bit), .rx_serial(rx_serial),
        .rd_clk(rd_clk), .rd_rst_n(rd_rst_n),
        .mem_rd_addr(mem_rd_addr), .mem_rd_data(mem_rd_data),
        .uart_framing_error(uart_framing_error), .fifo_wr_full(fifo_wr_full)
    );

    task send_byte(input [7:0] b);
        integer i;
        begin
            rx_serial = 0;                       // start bit
            repeat (CLKS_PER_BIT) @(posedge wr_clk);
            for (i = 0; i < 8; i = i + 1) begin
                rx_serial = b[i];
                repeat (CLKS_PER_BIT) @(posedge wr_clk);
            end
            rx_serial = 1;                       // stop bit
            repeat (CLKS_PER_BIT) @(posedge wr_clk);
        end
    endtask

    logic [7:0] expected [0:3];
    int pass_count;

    initial begin
        expected[0] = 8'hDE;
        expected[1] = 8'hAD;
        expected[2] = 8'hBE;
        expected[3] = 8'hEF;
    end

    initial begin
        wr_rst_n = 0; rd_rst_n = 0;
        repeat (5) @(posedge wr_clk);
        wr_rst_n = 1;
        repeat (5) @(posedge rd_clk);
        rd_rst_n = 1;

        repeat (5) @(posedge wr_clk);

        send_byte(expected[0]);
        send_byte(expected[1]);
        send_byte(expected[2]);
        send_byte(expected[3]);

        // Give the last byte time to cross the CDC boundary and land in memory
        repeat (50) @(posedge rd_clk);

        // Read back each memory location and check it
        pass_count = 0;
        for (int a = 0; a < 4; a++) begin
            mem_rd_addr = a[7:0];
            @(posedge rd_clk);
            @(posedge rd_clk);   // synchronous read - one extra cycle for rd_data to settle
            if (mem_rd_data === expected[a]) begin
                $display("addr %0d: OK, got 0x%0h", a, mem_rd_data);
                pass_count++;
            end else begin
                $display("addr %0d: MISMATCH, expected 0x%0h got 0x%0h", a, expected[a], mem_rd_data);
            end
        end

        if (pass_count == 4)
            $display("TEST PASSED: all 4 bytes traveled UART -> FIFO -> memory correctly");
        else
            $display("TEST FAILED: only %0d of 4 bytes correct", pass_count);

        if (uart_framing_error) $display("WARNING: framing error flagged during test");
        if (fifo_wr_full)       $display("NOTE: FIFO reported full at end of test");

        $finish;
    end

endmodule
