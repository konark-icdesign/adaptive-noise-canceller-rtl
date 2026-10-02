# I2S output and full-duplex bridge

This revision completes the simulated digital-audio framing path around the LMS
core. It still does not claim a physical codec, DAC, microphone or FPGA-board
measurement.

## Output mapping

The LMS result is returned as 16-bit stereo I2S using the same external BCLK/WS
timing as the input side:

- TX left = LMS error/output `e[n]` (the cleaned signal in the ANC model);
- TX right = LMS `noise_estimate` `y[n]`.

The right channel is primarily diagnostic. A later physical codec integration
could duplicate the cleaned signal or choose another routing policy without
changing the adaptive arithmetic.

## Return clock-domain crossing

LMS results are produced in the 50 MHz system domain. The existing one-entry
request/acknowledge bundled-data bridge is instantiated in the reverse direction
to move complete `error/noise_estimate` pairs into the I2S BCLK domain.

The LMS valid/ready sink is therefore the return CDC itself: a result is not
removed from the buffered LMS wrapper until the CDC can hold it.

At 48 kHz there is ample time for the five-cycle LMS update and CDC handshake
before the next stereo frame boundary in the simulated clock relationship.

## I2S transmitter behavior

`i2s_stereo_tx16.v` launches serial data on falling BCLK edges so a conventional
receiver can sample on rising edges. It follows the same exact 16-bit slot rule
used by the ingress test:

- bits 15 through 1 are launched on same-channel falling edges;
- WS changes one bit clock before the next MSB;
- the WS-transition falling edge carries bit 0 of the channel that just ended.

A pending result is loaded only on a right-to-left frame boundary. Startup
silence before the first processed result is not counted as an underrun.

Once the transmitter has sent its first valid result, a later frame boundary
without a pending pair increments `underrun_count` and outputs zeros for that
frame. This makes missing output audio explicit.

## Verification plan

The full-duplex test drives independent clocks:

- 50 MHz LMS/system clock;
- 1.536 MHz BCLK for 48 kHz, 16-bit stereo I2S.

The existing acoustic reference/desired samples enter through the real I2S RX.
The LMS output then crosses back into BCLK and is serialized by the new TX. A
second I2S receiver in the testbench decodes the generated serial stream.

The first 128 valid serialized result pairs must match:

- TX left = expected fixed-point `error`;
- TX right = expected fixed-point `noise_estimate`.

The test also requires zero RX overrun/framing errors, zero TX underruns/timing
errors during continuous nominal operation, and zero LMS output overflow.

A standalone TX test supplies exactly one sample pair and then intentionally
withholds the next. The first frame must serialize exactly and the next frame
must increment the explicit TX underrun count.

Generic Yosys synthesis is used only as a synthesizability check. The repository
still does not contain a complete multi-clock ECP5 timing constraint set for the
external BCLK and 50 MHz system domains, so no new device-specific full-duplex
Fmax claim is made here.
