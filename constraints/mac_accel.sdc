# mac_accel.sdc - single clock domain.
set CLK_PERIOD 5.00
create_clock -name clk -period $CLK_PERIOD [get_ports clk]
set_clock_uncertainty 0.05 [all_clocks]
set_input_delay  0.20 -clock clk [delete_from_list [all_inputs] [get_ports {clk resetn}]]
set_output_delay 0.20 -clock clk [all_outputs]
set_driving_cell -lib_cell BUF_X1 [all_inputs]
set_load 2.0 [all_outputs]
set_false_path -from [get_ports resetn]
