# Parallel versus serialized LMS hardware

The original RTL computes the four-tap FIR estimate and four coefficient products in the same accepted sample update. That is convenient for throughput, but it exposes several multiplications in parallel.

The alternative `rtl/lms_adaptive_filter_serial.v` deliberately reuses one signed 16x16 multiplier. It performs:

1. four FIR multiply-accumulate cycles;
2. error calculation;
3. four coefficient-update multiply cycles.

The current implementation therefore has an initiation interval of nine clocks per input sample. It is not intended to replace the original RTL automatically. It exists to quantify the normal DSP hardware tradeoff:

```text
parallel arithmetic -> more multipliers, maximum sample throughput
serialized arithmetic -> one shared multiplier, lower throughput, more control/register logic
```

Both implementations use the same Q1.15 saturation and LMS update equation. The serialized core is checked against the same 4,096-sample bit-exact acoustic vector set as the parallel core. A synthesis result is not accepted unless that parity test passes.

## What the synthesis report means

`scripts/run_synthesis.sh` runs two forms of generic Yosys synthesis for each design:

- a logical netlist after process lowering/optimization, used to count arithmetic cells such as `$mul`;
- generic synthesis/technology mapping, used only as a relative generic-cell comparison.

This is **not** FPGA implementation. It does not provide Xilinx/Intel/Lattice DSP-block usage, LUT count after place-and-route, or Fmax. Those require choosing a real target part and constraints.

The 50 MHz and 100 MHz sample-rate figures in the report are arithmetic initiation-rate calculations only:

```text
sample_rate = clock_rate / initiation_interval
```

They should not be read as timing-closure claims.
