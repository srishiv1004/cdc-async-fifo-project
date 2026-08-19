module mem_model_sram #(
    parameter int DATA_WIDTH = 8,
    parameter int ADDR_WIDTH = 8       // external interface width (unchanged)
) (
    input  logic                     clk,

    input  logic                     wr_en,
    input  logic [ADDR_WIDTH-1:0]    wr_addr,
    input  logic [DATA_WIDTH-1:0]    wr_data,

    input  logic [ADDR_WIDTH-1:0]    rd_addr,
    output logic [DATA_WIDTH-1:0]    rd_data
);

    localparam int SRAM_ADDR_WIDTH = 10;   // fixed by the macro itself

    sky130_sram_1kbyte_1rw1r_8x1024_8 u_sram (
        // Port 0 (RW) - driven by write_ctrl
        .clk0   (clk),
        .csb0   (~wr_en),                  // active-low chip select: selected when writing
        .web0   (1'b0),                    // active-low write enable: always write mode when selected
        .wmask0 (1'b1),                    // single write-mask bit covers the full 8-bit word
        .addr0  ({{(SRAM_ADDR_WIDTH-ADDR_WIDTH){1'b0}}, wr_addr}),
        .din0   (wr_data),
        .dout0  (),                        // unused - this port is write-only from our side

        // Port 1 (R) - dedicated external readback port
        .clk1   (clk),
        .csb1   (1'b0),                    // always selected/active for reading
        .addr1  ({{(SRAM_ADDR_WIDTH-ADDR_WIDTH){1'b0}}, rd_addr}),
        .dout1  (rd_data)
    );

endmodule
