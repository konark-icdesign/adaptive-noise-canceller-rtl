# Acoustic-style ANC and path-tracking simulation

This is a deterministic synthetic experiment, not a microphone/room measurement.
The primary input is `clean + correlated noise`; the LMS reference sees the noise source
before an unknown four-tap path. That path changes halfway through the run.

- input SNR before the path change: **1.70 dB**
- input SNR after the path change: **0.47 dB**
- fixed-point/float error RMSE at mu=1/16: **0.001347** full-scale

| mu | pre-change output SNR | post-change output SNR | pre improvement | post improvement | samples to recover >=15 dB | final Q1.15 weights |
|---:|---:|---:|---:|---:|---:|---|
| 1/8 | 15.50 dB | 14.69 dB | 13.80 dB | 14.22 dB | 1700 | `[4916, 13275, -7832, 3370]` |
| 1/16 | 18.50 dB | 18.21 dB | 16.80 dB | 17.74 dB | 2800 | `[5052, 13329, -7589, 3650]` |
| 1/32 | 20.03 dB | 20.67 dB | 18.34 dB | 20.20 dB | 4100 | `[5486, 13293, -7186, 3392]` |
| 1/64 | 16.59 dB | 14.51 dB | 14.89 dB | 14.04 dB | None | `[6622, 11507, -5465, 2340]` |
| 1/128 | 11.10 dB | 9.57 dB | 9.40 dB | 9.09 dB | None | `[8247, 8073, -2938, 982]` |

## Negative control

The same primary signal was processed using an independent, uncorrelated reference.
With mu=1/16 the output SNR was only **1.58 dB** before
and **0.44 dB** after the path change.
This is intentional: LMS needs a reference correlated with the noise to cancel it.

## Interpretation

For this workload the best average steady-state fixed-point SNR came from **1/32**.
That does not replace the RTL default universally. The earlier system-identification test and this ANC test
have different signal statistics, so step size remains an engineering tradeoff rather than a magic constant.
No output/error/coefficient saturation occurred in the tested amplitude envelope.

The path-change recovery metric uses a 500-sample sliding SNR window and reports the first 100-sample grid
position after the switch where output SNR reaches at least 15 dB.
