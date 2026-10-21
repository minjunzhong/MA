SIM ?= icarus
TOPLEVEL_LANG = verilog
TOPLEVEL = eyeriss_four_cluster
MODULE = test_four_cluster
export PYTHONPATH := $(CURDIR)/tests:$(PYTHONPATH)
ifeq ($(TDD_RED),1)
VERILOG_SOURCES = $(CURDIR)/tests/red_stub.sv
else
VERILOG_SOURCES = $(CURDIR)/rtl/eyeriss_pe.sv $(CURDIR)/rtl/eyeriss_four_cluster.sv
endif
COMPILE_ARGS += -g2012
include $(shell cocotb-config --makefiles)/Makefile.sim
