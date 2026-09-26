# ECP5 implementation study

Reference implementation target only: **LFE5U-25F, CABGA256, speed grade 6**. This is synthesis/place-and-route evidence from Yosys + nextpnr, not physical FPGA-board validation.

| metric | parallel LMS | serialized LMS |
|---|---:|---:|
| LUT4s before packing | 509 | 643 |
| DFFs before packing | 144 | 246 |
| ECP5 MULT18X18D DSP blocks | **8** | **1** |
| DP16KD BRAMs | 0 | 0 |
| initiation interval | 1 clock/sample | 9 clocks/sample |
| routed max frequency | **23.30 MHz** | **34.59 MHz** |
| closes 50 MHz target | no | no |
| routed arithmetic sample capacity | 23.30 MS/s | 3.84 MS/s |
| margin over 48 kHz audio | ~485x | ~80x |

## What changed compared with generic synthesis

Generic Yosys synthesis showed the serialized architecture using much less multiplier logic. The ECP5 flow makes the hardware tradeoff clearer: the parallel core maps eight multiplies into eight dedicated `MULT18X18D` DSP blocks, while the serialized core reuses one DSP block.

The serialized core therefore saves **7 DSP blocks (87.5%)**, but costs more LUTs and registers for muxing/state/control:

- LUT4 count rises from 509 to 643;
- DFF count rises from 144 to 246;
- DSP usage falls from 8 to 1.

## Timing result

The deliberately aggressive 50 MHz constraint did **not** close for either current implementation.

- parallel routed Fmax: **23.30 MHz**;
- serialized routed Fmax: **34.59 MHz**.

That failure is kept in the report rather than hidden. For the actual 48 kHz audio use case, however, both designs have large arithmetic-throughput margin. The parallel core can accept one sample every clock. The serialized core accepts one every nine clocks, so its routed arithmetic capacity is approximately:

```text
34.59 MHz / 9 = 3.84 MS/s
```

which is still about 80 times 48 kHz.

These numbers are specific to this reference target, unconstrained I/O placement, current RTL structure and tool versions. They are not portable Fmax/resource guarantees for another FPGA or a physical board.
