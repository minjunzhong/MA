SIM ?= icarus
TOPLEVEL_LANG = verilog
TOPLEVEL = eyeriss_four_cluster
MODULE = test_four_cluster
export PYTHONPATH := $(CURDIR)/tests:$(PYTHONPATH)
ifeq ($(TDD_RED),1)
VERILOG_SOURCES = $(CURDIR)/tests/red_stub.sv
else
VERILOG_SOURCES = $(CURDIR)/rtl/eyeriss_pe.sv $(CURDIR)/rtl/eyeriss_cluster.sv $(CURDIR)/rtl/eyeriss_four_cluster.sv
endif
COMPILE_ARGS += -g2012
include $(shell cocotb-config --makefiles)/Makefile.sim

.PHONY: test lint
test: sim
	python3 scripts/check_results.py results.xml

# Reset qualifies unreset scratchpad writes synchronously and accumulator reset
# asynchronously, deliberately; all other -Wall diagnostics remain fatal.
lint:
	verilator --lint-only -Wall -Wno-SYNCASYNCNET --top-module $(TOPLEVEL) $(VERILOG_SOURCES)
