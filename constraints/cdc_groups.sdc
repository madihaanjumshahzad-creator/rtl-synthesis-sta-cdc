# wclk and rclk are unrelated. Crossings go through the 2-flop synchronizers
# or are safe by the FIFO protocol (memory read), so don't time them.
set_clock_groups -asynchronous -group {wclk} -group {rclk}
