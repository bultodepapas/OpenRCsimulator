"""Run pinned-engine crash checks and native rendered/audio scenarios; retain evidence.

Python 3, no packages. Native scenarios require a display and working audio device.
Example: python research/crash-damage/cr-22a/qualify.py --godot .tools/Godot_v4.7.2-stable_win64_console.exe --out .tools/crash-qualification
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[3]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--headless-only", action="store_true")
    args = parser.parse_args()
    engine, out = args.godot.resolve(), args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    base = [str(engine), "--path", str(ROOT / "app")]
    summary = {"tests": {}, "scenarios": {}, "source_sha256": {}}
    files = list((ROOT / "app/render/crash").glob("*.gd"))
    files += [ROOT / p for p in ["app/main.gd", "app/sim/flight_session.gd", "research/crash-damage/cr-22a/scenario.gd"]]
    for path in files:
        summary["source_sha256"][path.relative_to(ROOT).as_posix()] = hashlib.sha256(path.read_bytes()).hexdigest()

    def run(label, command):
        result = subprocess.run(command, capture_output=True, timeout=180, cwd=ROOT)
        log = result.stdout + result.stderr
        (out / (label + ".log")).write_bytes(log)
        text = log.decode("utf-8", errors="replace")
        errors = re.findall(r"^(?:(?:SCRIPT|SHADER) )?ERROR:.*", text, re.M)
        record = {"exit_code": result.returncode, "engine_errors": errors,
                  "checks": re.findall(r"^\d+ checks,.*", text, re.M)}
        print(label, json.dumps(record), flush=True)
        return record

    for test in ["severity", "effects", "wreck", "audio", "integration", "pose"]:
        summary["tests"][test] = run("test-" + test, base + ["--headless", "--audio-driver", "Dummy", "--script", f"res://tests/test_crash_{test}.gd"])
    if not args.headless_only:
        summary["tests"]["integration-native"] = run("test-integration-native", base + ["--script", "res://tests/test_crash_integration.gd"])
        for name, aircraft, flown in [
            ("ugly-flown", "jensen-das-ugly-stik-60", True),
            ("jet-flown", "sebart-avanti-s-a200-p100rx", True),
            ("scrape", "jensen-das-ugly-stik-60", False),
            ("wingtip", "jensen-das-ugly-stik-60", False),
        ]:
            command = base + ["--script", str(ROOT / "research/crash-damage/cr-22a/scenario.gd"), "--",
                              f"--aircraft={aircraft}", f"--crash-out={out}", f"--crash-name={name}", "--crash-audio", "--audio-seed=2201"]
            if flown:
                command.append("--crash-flown")
            summary["scenarios"][name] = run(name, command)
    summary["source_unchanged"] = all(hashlib.sha256((ROOT / p).read_bytes()).hexdigest() == digest for p, digest in summary["source_sha256"].items())
    summary["passed"] = summary["source_unchanged"] and all(record["exit_code"] == 0 and not record["engine_errors"] for group in ["tests", "scenarios"] for record in summary[group].values())
    (out / "qualification.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    raise SystemExit(0 if summary["passed"] else 1)


if __name__ == "__main__":
    main()
