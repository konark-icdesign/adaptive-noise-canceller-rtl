# Buffered streaming wrapper

The staged LMS core already closes the 50 MHz ECP5 reference target, but its
core-level `sample_valid/sample_ready` interface accepts a new sample only when
the five-stage update is idle. This revision adds a small stream boundary around
that core rather than changing the LMS arithmetic.

## Interface

`rtl/lms_stream_wrapper.v` provides:

- source-side `s_valid/s_ready` handshake;
- four-entry input FIFO for short producer bursts;
- existing staged LMS core unchanged internally;
- two-entry result FIFO;
- sink-side `m_valid/m_ready` handshake;
- accepted/emitted sample counters;
- input and output backpressure-cycle counters;
- an output-overflow event counter that should remain zero.

In a valid/ready protocol, `valid && !ready` is normal backpressure, not an
overflow. The wrapper therefore counts those stall cycles explicitly instead of
mislabeling them as lost samples.

## Output reservation

The core has only one sample in flight, but there is a subtle boundary case when
it returns to IDLE: `core_out_valid` can still be presenting the just-completed
result while `sample_ready` is already high.

The wrapper computes output occupancy after the current result write and any
simultaneous sink pop before launching the next core transaction. A new sample
is launched only if one output slot remains reservable for its future result.
This makes output loss impossible under a protocol-compliant sink even if the
sink stalls indefinitely after launch.

## Verification

Two deterministic tests use the same fixed-point reference vectors as the
existing 4,096-sample parity tests.

`tb/tb_lms_stream_wrapper.v`:

- sends all 4,096 samples through the wrapper;
- inserts pseudo-random producer bubbles;
- creates pseudo-random sink readiness plus forced long sink stalls;
- checks every output/error/coefficient tuple bit-exactly;
- checks output stability while `m_valid && !m_ready`;
- requires both input and output backpressure to be exercised;
- requires zero output-overflow events.

`tb/tb_lms_stream_48k.v`:

- drives 256 reference samples at an average 48 kHz cadence from a 50 MHz clock;
- uses a repeating 1042, 1042, 1041 clock spacing;
- checks bit-exact output;
- requires zero source backpressure at that cadence.

These are RTL simulations, not an ADC/I2S or physical FPGA measurement.


## First ECP5 implementation failure

The first wrapper implementation attempt did not reach placement/timing because
the synthesis top exposed all five 32-bit diagnostic counters as package pins.
Together with stream data and coefficient outputs, nextpnr saw 294 TRELLIS_IO
cells on a CABGA256 target with 197 available I/O cells and rejected placement.

That is an integration-model error rather than a reason to delete the counters:
real hardware would read counters through a register/debug interface, not one
pin per bit. The corrected ECP5 reference top keeps the counters internal and
XOR-reduces each 32-bit counter to one debug-status bit. Every counter bit still
feeds observable logic for the implementation study, while the package I/O
model stays physically plausible enough to reach placement and timing.
