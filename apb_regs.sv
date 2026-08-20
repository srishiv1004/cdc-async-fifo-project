module apb_regs #(
    parameter int BAUD_WIDTH  = 16,
    parameter int COUNT_WIDTH = 32
) (
    // -------------------------------------------------------------------
    // APB side (apb_clk domain)
    // -------------------------------------------------------------------
    input  logic                  PCLK,
    input  logic                  PRESETn,
    input  logic [3:0]            PADDR,
    input  logic                  PWRITE,
    /* verilator lint_off UNUSEDSIGNAL */
    input  logic [31:0]           PWDATA,   // upper bits unused - BAUD_DIV narrower than the bus
    /* verilator lint_on UNUSEDSIGNAL */
    input  logic                  PSEL,
    input  logic                  PENABLE,
    output logic [31:0]           PRDATA,
    output logic                  PREADY,

    // -------------------------------------------------------------------
    // wr_clk side - connects to the UART/FIFO datapath
    // -------------------------------------------------------------------
    input  logic                  wr_clk,
    input  logic                  wr_rst_n,

    input  logic                  rx_valid,       // pulses once per received byte
    input  logic                  framing_error,  // live status bit, wr_clk domain
    input  logic                  fifo_wr_full,   // live status bit, wr_clk domain

    output logic [BAUD_WIDTH-1:0] clks_per_bit    // synchronized config, to uart_rx
);

    // No wait states in this design - always ready the same cycle.
    assign PREADY = 1'b1;

    localparam logic [3:0] AddrBaudDiv   = 4'h0;
    localparam logic [3:0] AddrStatus     = 4'h4;
    localparam logic [3:0] AddrByteCount = 4'h8;

    wire apb_xfer = PSEL && PENABLE;   // a real APB transfer is happening this cycle

    // =====================================================================
    // Technique 1: 2-flop synchronizers for single-bit status flags
    // (wr_clk domain -> apb_clk domain)
    // =====================================================================
    logic framing_error_sync1, framing_error_sync2;
    logic fifo_wr_full_sync1,  fifo_wr_full_sync2;

    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            framing_error_sync1 <= 1'b0;
            framing_error_sync2 <= 1'b0;
            fifo_wr_full_sync1  <= 1'b0;
            fifo_wr_full_sync2  <= 1'b0;
        end else begin
            framing_error_sync1 <= framing_error;
            framing_error_sync2 <= framing_error_sync1;
            fifo_wr_full_sync1  <= fifo_wr_full;
            fifo_wr_full_sync2  <= fifo_wr_full_sync1;
        end
    end

    // =====================================================================
    // Technique 2: gray-coded counter, same pattern as async_fifo.sv's
    // pointers (wr_clk domain -> apb_clk domain)
    // =====================================================================
    logic [COUNT_WIDTH-1:0] byte_bin, byte_bin_next, byte_gray, byte_gray_next;

    assign byte_bin_next  = byte_bin + COUNT_WIDTH'(rx_valid);
    assign byte_gray_next = (byte_bin_next >> 1) ^ byte_bin_next;

    always_ff @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            byte_bin  <= '0;
            byte_gray <= '0;
        end else begin
            byte_bin  <= byte_bin_next;
            byte_gray <= byte_gray_next;
        end
    end

    logic [COUNT_WIDTH-1:0] byte_gray_sync1, byte_gray_sync2;
    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            byte_gray_sync1 <= '0;
            byte_gray_sync2 <= '0;
        end else begin
            byte_gray_sync1 <= byte_gray;
            byte_gray_sync2 <= byte_gray_sync1;
        end
    end

    // Gray-to-binary conversion (combinational) for the APB read side
    logic [COUNT_WIDTH-1:0] byte_count_bin_apb;
    always_comb begin
        byte_count_bin_apb[COUNT_WIDTH-1] = byte_gray_sync2[COUNT_WIDTH-1];
        for (int i = COUNT_WIDTH-2; i >= 0; i--) begin
            byte_count_bin_apb[i] = byte_count_bin_apb[i+1] ^ byte_gray_sync2[i];
        end
    end

    // =====================================================================
    // Technique 3: toggle-qualified synchronizer for BAUD_DIV
    // (apb_clk domain -> wr_clk domain - the REVERSE direction)
    // =====================================================================
    logic [BAUD_WIDTH-1:0] baud_div_reg;
    logic baud_div_toggle;

    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            baud_div_reg    <= '0;
            baud_div_toggle <= 1'b0;
        end else if (apb_xfer && PWRITE && PADDR == AddrBaudDiv) begin
            baud_div_reg    <= PWDATA[BAUD_WIDTH-1:0];
            baud_div_toggle <= ~baud_div_toggle;   // flip to signal "new value"
        end
    end


    logic [BAUD_WIDTH-1:0] baud_div_sync1, baud_div_sync2;
    logic toggle_sync1, toggle_sync2, toggle_sync2_prev;

    always_ff @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            baud_div_sync1    <= '0;
            baud_div_sync2    <= '0;
            toggle_sync1      <= 1'b0;
            toggle_sync2      <= 1'b0;
            toggle_sync2_prev <= 1'b0;
            clks_per_bit      <= '0;
        end else begin
            baud_div_sync1    <= baud_div_reg;
            baud_div_sync2    <= baud_div_sync1;
            toggle_sync1      <= baud_div_toggle;
            toggle_sync2      <= toggle_sync1;
            toggle_sync2_prev <= toggle_sync2;


            if (toggle_sync2 != toggle_sync2_prev) begin
                clks_per_bit <= baud_div_sync2;
            end
        end
    end

    // =====================================================================
    // APB read mux
    // =====================================================================
    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            PRDATA <= 32'h0;
        end else if (apb_xfer && !PWRITE) begin
            case (PADDR)
                AddrBaudDiv:   PRDATA <= {{(32-BAUD_WIDTH){1'b0}}, baud_div_reg};
                AddrStatus:     PRDATA <= {30'b0, fifo_wr_full_sync2, framing_error_sync2};
                AddrByteCount: PRDATA <= byte_count_bin_apb;
                default:         PRDATA <= 32'h0;
            endcase
        end
    end

endmodule
