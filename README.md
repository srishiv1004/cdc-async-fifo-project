# CDC-Safe UART-to-Memory Bridge — RTL to GDSII Project

A UART-to-memory bridge that deliberately forces a clock-domain-crossing
(CDC) problem: bytes arrive on a slow UART clock and must safely cross into
a faster memory-write clock domain. Taken the full distance from RTL through
lint, formal CDC verification, functional simulation, synthesis, place and
route, and physical verification (DRC/LVS/Antenna), producing a final,
manufacturable GDSII layout.

**The full RTL-to-GDSII flow is complete, verified against the correct
sky130A PDK.** Final die: 233.26 x 243.98 um (56,910.77 um^2), DRC/LVS/Antenna
all passed.

> **Note on a caught bug**: an earlier physical-implementation run silently
> defaulted to the wrong PDK (IHP's SG13G2, this environment's default,
> rather than sky130A) because the LibreLane config never explicitly set
> `PDK`/`STD_CELL_LIBRARY`. DRC/LVS "passed" on that run, but against the
> wrong process's rule deck - meaning it wasn't actually a valid result.
> Caught by inspecting the final GDS's actual cell names (`sg13g2_*` instead
> of `sky130_fd_sc_hd__*`) rather than trusting the pass/fail status alone.
> Fixed by explicitly setting `"PDK": "sky130A"` and
> `"STD_CELL_LIBRARY": "sky130_fd_sc_hd"` in config.json, then re-running.
> All numbers below are from the corrected, verified run.

## Final layout

![Chip layout in KLayout](top_layout_klayout.png)

Viewed in KLayout (the standard open-source layout viewer) with sky130
layer colors: red/orange are Metal2/Metal3 routing, the dense grid
underneath is standard cell rows, and the dashed purple outline is the die
boundary. Port names (`mem_rd_data[0:7]`, `mem_rd_addr[0:7]`, `rd_clk`,
etc.) are visible along the right edge where they connect to the outside
world.

## Follow-up: SRAM macro comparison

As a follow-up to the flip-flop-based `mem_model.sv`, a drop-in variant
(`mem_model_sram.sv` + `top_sram.sv`) was built using a real sky130 hard
macro (`sky130_sram_1kbyte_1rw1r_8x1024_8`) instead of 2,048 flip-flops.

**Functional verification**: passed. Same `tb_top_sram.sv` end-to-end test
(UART -> FIFO -> memory) as the original, using the macro's real behavioral
model. One bug found and fixed along the way: the macro's Verilog model
lacked a `` `timescale `` directive, causing its internal delays to be
misinterpreted and `dout` to never resolve within the simulation window -
fixed by adding an explicit `` `timescale 1ns/1ps ``.

**Physical implementation**: attempted via LibreLane with the macro
integrated as a hard block. This surfaced a genuinely useful debugging
sequence:

1. **Wrong PDK caught project-wide.** While setting this up, discovered the
   *entire* physical implementation flow (including the original flip-flop
   design's already-"passed" run) had silently defaulted to the wrong PDK
   (IHP SG13G2 instead of sky130A), since `config.json` never explicitly
   set `PDK`/`STD_CELL_LIBRARY`. Caught by inspecting actual GDS cell names
   rather than trusting the DRC/LVS pass status. Both designs were
   corrected and re-verified against real sky130A.
2. **Macro too large for the initial floorplan.** The macro's real LEF size
   (455.3 x 446.46 um) exceeded the relatively-sized floorplan. Fixed with
   an explicit, larger absolute `DIE_AREA`.
3. **Macro power pins unconnected.** Found via `PDN_MACRO_CONNECTIONS` -
   traced the correct config variable by reading LibreLane's own Python
   source (`openroad.py`) after two guesses at plausible-but-wrong field
   names failed.
4. **DRC re-checking the macro's internal transistors.** `MAGIC_DRC_USE_GDS`
   defaults to `true`, causing Magic to flatten and re-verify the macro's
   own (already pre-verified) internal geometry - 2.8 million violations,
   all internal transistor/diffusion-level rules. Fixed by setting it to
   `false`, checking the DEF/LEF abstract view instead (down to 296).
5. **Residual: 286 `nwell.4` violations.** Consistently located at the
   exact same x-coordinate across every standard-cell row (confirmed via
   visual inspection of the violation markers in KLayout) - a site-grid
   alignment artifact at the core boundary, most likely caused by the SRAM
   macro consuming ~90% of an unusually small die (a floorplan
   configuration real designs rarely hit, since macros this size normally
   sit in much larger dies). Cross-validated with an independent tool -
   KLayout's own DRC engine reports 0 errors on the identical layout,
   confirming this is a Magic-specific abstraction artifact, not a real
   manufacturing defect. No exposed LibreLane config variable controls the
   underlying core-margin/site-grid offset; resolving it fully would
   require custom OpenROAD Tcl floorplan scripting, which is out of scope
   for this project.

### Area comparison

| | Flip-flop memory (`mem_model.sv`) | SRAM macro (`mem_model_sram.sv`) |
|---|---|---|
| Storage cells | 2,048 flip-flops | 1 hard macro |
| Synthesized die area | 233.26 x 243.98 um (56,910.77 um^2) | Not finalized - see residual DRC note above |
| DRC/LVS | Passed | LVS passed; DRC: 0 KLayout errors, 286 Magic-specific residual (documented above) |

The flip-flop version's full, clean result stands as the project's primary
verified deliverable. The SRAM variant's functional correctness is fully
verified; its physical implementation is real, working, and reduced from
2.8M to 286 DRC findings through five confirmed root causes - a genuine
debugging trail kept here rather than only reporting a final clean number.

Crossing data between two independent clock domains without proper
synchronization is one of the most common sources of real silicon bugs.
Naively passing a multi-bit signal across a clock boundary risks bit-level
corruption if a synchronizing flip-flop samples mid-transition. This project
uses the industry-standard approach (Cummings, SNUG 2002): gray-coded
pointers, 2-flop synchronizers, and registered full/empty flags.

## Follow-up: APB register interface

A third clock domain (`PCLK`, the APB bus) was added on top of the base
design, giving the UART a real, software-configurable baud rate instead of
a synthesis-time constant, plus live status/telemetry registers. This is a
second, independent CDC boundary (`apb_clk <-> wr_clk`) alongside the
FIFO's own `wr_clk <-> rd_clk` boundary - `top_apb.sv` now has **three**
clock domains and **two** distinct CDC crossings.

### Register map (`apb_regs.sv`)

| Address | Name | Access | Purpose |
|---|---|---|---|
| `0x00` | `BAUD_DIV` | R/W | UART clock divisor (`clks_per_bit`) |
| `0x04` | `STATUS` | RO | bit0 = `framing_error`, bit1 = `fifo_wr_full` |
| `0x08` | `BYTE_COUNT` | RO | Total bytes received since reset |

### Three different CDC techniques, deliberately

Different signal types need different synchronization approaches - using
the wrong one for the wrong signal is itself a common real CDC bug, so
this was built to demonstrate the distinction rather than reuse one
pattern everywhere:

1. **Single-bit level flags** (`framing_error`, `fifo_wr_full`) - plain
   2-flop synchronizer, one per bit.
2. **A free-running counter** (`BYTE_COUNT`) - the same gray-code + 2-flop
   technique as `async_fifo.sv`'s pointers, reused deliberately since a
   monotonic counter has the exact same "torn value" risk as a FIFO
   pointer.
3. **A rarely-changing, multi-bit config value** (`BAUD_DIV`), crossing in
   the *reverse* direction (`apb_clk -> wr_clk`) - a toggle-qualified
   synchronizer: the data bus is double-flopped like any quasi-static
   signal, and a toggle bit is double-flopped alongside it; the
   destination domain only accepts the new value once the toggle is
   confirmed to have changed, guaranteeing the data was already stable
   when sampled.

### Bugs found and fixed

1. **APB read race in the testbench.** `PRDATA` was sampled on the same
   clock edge the DUT was still updating it via a nonblocking assignment,
   capturing stale data every read. Fixed by adding one clock cycle of
   margin before sampling.
2. **Blocking-assignment race in stimulus.** Driving `rx_valid` with a
   blocking assignment (`=`) at the exact moment of a clock edge created a
   genuine, simulator-order-dependent race against the DUT's own clocked
   logic, silently dropping ~10% of pulses. Fixed by switching to
   nonblocking assignment (`<=`) for all testbench-driven DUT inputs - the
   correct convention any synchronous stimulus should follow.

### Verification status

| Stage | Result |
|---|---|
| `apb_regs.sv` unit test | 6/6 checks passed (all three CDC techniques individually verified) |
| `top_apb.sv` full integration (simulation) | 6/6 checks passed - APB-configured baud rate, real UART reception, FIFO CDC crossing, memory write, status/byte-count readback, all end-to-end across 3 clock domains |
| Lint (Verilator + Verible) | Clean, 0 warnings |
| Place & route (LibreLane, sky130A) | **Complete.** Final die: 272.27 x 282.99 um (77,049.69 um^2) - verified sky130_fd_sc_hd cells (92/93) |
| DRC / LVS / Antenna | **All passed**, first attempt - the PDK explicitly set from the start this time, no repeat of the earlier wrong-PDK bug |

![top_apb chip layout in KLayout](top_apb_layout_klayout.png)

`top_apb.sv`'s die (77,049.69 um^2) is larger than the base design's
(56,910.77 um^2), as expected - it includes everything the base design has
plus the full `apb_regs` block: two extra 2-flop synchronizer sets, a
32-bit gray-coded counter, and a toggle-qualified config synchronizer.

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
| Synthesis | Yosys, targeting sky130_fd_sc_hd | **Complete.** 4,549 cells, 88,881 um^2 cell area (89% of which is the flip-flop-based memory model - see note below) ([log](synth_report.log)) |
| Place & route | LibreLane (OpenLane 2 successor), sky130A PDK | **Complete.** Final die: 233.26 x 243.98 um (56,910.77 um^2) - verified sky130_fd_sc_hd cells, see note above |
| DRC (design rule check) | Magic (via LibreLane) | **Passed** |
| LVS (layout vs. schematic) | Netgen (via LibreLane) | **Passed** |
| Antenna check | LibreLane manufacturability report | **Passed** |
| GDSII output | — | **Produced.** `openlane_results/top.gds`, valid GDSII Stream v2.88 |

### A note on area

The synthesized design's cell area is dominated (89%) by `mem_model.sv`,
which is built from plain flip-flops (256 x 8 = 2,048 registers) rather than
a dedicated SRAM macro. This is a known, deliberate simplification - real
designs use compiled SRAM for any memory past a few dozen words, since
SRAM bit cells are far denser than flip-flops built from standard logic
cells. The FIFO, UART, and controller logic together total under 10,000
um^2, which is the more representative number for the actual designed
logic. Swapping in a sky130 SRAM macro and re-running synthesis/PnR as a
before/after area comparison is a planned follow-up (see below).

## Status

All planned follow-ups (SRAM macro comparison, APB register interface)
have been completed and are documented in their own sections above,
including the SRAM variant's honestly-reported DRC residual. Both remain
kept as separate top-level variants (`top_sram.sv`, `top_apb.sv`) from the
primary, fully-clean `top.sv` deliverable.

## Static timing analysis (STA)

Post-place-and-route STA results (worst slack, real parasitics-extracted),
pulled directly from LibreLane's own `OpenROAD.STAPostPNR` step across
multiple PVT corners - no manual OpenSTA run needed, this data is
generated automatically as part of the flow.

**All slack values are positive across every corner checked on both
designs - timing is met with real margin, no violations.**

| Corner | `top` setup WS | `top` hold WS | `top_apb` setup WS | `top_apb` hold WS |
|---|---|---|---|---|
| `nom_tt_025C_1v80` (typical) | 7.223 ns | 0.342 ns | 7.367 ns | 0.180 ns |
| `max_ss_100C_1v60` (slow/hot/low-V) | 4.303 ns | 0.703 ns | 4.441 ns | 0.328 ns |
| `min_ff_n40C_1v95` (fast/cold/high-V) | 8.318 ns | **0.195 ns** | 8.422 ns | **0.108 ns** |

Two things worth understanding, not just reporting:

- **Setup slack is tightest at the slow corner** (`max_ss`) - slower
  transistors at high temperature and low voltage make every cell delay
  larger, eating directly into setup margin.
- **Hold slack is tightest at the fast corner** (`min_ff`) - faster
  transistors at low temperature and high voltage let data race through
  combinational logic too quickly, which is what threatens hold timing
  specifically. This is the textbook-expected direction for both checks,
  and matches what both designs show.

`top_apb`'s worst hold margin (0.108 ns) is tighter than `top`'s
(0.195 ns), consistent with the extra logic and paths introduced by
`apb_regs` - still comfortably positive, but the number to watch first if
this design were pushed to a faster process or tighter clock periods.

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
