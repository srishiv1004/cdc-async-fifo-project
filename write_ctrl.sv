module write_ctrl #(
    parameter int DATA_WIDTH = 8,
    parameter int MEM_ADDR_WIDTH = 8   // 256 memory locations by default
) (
    input  logic                     clk,
    input  logic                     rst_n,

    // FIFO read-side interface
    input  logic                     rd_empty,
    input  logic [DATA_WIDTH-1:0]    rd_data,
    output logic                     rd_en,

    // Memory write interface
    output logic                     mem_wr_en,
    output logic [MEM_ADDR_WIDTH-1:0] mem_wr_addr,
    output logic [DATA_WIDTH-1:0]    mem_wr_data
);

    assign rd_en = !rd_empty;


    logic [MEM_ADDR_WIDTH-1:0] wr_addr;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_addr     <= '0;
            mem_wr_en   <= 1'b0;
            mem_wr_addr <= '0;
            mem_wr_data <= '0;
        end else begin
            mem_wr_en <= rd_en;

            if (rd_en) begin
                mem_wr_addr <= wr_addr;
                mem_wr_data <= rd_data;
                wr_addr     <= wr_addr + 1'b1;
            end
        end
    end

endmodule
