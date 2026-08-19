module top #(
    parameter int DATA_WIDTH    = 8,
    parameter int FIFO_ADDR_WIDTH = 4,   // FIFO depth = 2**4 = 16
    parameter int MEM_ADDR_WIDTH  = 8    // memory depth = 2**8 = 256
) (
    // Slow domain - UART / FIFO write side
    input  logic                  wr_clk,
    input  logic                  wr_rst_n,
    input  logic [15:0]           clks_per_bit,   // UART baud divisor
    input  logic                  rx_serial,

    // Fast domain - FIFO read side / memory
    input  logic                  rd_clk,
    input  logic                  rd_rst_n,

    // Memory readback port, for verification / a future host interface
    input  logic [MEM_ADDR_WIDTH-1:0] mem_rd_addr,
    output logic [DATA_WIDTH-1:0]     mem_rd_data,

    // Debug/status outputs
    output logic                  uart_framing_error,
    output logic                  fifo_wr_full
);

    // -------------------------------------------------------------------
    // UART RX (wr_clk domain)
    // -------------------------------------------------------------------
    logic uart_rx_valid;
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
    // Async FIFO - the CDC boundary
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
    // Write controller (rd_clk domain)
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
    // Memory (rd_clk domain)
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
