"""Isolate the H12 failure in a disposable test copy, without changing production."""
from __future__ import annotations

import hashlib
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "docs/research/physics-audit-2026-10-14/checks"
SOURCE = ROOT / "app/tests/test_aero_flow.gd"


def main() -> None:
    source_bytes = SOURCE.read_bytes()
    source = source_bytes.decode("utf-8")
    pattern = 'for key in ["induced_map", "strip_slope", "strip_cl0"]:'
    assert source.count(pattern) == 1
    disposable = ROOT / "tmp/physics-audit-2026-10-14/test_aero_flow_without_polar.gd"
    disposable.parent.mkdir(parents=True, exist_ok=True)
    disposable.write_text(source.replace(pattern, 'for key in ["wing_polar", "induced_map", "strip_slope", "strip_cl0"]:'), encoding="utf-8")
    records = []
    for label, target in (("h12-current", SOURCE), ("h12-polar-neutralized-disposable-test", disposable)):
        command = [str(ROOT / ".tools/Godot_v4.7.2-stable_win64_console.exe"), "--headless", "--path", str(ROOT / "app"), "--audio-driver", "Dummy", "--script", str(target)]
        result = subprocess.run(command, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=120)
        output = result.stdout + "\n--- STDERR ---\n" + result.stderr
        (OUT / f"{label}.log").write_text(output, encoding="utf-8")
        record = {"label": label, "command": command, "exit_code": result.returncode,
                  "source_sha256": hashlib.sha256(target.read_bytes()).hexdigest(),
                  "summaries": [line for line in output.splitlines() if line.startswith(("H4 ", "H12 "))]}
        records.append(record)
        print(record, flush=True)
    assert SOURCE.read_bytes() == source_bytes, "Production test changed during investigation"
    (OUT / "h12-isolation.json").write_text(json.dumps(records, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
