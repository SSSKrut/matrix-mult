SIM ?= icarus
TOPLEVEL_LANG ?= verilog

M ?= 3
K ?= 4
N ?= 2

VERILOG_SOURCES = $(CURDIR)/../matmul.v
COCOTB_TOPLEVEL = matmul
COCOTB_TEST_MODULES = test_matmul

export MATMUL_M = $(M)
export MATMUL_K = $(K)
export MATMUL_N = $(N)

ifeq ($(SIM),icarus)
    COMPILE_ARGS += -Pmatmul.M=$(M) -Pmatmul.K=$(K) -Pmatmul.N=$(N)
else ifeq ($(SIM),verilator)
    EXTRA_ARGS += -GM=$(M) -GK=$(K) -GN=$(N)
endif

SIM_BUILD = sim_build/$(SIM)_$(M)-$(K)-$(N)

include $(shell cocotb-config --makefiles)/Makefile.sim
