BUILD_DIR := build
RTL := rtl/lms_adaptive_filter.v
TB := tb/tb_lms_adaptive_filter.v
SIM := $(BUILD_DIR)/lms_tb
PARITY_SIM := $(BUILD_DIR)/lms_parity_tb
SERIAL_PARITY_SIM := $(BUILD_DIR)/lms_serial_parity_tb
PIPELINED_PARITY_SIM := $(BUILD_DIR)/lms_pipelined_parity_tb
STREAM_PARITY_SIM := $(BUILD_DIR)/lms_stream_parity_tb
STREAM_48K_SIM := $(BUILD_DIR)/lms_stream_48k_tb
I2S_INGRESS_SIM := $(BUILD_DIR)/lms_i2s_input_tb
I2S_OVERRUN_SIM := $(BUILD_DIR)/i2s_rx_overrun_tb
REF := $(BUILD_DIR)/lms_reference
CC ?= gcc
CFLAGS ?= -std=c11 -Wall -Wextra -O2
PYTHON ?= python3

.PHONY: all test sim wave reference experiment anc-experiment parity-vectors rtl-parity serial-parity pipelined-parity stream-parity stream-48k i2s-ingress i2s-overrun i2s-synth-check synthesis-report ecp5-implementation clean

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

experiment:
	$(PYTHON) model/lms_mu_sweep.py --output-dir results

anc-experiment:
	$(PYTHON) model/anc_system_sim.py --output-dir results

parity-vectors: $(BUILD_DIR)
	$(PYTHON) model/generate_rtl_parity_vectors.py --output-dir $(BUILD_DIR)/parity --manifest results/rtl_parity_manifest.json

rtl-parity: parity-vectors
	iverilog -g2012 -Wall -o $(PARITY_SIM) $(RTL) tb/tb_lms_vector_parity.v
	vvp $(PARITY_SIM)

serial-parity: parity-vectors
	iverilog -g2012 -Wall -o $(SERIAL_PARITY_SIM) rtl/lms_adaptive_filter_serial.v tb/tb_lms_serial_parity.v
	vvp $(SERIAL_PARITY_SIM)

pipelined-parity: parity-vectors
	iverilog -g2012 -Wall -o $(PIPELINED_PARITY_SIM) rtl/lms_adaptive_filter_pipelined.v tb/tb_lms_pipelined_parity.v
	vvp $(PIPELINED_PARITY_SIM)

stream-parity: parity-vectors
	iverilog -g2012 -Wall -o $(STREAM_PARITY_SIM) rtl/lms_adaptive_filter_pipelined.v rtl/lms_stream_wrapper.v tb/tb_lms_stream_wrapper.v
	vvp $(STREAM_PARITY_SIM)

stream-48k: parity-vectors
	iverilog -g2012 -Wall -o $(STREAM_48K_SIM) rtl/lms_adaptive_filter_pipelined.v rtl/lms_stream_wrapper.v tb/tb_lms_stream_48k.v
	vvp $(STREAM_48K_SIM)

i2s-ingress: parity-vectors
	iverilog -g2012 -Wall -o $(I2S_INGRESS_SIM) rtl/i2s_stereo_rx16.v rtl/audio_pair_cdc.v rtl/lms_adaptive_filter_pipelined.v rtl/lms_stream_wrapper.v rtl/lms_i2s_input_bridge.v tb/tb_lms_i2s_input_bridge.v
	vvp $(I2S_INGRESS_SIM)

i2s-overrun:
	iverilog -g2012 -Wall -o $(I2S_OVERRUN_SIM) rtl/i2s_stereo_rx16.v tb/tb_i2s_rx16_overrun.v
	vvp $(I2S_OVERRUN_SIM)

i2s-synth-check:
	yosys -q -p 'read_verilog -sv rtl/i2s_stereo_rx16.v rtl/audio_pair_cdc.v rtl/lms_adaptive_filter_pipelined.v rtl/lms_stream_wrapper.v rtl/lms_i2s_input_bridge.v; synth -top lms_i2s_input_bridge; check'

synthesis-report:
	bash scripts/run_synthesis.sh

ecp5-implementation:
	bash scripts/run_ecp5.sh

wave: test
	gtkwave $(BUILD_DIR)/lms.vcd

clean:
	rm -rf $(BUILD_DIR)
