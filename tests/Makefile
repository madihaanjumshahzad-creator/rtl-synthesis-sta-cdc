SIM ?= icarus
TOPLEVEL_LANG = verilog
VERILOG_SOURCES = $(PWD)/../rtl/cdc_top.v $(PWD)/../rtl/async_fifo.v \
                  $(PWD)/../rtl/sync_2ff.v $(PWD)/../rtl/reset_sync.v
TOPLEVEL = cdc_top
MODULE = test_async_fifo
include $(shell cocotb-config --makefiles)/Makefile.sim
