`timescale 1ns/1ps

module tb_top_apb;

    localparam CLKS_PER_BIT = 20;

    // Three independent clocks - the whole point of this integration test
    logic wr_clk = 0, rd_clk = 0, PCLK = 0;
    always #20   wr_clk = ~wr_clk;   // 25 MHz
    always #4.97 rd_clk = ~rd_clk;   // ~100.7 MHz
    always #10   PCLK   = ~PCLK;     // 50 MHz APB domain

    logic wr_rst_n = 0, rd_rst_n = 0, PRESETn = 0;
    logic rx_serial = 1;
    logic [7:0] mem_rd_addr;
    logic [7:0] mem_rd_data;

    logic [3:0]  PADDR;
    logic        PWRITE, PSEL, PENABLE;
    logic [31:0] PWDATA, PRDATA;
    logic        PREADY;

    top_apb #(.DATA_WIDTH(8), .FIFO_ADDR_WIDTH(4), .MEM_ADDR_WIDTH(8)) dut (
        .wr_clk(wr_clk), .wr_rst_n(wr_rst_n), .rx_serial(rx_serial),
        .rd_clk(rd_clk), .rd_rst_n(rd_rst_n),
        .mem_rd_addr(mem_rd_addr), .mem_rd_data(mem_rd_data),
        .PCLK(PCLK), .PRESETn(PRESETn),
        .PADDR(PADDR), .PWRITE(PWRITE), .PWDATA(PWDATA),
        .PSEL(PSEL), .PENABLE(PENABLE), .PRDATA(PRDATA), .PREADY(PREADY)
    );

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
            @(posedge PCLK);
            data = PRDATA;
        end
    endtask

    task send_byte(input [7:0] b);
        integer i;
        begin
            rx_serial = 0;
            repeat (CLKS_PER_BIT) @(posedge wr_clk);
            for (i = 0; i < 8; i = i + 1) begin
                rx_serial = b[i];
                repeat (CLKS_PER_BIT) @(posedge wr_clk);
            end
            rx_serial = 1;
            repeat (CLKS_PER_BIT) @(posedge wr_clk);
        end
    endtask

    logic [31:0] rdata;
    int pass_count = 0, fail_count = 0;

    task check(input string name, input logic cond);
        begin
            if (cond) begin $display("PASS: %s", name); pass_count++; end
            else begin $display("FAIL: %s", name); fail_count++; end
        end
    endtask

    initial begin
        PADDR = 0; PWRITE = 0; PWDATA = 0; PSEL = 0; PENABLE = 0;

        wr_rst_n = 0; rd_rst_n = 0; PRESETn = 0;
        repeat (5) @(posedge wr_clk);
        wr_rst_n = 1;
        repeat (5) @(posedge rd_clk);
        rd_rst_n = 1;
        repeat (5) @(posedge PCLK);
        PRESETn = 1;
        repeat (5) @(posedge PCLK);

        // Configure baud rate via APB BEFORE sending any UART data
        apb_write(4'h0, CLKS_PER_BIT);
        repeat (20) @(posedge wr_clk);   // let the toggle-sync settle

        apb_read(4'h0, rdata);
        check("BAUD_DIV configured correctly via APB", rdata == CLKS_PER_BIT);

        // Send a byte over UART at the APB-configured baud rate
        send_byte(8'hA5);
        repeat (50) @(posedge rd_clk);   // let it cross the FIFO CDC boundary and land in memory

        mem_rd_addr = 8'h00;
        @(posedge rd_clk); @(posedge rd_clk);
        check("Byte received at APB-configured baud rate reached memory", mem_rd_data == 8'hA5);

        // Check BYTE_COUNT reflects the one byte received
        apb_read(4'h8, rdata);
        check("BYTE_COUNT reflects 1 byte received", rdata == 32'd1);

        // Check STATUS - no framing error expected on a clean frame
        apb_read(4'h4, rdata);
        check("STATUS shows no framing error on clean frame", rdata[0] == 1'b0);

        // Send a second byte, confirm byte count increments and data still correct
        send_byte(8'h3C);
        repeat (50) @(posedge rd_clk);

        mem_rd_addr = 8'h01;
        @(posedge rd_clk); @(posedge rd_clk);
        check("Second byte reached memory correctly", mem_rd_data == 8'h3C);

        apb_read(4'h8, rdata);
        check("BYTE_COUNT reflects 2 bytes received", rdata == 32'd2);

        $display("");
        if (fail_count == 0)
            $display("TEST PASSED: all %0d checks passed - full 3-clock-domain integration verified", pass_count);
        else
            $display("TEST FAILED: %0d passed, %0d failed", pass_count, fail_count);

        $finish;
    end

endmodule
