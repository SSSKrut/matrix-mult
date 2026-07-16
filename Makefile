IVERILOG  ?= iverilog -g2012
VVP       ?= vvp
VERILATOR ?= verilator

SRC = matmul.v tb_matmul.v

# геометрии для прогона: M-K-N
GEOMS = 3-4-2 1-1-1 5-1-3 2-8-2 4-4-4

geom_M = $(word 1,$(subst -, ,$*))
geom_K = $(word 2,$(subst -, ,$*))
geom_N = $(word 3,$(subst -, ,$*))

all: lint test test-vl test-py test-py-vl

lint:
	$(VERILATOR) --lint-only -Wall --top-module matmul matmul.v

# --- Icarus Verilog ---
test: $(GEOMS:%=test-%)

test-%: $(SRC)
	$(IVERILOG) -o sim_$* \
	    -Ptb_matmul.M=$(geom_M) \
	    -Ptb_matmul.K=$(geom_K) \
	    -Ptb_matmul.N=$(geom_N) \
	    $(SRC)
	$(VVP) sim_$*

# --- Verilator ---
test-vl: $(GEOMS:%=test-vl-%)

test-vl-%: $(SRC)
	$(VERILATOR) --binary --timing --quiet -Wno-fatal \
	    -GM=$(geom_M) -GK=$(geom_K) -GN=$(geom_N) \
	    --top-module tb_matmul --Mdir obj_vl_$* -o sim $(SRC)
	./obj_vl_$*/sim

# --- cocotb (Python) ---
test-py: $(GEOMS:%=test-py-%)

test-py-%:
	$(MAKE) -C tests SIM=icarus M=$(geom_M) K=$(geom_K) N=$(geom_N)

test-py-vl:
	$(MAKE) -C tests SIM=verilator

wave: $(SRC)
	$(IVERILOG) -o sim_wave $(SRC)
	$(VVP) sim_wave +dump

clean:
	rm -f sim_* tb_matmul.vcd
	rm -rf obj_dir obj_vl_*
	rm -rf tests/sim_build tests/__pycache__ tests/results.xml

.PHONY: all lint test test-vl test-py test-py-vl wave clean
