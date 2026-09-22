#!/usr/bin/env python3
"""Generate deterministic acoustic-style vectors and bit-exact LMS expectations."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from anc_system_sim import make_signals, q15, sat16

N = 4096
MU_SHIFT = 4
TAPS = 4


def hex16(value: int) -> str:
    return f"{value & 0xFFFF:04x}"


def write_mem(path: Path, values):
    path.write_text("\n".join(hex16(v) for v in values) + "\n", encoding="ascii")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-dir", default="build/parity")
    parser.add_argument("--manifest", default="results/rtl_parity_manifest.json")
    args = parser.parse_args()

    _, reference, _, _, desired = make_signals()
    reference_q = [q15(v) for v in reference[:N]]
    desired_q = [q15(v) for v in desired[:N]]

    weights = [0] * TAPS
    history = [0] * TAPS
    expected_y, expected_e = [], []
    coeffs = [[], [], [], []]
    saturations = {"output": 0, "error": 0, "weights": 0}

    for x, d in zip(reference_q, desired_q):
        history = [x] + history[:-1]
        y_raw = sum(weights[k] * history[k] for k in range(TAPS)) >> 15
        y = sat16(y_raw)
        saturations["output"] += y != y_raw

        e_raw = d - y
        e = sat16(e_raw)
        saturations["error"] += e != e_raw

        for k in range(TAPS):
            delta = (e * history[k]) >> (15 + MU_SHIFT)
            raw = weights[k] + delta
            updated = sat16(raw)
            saturations["weights"] += updated != raw
            weights[k] = updated

        expected_y.append(y)
        expected_e.append(e)
        for k in range(TAPS):
            coeffs[k].append(weights[k])

    out = Path(args.output_dir)
    out.mkdir(parents=True, exist_ok=True)
    write_mem(out / "reference.mem", reference_q)
    write_mem(out / "desired.mem", desired_q)
    write_mem(out / "expected_y.mem", expected_y)
    write_mem(out / "expected_e.mem", expected_e)
    for k in range(TAPS):
        write_mem(out / f"expected_c{k}.mem", coeffs[k])

    manifest = {
        "scope": "4096-sample acoustic-style Q1.15 vector set for sample-by-sample RTL parity",
        "samples": N,
        "mu_shift": MU_SHIFT,
        "mu": "1/16",
        "final_coefficients_q15": weights,
        "saturations": saturations,
        "input_peak_q15": max(max(abs(v) for v in reference_q), max(abs(v) for v in desired_q)),
        "path": [0.52, -0.28, 0.16, -0.07],
        "contains_clean_signal_plus_correlated_noise": True,
    }
    target = Path(args.manifest)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print(json.dumps(manifest, indent=2))


if __name__ == "__main__":
    main()
