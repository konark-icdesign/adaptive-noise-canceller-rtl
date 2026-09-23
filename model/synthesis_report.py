#!/usr/bin/env python3
"""Summarize Yosys logical/generic-cell output for the two LMS architectures."""

from __future__ import annotations

import argparse
import json
from collections import Counter
from pathlib import Path


def load_counts(path: Path):
    data = json.loads(path.read_text(encoding="utf-8"))
    modules = data["modules"]
    if len(modules) != 1:
        raise SystemExit(f"expected one flattened module in {path}, found {list(modules)}")
    module = next(iter(modules.values()))
    counts = Counter(cell["type"] for cell in module.get("cells", {}).values())
    return counts


def dff_count(counts):
    return sum(v for k, v in counts.items() if "DFF" in k.upper() or k.startswith("$dff") or k.startswith("$sdff") or k.startswith("$adff"))


def mux_count(counts):
    return sum(v for k, v in counts.items() if "MUX" in k.upper() or k.startswith("$mux"))


def summary(logical_path: Path, gate_path: Path, cycles_per_sample: int):
    logical = load_counts(logical_path)
    gate = load_counts(gate_path)
    return {
        "logical_cells": sum(logical.values()),
        "multipliers": logical.get("$mul", 0),
        "adders": logical.get("$add", 0),
        "subtractors": logical.get("$sub", 0),
        "muxes": mux_count(logical),
        "register_cells": dff_count(logical),
        "generic_gate_cells": sum(gate.values()),
        "cycles_per_sample": cycles_per_sample,
        "samples_per_second_at_50mhz": 50_000_000 / cycles_per_sample,
        "samples_per_second_at_100mhz": 100_000_000 / cycles_per_sample,
        "logical_cell_types": dict(sorted(logical.items())),
        "generic_gate_cell_types": dict(sorted(gate.items())),
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--input-dir", default="build/synth")
    parser.add_argument("--output-dir", default="results")
    args = parser.parse_args()
    src = Path(args.input_dir)
    out = Path(args.output_dir)
    out.mkdir(parents=True, exist_ok=True)

    parallel = summary(src / "parallel_logical.json", src / "parallel_gate.json", 1)
    serial = summary(src / "serial_logical.json", src / "serial_gate.json", 9)

    checks = {
        "serial_uses_fewer_logical_multipliers": serial["multipliers"] < parallel["multipliers"],
        "parallel_accepts_one_sample_per_clock": parallel["cycles_per_sample"] == 1,
        "serial_meets_48khz_at_50mhz_by_large_margin": serial["samples_per_second_at_50mhz"] >= 48_000 * 10,
    }
    result = {
        "scope": "generic Yosys synthesis; no FPGA family mapping and no timing/Fmax claim",
        "parallel": parallel,
        "serial": serial,
        "checks": checks,
        "passed": all(checks.values()),
    }

    (out / "synthesis_compare.json").write_text(json.dumps(result, indent=2), encoding="utf-8")

    lines = [
        "# LMS architecture synthesis comparison",
        "",
        "Generic Yosys synthesis only. These numbers are useful for relative architecture comparison,",
        "not as FPGA LUT/DSP/Fmax claims. A device-specific implementation is still required for that.",
        "",
        "| metric | current parallel LMS | serialized MAC LMS |",
        "|---|---:|---:|",
        f"| logical multipliers | {parallel['multipliers']} | {serial['multipliers']} |",
        f"| logical adders | {parallel['adders']} | {serial['adders']} |",
        f"| logical muxes | {parallel['muxes']} | {serial['muxes']} |",
        f"| logical register cells | {parallel['register_cells']} | {serial['register_cells']} |",
        f"| total logical cells | {parallel['logical_cells']} | {serial['logical_cells']} |",
        f"| generic gate cells after synth | {parallel['generic_gate_cells']} | {serial['generic_gate_cells']} |",
        f"| initiation interval | {parallel['cycles_per_sample']} clock | {serial['cycles_per_sample']} clocks |",
        f"| theoretical sample rate at 50 MHz* | {parallel['samples_per_second_at_50mhz']:.0f}/s | {serial['samples_per_second_at_50mhz']:.0f}/s |",
        "",
        "\*Arithmetic throughput only. This is not a timing-closure result.",
        "",
        "The serialized version intentionally trades throughput for multiplier reuse. Its separate",
        "4096-sample RTL parity test must pass before this comparison is accepted.",
    ]
    (out / "synthesis_compare.md").write_text("\n".join(lines) + "\n", encoding="utf-8")

    print(json.dumps({
        "passed": result["passed"],
        "parallel": {k: parallel[k] for k in ("multipliers", "adders", "muxes", "register_cells", "logical_cells", "generic_gate_cells", "cycles_per_sample")},
        "serial": {k: serial[k] for k in ("multipliers", "adders", "muxes", "register_cells", "logical_cells", "generic_gate_cells", "cycles_per_sample")},
        "checks": checks,
    }, indent=2))
    if not result["passed"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
