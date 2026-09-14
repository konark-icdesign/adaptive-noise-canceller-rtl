# Adaptive Noise Canceller RTL

A fixed-point, four-tap LMS adaptive filter implemented in Verilog.

This project started as a simple FIR prototype and has been extended into a real adaptive filter with coefficient updates, Q1.15 arithmetic, saturation, a self-checking convergence testbench, and automated CI simulation.

## What the design implements

The adaptive filter estimates the component of `desired_in` that is correlated with the reference input.

The core LMS equations are:

```text
y[n] = sum(w_i[n] * x[n-i])

e[n] = d[n] - y[n]

w_i[n+1] = w_i[n] + mu * e[n] * x[n-i]
```

Where:

- `x[n]` is the reference/noise input
- `d[n]` is the desired signal input
- `y[n]` is the adaptive-filter estimate
- `e[n]` is the residual/error output
- `w_i` are adaptive coefficients

The default learning rate is `mu = 1/16`, implemented with a shift so the update remains hardware friendly.

## Fixed-point format

The datapath uses signed 16-bit Q1.15 values for samples and coefficients.

Examples:

```text
+0.5  ->  16384
+0.25 ->   8192
-0.25 ->  -8192
```

Intermediate multiplication and accumulation use wider signed registers before being shifted back to Q1.15. Output/error/coefficient updates are saturated to the 16-bit signed range.

See [`docs/fixed_point_and_algorithm.md`](docs/fixed_point_and_algorithm.md) for the scaling details.

## Repository structure

```text
rtl/
  lms_adaptive_filter.v       LMS adaptive-filter RTL

tb/
  tb_lms_adaptive_filter.v    self-checking convergence testbench

docs/
  fixed_point_and_algorithm.md

.github/workflows/
  verilog-ci.yml              automated simulation on push / pull request

Makefile                      one-command simulation flow
```

## Verification

The testbench uses a pseudo-random reference input and creates a hidden two-tap path:

```text
h0 = +0.5
h1 = -0.25
```

The desired signal is generated as:

```text
d[n] = 0.5*x[n] - 0.25*x[n-1]
```

All adaptive coefficients begin at zero. During training, the LMS implementation should learn approximately:

```text
[+0.5, -0.25, 0, 0]
```

The testbench automatically checks:

- at least a 10x reduction in mean-squared error between early and late training windows;
- convergence of the first two coefficients toward the hidden path;
- the unused coefficients remaining near zero.

If the convergence checks fail, the simulation exits with a failure status.

## Run locally

Requirements:

- Icarus Verilog
- GNU Make
- GTKWave (optional, for waveforms)

Run the self-checking test:

```bash
git clone https://github.com/konark-icdesign/adaptive-noise-canceller-rtl.git
cd adaptive-noise-canceller-rtl
make test
```

Open the generated waveform:

```bash
make wave
```

Clean generated files:

```bash
make clean
```

Without Make:

```bash
mkdir -p build
iverilog -g2012 -Wall -o build/lms_tb rtl/lms_adaptive_filter.v tb/tb_lms_adaptive_filter.v
vvp build/lms_tb
```

## Why this is an adaptive filter, not just an FIR filter

A fixed FIR filter uses coefficients chosen beforehand and keeps them constant.

This design computes an error for every valid sample and updates the coefficients in hardware using the LMS rule. The coefficient outputs are exposed so convergence can be observed directly during simulation.

## Current scope

This repository demonstrates the adaptive DSP core and verifies convergence using a synthetic unknown path. It is not presented as a complete acoustic noise-cancellation product: microphone front ends, ADC/DAC interfaces, acoustic feedback paths, and real-time audio I/O are outside the current RTL scope.

## Next engineering steps

- compare RTL output against a software golden model on identical sample vectors;
- add configurable tap count and runtime learning-rate control;
- add coefficient-update enable/freeze control;
- evaluate saturation/rounding choices and convergence-vs-step-size tradeoffs;
- synthesize the design and report area/timing/resource cost;
- map the design to FPGA hardware for real-time sample streaming.

## License

MIT License. See [`LICENSE`](LICENSE).
