`timescale 1ns/1ps

module tb_write_ctrl;

    logic clk = 0;
    logic rst_n = 0;
    logic rd_empty;
    logic [7:0] rd_data;
    logic rd_en;
    logic mem_wr_en;
    logic [7:0] mem_wr_addr;
    logic [7:0] mem_wr_data;

    always #5 clk = ~clk;

    write_ctrl #(.DATA_WIDTH(8), .MEM_ADDR_WIDTH(8)) dut (
        .clk(clk), .rst_n(rst_n),
        .rd_empty(rd_empty), .rd_data(rd_data), .rd_en(rd_en),
        .mem_wr_en(mem_wr_en), .mem_wr_addr(mem_wr_addr), .mem_wr_data(mem_wr_data)
    );

    // Fake FIFO: holds 5 bytes, empty until they're all popped
    logic [7:0] fifo_mem [0:4];
    initial begin
        fifo_mem[0] = 8'h11;
        fifo_mem[1] = 8'h22;
        fifo_mem[2] = 8'h33;
        fifo_mem[3] = 8'h44;
        fifo_mem[4] = 8'h55;
    end
    int pop_idx = 0;
    assign rd_empty = (pop_idx >= 5);
    assign rd_data  = (pop_idx < 5) ? fifo_mem[pop_idx] : 8'h00;

    always @(posedge clk) begin
        if (rst_n && rd_en && !rd_empty) pop_idx <= pop_idx + 1;
    end

    // Simple memory model to check writes land correctly
    logic [7:0] mem [0:255];
    always @(posedge clk) begin
        if (mem_wr_en) mem[mem_wr_addr] <= mem_wr_data;
    end

    initial begin
        rst_n = 0;
        repeat (3) @(posedge clk);
        rst_n = 1;

        repeat (30) @(posedge clk);

        if (mem[0] === 8'h11 && mem[1] === 8'h22 && mem[2] === 8'h33 &&
            mem[3] === 8'h44 && mem[4] === 8'h55)
            $display("TEST PASSED: all 5 bytes written to memory correctly (0x%0h 0x%0h 0x%0h 0x%0h 0x%0h)",
                mem[0], mem[1], mem[2], mem[3], mem[4]);
        else
            $display("TEST FAILED: mem = 0x%0h 0x%0h 0x%0h 0x%0h 0x%0h",
                mem[0], mem[1], mem[2], mem[3], mem[4]);

        $finish;
    end

endmodule
