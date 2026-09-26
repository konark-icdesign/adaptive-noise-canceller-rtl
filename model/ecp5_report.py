#!/usr/bin/env python3
import argparse, json, re
from pathlib import Path

def yosys_counts(path):
    data=json.loads(Path(path).read_text())
    mod=next(iter(data["modules"].values()))
    counts={}
    for c in mod.get("cells",{}).values():
        t=c["type"]
        counts[t]=counts.get(t,0)+1
    return counts

def parse_log(path):
    text=Path(path).read_text(errors="replace")
    mhz=None
    matches=re.findall(r"Max frequency for clock.*?:\s*([0-9.]+) MHz", text)
    if matches:
        mhz=float(matches[-1])
    return {"max_frequency_mhz":mhz}

def summarize(name, build):
    c=yosys_counts(build/f"{name}.json")
    t=parse_log(build/f"{name}_pnr.log")
    return {
      "TRELLIS_SLICE": c.get("TRELLIS_SLICE",0),
      "MULT18X18D": c.get("MULT18X18D",0),
      "ALU54B": c.get("ALU54B",0),
      "DP16KD": c.get("DP16KD",0),
      "DCCA": c.get("DCCA",0),
      "max_frequency_mhz": t["max_frequency_mhz"],
      "meets_50mhz": (t["max_frequency_mhz"] is not None and t["max_frequency_mhz"] >= 50.0),
    }

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--build-dir",default="build/ecp5")
    ap.add_argument("--output-dir",default="results")
    a=ap.parse_args()
    build=Path(a.build_dir)
    out=Path(a.output_dir)
    out.mkdir(parents=True,exist_ok=True)
    p=summarize("parallel",build)
    s=summarize("serial",build)
    result={
      "scope":"Lattice ECP5-25F reference-target synth_ecp5 + nextpnr-ecp5 place-and-route; not a physical-board measurement",
      "target":"LFE5U-25F, CABGA256, speed grade 6",
      "constraint_mhz":50.0,
      "parallel":p,
      "serial":s,
      "checks":{
        "parallel_meets_50mhz":p["meets_50mhz"],
        "serial_meets_50mhz":s["meets_50mhz"],
        "serial_uses_fewer_dsp_multipliers":s["MULT18X18D"] < p["MULT18X18D"],
      }
    }
    result["passed"]=all(result["checks"].values())
    (out/"ecp5_implementation.json").write_text(json.dumps(result,indent=2))
    lines=[
      "# ECP5 implementation study","",
      "Reference implementation target only: LFE5U-25F, CABGA256, speed grade 6. This is synthesis/place-and-route evidence, not physical FPGA-board validation.","",
      "| metric | parallel LMS | serialized LMS |","|---|---:|---:|",
      f"| ECP5 slices | {p['TRELLIS_SLICE']} | {s['TRELLIS_SLICE']} |",
      f"| MULT18X18D DSP blocks | {p['MULT18X18D']} | {s['MULT18X18D']} |",
      f"| DP16KD BRAMs | {p['DP16KD']} | {s['DP16KD']} |",
      f"| reported max frequency | {p['max_frequency_mhz']} MHz | {s['max_frequency_mhz']} MHz |",
      f"| meets 50 MHz constraint | {p['meets_50mhz']} | {s['meets_50mhz']} |","",
      "The parallel core accepts one sample per clock; the serialized core accepts one every nine clocks. At 50 MHz that corresponds to arithmetic input capacities of 50 MS/s and 5.56 MS/s respectively, both well above 48 kHz audio if timing closes.","",
      "These figures depend on the reference FPGA family, synthesis mapping and unconstrained I/O placement. They are not portable resource/Fmax claims for a different FPGA."
    ]
    (out/"ecp5_implementation.md").write_text("\n".join(lines)+"\n")
    print(json.dumps(result,indent=2))
    if not result["passed"]:
        raise SystemExit(1)

if __name__=="__main__":
    main()
