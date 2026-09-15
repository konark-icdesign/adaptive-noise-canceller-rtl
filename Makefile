BUILD_DIR := build
RTL := rtl/lms_adaptive_filter.v
TB := tb/tb_lms_adaptive_filter.v
SIM := $(BUILD_DIR)/lms_tb
REF := $(BUILD_DIR)/lms_reference
CC ?= gcc
CFLAGS ?= -std=c11 -Wall -Wextra -O2

.PHONY: all test sim wave reference clean

all: test

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

sim: $(BUILD_DIR)
	iverilog -g2012 -Wall -o $(SIM) $(RTL) $(TB)

test: sim
	vvp $(SIM)

reference: $(BUILD_DIR)
	$(CC) $(CFLAGS) model/lms_reference.c -o $(REF)
	$(REF)

wave: test
	gtkwave $(BUILD_DIR)/lms.vcd

clean:
	rm -rf $(BUILD_DIR)
