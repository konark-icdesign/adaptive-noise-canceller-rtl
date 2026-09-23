#!/usr/bin/env bash
set -euo pipefail
mkdir -p build/synth results

yosys -q -p 'read_verilog -sv rtl/lms_adaptive_filter.v; hierarchy -top lms_adaptive_filter; proc; opt; flatten; opt; memory; opt; write_json build/synth/parallel_logical.json'
yosys -q -p 'read_verilog -sv rtl/lms_adaptive_filter.v; hierarchy -top lms_adaptive_filter; synth -top lms_adaptive_filter; write_json build/synth/parallel_gate.json'

yosys -q -p 'read_verilog -sv rtl/lms_adaptive_filter_serial.v; hierarchy -top lms_adaptive_filter_serial; proc; opt; flatten; opt; memory; opt; write_json build/synth/serial_logical.json'
yosys -q -p 'read_verilog -sv rtl/lms_adaptive_filter_serial.v; hierarchy -top lms_adaptive_filter_serial; synth -top lms_adaptive_filter_serial; write_json build/synth/serial_gate.json'

python3 model/synthesis_report.py --input-dir build/synth --output-dir results
