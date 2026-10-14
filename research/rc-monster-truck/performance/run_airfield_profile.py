"""Run the production airfield course profiler with a hidden, bounded Godot process."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
GODOT = ROOT / ".tools" / "Godot_v4.7.2-stable_win64.exe"
SOURCES = [
    "app/physics/ground_vehicle/airfield_course.gd",
    "app/physics/ground_vehicle/airfield_track.gd",
    "app/physics/ground_vehicle/vehicle_dynamics.gd",
    "app/physics/ground_terrain.gd",
    "app/physics/ground_contact.gd",
    "app/sim/ground_vehicle/session.gd",
    "app/data/ground_vehicle/airfield_track.json",
    "app/data/fields/default.json",
    "research/rc-monster-truck/performance/vehicle_snapshot.json",
    "research/rc-monster-truck/performance/bench_airfield.gd",
]


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def source_identity():
    return {name: sha256(ROOT / name) for name in SOURCES}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, default=GODOT)
    parser.add_argument("--out", type=Path, required=True,
                        help="new evidence directory; existing output is never overwritten")
    args = parser.parse_args()
    out = args.out.resolve()
    if out.exists():
        parser.error("--out must be a new directory")
    binary = args.godot.resolve()
    if not binary.is_file():
        parser.error(f"Godot executable not found: {binary}")
    profile_path = out / "profile.json"
    command = [str(binary), "--headless", "--path", "app", "--audio-driver", "Dummy",
               "--script", str(ROOT / "research/rc-monster-truck/performance/bench_airfield.gd"),
               "--", f"--output={profile_path}"]
    started = datetime.now(timezone.utc)
    before = source_identity()
    out.mkdir(parents=True)
    try:
        result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True,
                                encoding="utf-8", errors="replace", timeout=300,
                                creationflags=0x08000000 if os.name == "nt" else 0)
        output = result.stdout + result.stderr
        code = result.returncode
    except subprocess.TimeoutExpired as exc:
        output = f"TIMEOUT after 300 seconds: {exc}"
        code = -1
    (out / "run.log").write_text(output, encoding="utf-8")
    if code != 0 or not profile_path.is_file():
        print(output, file=sys.stderr)
        raise SystemExit(f"profile failed (exit {code}); see {out / 'run.log'}")
    report = json.loads(profile_path.read_text(encoding="utf-8"))
    after = source_identity()
    report["execution"] = {
        "started_utc": started.isoformat(),
        "repo_head": subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT, capture_output=True,
                                     text=True, check=True).stdout.strip(),
        "godot": str(binary),
        "godot_sha256": sha256(binary),
        "command": command,
        "exit_code": code,
        "timeout_seconds": 300,
        "source_sha256_before": before,
        "source_sha256_after": after,
        "sources_unchanged_during_profile": before == after,
    }
    profile_path.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(json.dumps({"ok": code == 0 and before == after,
                      "profile": str(profile_path),
                      "tick_cost": report.get("tick_cost"),
                      "sampler_cost": report.get("sampler_cost"),
                      "sources_unchanged": before == after}, indent=2))
    raise SystemExit(0 if before == after else 1)


if __name__ == "__main__":
    main()
