"""Preserve exact baselines, compare data candidates, and verify current catalog recordings."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys

from run_fixture_checks import identity

ROOT = Path(__file__).resolve().parents[3]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, required=True)
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--baseline", type=Path, required=True, help="prior catalog-pulses directory")
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    app, godot, out = args.app.resolve(), args.godot.resolve(), args.out.resolve()
    baseline = args.baseline.resolve()
    out.mkdir(parents=True, exist_ok=False)
    before = identity(app)
    commands = []
    error = ""
    prefix = [str(godot), "--headless", "--path", str(app), "--audio-driver", "Dummy"]

    def run(label, command):
        try:
            result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                    text=True, timeout=240)
            log, code = result.stdout, result.returncode
        except subprocess.TimeoutExpired as exc:
            log, code = exc.stdout or b"", 124
            if isinstance(log, bytes):
                log = log.decode("utf-8", errors="replace")
        (out / (label + ".log")).write_text(log, encoding="utf-8")
        errors = [s for s in log.splitlines() if s.startswith(("ERROR:", "SCRIPT ERROR:", "FAIL"))]
        commands.append({"label": label, "command": command, "exit_code": code, "errors": errors})
        print(json.dumps({"label": label, "exit_code": code, "errors": errors}), flush=True)
        if code != 0 or errors:
            raise RuntimeError(label + " failed; retained output is not an accepted run")

    def replay(label, recording, candidate=None):
        folder = out / label
        folder.mkdir()
        command = prefix + ["--script", "res://tools/flight_log_cli.gd", "--",
                            "--log=" + str(recording), "--csv=" + str(folder / "flight.csv"),
                            "--report=" + str(folder / "replay.json"), "--replay"]
        if candidate is not None:
            command += ["--candidate=" + str(candidate)]
        run(label, command)
        report = json.loads((folder / "replay.json").read_text(encoding="utf-8"))
        expected_mode = "exact" if candidate is None else "candidate"
        if (report.get("status") != "ok" or not report.get("complete") or report.get("rows") != 1441
                or report.get("mode") != expected_mode or report.get("solver_changed")):
            raise RuntimeError(label + " did not establish the declared complete same-source replay")

    try:
        for name, filename in [("stik", "jensen_ugly_stik_60.json"), ("jet", "sebart_avanti_s_a200.json")]:
            recording = baseline / (name + "-normal-yaw.orfl")
            replay(name + "-baseline-exact", recording)
            replay(name + "-data-candidate", recording, app / "data/aircraft" / filename)
            run(name + "-compare", [sys.executable, str(ROOT / "tools/flight_log/flight_log.py"), "compare",
                str(out / (name + "-baseline-exact") / "flight.csv"),
                str(out / (name + "-data-candidate") / "flight.csv"), "--out", str(out / (name + "-comparison.json"))])
        probe = ROOT / "research/physics-audit-2026-10-14/session_probe.gd"
        run("catalog-pulses", prefix + ["--script", str(probe), "--", "--out=" + str(out / "catalog-pulses")])
        for name in ["stik", "jet"]:
            replay(name + "-current-exact", out / "catalog-pulses" / (name + "-normal-yaw.orfl"))
    except (RuntimeError, OSError, ValueError) as exc:
        error = str(exc)
    after = identity(app)
    drift = [p for p in sorted(before.keys() | after.keys()) if before.get(p) != after.get(p)]
    report = {"ok": not error and not drift, "error": error, "source_drift": drift,
              "source_before": before, "source_after": after, "commands": commands,
              "runner_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
              "godot_sha256": hashlib.sha256(godot.read_bytes()).hexdigest(),
              "purpose": "software data-change comparison and exact replay; not physical validation"}
    (out / "verification.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"ok": report["ok"], "error": error, "source_drift": drift}))
    return 0 if report["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
