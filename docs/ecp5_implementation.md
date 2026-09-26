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

Both cores must still pass their existing 4,096-sample bit-exact RTL tests in CI before implementation results are accepted.

The 50 MHz throughput interpretation is:

- parallel core: one accepted sample/clock = 50 MS/s arithmetic initiation rate;
- serialized core: one accepted sample/9 clocks = 5.56 MS/s arithmetic initiation rate.

Those rates only matter if nextpnr reports timing closure at or above 50 MHz. They are not physical ADC/I2S throughput measurements.


## Routed result

The first 50 MHz place-and-route attempt exposed a real limitation rather than being silently relaxed. The parallel core routed at **23.30 MHz**, with the long coefficient-update datapath as the limiting path. The serialized core routed at **34.59 MHz**.

Resource mapping:

| resource | parallel | serialized |
|---|---:|---:|
| LUT4 | 509 | 643 |
| DFF | 144 | 246 |
| MULT18X18D | 8 | 1 |
| DP16KD | 0 | 0 |

The serialized architecture therefore cuts dedicated multiplier use by 87.5%, but increases control/mux/register logic. Its nine-clock initiation interval means the 34.59 MHz routed result corresponds to about 3.84 MS/s, still roughly 80 times a 48 kHz audio stream.

No claim is made that either current core closes 50 MHz. Reaching that target would require further pipelining/retiming or architectural changes.
