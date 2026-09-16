# Fixed-Point LMS Adaptive Filter RTL

4-tap LMS adaptive filter in Verilog using signed Q1.15 fixed-point arithmetic.

This started as a basic fixed-coefficient FIR and I later changed it into an actual LMS filter with coefficient updates, saturation and a convergence test.

## Design

```text
y[n] = sum(w_i[n] * x[n-i])
e[n] = d[n] - y[n]
w_i[n+1] = w_i[n] + mu * e[n] * x[n-i]
```

Current implementation:

- 16-bit signed Q1.15 samples and coefficients
- 4 taps
- default `mu = 1/16`
- wider multiply/accumulate path
- saturation back to 16-bit Q1.15

RTL: [`rtl/lms_adaptive_filter.v`](rtl/lms_adaptive_filter.v)

Fixed-point notes: [`docs/fixed_point_and_algorithm.md`](docs/fixed_point_and_algorithm.md)

## RTL verification

The testbench builds a hidden 2-tap path:

```text
h0 = +0.5
h1 = -0.25

d[n] = 0.5*x[n] - 0.25*x[n-1]
```

The adaptive filter starts with all coefficients at zero and runs for 3000 pseudo-random samples.

One run gives:

```text
Early-window mean squared error : 1641547
Late-window mean squared error  : 6786
Learned coefficients (Q1.15)    : 16179, -8414, -216, -192
Expected approximately          : 16384, -8192, 0, 0

PASS: LMS adaptation and convergence verified.
```

Late-window MSE is about 242x lower than the early window.

![Icarus Verilog LMS convergence test](docs/images/simulation_pass.png)

![GTKWave LMS adaptive filter simulation](docs/images/gtkwave_lms.png)

## C reference model

I added a small C model in `model/lms_reference.c` using the same fixed-point scaling, LFSR input sequence and hidden 2-tap path as the RTL test.

It is useful as a second implementation of the algorithm, not another Verilog testbench.

```bash
make reference
```

Current C output matches the RTL run:

```text
C reference model
early MSE : 1641547
late MSE  : 6786
coeffs    : 16179, -8414, -216, -192
```

## Step-size experiment

`model/lms_mu_sweep.py` runs the same deterministic fixed-point problem with four LMS step sizes: `1/8`, `1/16`, `1/32` and `1/64`.

```bash
make experiment
```

The run shows the expected convergence tradeoff. In this test, larger step sizes adapt faster during the fixed 3000-sample window, while smaller values are still approaching the hidden coefficients.

| mu | early MSE | late MSE | MSE reduction | final coefficients |
|---:|---:|---:|---:|---|
| 1/8 | 256173 | 1557 | 22.16 dB | `[16281, -8297, -106, -96]` |
| 1/16 | 1641547 | 6786 | 23.84 dB | `[16179, -8414, -216, -192]` |
| 1/32 | 5678045 | 33616 | 22.28 dB | `[15946, -8684, -476, -408]` |
| 1/64 | 12828515 | 148326 | 19.37 dB | `[15345, -9174, -932, -805]` |

![LMS step-size sweep](results/mu_sweep.svg)

Full results: [`results/mu_sweep.md`](results/mu_sweep.md)

This is not a claim that one `mu` is universally best. LMS stability and convergence depend on the input power, correlation, filter length and fixed-point scaling.

All three checks run in GitHub Actions: RTL simulation, C reference model and the Python step-size experiment.

## Run

```bash
make test
make reference
make experiment
```

Waveform:

```bash
make wave
```

## Structure

```text
rtl/
  lms_adaptive_filter.v

tb/
  tb_lms_adaptive_filter.v

model/
  lms_reference.c
  lms_mu_sweep.py

results/
  mu_sweep.csv
  mu_sweep.md
  mu_sweep.svg

docs/
  fixed_point_and_algorithm.md
  images/

.github/workflows/
  verilog-ci.yml

Makefile
```

## Scope

This is the adaptive-filter RTL core and verification setup. It is not a complete acoustic ANC system with microphones, ADC/DAC and speakers.

A useful later step would be synthesis/timing/resource measurements or FPGA testing, not just adding more taps for no reason.

## License

MIT License. See [`LICENSE`](LICENSE).
