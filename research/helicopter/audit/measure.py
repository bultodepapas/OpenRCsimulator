#!/usr/bin/env python3
"""Paired whole-session control optimization proof on disposable script copies."""
import argparse
import hashlib
import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    args = parser.parse_args()
    out = args.out.resolve()
    out.relative_to((ROOT / ".tools").resolve())
    out.mkdir(parents=True, exist_ok=False)
    flight_path = ROOT / "app/physics/rotorcraft/flight_dynamics.gd"
    session_path = ROOT / "app/sim/helicopter_flight_session.gd"
    flight = flight_path.read_text(encoding="utf-8")
    session = session_path.read_text(encoding="utf-8")
    token = "Electronics.fast_evaluate(context.electronics_model"
    assert flight.count(token) == 1
    reference_flight = out / "reference_flight.gd"
    reference_flight.write_text(flight.replace(token, "Electronics.evaluate(context.electronics_model"), encoding="utf-8", newline="\n")
    token = 'preload("res://physics/rotorcraft/flight_dynamics.gd")'
    assert session.count(token) == 1
    reference_session = out / "reference_session.gd"
    reference_session.write_text(session.replace(token, "preload(" + json.dumps(reference_flight.as_posix()) + ")"), encoding="utf-8", newline="\n")
    provenance = {"comparison": "same session/kernel laws; only electronics revalidation entry differs",
                  "flight_source_sha256": hashlib.sha256(flight_path.read_bytes()).hexdigest(),
                  "session_source_sha256": hashlib.sha256(session_path.read_bytes()).hexdigest()}
    (out / "provenance.json").write_text(json.dumps(provenance, indent=2) + "\n", encoding="utf-8")
    result = subprocess.run([str(args.godot.resolve()), "--headless", "--path", str(ROOT / "app"),
                             "--script", str(Path(__file__).with_name("bench_session.gd")), "--",
                             "--reference-session=" + str(reference_session), "--out=" + str(out / "paired.json")],
                            cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, encoding="utf-8", errors="replace", timeout=180)
    (out / "paired.log").write_text(result.stdout, encoding="utf-8")
    if result.returncode or re.search(r"^(?:SCRIPT |SHADER )?ERROR:", result.stdout, re.MULTILINE):
        raise RuntimeError(result.stdout[-4000:])
    report = json.loads((out / "paired.json").read_text())
    assert report["ok"] and report["state_hashes"] == report["reference_state_hashes"]
    print(json.dumps({k: report[k] for k in ("medians", "reference_whole_tick_median_us", "paired_whole_tick_speedup", "ok")}, indent=2))


if __name__ == "__main__":
    main()
