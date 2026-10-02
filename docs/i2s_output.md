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


## Verified simulation result

The corrected CI run passed the complete new output path.

Standalone transmitter:

- one pending stereo pair serialized exactly;
- decoded left/right values matched the supplied pair;
- the following missing result frame incremented `underrun_count` by exactly one;
- zero transmitter timing errors;
- zero monitor framing errors.

Full-duplex path:

- 136 input I2S frames were driven to provide startup/flush margin;
- 135 sample pairs were accepted by the LMS stream;
- 135 LMS results moved into the return path;
- 135 TX pairs were loaded;
- 134 valid TX frames had completed when the test stopped;
- the first 128 completed TX frames were decoded and matched the fixed-point
  reference exactly;
- zero RX overrun/framing errors;
- zero TX underruns/timing errors during continuous nominal streaming;
- zero LMS input stalls and zero LMS output-overflow events.

The count offsets are pipeline/startup effects in a continuously clocked framed
interface; the parity assertion is made only on frames explicitly marked as
completed valid LMS results.

## Testbench failures retained

The first TX CI attempt failed for two testbench reasons:

1. WS was changed on the same falling BCLK edge the transmitter samples, creating
   a simulator race. The test also clocked through two genuine missing-result
   frame boundaries while expecting one underrun.
2. After fixing edge setup, the test still skipped the first left-channel data
   edge after initial synchronization. That created one extra same-channel bit
   clock, correctly producing one TX timing error and one monitor framing error.

The final stimulus gives WS setup time before falling BCLK, begins the left MSB
immediately after synchronization, and stops after the single intended underrun
boundary. No transmitter RTL arithmetic/framing change was needed for those two
failures.
