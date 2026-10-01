# I2S ingress bridge

This revision adds a digital-audio input boundary in front of the buffered LMS
stream. It does not add an audio codec, ADC or physical FPGA result.

## Format

The receiver implements classic 16-bit stereo I2S framing:

- WS low: left channel;
- WS high: right channel;
- WS changes one bit clock before the next channel MSB;
- the serial bit present on the WS-transition sampling edge is the LSB of the
  channel that just ended.

For this experiment:

- left sample = LMS reference `x[n]`;
- right sample = desired/primary `d[n]`.

At 48 kHz with 16 bits per channel, the test BCLK is 1.536 MHz.

## Clock-domain crossing

I2S is received in the BCLK domain. A one-entry bundled-data request/
acknowledge bridge moves complete stereo pairs into the 50 MHz LMS system
clock.

The source pair is held stable until the acknowledgement returns. The request
toggle passes through two destination flip-flops before the destination captures
the bundled data. The destination then holds `valid` until the existing LMS
stream wrapper accepts the pair.

This is a small-rate CDC suitable for the current 48 kHz experiment. It is not
presented as a replacement for a vendor-provided asynchronous FIFO in a larger
or safety-critical design.

## No fake backpressure on I2S

The external I2S source cannot be told to stop. Therefore the receiver has one
complete-frame holding slot. If another stereo frame completes before that slot
moves into the CDC bridge, the new frame is dropped and `overrun_count`
increments.

That failure path is tested explicitly. It is intentionally different from the
valid/ready LMS stream, where a source is allowed to wait.

## Verification

The main test drives 256 samples from the existing acoustic parity vector set as
standard I2S frames using an independent 1.536 MHz BCLK and a 50 MHz LMS clock.

The check requires:

- exactly 256 decoded stereo frames;
- zero I2S framing errors;
- zero I2S overruns at nominal 48 kHz;
- 256 LMS samples accepted and emitted;
- zero LMS input backpressure at nominal cadence;
- every noise estimate, error and coefficient tuple bit-exact with the existing
  fixed-point reference.

A second receiver-only test blocks `frame_ready`, transmits two frames and
requires the first frame to remain intact while the second increments the
explicit overrun counter.

The bridge is also passed through generic Yosys synthesis as a synthesizability
check. No I2S timing closure or physical codec/board measurement is claimed.


## Verified simulation result

The first CI run of the complete ingress path passed:

- 256 standard-I2S stereo frames decoded;
- 256 sample pairs accepted by the LMS stream;
- 256 LMS results emitted;
- zero I2S overruns at nominal 48 kHz;
- zero I2S framing errors;
- zero LMS input-stall cycles at nominal cadence;
- zero LMS output-overflow events;
- all noise-estimate, error and coefficient outputs bit-exact with the existing
  fixed-point reference.

The blocked-consumer receiver test also passed: with `frame_ready=0`, the first
complete stereo frame remained stable and the next completed frame incremented
`overrun_count` by exactly one.

Generic Yosys synthesis/check of the complete I2S ingress + CDC + buffered LMS
top also completed successfully. This confirms synthesizability only; it is not
a two-clock timing-closure result.
