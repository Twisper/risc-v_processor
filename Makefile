SVC ?= iverilog
SVC_FLAGS = -g2012 -Wall -Wno-timescale -o

VTR ?= verilator
VTR_FLAGS = --lint-only -Wall

WAVES ?= gtkwave

TB_DIR = ./dv/testbenches
CORE_DIR = ./rtl/core
SIMS_DIR = ./dv/simulations

PKG_SRC = $(CORE_DIR)/riscv_pkg.sv

CORE_SRCS = \
	$(CORE_DIR)/adder.sv \
	$(CORE_DIR)/shifter.sv \
	$(CORE_DIR)/b_extension.sv \
	$(CORE_DIR)/alu.sv

TB_ALU_SRC = $(TB_DIR)/tb_alu.sv

ALU_SRCS = $(PKG_SRC) $(CORE_SRCS) $(TB_ALU_SRC)

OUT_ALU = $(SIMS_DIR)/sim_alu.vvp

all: alu_compile alu_run

alu_check: $(CORE_SRCS)
	$(VTR) $(VTR_FLAGS) $(CORE_SRCS)

alu_compile: $(CORE_SRCS) $(TB_ALU_SRCS)
	$(SVC) $(SVC_FLAGS) $(OUT_ALU) $(CORE_SRCS)

alu_run: $(OUT_ALU)
	vvp $(OUT_ALU)

waves_alu: 
	$(WAVES) dump.vcd &

clean_alu:
	rm -f $(OUT_ALU) dump.vcd