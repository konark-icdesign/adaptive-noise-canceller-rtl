Small C reference for the fixed-point LMS RTL.

It uses the same 3000-sample LFSR sequence and the same hidden two-tap path as the Verilog testbench. Right now it reproduces the RTL convergence numbers exactly.

```bash
make reference
```

This is mainly here so the algorithm is checked in a second implementation before doing any FPGA or synthesis work.
