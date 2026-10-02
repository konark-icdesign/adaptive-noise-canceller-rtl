# Full-duplex I2S LMS verification

Evidence level: RTL simulation plus generic Yosys synthesizability check.

No physical codec, DAC, ADC, microphone or FPGA-board measurement is claimed.

## Data path

```text
16-bit stereo I2S input
  left  = reference x[n]
  right = desired d[n]
          |
          v
I2S RX -> BCLK-to-50MHz CDC -> buffered staged LMS
          |
          v
50MHz-to-BCLK CDC -> I2S TX
  left  = error / cleaned output e[n]
  right = noise estimate y[n]
```

Clocking used in simulation:

- LMS/system clock: 50 MHz;
- I2S BCLK: 1.536 MHz;
- frame rate: 48 kHz;
- exact 16-bit stereo slots.

## Standalone TX result

| check | result |
|---|---:|
| supplied valid frames | 1 |
| valid frames serialized | 1 |
| decoded serial parity | exact |
| intentional following underruns | 1 |
| TX timing errors | 0 |
| monitor framing errors | 0 |

The missing second result is reported as an underrun rather than silently
repeating the previous valid sample.

## End-to-end result

The test drove 136 acoustic-vector input frames to provide pipeline startup and
flush margin.

| metric | result |
|---|---:|
| RX frames decoded | 136 |
| LMS samples accepted | 135 |
| LMS results emitted to return CDC | 135 |
| TX result pairs loaded | 135 |
| TX valid frames completed before stop | 134 |
| serialized result pairs checked | 128 |
| checked result mismatches | 0 |
| RX overruns | 0 |
| RX framing errors | 0 |
| TX underruns during nominal stream | 0 |
| TX timing errors | 0 |
| LMS input-stall cycles | 0 |
| LMS output-overflow events | 0 |

For all 128 checked completed result frames:

- TX left matched the expected fixed-point LMS error sample;
- TX right matched the expected fixed-point noise-estimate sample.

The unequal raw input/accepted/sent counts are expected startup/termination
pipeline offsets, not dropped checked results.

## Development failures

Two failed CI attempts are part of the engineering record.

First attempt:
- testbench changed WS on the same falling edge sampled by the TX;
- simulator race meant the intended initial boundary was not deterministic;
- the test also generated two missing-frame boundaries but expected one
  underrun.

Second attempt:
- WS setup was corrected;
- the testbench then waited past the first left-MSB edge after synchronization;
- this inserted one extra same-channel clock;
- TX timing-error count = 1 and monitor framing-error count = 1.

Final test:
- drives WS with setup before the falling edge;
- starts the first left MSB immediately after sync;
- creates exactly one intentional underrun boundary;
- passes.

## Synthesis boundary

The full hierarchy passes generic Yosys `synth` + `check`.

No device-specific full-duplex Fmax is reported. The current ECP5 implementation
flow does not yet carry an honest multi-clock timing constraint model for both
external I2S BCLK and the 50 MHz system clock.
