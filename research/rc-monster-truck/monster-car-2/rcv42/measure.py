"""Run accepted RCV-42 measurements sequentially, retaining exits, logs and hashes."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[4]
LANES = [
    ("batch", "research/rc-monster-truck/monster-car-2/rcv42/probe_batch.gd"),
    ("paired", "research/rc-monster-truck/monster-car-2/rcv42/bench_pair.gd"),
    ("candidate", "research/rc-monster-truck/monster-car-2/rcv41/bench_session.gd"),
]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    paths = [*sorted((ROOT / "app/physics/ground_vehicle").glob("*.gd")),
             ROOT / "app/physics/math3d.gd", ROOT / "app/sim/ground_vehicle/session.gd",
             *sorted(Path(__file__).parent.glob("*.gd"))]
    identities = {p.relative_to(ROOT).as_posix(): sha(p) for p in paths}
    rows = []
    for name, script in LANES:
        report_path, log_path = out / (name + ".json"), out / (name + ".log")
        command = [str(args.godot.resolve()), "--headless", "--path", str(ROOT / "app"),
                   "--audio-driver", "Dummy", "--script", "res://../" + script,
                   "--", "--output=" + report_path.as_posix()]
        result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True,
                                encoding="utf-8", errors="replace", timeout=300)
        log = result.stdout + result.stderr
        log_path.write_text(log, encoding="utf-8")
        errors = re.findall(r"^(?:(?:SCRIPT |SHADER )?ERROR:|FAIL[: ]).*$", log, re.M)
        if result.returncode or errors or not report_path.exists():
            raise RuntimeError(f"{name} failed: exit={result.returncode}, errors={errors}")
        report = json.loads(report_path.read_text(encoding="utf-8"))
        if not report.get("complete"):
            raise RuntimeError(f"Incomplete {name}")
        rows.append({"name": name, "exit_code": result.returncode, "errors": errors,
                     "report_sha256": sha(report_path), "log_sha256": sha(log_path),
                     "script": script, "script_sha256": sha(ROOT / script)})
        print(f"PASS {name}", flush=True)
    for path, digest in identities.items():
        if sha(ROOT / path) != digest:
            raise RuntimeError(f"Source changed during measurement: {path}")
    (out / "measurement-receipt.json").write_text(json.dumps({"complete": True,
        "sources": identities, "measurements": rows}, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
