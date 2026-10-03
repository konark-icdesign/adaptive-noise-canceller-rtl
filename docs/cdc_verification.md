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


## Verified CI result

All three deterministic stress runs transferred all 512 ordered pairs exactly.

| direction / clock case | source half-period | destination half-period | phase | source stall cycles | destination stall cycles | result |
|---|---:|---:|---:|---:|---:|---|
| I2S-like -> 50 MHz | 325.520833 ns | 10 ns | 7.25 ns | 1022 | 466 | PASS |
| 50 MHz -> I2S-like | 10 ns | 325.520833 ns | 113.75 ns | 80672 | 450 | PASS |
| awkward unrelated clocks | 37 ns | 53 ns | 17 ns | 3974 | 488 | PASS |

For every case:

- 512/512 source pairs were accepted;
- 512/512 destination pairs were consumed;
- values arrived in exact sequence;
- no pair was duplicated or lost;
- destination data stayed stable whenever `d_valid && !d_ready`;
- forced destination stalls were exercised;
- the slower-destination cases produced substantial source backpressure;
- no timeout/deadlock occurred.

The very large source-stall count in the 50 MHz -> 1.536 MHz direction is
expected for a one-entry handshake: the fast source spends most cycles waiting
for the much slower destination and acknowledgement return. It is not a dropped
sample count.

These simulations validate the digital handshake protocol. They still do not
model metastability resolution time, synchronizer MTBF, routed synchronizer
placement or board-level clock quality.
