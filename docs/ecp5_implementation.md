# ECP5 reference implementation

This stage takes the already bit-exact parallel and serialized LMS RTL cores through a device-specific open-source FPGA flow.

Reference target:

- Lattice ECP5 LFE5U-25F
- CABGA256 package
- speed grade 6
- 50 MHz clock constraint

The target is used because Yosys and nextpnr can map arithmetic into ECP5-specific resources, including `MULT18X18D` DSP blocks, and can perform placement/routing and timing analysis. It is a reproducible reference target, not a recommendation to buy a specific board.

The flow is:

```text
Verilog
  -> Yosys synth_ecp5
  -> ECP5 JSON netlist
  -> nextpnr-ecp5 place and route
  -> resource + timing report
```

All architecture variants must pass their 4,096-sample bit-exact RTL tests in CI before implementation results are accepted.

The 50 MHz throughput interpretation is:

- original parallel core: one accepted sample/clock;
- staged parallel core: one accepted sample/5 clocks;
- serialized core: one accepted sample/9 clocks.

Those rates only matter if nextpnr reports timing closure at or above 50 MHz. They are not physical ADC/I2S throughput measurements.


## Routed result

The first 50 MHz place-and-route attempt exposed a real limitation rather than being silently relaxed. The original parallel core routed at **23.30 MHz**, with the long coefficient-update datapath as the limiting path. The serialized core routed at **34.59 MHz**.

A staged-parallel version was then added specifically to shorten that path while preserving the numerical update order. It registers FIR products, balances the FIR sum, separates error generation, reuses four multipliers for the correlation stage and commits coefficients in a final stage.

Resource/timing mapping:

| resource | original parallel | staged parallel | serialized |
|---|---:|---:|---:|
| LUT4 | 509 | 657 | 643 |
| DFF | 144 | 419 | 246 |
| MULT18X18D | 8 | 4 | 1 |
| DP16KD | 0 | 0 | 0 |
| initiation interval | 1 | 5 | 9 |
| routed Fmax | 23.30 MHz | **61.94 MHz** | 34.59 MHz |

The staged core passed the same 4,096-sample bit-exact test and is the first current architecture to close the 50 MHz reference constraint. Its routed arithmetic initiation capacity is about **12.39 MS/s**, around 258 times a 48 kHz audio stream.

The result also shows the hardware tradeoff clearly: extra staging increases register/control cost, but cuts DSP usage from 8 to 4 and more than doubles routed Fmax compared with the original core.
