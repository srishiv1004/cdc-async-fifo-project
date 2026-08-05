`timescale 1ns/1ps

module tb_uart_rx;

    localparam CLKS_PER_BIT = 20;   // small divisor for a fast, short test

    logic clk = 0;
    logic rst_n = 0;
    logic [15:0] clks_per_bit = CLKS_PER_BIT;
    logic rx_serial = 1;
    logic rx_valid;
    logic [7:0] rx_data;
    logic framing_error;

    always #5 clk = ~clk;   // 100 MHz test clock, unrelated to real UART timing

    uart_rx dut (
        .clk(clk), .rst_n(rst_n), .clks_per_bit(clks_per_bit),
        .rx_serial(rx_serial), .rx_valid(rx_valid),
        .rx_data(rx_data), .framing_error(framing_error)
    );

    task send_byte(input [7:0] b);
        integer i;
        begin
            rx_serial = 0;                       // start bit
            repeat (CLKS_PER_BIT) @(posedge clk);
            for (i = 0; i < 8; i = i + 1) begin
                rx_serial = b[i];
                repeat (CLKS_PER_BIT) @(posedge clk);
            end
            rx_serial = 1;                       // stop bit
            repeat (CLKS_PER_BIT) @(posedge clk);
        end
    endtask

    initial begin
        rst_n = 0;
        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (5) @(posedge clk);

        send_byte(8'hA5);
        repeat (5) @(posedge clk);
        if (rx_data === 8'hA5 && !framing_error)
            $display("TEST 1 PASSED: received 0x%0h correctly", rx_data);
        else
            $display("TEST 1 FAILED: expected 0xA5, got 0x%0h, framing_error=%b", rx_data, framing_error);

        send_byte(8'h3C);
        repeat (5) @(posedge clk);
        if (rx_data === 8'h3C && !framing_error)
            $display("TEST 2 PASSED: received 0x%0h correctly", rx_data);
        else
            $display("TEST 2 FAILED: expected 0x3C, got 0x%0h, framing_error=%b", rx_data, framing_error);

        $finish;
    end

    // Catch the valid pulse whenever it happens
    always @(posedge clk) if (rx_valid) $display("  rx_valid pulsed, rx_data=0x%0h at time %0t", rx_data, $time);

endmodule
