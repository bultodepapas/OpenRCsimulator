#!/usr/bin/env python3
"""TOD-07: exercise a Linux export without a source-project fallback."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    args = parser.parse_args()
    binary = args.binary.resolve()
    results = {}
    with tempfile.TemporaryDirectory(prefix="openrc-tod-export-") as directory:
        work = Path(directory)
        for name, options in (("legacy", []), ("night", ["--time-of-day=00:00"]),
                              ("noon", ["--time-of-day=12:00"])):
            trace = work / (name + ".csv")
            run = subprocess.run(
                [str(binary), "--headless", "--audio-driver", "Dummy", "--",
                 "--trace=" + str(trace), "--t=.1", *options],
                cwd=work, capture_output=True, text=True, timeout=90,
            )
            log = run.stdout + run.stderr
            if run.returncode or re.search(r"^(?:SCRIPT |SHADER )?ERROR:", log, re.M):
                raise RuntimeError(log)
            lines = trace.read_text().splitlines()
            context = next((json.loads(line.split(": ", 1)[1]) for line in lines
                            if line.startswith("# visual_context: ")), None)
            physics = "\n".join(line for line in lines if not line.startswith(
                ("# visual_context: ", "# created_utc: ")))
            assert bool(context) == (name != "legacy")
            results[name] = {
                "context": context,
                "physics_sha256": hashlib.sha256(physics.encode()).hexdigest(),
                "data_rows": sum(bool(line) and not line.startswith("#") for line in lines) - 1,
            }
            assert results[name]["data_rows"] == 25
        assert len({row["physics_sha256"] for row in results.values()}) == 1
        assert results["night"]["context"]["solar"]["elevation_deg"] < -18
        invalid_trace = work / "invalid.csv"
        invalid = subprocess.run(
            [str(binary), "--headless", "--audio-driver", "Dummy", "--",
             "--time-of-day=25:00", "--trace=" + str(invalid_trace), "--t=.1"],
            cwd=work, capture_output=True, text=True, timeout=90,
        )
        assert invalid.returncode != 0 and not invalid_trace.exists()
        assert "lighting:" in invalid.stdout + invalid.stderr
    report = {
        "format": "openrc-tod-export-check v1", "ok": True,
        "binary_sha256": hashlib.sha256(binary.read_bytes()).hexdigest(),
        "routes": results, "invalid_refused": True, "physics_equal": True,
        "scope": "Linux native headless, embedded pack, empty working directory; no source --path",
    }
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(report, indent=2) + "\n")
    print("Linux pack: legacy/noon/night physics identical; context and invalid-input refusal verified.")


if __name__ == "__main__":
    main()
