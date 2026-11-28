#!/usr/bin/env python3
"""Reproduce the dated counterexamples through OpenRC's checked runner, serially."""
import argparse
import hashlib
import json
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
CASES = {
    "turbine": ("turbine_admission.gd", "TURBINE ADMISSION 34 checks, 0 failed", 240, []),
    "skyline": ("skyline_tree_toggle.gd", "AUDIT_TREE_SKYLINE", 120, []),
    "birds": ("birds_off_poll.gd", "AUDIT_BIRDS_OFF", 120, []),
    "water": ("water_after_expiry.gd", "AUDIT_WATER_TAIL", 180, ["--soundscape=off"]),
    "rotor": ("rotor_null.gd", "ROTATIONAL NULL", 120, []),
    "gate": ("gate_projection.gd", "R2_GATE_PROJECTION cases=7 failed=0", 120, []),
    "lake": ("lake_crest.gd", "R2_LAKE_CREST checks=12 failed=0", 120, []),
    "records": ("race_book_two_windows.gd", "R2_RACE_BOOK", 180, []),
    "draft": ("controller_duplicate_draft.gd", "R2_CONTROLLER_DRAFT", 180, []),
}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True, type=Path, help="Pinned Godot executable")
    parser.add_argument("--case", choices=["all", *CASES], default="all")
    args = parser.parse_args()
    engine = args.godot.resolve()
    version = subprocess.check_output([str(engine), "--version"], text=True).strip()
    if version != "4.8.beta2.official.cafc17a19":
        parser.error("This evidence requires Godot 4.8.beta2.official.cafc17a19; got " + version)
    (REPO / "tmp").mkdir(exist_ok=True)
    output = Path(tempfile.mkdtemp(prefix="swarm-systems-r2-", dir=REPO / "tmp"))
    summary = []
    selected = CASES if args.case == "all" else {args.case: CASES[args.case]}
    for name, (script_name, marker, timeout, extra) in selected.items():
        script = HERE / "probes" / script_name
        command = [
            sys.executable, str(REPO / "tools/godot/run_checked.py"),
            "--label", "r2-" + name, "--timeout", str(timeout),
            "--require-text", marker, "--out-dir", str(output),
            "--", str(engine), "--headless", "--path", str(REPO / "app"),
            "--audio-driver", "Dummy", "--script", str(script),
        ]
        if extra:
            command += ["--", *extra]
        with (output / (name + "-console.log")).open("w") as stream:
            completed = subprocess.run(command, cwd=REPO, stdout=stream, stderr=subprocess.STDOUT)
        reports = list(output.glob("r2-" + name + "-*/report.json"))
        if len(reports) != 1:
            raise RuntimeError("Expected one checked report for " + name)
        report = json.loads(reports[0].read_text())
        summary.append({
            "case": name, "probe_sha256": hashlib.sha256(script.read_bytes()).hexdigest(),
            "report": str(reports[0].relative_to(output)),
            **{key: report[key] for key in ("ok", "exit_code", "counts", "log_sha256")},
        })
        (output / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
        print(name, "PASS" if report["ok"] else "FAIL", str(reports[0]), flush=True)
        if completed.returncode or not report["ok"]:
            return completed.returncode or 1
    print("Results:", output)
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
