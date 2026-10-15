"""Run the audit remediation regression set and retain exact source identities.

Uses the installed pinned engine. Each output directory must be new. This is
software verification; it neither regenerates goldens nor certifies an aircraft.
"""
from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import re
import subprocess
import time

ROOT = Path(__file__).resolve().parents[3]
TESTS = (
    "aero aero_flow aero_continuity wing_polar wing_polar_session downwash_lag "
    "tail_downwash ground_effect dynamics propulsion propulsion_scalar "
    "propeller_wake slipstream_scalar slipstream_downwash wash_profile wash_transport "
    "swirl_accuracy swirl_optimization swirl_torque turbine turbine_continuous "
    "avanti_handling ground_start_integrity retractable_gear_ground "
    "runway_transaction simulation checkpoint replay_integrity flight_log "
    "modes rigid_body rotor_coupling shaft_equilibrium shaft_data mass_inventory "
    "glow_flight_physics glow_installation"
).split()


def identity(app: Path) -> dict[str, str]:
    result = {}
    for directory in ("physics", "sim", "data/aircraft", "data/propulsion"):
        for p in sorted((app / directory).rglob("*")):
            if p.is_file() and p.suffix in (".gd", ".json"):
                result[p.relative_to(app).as_posix()] = hashlib.sha256(p.read_bytes()).hexdigest()
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--app", type=Path, default=ROOT / "app")
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--jobs", type=int, default=3)
    parser.add_argument("--tests", nargs="+", default=TESTS)
    args = parser.parse_args()
    if args.out.exists():
        parser.error("--out must name a new directory; historical evidence is immutable")
    args.out.mkdir(parents=True)
    before = identity(args.app)
    (args.out / "sources-before.json").write_text(json.dumps(before, indent=2) + "\n")

    def run(name: str) -> dict:
        command = [str(args.godot.resolve()), "--headless", "--path", str(args.app.resolve()),
                   "--audio-driver", "Dummy", "--script", f"res://tests/test_{name}.gd"]
        started = time.monotonic()
        try:
            result = subprocess.run(command, capture_output=True, text=True, timeout=300)
            output, exit_code = result.stdout + result.stderr, result.returncode
        except subprocess.TimeoutExpired as error:
            output = f"TIMEOUT: {error}\n"
            exit_code = -1
        (args.out / f"{name}.log").write_text(output, encoding="utf-8")
        errors = re.findall(r"(?m)^(?:(?:SCRIPT|SHADER) )?ERROR:.*|^FAIL.*", output)
        return dict(name=name, command=command, exit_code=exit_code,
                    seconds=round(time.monotonic()-started, 3),
                    ok=exit_code == 0 and not errors, errors=errors[:20])

    with ThreadPoolExecutor(max_workers=max(1, min(args.jobs, 4))) as executor:
        results = list(executor.map(run, args.tests))
    after = identity(args.app)
    drift = [p for p in sorted(before.keys() | after.keys()) if before.get(p) != after.get(p)]
    report = dict(purpose="software regression, not physical validation", results=results,
                  source_drift=drift, stable_source=not drift,
                  ok=not drift and all(r["ok"] for r in results))
    (args.out / "sources-after.json").write_text(json.dumps(after, indent=2) + "\n")
    (args.out / "verification.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"ok": report["ok"], "passed": sum(r["ok"] for r in results),
                      "total": len(results), "failed": [r["name"] for r in results if not r["ok"]],
                      "source_drift": drift}, indent=2))
    return 0 if report["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
