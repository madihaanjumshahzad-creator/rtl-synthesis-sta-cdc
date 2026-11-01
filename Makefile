# RTL to timing: CDC design, simulation, synthesis and STA with free tools.
#
#   make lib    download the Nangate 45 nm open cell library (once)
#   make lint   Verilator lint
#   make sim    cocotb tests of the async FIFO (Icarus Verilog)
#   make synth  Yosys synthesis of cdc_top and mac_accel
#   make sta    OpenSTA timing of both netlists
#   make all    everything above except lib

LIB_URL = https://raw.githubusercontent.com/The-OpenROAD-Project/OpenROAD-flow-scripts/master/flow/platforms/nangate45/lib/NangateOpenCellLibrary_typical.lib
LIB     = lib/NangateOpenCellLibrary_typical.lib
TOPS    = cdc_top mac_accel

.PHONY: all lib lint sim synth sta clean

all: lint sim synth sta

lib: $(LIB)
$(LIB):
	mkdir -p lib
	curl -sSfL -o $@ $(LIB_URL)

lint:
	verilator --lint-only -Wall --top-module cdc_top rtl/cdc_top.v rtl/async_fifo.v rtl/sync_2ff.v rtl/reset_sync.v
	verilator --lint-only -Wall rtl/mac_accel.v

sim:
	$(MAKE) -C tests

synth: $(LIB)
	for t in $(TOPS); do TOP=$$t yosys -q -c syn/synth.tcl || exit 1; done

sta: synth
	for t in $(TOPS); do TOP=$$t sta -no_splash -exit sta/sta.tcl || exit 1; done

clean:
	rm -rf build tests/sim_build tests/results.xml tests/__pycache__
