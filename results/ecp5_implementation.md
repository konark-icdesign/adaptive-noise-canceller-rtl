# ECP5 implementation study

Reference implementation target only: LFE5U-25F, CABGA256, speed grade 6. This is synthesis/place-and-route evidence, not physical FPGA-board validation.

| metric | original parallel | staged parallel | stream wrapper | serialized |
|---|---:|---:|---:|---:|
| LUT4s before packing | 509 | 657 | 1193 | 643 |
| DFFs before packing | 144 | 419 | 593 | 246 |
| MULT18X18D DSP blocks | 8 | 4 | 4 | 1 |
| DP16KD BRAMs | 0 | 0 | 0 | 0 |
| sustained core initiation interval | 1 | 5 | 5 | 9 |
| reported max frequency | 23.30 MHz | 61.94 MHz | 65.02 MHz | 34.59 MHz |
| meets 50 MHz constraint | False | True | True | False |

Using routed Fmax, estimated arithmetic initiation capacity is 23,300,000 samples/s original, 12,388,000 samples/s staged-parallel, 13,004,000 samples/s through the buffered wrapper, and 3,843,333 samples/s serialized. All are far above a 48 kHz sample stream.

The stream-wrapper top used for this reference run keeps the five 32-bit diagnostic counters internal and XOR-reduces each to one observable debug bit. The first attempt exposed every counter bit as a package pin and failed before placement with 294 requested I/O cells on a 197-I/O target. That failed attempt is retained in the streaming-wrapper documentation.

The wrapper adds 536 LUT4s and 174 DFFs relative to the bare staged core while preserving the same four DSP multipliers. Most of that overhead is buffering, diagnostic counters and their control. The reported 65.02 MHz versus 61.94 MHz should not be interpreted as the wrapper making the arithmetic faster; placement/routing changed between tops. The meaningful result is that the buffered boundary still closes the 50 MHz reference constraint.

These figures depend on the reference FPGA family, synthesis mapping, the debug-preservation harness and unconstrained I/O placement. They are not portable resource/Fmax claims for a different FPGA.
