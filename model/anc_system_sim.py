#!/usr/bin/env python3
"""Deterministic acoustic-style LMS experiment for the fixed-point RTL project.

This is still simulation: a synthetic desired signal is mixed with noise produced by
an unknown reference-to-primary path. The path changes halfway through the run so
tracking after a plant change can be measured. A second uncorrelated reference is
used as a negative control; adaptive cancellation should not magically work there.
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import random
from dataclasses import dataclass
from pathlib import Path

FS = 8000
NSAMPLES = 20000
PATH_CHANGE = 10000
TAPS = 4
SEED = 20260923
H1 = (0.52, -0.28, 0.16, -0.07)
H2 = (0.18, 0.43, -0.22, 0.11)
MU_SHIFTS = (3, 4, 5, 6, 7)


def sat16(value: int) -> int:
    return max(-32768, min(32767, int(value)))


def q15(value: float) -> int:
    return sat16(round(value * 32768.0))


def power(values, start: int, stop: int) -> float:
    window = values[start:stop]
    return sum(v * v for v in window) / len(window)


def snr_db(clean, residual_noise, start: int, stop: int) -> float:
    return 10.0 * math.log10(power(clean, start, stop) / power(residual_noise, start, stop))


def make_signals():
    clean = [
        0.14 * math.sin(2.0 * math.pi * 440.0 * n / FS)
        + 0.08 * math.sin(2.0 * math.pi * 730.0 * n / FS)
        + 0.05 * math.sin(2.0 * math.pi * 1230.0 * n / FS)
        for n in range(NSAMPLES)
    ]

    rng = random.Random(SEED)
    reference = []
    previous = 0.0
    for _ in range(NSAMPLES):
        white = rng.gauss(0.0, 0.18)
        sample = max(-0.65, min(0.65, 0.65 * previous + white))
        reference.append(sample)
        previous = sample

    rng_bad = random.Random(SEED + 991)
    uncorrelated = []
    previous = 0.0
    for _ in range(NSAMPLES):
        white = rng_bad.gauss(0.0, 0.18)
        sample = max(-0.65, min(0.65, 0.65 * previous + white))
        uncorrelated.append(sample)
        previous = sample

    noise = []
    for n in range(NSAMPLES):
        h = H1 if n < PATH_CHANGE else H2
        noise.append(sum(h[k] * (reference[n-k] if n >= k else 0.0) for k in range(TAPS)))
    desired = [clean[n] + noise[n] for n in range(NSAMPLES)]
    return clean, reference, uncorrelated, noise, desired


def lms_float(reference, desired, mu: float):
    weights = [0.0] * TAPS
    history = [0.0] * TAPS
    estimate, error = [], []
    for x, d in zip(reference, desired):
        history = [x] + history[:-1]
        y = sum(weights[k] * history[k] for k in range(TAPS))
        e = d - y
        for k in range(TAPS):
            weights[k] += mu * e * history[k]
        estimate.append(y)
        error.append(e)
    return estimate, error, weights


@dataclass
class FixedRun:
    mu_shift: int
    estimate: list[float]
    error: list[float]
    weights_q15: list[int]
    y_saturations: int
    error_saturations: int
    weight_saturations: int


def lms_fixed(reference, desired, mu_shift: int) -> FixedRun:
    reference_q = [q15(v) for v in reference]
    desired_q = [q15(v) for v in desired]
    weights = [0] * TAPS
    history = [0] * TAPS
    estimate, error = [], []
    y_sat = e_sat = w_sat = 0

    for x, d in zip(reference_q, desired_q):
        history = [x] + history[:-1]
        y_raw = sum(weights[k] * history[k] for k in range(TAPS)) >> 15
        y = sat16(y_raw)
        y_sat += y != y_raw

        e_raw = d - y
        e = sat16(e_raw)
        e_sat += e != e_raw

        for k in range(TAPS):
            delta = (e * history[k]) >> (15 + mu_shift)
            w_raw = weights[k] + delta
            new_w = sat16(w_raw)
            w_sat += new_w != w_raw
            weights[k] = new_w

        estimate.append(y / 32768.0)
        error.append(e / 32768.0)

    return FixedRun(mu_shift, estimate, error, weights, y_sat, e_sat, w_sat)


def recovery_samples(clean, residual, threshold_db=15.0):
    window = 500
    for start in range(PATH_CHANGE, min(NSAMPLES-window+1, PATH_CHANGE+6000), 100):
        if snr_db(clean, residual, start, start + window) >= threshold_db:
            return start - PATH_CHANGE
    return None


def run_case(clean, reference, noise, desired, mu_shift):
    run = lms_fixed(reference, desired, mu_shift)
    residual = [run.error[n] - clean[n] for n in range(NSAMPLES)]
    return {
        "mu_shift": mu_shift,
        "mu": f"1/{1 << mu_shift}",
        "pre_output_snr_db": snr_db(clean, residual, 6000, 9000),
        "post_output_snr_db": snr_db(clean, residual, 16000, 19000),
        "pre_improvement_db": snr_db(clean, residual, 6000, 9000) - snr_db(clean, noise, 6000, 9000),
        "post_improvement_db": snr_db(clean, residual, 16000, 19000) - snr_db(clean, noise, 16000, 19000),
        "recovery_to_15db_samples": recovery_samples(clean, residual),
        "weights_q15": run.weights_q15,
        "weights_real": [v / 32768.0 for v in run.weights_q15],
        "saturations": {
            "output": run.y_saturations,
            "error": run.error_saturations,
            "weights": run.weight_saturations,
        },
        "run": run,
    }


def write_csv(cases, path: Path):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(["mu", "pre_output_snr_db", "post_output_snr_db", "pre_improvement_db",
                         "post_improvement_db", "recovery_to_15db_samples", "final_weights_q15",
                         "total_saturations"])
        for c in cases:
            sat = sum(c["saturations"].values())
            writer.writerow([c["mu"], f'{c["pre_output_snr_db"]:.3f}', f'{c["post_output_snr_db"]:.3f}',
                             f'{c["pre_improvement_db"]:.3f}', f'{c["post_improvement_db"]:.3f}',
                             c["recovery_to_15db_samples"], c["weights_q15"], sat])


def write_markdown(result, path: Path):
    lines = [
        "# Acoustic-style ANC and path-tracking simulation",
        "",
        "This is a deterministic synthetic experiment, not a microphone/room measurement.",
        "The primary input is `clean + correlated noise`; the LMS reference sees the noise source",
        "before an unknown four-tap path. That path changes halfway through the run.",
        "",
        f"- input SNR before the path change: **{result['input_snr_pre_db']:.2f} dB**",
        f"- input SNR after the path change: **{result['input_snr_post_db']:.2f} dB**",
        f"- fixed-point/float error RMSE at mu=1/16: **{result['fixed_float_error_rmse']:.6f}** full-scale",
        "",
        "| mu | pre-change output SNR | post-change output SNR | pre improvement | post improvement | samples to recover >=15 dB | final Q1.15 weights |",
        "|---:|---:|---:|---:|---:|---:|---|",
    ]
    for c in result["cases"]:
        lines.append(
            f"| {c['mu']} | {c['pre_output_snr_db']:.2f} dB | {c['post_output_snr_db']:.2f} dB | "
            f"{c['pre_improvement_db']:.2f} dB | {c['post_improvement_db']:.2f} dB | "
            f"{c['recovery_to_15db_samples']} | `{c['weights_q15']}` |"
        )
    lines += [
        "",
        "## Negative control",
        "",
        "The same primary signal was processed using an independent, uncorrelated reference.",
        f"With mu=1/16 the output SNR was only **{result['uncorrelated_reference']['pre_output_snr_db']:.2f} dB** before",
        f"and **{result['uncorrelated_reference']['post_output_snr_db']:.2f} dB** after the path change.",
        "This is intentional: LMS needs a reference correlated with the noise to cancel it.",
        "",
        "## Interpretation",
        "",
        f"For this workload the best average steady-state fixed-point SNR came from **{result['best_mu']}**.",
        "That does not replace the RTL default universally. The earlier system-identification test and this ANC test",
        "have different signal statistics, so step size remains an engineering tradeoff rather than a magic constant.",
        "No output/error/coefficient saturation occurred in the tested amplitude envelope.",
        "",
        "The path-change recovery metric uses a 500-sample sliding SNR window and reports the first 100-sample grid",
        "position after the switch where output SNR reaches at least 15 dB.",
    ]
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def serializable_case(case):
    return {k: v for k, v in case.items() if k != "run"}


def run_experiment():
    clean, reference, uncorrelated, noise, desired = make_signals()
    input_pre = snr_db(clean, noise, 6000, 9000)
    input_post = snr_db(clean, noise, 16000, 19000)

    cases = [run_case(clean, reference, noise, desired, shift) for shift in MU_SHIFTS]
    best = max(cases, key=lambda c: (c["pre_output_snr_db"] + c["post_output_snr_db"]) / 2.0)

    default = next(c for c in cases if c["mu_shift"] == 4)
    bad = run_case(clean, uncorrelated, noise, desired, 4)

    ref_qfloat = [q15(v) / 32768.0 for v in reference]
    desired_qfloat = [q15(v) / 32768.0 for v in desired]
    _, float_error, _ = lms_float(ref_qfloat, desired_qfloat, 1.0 / 16.0)
    fixed_error = default["run"].error
    rmse = math.sqrt(sum((a-b) ** 2 for a, b in zip(float_error, fixed_error)) / NSAMPLES)
    max_error = max(abs(a-b) for a, b in zip(float_error, fixed_error))

    checks = {
        "default_mu_improves_pre_snr_by_12db": default["pre_improvement_db"] >= 12.0,
        "default_mu_improves_post_snr_by_12db": default["post_improvement_db"] >= 12.0,
        "default_mu_retracks_after_path_change": default["recovery_to_15db_samples"] is not None,
        "fixed_float_rmse_below_0p002_full_scale": rmse < 0.002,
        "no_fixed_point_saturation_in_test_envelope": all(
            sum(c["saturations"].values()) == 0 for c in cases
        ),
        "uncorrelated_reference_does_not_fake_anc": bad["pre_improvement_db"] < 3.0,
    }

    return {
        "scope": "deterministic synthetic ANC/path-tracking simulation; no physical microphone, ADC, DAC or room measurement",
        "sample_rate_hz": FS,
        "samples": NSAMPLES,
        "path_change_sample": PATH_CHANGE,
        "hidden_path_before": H1,
        "hidden_path_after": H2,
        "input_snr_pre_db": input_pre,
        "input_snr_post_db": input_post,
        "best_mu": best["mu"],
        "fixed_float_error_rmse": rmse,
        "fixed_float_error_max_abs": max_error,
        "cases": [serializable_case(c) for c in cases],
        "uncorrelated_reference": serializable_case(bad),
        "checks": checks,
        "passed": all(checks.values()),
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-dir", default="results")
    args = parser.parse_args()
    out = Path(args.output_dir)
    out.mkdir(parents=True, exist_ok=True)

    result = run_experiment()
    (out / "anc_system_sim.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
    write_csv(result["cases"], out / "anc_system_sim.csv")
    write_markdown(result, out / "anc_system_sim.md")

    print(json.dumps({
        "passed": result["passed"],
        "input_snr_pre_db": round(result["input_snr_pre_db"], 3),
        "input_snr_post_db": round(result["input_snr_post_db"], 3),
        "best_mu": result["best_mu"],
        "fixed_float_error_rmse": round(result["fixed_float_error_rmse"], 7),
        "checks": result["checks"],
    }, indent=2))
    if not result["passed"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
