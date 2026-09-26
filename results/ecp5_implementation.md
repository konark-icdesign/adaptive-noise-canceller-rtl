# ECP5 implementation study

Reference implementation target: **LFE5U-25F, CABGA256, speed grade 6** using Yosys `synth_ecp5` and nextpnr-ecp5.

This is routed implementation evidence, not physical-board validation.

| metric | original parallel | staged parallel | serialized |
|---|---:|---:|---:|
| LUT4s before packing | 509 | 657 | 643 |
| DFFs before packing | 144 | 419 | 246 |
| ECP5 MULT18X18D DSP blocks | 8 | 4 | 1 |
| DP16KD BRAMs | 0 | 0 | 0 |
| initiation interval | 1 clock | 5 clocks | 9 clocks |
| routed Fmax | **23.30 MHz** | **61.94 MHz** | **34.59 MHz** |
| closes 50 MHz target | no | **yes** | no |
| arithmetic sample capacity at routed Fmax | 23.30 MS/s | 12.39 MS/s | 3.84 MS/s |
| margin over 48 kHz audio | ~485x | ~258x | ~80x |

## Timing result

The original one-cycle parallel implementation failed the 50 MHz reference target because FIR, error and coefficient-update arithmetic sat in the same clock interval.

The staged design separates the work across five states:

```text
capture/FIR multiply
        ->
balanced FIR sum
        ->
Q1.15 output + error
        ->
correlation multiply
        ->
coefficient commit
```

The four multipliers are reused between FIR and correlation phases. That changes the architecture from 8 DSP blocks to 4 DSP blocks while also shortening the longest combinational path enough to route at **61.94 MHz**.

The 4,096-sample bit-exact test passed, so the staging did not alter the fixed-point LMS result or coefficient-update order.

## Tradeoff

The timing improvement is not free:

- LUT4: 509 -> 657;
- DFF: 144 -> 419;
- DSP: 8 -> 4;
- initiation interval: 1 -> 5 clocks;
- routed Fmax: 23.30 -> 61.94 MHz.

For 48 kHz audio, the five-clock initiation interval is still insignificant. At routed Fmax:

```text
61.94 MHz / 5 = 12.388 MS/s
```

which is about 258 times the 48 kHz requirement.

The serialized architecture remains the minimum-DSP option at one DSP block, while the staged-parallel architecture is the only current version that closes the 50 MHz reference target.
