module mem_model #(
    parameter int DATA_WIDTH = 8,
    parameter int ADDR_WIDTH = 8       // 2**ADDR_WIDTH locations
) (
    input  logic                     clk,

    // Write port
    input  logic                     wr_en,
    input  logic [ADDR_WIDTH-1:0]    wr_addr,
    input  logic [DATA_WIDTH-1:0]    wr_data,

    // Read port (synchronous - rd_data valid the cycle AFTER rd_addr is applied)
    input  logic [ADDR_WIDTH-1:0]    rd_addr,
    output logic [DATA_WIDTH-1:0]    rd_data
);

    logic [DATA_WIDTH-1:0] mem [1<<ADDR_WIDTH];

    always_ff @(posedge clk) begin
        if (wr_en) mem[wr_addr] <= wr_data;
        rd_data <= mem[rd_addr];
    end

endmodule
