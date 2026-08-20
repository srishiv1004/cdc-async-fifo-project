# =============================================================================
# base_apb.sdc
#
# Timing constraints for top_apb - THREE clock domains this time, all
# mutually asynchronous. Same reasoning as base.sdc: without declaring
# these asynchronous, STA would try to time paths directly between domains
# that only ever communicate through synchronizers, producing a wall of
# false failing paths.
# =============================================================================

# Slow domain: 25 MHz -> 40 ns period
create_clock -name wr_clk -period 40 [get_ports wr_clk]

# Fast domain: 100 MHz -> 10 ns period
create_clock -name rd_clk -period 10 [get_ports rd_clk]

# APB domain: 50 MHz -> 20 ns period
create_clock -name PCLK -period 20 [get_ports PCLK]

# All three are mutually asynchronous - none of them communicate directly,
# only through the FIFO's and apb_regs's synchronizers.
set_clock_groups -name async_domains -asynchronous \
    -group {wr_clk} -group {rd_clk} -group {PCLK}

set_input_delay 0 -clock wr_clk [get_ports rx_serial]
set_input_delay 0 -clock rd_clk [get_ports mem_rd_addr]
set_output_delay 0 -clock rd_clk [get_ports mem_rd_data]
set_input_delay 0 -clock PCLK [get_ports PADDR]
set_input_delay 0 -clock PCLK [get_ports PWRITE]
set_input_delay 0 -clock PCLK [get_ports PWDATA]
set_input_delay 0 -clock PCLK [get_ports PSEL]
set_input_delay 0 -clock PCLK [get_ports PENABLE]
set_output_delay 0 -clock PCLK [get_ports PRDATA]
set_output_delay 0 -clock PCLK [get_ports PREADY]
