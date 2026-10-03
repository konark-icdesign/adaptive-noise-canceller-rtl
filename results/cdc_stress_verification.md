# CDC stress verification

Evidence level: deterministic RTL simulation.

No metastability MTBF or physical FPGA/board claim is made.

| case | pairs sent | pairs received | source stalls | destination stalls | order/data errors | timeout |
|---|---:|---:|---:|---:|---:|---:|
| 1.536 MHz -> 50 MHz | 512 | 512 | 1022 | 466 | 0 | no |
| 50 MHz -> 1.536 MHz | 512 | 512 | 80672 | 450 | 0 | no |
| ~13.5 MHz -> ~9.4 MHz, phase offset | 512 | 512 | 3974 | 488 | 0 | no |

The destination output was also checked for stability throughout every
`d_valid && !d_ready` interval.

Interpretation: the one-entry request/acknowledge bundled-data protocol preserves
sample order and value across the tested unrelated-clock relationships and
backpressure patterns. The fast-to-slow case naturally generates many source
stall cycles because only one transfer may be in flight.

This result is not an analog CDC sign-off. The `async_reg` attributes express
implementation intent for the four synchronizer flip-flops, but physical timing,
placement and MTBF remain outside this simulation.
