// =============================================================================
// sram_blackbox.v
//
// Synthesis-only blackbox stub for sky130_sram_1kbyte_1rw1r_8x1024_8.
// Same port list as the real macro's behavioral model, but no internal
// logic - this tells Yosys not to try to synthesize the SRAM from gates.
// The real physical macro (GDS/LEF) is placed as a fixed hard block during
// place & route instead. Not used for functional simulation - the full
// behavioral model (sky130_sram_1kbyte_1rw1r_8x1024_8.v) is used for that.
// =============================================================================

(* blackbox *)
module sky130_sram_1kbyte_1rw1r_8x1024_8 (
    clk0, csb0, web0, wmask0, addr0, din0, dout0,
    clk1, csb1, addr1, dout1
);
    parameter NUM_WMASKS = 1;
    parameter DATA_WIDTH = 8;
    parameter ADDR_WIDTH = 10;

    input  clk0;
    input  csb0;
    input  web0;
    input  [NUM_WMASKS-1:0] wmask0;
    input  [ADDR_WIDTH-1:0] addr0;
    input  [DATA_WIDTH-1:0] din0;
    output [DATA_WIDTH-1:0] dout0;

    input  clk1;
    input  csb1;
    input  [ADDR_WIDTH-1:0] addr1;
    output [DATA_WIDTH-1:0] dout1;

endmodule
