"""Compare healthy 3-second CSV traces against a pre-change app snapshot."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[3]
IDS = ["jensen-das-ugly-stik-60", "gp-extra-300s-60", "p51d-mustang-120", "sebart-avanti-s-a200-p100rx"]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--baseline", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    engine = str(args.godot.resolve())
    report = {}
    for aircraft in IDS:
        pair = []
        for label, path in [("before", args.baseline.resolve()), ("after", ROOT / "app")]:
            csv = out / f"{aircraft}-{label}.csv"
            run = subprocess.run([engine, "--headless", "--audio-driver", "Dummy", "--path", str(path), "--", f"--aircraft={aircraft}", f"--trace={csv}", "--t=3"], capture_output=True, timeout=60)
            log = run.stdout + run.stderr
            (out / f"{aircraft}-{label}.log").write_bytes(log)
            if run.returncode or b"ERROR:" in log:
                raise RuntimeError(f"{aircraft} {label}: engine failure")
            pair.append(csv.read_bytes())
        # Wall-clock creation time is intentionally volatile; retain every other
        # metadata/header/data byte in the comparison and hash.
        normalized = [b"\n".join(line for line in data.splitlines() if not line.startswith(b"# created_utc:")) for data in pair]
        report[aircraft] = {"identical": normalized[0] == normalized[1], "excluded_metadata": "created_utc only", "sha256_before": hashlib.sha256(normalized[0]).hexdigest(), "sha256_after": hashlib.sha256(normalized[1]).hexdigest(), "bytes": len(normalized[1])}
        print(aircraft, report[aircraft]["identical"], flush=True)
    (out / "trace-parity.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    raise SystemExit(0 if all(record["identical"] for record in report.values()) else 1)


if __name__ == "__main__":
    main()
