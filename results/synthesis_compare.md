# LMS architecture synthesis comparison

Generic Yosys synthesis only. These numbers are useful for relative architecture comparison, not as FPGA LUT/DSP/Fmax claims. A device-specific implementation is still required for that.

| metric | current parallel LMS | serialized MAC LMS |
|---|---:|---:|
| logical multipliers | 8 | 1 |
| logical adders | 7 | 6 |
| logical muxes | 16 | 32 |
| logical register cells | 9 | 15 |
| total logical cells | 53 | 94 |
| generic gate cells after synth | 16,443 | 3,905 |
| initiation interval | 1 clock | 9 clocks |
| theoretical sample rate at 50 MHz* | 50,000,000/s | 5,555,556/s |

*Arithmetic throughput only. This is not a timing-closure result.

The serialized version cuts the inferred multiplier count from eight to one. It needs more control, mux and register cells, but the generic post-synthesis cell count is about 76.3% lower in this Yosys flow because multiplier logic dominates the parallel implementation.

The trade is throughput: the parallel core can accept one sample per clock, while the serialized version accepts one every nine clocks. Even at a hypothetical 50 MHz clock, the serialized arithmetic rate is about 5.56 MS/s, far above 48 kHz audio. That does **not** prove a 50 MHz timing closure on any FPGA.

The serialized core also passed the same 4,096-sample bit-exact acoustic-vector verification as the parallel core. Its measured accept-to-result latency in the RTL testbench was eight clocks.
