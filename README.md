# CDC-Safe Async FIFO — RTL to GDSII Project

A dual-clock-domain async FIFO built as the foundation of a larger project: a
UART-to-memory bridge that deliberately forces a clock-domain-crossing (CDC)
problem, verified using lint, functional simulation, and (in progress) formal
CDC property checking, then carried through synthesis and physical design on
an open-source RTL-to-GDSII flow.

This repo currently covers the CDC-critical block — the async FIFO — through
RTL design, functional verification, and lint. Later stages (formal CDC
checks, synthesis, place & route, DRC/LVS) will be added as the project
progresses.

## Why an async FIFO

Crossing data between two independent clock domains without proper
synchronization is one of the most common sources of real silicon bugs.
Naively passing a multi-bit signal across a clock boundary risks bit-level
corruption if a synchronizing flip-flop samples mid-transition. This project
uses the industry-standard approach (Cummings, SNUG 2002): gray-coded
pointers, 2-flop synchronizers, and registered full/empty flags.

## Design

- **`async_fifo.sv`** — parameterized async FIFO (`DATA_WIDTH`, `ADDR_WIDTH`)
  with gray-coded write/read pointers, 2-flop synchronizers crossing the CDC
  boundary, and registered `wr_full` / `rd_empty` flags.
- **`tb_async_fifo.sv`** — testbench driving the FIFO with two independent,
  non-integer-ratio clocks (25 MHz write side, ~100.7 MHz read side) to
  exercise real phase-varying crossings, with a self-checking scoreboard.

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
| Functional simulation | ModelSim / Icarus Verilog, two independent clocks | All 20 words read back correctly |
| Lint | Verilator (`--lint-only -Wall`) | Clean, 0 warnings ([log](lint_verilator.log)) |
| Lint | Verible (`verilog-lint`) | Clean, 0 warnings ([log](lint_verible.log)) |
| Formal CDC check | SymbiYosys (SVA properties) | In progress |
| Synthesis → GDSII | Yosys → OpenLane/OpenROAD, sky130 PDK | Planned |
| DRC / LVS | Magic / Netgen | Planned |

## Tools

Verilator, Verible, SymbiYosys, Yosys, OpenLane, OpenROAD, Magic, and Netgen
via [iic-osic-tools](https://github.com/iic-jku/iic-osic-tools). Functional
simulation cross-checked in both ModelSim and Icarus Verilog.

## Running it yourself

```bash
# Functional simulation (Icarus Verilog)
iverilog -g2012 -o sim.out async_fifo.sv tb_async_fifo.sv
vvp sim.out

# Lint
verilator --lint-only -Wall -sv async_fifo.sv
verible-verilog-lint async_fifo.sv
```
