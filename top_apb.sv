module top_apb #(
    parameter int DATA_WIDTH      = 8,
    parameter int FIFO_ADDR_WIDTH = 4,
    parameter int MEM_ADDR_WIDTH  = 8
) (
    // Slow domain - UART / FIFO write side
    input  logic                  wr_clk,
    input  logic                  wr_rst_n,
    input  logic                  rx_serial,

    // Fast domain - FIFO read side / memory
    input  logic                  rd_clk,
    input  logic                  rd_rst_n,

    input  logic [MEM_ADDR_WIDTH-1:0] mem_rd_addr,
    output logic [DATA_WIDTH-1:0]     mem_rd_data,

    // APB domain - register interface (its own clock)
    input  logic                  PCLK,
    input  logic                  PRESETn,
    input  logic [3:0]            PADDR,
    input  logic                  PWRITE,
    input  logic [31:0]           PWDATA,
    input  logic                  PSEL,
    input  logic                  PENABLE,
    output logic [31:0]           PRDATA,
    output logic                  PREADY
);

    // -------------------------------------------------------------------
    // APB register file - drives baud config, reads back status/byte count
    // -------------------------------------------------------------------
    logic [15:0] clks_per_bit;
    logic uart_rx_valid, uart_framing_error, fifo_wr_full;

    apb_regs u_apb_regs (
        .PCLK(PCLK), .PRESETn(PRESETn),
        .PADDR(PADDR), .PWRITE(PWRITE), .PWDATA(PWDATA),
        .PSEL(PSEL), .PENABLE(PENABLE), .PRDATA(PRDATA), .PREADY(PREADY),
        .wr_clk(wr_clk), .wr_rst_n(wr_rst_n),
        .rx_valid(uart_rx_valid),
        .framing_error(uart_framing_error),
        .fifo_wr_full(fifo_wr_full),
        .clks_per_bit(clks_per_bit)
    );

    // -------------------------------------------------------------------
    // UART RX (wr_clk domain) - baud rate now driven by apb_regs
    // -------------------------------------------------------------------
    logic [DATA_WIDTH-1:0] uart_rx_data;

    uart_rx u_uart_rx (
        .clk           (wr_clk),
        .rst_n         (wr_rst_n),
        .clks_per_bit  (clks_per_bit),
        .rx_serial     (rx_serial),
        .rx_valid      (uart_rx_valid),
        .rx_data       (uart_rx_data),
        .framing_error (uart_framing_error)
    );

    // -------------------------------------------------------------------
    // Async FIFO - the FIFO's own CDC boundary (unchanged from top.sv)
    // -------------------------------------------------------------------
    logic fifo_rd_empty;
    logic [DATA_WIDTH-1:0] fifo_rd_data;
    logic fifo_rd_en;
    logic fifo_wr_en;

    assign fifo_wr_en = uart_rx_valid && !fifo_wr_full;

    async_fifo #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(FIFO_ADDR_WIDTH)
    ) u_async_fifo (
        .wr_clk   (wr_clk),
        .wr_rst_n (wr_rst_n),
        .wr_en    (fifo_wr_en),
        .wr_data  (uart_rx_data),
        .wr_full  (fifo_wr_full),

        .rd_clk   (rd_clk),
        .rd_rst_n (rd_rst_n),
        .rd_en    (fifo_rd_en),
        .rd_data  (fifo_rd_data),
        .rd_empty (fifo_rd_empty)
    );

    // -------------------------------------------------------------------
    // Write controller (rd_clk domain) - unchanged from top.sv
    // -------------------------------------------------------------------
    logic mem_wr_en;
    logic [MEM_ADDR_WIDTH-1:0] mem_wr_addr;
    logic [DATA_WIDTH-1:0] mem_wr_data;

    write_ctrl #(
        .DATA_WIDTH(DATA_WIDTH),
        .MEM_ADDR_WIDTH(MEM_ADDR_WIDTH)
    ) u_write_ctrl (
        .clk         (rd_clk),
        .rst_n       (rd_rst_n),
        .rd_empty    (fifo_rd_empty),
        .rd_data     (fifo_rd_data),
        .rd_en       (fifo_rd_en),
        .mem_wr_en   (mem_wr_en),
        .mem_wr_addr (mem_wr_addr),
        .mem_wr_data (mem_wr_data)
    );

    // -------------------------------------------------------------------
    // Memory (rd_clk domain) - unchanged from top.sv
    // -------------------------------------------------------------------
    mem_model #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(MEM_ADDR_WIDTH)
    ) u_mem_model (
        .clk     (rd_clk),
        .wr_en   (mem_wr_en),
        .wr_addr (mem_wr_addr),
        .wr_data (mem_wr_data),
        .rd_addr (mem_rd_addr),
        .rd_data (mem_rd_data)
    );

endmodule
