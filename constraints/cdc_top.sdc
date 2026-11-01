# cdc_top.sdc - timing constraints for the async FIFO block.
# Units follow the library: ns and fF.

set WCLK_PERIOD 2.00
set RCLK_PERIOD 2.50

create_clock -name wclk -period $WCLK_PERIOD [get_ports wclk]
create_clock -name rclk -period $RCLK_PERIOD [get_ports rclk]
set_clock_uncertainty 0.05 [all_clocks]

# inputs and outputs of each domain, timed against their own clock
set_input_delay  0.20 -clock wclk [get_ports {winc wdata[*]}]
set_output_delay 0.20 -clock wclk [get_ports wfull]
set_input_delay  0.20 -clock rclk [get_ports rinc]
set_output_delay 0.20 -clock rclk [get_ports {rdata[*] rempty}]

set_driving_cell -lib_cell BUF_X1 [all_inputs]
set_load 2.0 [all_outputs]

# raw reset is asynchronous; the reset synchronizers handle it
set_false_path -from [get_ports arst_n]
