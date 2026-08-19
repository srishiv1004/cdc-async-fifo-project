# CDC-Safe UART-to-Memory Bridge — RTL to GDSII Project

A UART-to-memory bridge that deliberately forces a clock-domain-crossing
(CDC) problem: bytes arrive on a slow UART clock and must safely cross into
a faster memory-write clock domain. Verified using lint, functional
simulation, and formal CDC property checking, and being carried through
synthesis and physical design on an open-source RTL-to-GDSII flow.

RTL design, integration, functional verification, lint, and formal CDC
verification are complete. Synthesis, place & route, and physical
verification (DRC/LVS/ERC) are in progress.

## Why an async FIFO

Crossing data between two independent clock domains without proper
synchronization is one of the most common sources of real silicon bugs.
Naively passing a multi-bit signal across a clock boundary risks bit-level
corruption if a synchronizing flip-flop samples mid-transition. This project
uses the industry-standard approach (Cummings, SNUG 2002): gray-coded
pointers, 2-flop synchronizers, and registered full/empty flags.

## Design

- **`uart_rx.sv`** — UART receiver (8N1 framing), slow write-clock domain.
  Mid-bit sampling, start-bit glitch rejection, framing error detection.
- **`async_fifo.sv`** — parameterized async FIFO (`DATA_WIDTH`, `ADDR_WIDTH`)
  with gray-coded write/read pointers, 2-flop synchronizers crossing the CDC
  boundary, and registered `wr_full` / `rd_empty` flags. This is the CDC
  boundary of the whole design.
- **`write_ctrl.sv`** — fast read-clock domain, greedily consumes from the
  FIFO and writes each byte into memory at an auto-incrementing address.
- **`mem_model.sv`** — simple synchronous memory with a write port (driven
  by `write_ctrl`) and a read port (for verification / future host access).
- **`top.sv`** — wires the above into one complete system:
  `uart_rx (wr_clk) -> async_fifo (CDC boundary) -> write_ctrl (rd_clk) -> mem_model`.

Testbenches: `tb_async_fifo.sv`, `tb_uart_rx.sv`, `tb_write_ctrl.sv` test
each block individually; `tb_top.sv` drives real UART serial bits through
the entire chain end-to-end and verifies the bytes land correctly in memory
after crossing the CDC boundary - all 4 bytes of a test pattern (`DE AD BE
EF`) traveled UART -> FIFO -> memory correctly on the first integration
attempt, since each block was already individually verified before wiring
them together.

## Bugs found and fixed along the way

Documenting these because the debugging process is the actual point of a CDC
project — anyone can claim "I built a CDC-safe FIFO," this is the evidence.

1. **Zero-delay combinational loop.** The initial `wr_full`/`rd_empty` logic
   gated the pointer's own next-state calculation, creating a feedback loop
   with no register in it. Caught via simulator deadlock (`iteration limit
   reached`) in ModelSim. Fixed by removing the internal gating — pointer
   increment is now the writer/reader's responsibility, matching standard
   FIFO interface contracts.
2. **Testbench protocol violation.** After fixing (1), the writer testbench
   kept `wr_en` asserted while stalled on `wr_full`, causing the write
   pointer to race ahead uncontrolled. Fixed by deasserting `wr_en` during
   the stall — a good illustration of why "never assert `wr_en` while full"
   is a hardware contract, not a suggestion.
3. **Registered vs. combinational flag mismatch.** The read side stalled
   permanently after 8 of 20 words. Root cause: `rd_empty` was raw
   combinational look-ahead logic, but the reader used a one-cycle-delayed
   registered enable — the two fell permanently out of phase once the write
   rate slowed relative to the read clock. Fixed by registering `wr_full`
   and `rd_empty` as flip-flop outputs (Cummings-style), which is what makes
   them safe for external logic to consume combinationally.

## Verification status

| Stage | Tool | Result |
|---|---|---|
| Functional simulation — per block | ModelSim / Icarus Verilog | FIFO: 20/20 words correct. UART RX: 2/2 test bytes decoded correctly. Write controller: 5/5 bytes written to memory correctly. |
| Functional simulation — full integration | Icarus Verilog, `tb_top.sv`, two independent clocks | All 4 bytes of test pattern traveled UART → FIFO → memory correctly, end-to-end |
| Lint | Verilator (`--lint-only -Wall`) | Clean, 0 warnings across all blocks ([FIFO](lint_verilator.log), [top-level](lint_top_verilator.log)) |
| Lint | Verible (`verilog-lint`) | Clean, 0 warnings across all blocks ([FIFO](lint_verible.log), [top-level](lint_top_verible.log)) |
| Formal CDC check | SymbiYosys, bounded model checking (Yices) | **Passed** on correct design ([log](formal_correct.log)); **caught** a deliberately-injected CDC bug ([log](formal_buggy.log)) |
| Synthesis → GDSII | Yosys → OpenLane/OpenROAD, sky130 PDK | Next |
| DRC (design rule check) | Magic | Planned |
| LVS (layout vs. schematic) | Netgen | Planned |
| ERC (electrical rule check) | Magic / OpenROAD | Planned |

## Formal CDC verification

The pointer/synchronizer logic was extracted from `async_fifo.sv` into its own
module, `gray_ptr_sync.sv`, deliberately excluding the memory array - proving
properties on the full FIFO (with memory) overwhelmed the SMT solver, while
the extracted synchronizer alone verifies in seconds. This mirrors how real
CDC signoff tools scope their checks to the synchronizer itself.

Two properties are formally proven (see `` `ifdef FORMAL `` block in
`gray_ptr_sync.sv`):

1. The signal fed into the synchronizer changes by at most one bit per
   source-clock cycle - the property that makes gray coding safe for
   crossing clock domains.
2. The synchronizer is genuinely two register stages deep.

`gray_ptr_sync_buggy.sv` is an intentionally broken copy - the synchronizer
is fed the raw binary pointer instead of the gray-coded one, a classic real
CDC mistake. SymbiYosys catches this and fails in a handful of cycles
([log](formal_buggy.log)), confirming the check has real teeth rather than
passing on the correct design by coincidence.

One property that was tried and *removed*: asserting the synchronized output
itself changes by at most one bit between destination-clock samples. This
was disproven by SymbiYosys in ~7 seconds - it implicitly assumed the
destination clock is always at least as fast as the source, which isn't true
for two fully independent clocks. Left out deliberately rather than patched
with an artificial rate assumption.

## Tools

Verilator, Verible, SymbiYosys, Yosys, OpenLane, OpenROAD, Magic, and Netgen
via [iic-osic-tools](https://github.com/iic-jku/iic-osic-tools). Functional
simulation cross-checked in both ModelSim and Icarus Verilog.

## Running it yourself

```bash
# Functional simulation - individual FIFO
iverilog -g2012 -o sim.out async_fifo.sv tb_async_fifo.sv
vvp sim.out

# Functional simulation - full end-to-end integration
iverilog -g2012 -o top_sim.out top.sv async_fifo.sv uart_rx.sv write_ctrl.sv mem_model.sv tb_top.sv
vvp top_sim.out

# Lint
verilator --lint-only -Wall -sv top.sv async_fifo.sv uart_rx.sv write_ctrl.sv mem_model.sv
verible-verilog-lint top.sv async_fifo.sv uart_rx.sv write_ctrl.sv mem_model.sv
```
