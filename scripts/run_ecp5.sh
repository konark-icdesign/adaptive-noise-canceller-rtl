#!/usr/bin/env bash
set -euo pipefail
mkdir -p build/ecp5 results

run_one() {
  name="$1"
  top="$2"
  rtl_file="$3"

  yosys -q -p "read_verilog -sv ${rtl_file}; synth_ecp5 -top ${top} -json build/ecp5/${name}.json"

  nextpnr-ecp5 \
    --25k \
    --package CABGA256 \
    --speed 6 \
    --freq 50 \
    --timing-allow-fail \
    --lpf-allow-unconstrained \
    --json build/ecp5/${name}.json \
    --textcfg build/ecp5/${name}.config \
    --report build/ecp5/${name}_pnr.json \
    2>&1 | tee build/ecp5/${name}_pnr.log
}

run_one parallel lms_adaptive_filter rtl/lms_adaptive_filter.v
run_one pipelined lms_adaptive_filter_pipelined rtl/lms_adaptive_filter_pipelined.v
run_one serial lms_adaptive_filter_serial rtl/lms_adaptive_filter_serial.v

python3 model/ecp5_report.py --build-dir build/ecp5 --output-dir results
