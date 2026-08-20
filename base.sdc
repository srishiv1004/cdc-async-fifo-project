# =============================================================================
# base.sdc
#
# Timing constraints for OpenLane. Declares both clock domains and marks
# them as asynchronous to each other - without this, static timing analysis
# would try to check setup/hold timing BETWEEN wr_clk and rd_clk as if data
# had to travel directly from one to the other in a single cycle, which is
# never true in a correctly-built CDC design (the async_fifo's synchronizer
# is what actually handles the crossing safely, not a same-cycle timing
# path). This would otherwise show up as a wall of false failing paths.
# =============================================================================

# Slow domain: 25 MHz -> 40 ns period
create_clock -name wr_clk -period 40 [get_ports wr_clk]

# Fast domain: 100 MHz -> 10 ns period (rounded from ~100.7 MHz used in sim)
create_clock -name rd_clk -period 10 [get_ports rd_clk]

# The critical line: tell STA these two clocks are unrelated, so it does not
# attempt to time paths crossing between them directly.
set_clock_groups -name async_domains -asynchronous -group {wr_clk} -group {rd_clk}

set_input_delay 0 -clock wr_clk [get_ports rx_serial]
set_input_delay 0 -clock rd_clk [get_ports mem_rd_addr]
set_output_delay 0 -clock rd_clk [get_ports mem_rd_data]
