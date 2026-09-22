# ANC verification beyond system identification

The original RTL convergence test is a useful system-identification check: a four-tap LMS filter learns a hidden FIR path. This verification stage adds a second problem that is closer to adaptive noise cancellation.

This is still a synthetic model. It does not represent a measured microphone, loudspeaker, room impulse response, ADC or DAC.

## Signal model

The reference sensor observes a noise source `x[n]`. The primary input contains an independent desired signal `s[n]` plus that noise after an unknown path `h[n]`:

```text
v[n] = h[n] * x[n]
d[n] = s[n] + v[n]
y[n] = w[n]^T x_vec[n]
e[n] = d[n] - y[n]
```

If the adaptive filter identifies the correlated noise path, `y[n]` approaches `v[n]` and the error output approaches the desired signal `s[n]`.

The deterministic experiment uses an 8 kHz sample rate, 20,000 samples and a four-tap path. At sample 10,000 the hidden path changes from:

```text
[0.52, -0.28, 0.16, -0.07]
```

to:

```text
[0.18, 0.43, -0.22, 0.11]
```

That forces the filter to track a changed noise path instead of only converging once from zero.

## Measurements

`model/anc_system_sim.py` reports:

- input SNR and cleaned-output SNR;
- SNR improvement for five power-of-two LMS step sizes;
- recovery time after the hidden-path change;
- fixed-point saturation counts;
- error difference between floating-point LMS and Q1.15 LMS;
- an uncorrelated-reference negative control.

The negative control matters. If the reference is independent of the actual noise, LMS should not show a large cancellation gain. A model that reports strong cancellation in that case is probably measuring the wrong quantity or leaking information from the target into the reference.

## RTL parity

`model/generate_rtl_parity_vectors.py` generates 4,096 Q1.15 acoustic-style samples plus expected output, error and coefficient traces from the bit-exact Python model.

`tb/tb_lms_vector_parity.v` replays those vectors through the real Verilog core and compares, sample by sample:

```text
noise_estimate
error_out
coeff0
coeff1
coeff2
coeff3
```

This is stronger than only checking the final coefficients. A single arithmetic-shift, saturation or update-order difference should fail the parity run at the sample where it first diverges.

## Limits

The synthetic desired signal is a small multi-tone waveform and the reference noise is deterministic colored noise. These are useful controlled signals, not speech-quality or room-acoustic validation.

The next physical stage would need two acquisition channels with a genuinely correlated reference path, measured level/scaling, and a repeatable room/noise setup. At that point SNR improvement and tracking time should be recomputed from recorded data rather than reusing the synthetic numbers.
