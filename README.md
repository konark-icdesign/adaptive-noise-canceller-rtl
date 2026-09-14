# Fixed-Point LMS Adaptive Filter RTL

A 4-tap LMS adaptive filter implemented in Verilog using signed Q1.15 fixed-point arithmetic.

This repository started as a simple fixed-coefficient FIR filter. I later extended it into an adaptive LMS design by adding an error path, coefficient updates, fixed-point saturation, and a self-checking convergence testbench.

## Design

The filter uses the standard LMS equations:

```text
y[n] = sum(w_i[n] * x[n-i])
e[n] = d[n] - y[n]
w_i[n+1] = w_i[n] + mu * e[n] * x[n-i]
```

In this implementation:

- samples and coefficients are signed 16-bit Q1.15 values;
- the filter has four taps;
- the default learning rate is `mu = 1/16`;
- multiplication and accumulation use wider intermediate values;
- outputs and coefficient updates are saturated to the signed 16-bit range.

The RTL is in [`rtl/lms_adaptive_filter.v`](rtl/lms_adaptive_filter.v).

More detail on the fixed-point scaling is in [`docs/fixed_point_and_algorithm.md`](docs/fixed_point_and_algorithm.md).

## Verification

The testbench creates a known two-tap system:

```text
h0 = +0.5
h1 = -0.25
```

with

```text
d[n] = 0.5*x[n] - 0.25*x[n-1]
```

The LMS coefficients begin at zero and adapt over 3000 pseudo-random input samples. The testbench checks that the mean-squared error drops significantly and that the learned coefficients move close to the expected values.

One local run produced:

```text
Early-window mean squared error : 1641547
Late-window mean squared error  : 6786
Learned coefficients (Q1.15)    : 16179, -8414, -216, -192
Expected approximately          : 16384, -8192, 0, 0

PASS: LMS adaptation and convergence verified.
```

The measured late-window MSE is about 242 times lower than the early-window MSE.

### Simulation result

![Icarus Verilog LMS convergence test](docs/images/simulation_pass.png)

### GTKWave

![GTKWave LMS adaptive filter simulation](docs/images/gtkwave_lms.png)

## Repository structure

```text
rtl/
  lms_adaptive_filter.v

tb/
  tb_lms_adaptive_filter.v

docs/
  fixed_point_and_algorithm.md
  images/
    simulation_pass.png
    gtkwave_lms.png

.github/workflows/
  verilog-ci.yml

Makefile
```

## Running the project

Requirements:

- Icarus Verilog
- GNU Make
- GTKWave (optional)

Clone and run:

```bash
git clone https://github.com/konark-icdesign/adaptive-noise-canceller-rtl.git
cd adaptive-noise-canceller-rtl
make test
```

Open the waveform:

```bash
make wave
```

The same simulation is also run automatically through GitHub Actions.

## Scope

This project is the digital adaptive-filter core and its RTL verification environment. It does not include microphone/ADC/DAC hardware or a complete real-time acoustic noise-cancellation system.

Possible later extensions are FPGA implementation, synthesis/area/timing measurements, and comparison against a software reference model.

## License

MIT License. See [`LICENSE`](LICENSE).
