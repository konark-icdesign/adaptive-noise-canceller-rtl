# Clock-domain crossing verification

The I2S/LMS path uses the same one-entry bundled-data request/acknowledge bridge
in both directions:

```text
I2S BCLK -> 50 MHz system clock
50 MHz system clock -> I2S BCLK
```

The sample pair is not synchronized bit-by-bit. Instead, the source holds the
entire pair stable while a request toggle crosses through a two-flop
synchronizer. The destination captures the stable bundle only after seeing the
synchronized request, and the source cannot overwrite that bundle until the
acknowledgement returns through another two-flop synchronizer.

## Implementation intent

The four toggle synchronizer registers now carry the Verilog
`async_reg="true"` attribute. This documents the intended synchronizer chains
to synthesis/place-and-route tools. It does not by itself prove metastability
MTBF or physical placement quality.

## Stress simulation

`tb/tb_audio_pair_cdc_stress.v` sends 512 ordered sample pairs while:

- inserting pseudo-random source bubbles;
- applying pseudo-random destination backpressure;
- applying recurring forced destination stalls;
- checking that destination data remains stable while `d_valid && !d_ready`;
- checking every delivered pair for exact order and value;
- timing out on duplication, loss or deadlock.

CI runs the same testbench at three unrelated clock relationships:

1. ingress-like: 1.536 MHz source to 50 MHz destination;
2. return-like: 50 MHz source to 1.536 MHz destination;
3. awkward ratio: about 13.5 MHz source to 9.4 MHz destination with a phase
   offset chosen to vary edge relationships.

This is digital simulation. It cannot model analog metastability resolution.
The result is therefore evidence for protocol/order correctness across changing
clock ratios and phases, not a physical CDC sign-off.

## Device timing boundary

The current ECP5 report remains a single-clock arithmetic implementation study.
It would be misleading to publish a new "full-duplex Fmax" by simply applying
the 50 MHz `--freq` option to both the external BCLK domain and asynchronous
cross-domain paths.

A future device-specific sign-off should use a constraint flow that represents
the 50 MHz system clock and the external I2S BCLK separately and treats the
synchronizer crossings as asynchronous. Until then, the repository keeps the
multi-clock evidence at RTL/protocol level only.
