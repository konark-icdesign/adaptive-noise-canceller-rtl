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
