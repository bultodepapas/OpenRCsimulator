"""Capture the exact working-tree identity audited; never modify application files."""
from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "docs/research/physics-audit-2026-10-14"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("label", choices=("before", "after"))
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    paths = set()
    for folder in ("app/physics", "app/sim", "app/input", "app/data/aircraft", "app/data/schema", "app/data/ground", "app/data/atmosphere"):
        paths.update(p for p in (ROOT / folder).rglob("*") if p.is_file() and p.suffix in {".gd", ".json"})
    for name in ("app/project.godot", "app/spec.gd", "app/app_state/aircraft_catalog.gd", "app/main.gd", "app/app_root.gd"):
        paths.add(ROOT / name)
    hashes = {p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(paths)}
    result = {
        "audit_date": "2026-10-14", "timezone": "America/Bogota",
        "head": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
        "engine": subprocess.check_output([str(ROOT / ".tools/Godot_v4.7.2-stable_win64_console.exe"), "--version"], text=True).strip(),
        "source_sha256": hashes,
        "scope": "Current dirty working tree, not HEAD alone. Windows native headless. No production edits authorized by this audit.",
    }
    (OUT / f"identity-{args.label}.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    status = subprocess.check_output(["git", "status", "--short"], cwd=ROOT, text=True)
    (OUT / f"git-status-{args.label}.txt").write_text(status, encoding="utf-8")
    print(f"Captured {len(hashes)} source hashes at {result['head']}")
    if args.label == "after":
        before = json.loads((OUT / "identity-before.json").read_text(encoding="utf-8"))
        changed = [p for p in sorted(hashes.keys() | before["source_sha256"].keys()) if hashes.get(p) != before["source_sha256"].get(p)]
        (OUT / "source-drift.json").write_text(json.dumps({"changed_paths": changed}, indent=2) + "\n", encoding="utf-8")
        print(f"Source drift: {changed}")


if __name__ == "__main__":
    main()
