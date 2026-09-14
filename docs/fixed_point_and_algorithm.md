# LMS algorithm and fixed-point notes

## Signal format

The RTL uses signed 16-bit Q1.15 values for:

- reference input `x[n]`
- desired input `d[n]`
- filter output `y[n]`
- error `e[n]`
- coefficients `w_i[n]`

A Q1.15 integer value represents:

```text
real_value = integer_value / 32768
```

Examples:

- `16384` -> `+0.5`
- `8192`  -> `+0.25`
- `-8192` -> `-0.25`

## LMS equations

For a four-tap filter:

```text
y[n] = w0*x[n] + w1*x[n-1] + w2*x[n-2] + w3*x[n-3]

e[n] = d[n] - y[n]

wi[n+1] = wi[n] + mu * e[n] * x[n-i]
```

The default learning rate is:

```text
mu = 1/16
```

This is implemented as a power-of-two shift (`MU_SHIFT = 4`) so the update does not require a separate multiplier for `mu`.

## Scaling

Multiplying two Q1.15 values produces a Q2.30 product. The FIR accumulator keeps extra width so that four products can be summed without immediately overflowing.

To convert the FIR accumulator back to Q1.15:

```text
Q2.30 >> 15 -> Q1.15
```

For the LMS update, `e*x` is Q2.30. To apply `mu = 2^-MU_SHIFT` and return to the coefficient's Q1.15 scale:

```text
coefficient_delta = (e*x) >> (15 + MU_SHIFT)
```

For the default `MU_SHIFT = 4`, the total shift is 19 bits.

## Saturation

The output, error, and updated coefficients use saturation to the signed 16-bit range instead of wrap-around. This prevents a large intermediate value from turning into an unrelated sign/magnitude after truncation.

## Verification strategy

The testbench creates a pseudo-random reference input and passes it through a hidden two-tap path:

```text
h0 = +0.5
h1 = -0.25
```

The desired signal is therefore:

```text
d[n] = 0.5*x[n] - 0.25*x[n-1]
```

The LMS filter starts with all coefficients at zero. A correct implementation should learn approximately:

```text
[+0.5, -0.25, 0, 0]
```

The self-checking testbench verifies two things:

1. late-window mean-squared error is at least 10x lower than the early-window error;
2. the final coefficients are within fixed tolerances of the hidden path.

This synthetic system-identification test proves that the adaptation loop is working. In a practical adaptive-noise-cancellation setup, `d[n]` would contain a desired signal plus correlated noise, and `e[n]` would become the cleaned output.
