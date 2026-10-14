"""Focused AV-17-R2 software checks; no claim of full-suite or physical validation."""
from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
ERROR = re.compile(r"^(?:SCRIPT |SHADER )?ERROR:|^FAIL\b", re.MULTILINE)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    engine = [str(args.godot.resolve()), "--headless", "--path", str(ROOT / "app"), "--audio-driver", "Dummy"]
    tests = ["avanti_gamepad", "avanti_gamepad_flight", "avanti_keyboard", "avanti_handling", "rates",
             "wing_polar", "wing_polar_session", "aircraft_contract", "aircraft_data", "turbine_continuous",
             "retractable_gear", "checkpoint", "replay_integrity", "controller_flight_actions"]
    commands = [(name, engine + ["--script", f"res://tests/test_{name}.gd"]) for name in tests]
    commands += [("polar_builder", [sys.executable, "research/avanti-s/av17-r2/test_build_polar.py"]),
                 ("aircraft_current", [sys.executable, "research/avanti-s/av06/derive_physics.py", "--check"]),
                 ("schema_current", [sys.executable, "research/aircraft-standardization/build_schema.py", "--check"]),
                 ("parameters_current", [sys.executable, "research/aircraft-standardization/parameter_register.py", "--check"]),
                 ("descriptors_current", [sys.executable, "research/aircraft-editor/build_descriptors.py", "--check"])]

    def run(item: tuple[str, list[str]]) -> dict:
        name, argv = item
        try:
            result = subprocess.run(argv, cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=180)
            code, log = result.returncode, result.stdout + result.stderr
        except subprocess.TimeoutExpired:
            code, log = 124, "TIMEOUT\n"
        path = out / f"{name}.log"
        path.write_text(log, encoding="utf-8", newline="\n")
        ok = code == 0 and not ERROR.search(log)
        print(f"{'PASS' if ok else 'FAIL'} {name}", flush=True)
        return dict(name=name, argv=argv, ok=bool(ok), exit_code=code, log=path.name,
                    log_sha256=hashlib.sha256(path.read_bytes()).hexdigest())

    with ThreadPoolExecutor(max_workers=3) as pool:
        results = list(pool.map(run, commands))
    ok = all(row["ok"] for row in results)
    (out / "verification.json").write_text(json.dumps(dict(ok=ok, commands=results), indent=2) + "\n", encoding="utf-8")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
