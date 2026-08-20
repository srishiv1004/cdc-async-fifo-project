`timescale 1ns/1ps

module tb_apb_regs;

    // Two independent, non-integer-ratio clocks - same spirit as every
    // other CDC testbench in this project.
    logic PCLK = 0;
    logic wr_clk = 0;
    always #10   PCLK   = ~PCLK;    // 50 MHz APB domain
    always #4.97 wr_clk = ~wr_clk;  // ~100.7 MHz wr_clk domain

    logic PRESETn = 0, wr_rst_n = 0;
    logic [3:0]  PADDR;
    logic        PWRITE, PSEL, PENABLE;
    logic [31:0] PWDATA, PRDATA;
    logic        PREADY;

    logic rx_valid = 0, framing_error = 0, fifo_wr_full = 0;
    logic [15:0] clks_per_bit;

    apb_regs dut (
        .PCLK(PCLK), .PRESETn(PRESETn),
        .PADDR(PADDR), .PWRITE(PWRITE), .PWDATA(PWDATA),
        .PSEL(PSEL), .PENABLE(PENABLE), .PRDATA(PRDATA), .PREADY(PREADY),
        .wr_clk(wr_clk), .wr_rst_n(wr_rst_n),
        .rx_valid(rx_valid), .framing_error(framing_error), .fifo_wr_full(fifo_wr_full),
        .clks_per_bit(clks_per_bit)
    );

    // Simple APB write task (2-phase: setup then access)
    task apb_write(input [3:0] addr, input [31:0] data);
        begin
            @(posedge PCLK);
            PADDR <= addr; PWRITE <= 1; PWDATA <= data; PSEL <= 1; PENABLE <= 0;
            @(posedge PCLK);
            PENABLE <= 1;
            @(posedge PCLK);
            PSEL <= 0; PENABLE <= 0;
        end
    endtask

    task apb_read(input [3:0] addr, output [31:0] data);
        begin
            @(posedge PCLK);
            PADDR <= addr; PWRITE <= 0; PSEL <= 1; PENABLE <= 0;
            @(posedge PCLK);
            PENABLE <= 1;
            @(posedge PCLK);
            PSEL <= 0; PENABLE <= 0;
            @(posedge PCLK);   // extra edge - let PRDATA's update fully settle before sampling
            data = PRDATA;
        end
    endtask

    logic [31:0] rdata;
    int pass_count = 0;
    int fail_count = 0;

    task check(input string name, input logic cond);
        begin
            if (cond) begin
                $display("PASS: %s", name);
                pass_count++;
            end else begin
                $display("FAIL: %s", name);
                fail_count++;
            end
        end
    endtask

    initial begin
        PADDR = 0; PWRITE = 0; PWDATA = 0; PSEL = 0; PENABLE = 0;

        PRESETn = 0; wr_rst_n = 0;
        repeat (5) @(posedge PCLK);
        PRESETn = 1;
        repeat (5) @(posedge wr_clk);
        wr_rst_n = 1;
        repeat (5) @(posedge PCLK);

        // --- Technique 3 test: write BAUD_DIV, confirm it reaches wr_clk domain ---
        apb_write(4'h0, 32'd217);
        repeat (20) @(posedge wr_clk);   // give the toggle-qualified sync time to settle
        check("BAUD_DIV reaches wr_clk domain (clks_per_bit)", clks_per_bit == 16'd217);

        apb_read(4'h0, rdata);
        check("BAUD_DIV reads back correctly via APB", rdata == 32'd217);

        // --- Technique 1 test: status flags cross wr_clk -> apb_clk ---
        framing_error = 1;
        repeat (10) @(posedge PCLK);
        apb_read(4'h4, rdata);
        check("framing_error visible in STATUS register", rdata[0] == 1'b1);
        framing_error = 0;

        fifo_wr_full = 1;
        repeat (10) @(posedge PCLK);
        apb_read(4'h4, rdata);
        check("fifo_wr_full visible in STATUS register", rdata[1] == 1'b1);
        fifo_wr_full = 0;

        // --- Technique 2 test: byte counter (gray-coded) crosses wr_clk -> apb_clk ---
        for (int i = 0; i < 10; i++) begin
            rx_valid <= 1;
            @(posedge wr_clk);
            rx_valid <= 0;
            @(posedge wr_clk);
        end
        repeat (10) @(posedge PCLK);
        apb_read(4'h8, rdata);
        check("BYTE_COUNT correctly synchronized after 10 pulses", rdata == 32'd10);

        // Second BAUD_DIV write, confirm the toggle mechanism works a second time
        apb_write(4'h0, 32'd100);
        repeat (20) @(posedge wr_clk);
        check("BAUD_DIV updates correctly on second write", clks_per_bit == 16'd100);

        $display("");
        if (fail_count == 0)
            $display("TEST PASSED: all %0d checks passed", pass_count);
        else
            $display("TEST FAILED: %0d passed, %0d failed", pass_count, fail_count);

        $finish;
    end

endmodule
