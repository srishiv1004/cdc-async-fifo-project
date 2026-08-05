// =============================================================================
// uart_rx.sv
//
// UART receiver, standard 8N1 framing (1 start bit, 8 data bits, no parity,
// 1 stop bit). Lives entirely in the slow write-clock domain (wr_clk) - it
// does NOT cross any clock boundary itself. Its output (rx_data/rx_valid) is
// what gets pushed into async_fifo's write port, which is where the actual
// CDC boundary lives.
//
// Baud generation: a configurable clock divisor (clks_per_bit) sets the
// number of wr_clk cycles per UART bit period. This is meant to be driven
// from apb_regs.sv so baud rate is software-configurable rather than a
// synthesis-time constant.
//
//   clks_per_bit = CLK_FREQ_HZ / BAUD_RATE
//   e.g. 25 MHz clk, 115200 baud -> clks_per_bit ~= 217
// =============================================================================

module uart_rx #(
    parameter int CLKS_PER_BIT_DEFAULT = 217   // 25 MHz / 115200 baud, ~default
) (
    input  logic        clk,             // wr_clk domain - same domain as FIFO write side
    input  logic         rst_n,
    input  logic [15:0] clks_per_bit,    // runtime baud divisor, from apb_regs
    input  logic         rx_serial,       // asynchronous input pin - NOT yet synchronized
    output logic         rx_valid,        // 1-cycle pulse when rx_data is valid
    output logic [7:0]  rx_data,
    output logic         framing_error    // stop bit was not '1' - malformed frame
);

    // -------------------------------------------------------------------
    // Input synchronizer: rx_serial comes from an external pin, which is
    // itself an asynchronous signal relative to clk (a genuine, if small,
    // CDC concern - not from another on-chip clock domain, but from an
    // uncontrolled external world). Standard 2-flop synchronizer.
    // -------------------------------------------------------------------
    logic rx_sync1, rx_sync2;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_sync1 <= 1'b1;   // idle line level is '1'
            rx_sync2 <= 1'b1;
        end else begin
            rx_sync1 <= rx_serial;
            rx_sync2 <= rx_sync1;
        end
    end

    // -------------------------------------------------------------------
    // FSM
    // -------------------------------------------------------------------
    typedef enum logic [2:0] {
        S_IDLE,
        S_START_BIT,
        S_DATA_BITS,
        S_STOP_BIT,
        S_CLEANUP
    } state_e;

    state_e state;

    logic [15:0] clk_count;
    logic [2:0]  bit_index;      // which of the 8 data bits we're on
    logic [7:0]  rx_shift_reg;

    // Effective divisor: use runtime value if nonzero, else the default
    logic [15:0] div;
    assign div = (clks_per_bit != 16'd0) ? clks_per_bit : CLKS_PER_BIT_DEFAULT[15:0];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= S_IDLE;
            clk_count     <= '0;
            bit_index     <= '0;
            rx_shift_reg  <= '0;
            rx_valid      <= 1'b0;
            rx_data       <= '0;
            framing_error <= 1'b0;
        end else begin
            rx_valid <= 1'b0;   // default: pulse is low unless S_CLEANUP says otherwise

            case (state)
                // Wait for the line to fall - that's the start bit edge
                S_IDLE: begin
                    clk_count <= '0;
                    bit_index <= '0;
                    if (!rx_sync2) state <= S_START_BIT;
                    else           state <= S_IDLE;
                end

                // Sample at the MIDDLE of the start bit to confirm it's real
                // (rejects glitches shorter than half a bit period)
                S_START_BIT: begin
                    if (clk_count == (div >> 1) - 1) begin
                        if (!rx_sync2) begin
                            clk_count <= '0;
                            state     <= S_DATA_BITS;
                        end else begin
                            state <= S_IDLE;   // false start, glitch - abort
                        end
                    end else begin
                        clk_count <= clk_count + 16'd1;
                    end
                end

                // Sample each of the 8 data bits at the middle of its period
                S_DATA_BITS: begin
                    if (clk_count < div - 1) begin
                        clk_count <= clk_count + 16'd1;
                    end else begin
                        clk_count               <= '0;
                        rx_shift_reg[bit_index] <= rx_sync2;
                        if (bit_index < 3'd7) begin
                            bit_index <= bit_index + 3'd1;
                        end else begin
                            bit_index <= '0;
                            state     <= S_STOP_BIT;
                        end
                    end
                end

                // Confirm stop bit is '1' - if not, flag a framing error
                S_STOP_BIT: begin
                    if (clk_count < div - 1) begin
                        clk_count <= clk_count + 16'd1;
                    end else begin
                        framing_error <= !rx_sync2;
                        state         <= S_CLEANUP;
                    end
                end

                // One-cycle pulse announcing the received byte, then back to idle
                S_CLEANUP: begin
                    rx_valid <= 1'b1;
                    rx_data  <= rx_shift_reg;
                    state    <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
