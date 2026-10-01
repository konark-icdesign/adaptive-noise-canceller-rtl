# I2S ingress verification

Evidence level: RTL simulation + generic Yosys synthesizability check.

No physical codec, ADC, FPGA board or I2S electrical/timing measurement is
claimed.

## Nominal 48 kHz ingress

Configuration:

- stereo 16-bit I2S;
- 48 kHz frame rate;
- 1.536 MHz I2S BCLK;
- independent 50 MHz LMS system clock;
- left = LMS reference;
- right = desired/primary input;
- first 256 samples from the existing acoustic parity vector set.

Result:

| check | result |
|---|---:|
| decoded stereo frames | 256 |
| LMS samples accepted | 256 |
| LMS results emitted | 256 |
| I2S overruns | 0 |
| I2S framing errors | 0 |
| LMS input-stall cycles | 0 |
| LMS output-overflow events | 0 |
| numerical parity | bit-exact |

Every emitted tuple of noise estimate, error and four adaptive coefficients
matched the existing fixed-point reference sample-by-sample.

## Forced receive overrun

The receiver was then tested with its downstream `frame_ready` held low while
two complete stereo frames were transmitted.

Observed behavior:

- first frame remained valid and unchanged;
- second frame was not silently substituted for the first;
- overrun counter incremented by exactly one;
- framing-error count remained zero.

This test matters because physical I2S has no backpressure signal. Once the
single receive holding slot is occupied, a new frame can only be dropped and
reported.

## Synthesis check

The complete hierarchy

```text
I2S RX -> bundled-data CDC -> buffered staged LMS
```

passed generic Yosys `synth` + `check`.

No device-specific I2S/CDC Fmax is reported yet because the current ECP5 timing
flow is single-clock and would not be an honest constraint model for the
independent BCLK and 50 MHz system-clock domains.
