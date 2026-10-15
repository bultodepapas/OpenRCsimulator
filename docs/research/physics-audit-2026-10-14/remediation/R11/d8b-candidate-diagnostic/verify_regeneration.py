#!/usr/bin/env python3
"""Verify scratch D8b candidate regeneration against frozen-07 inputs and history."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[6]
SCRATCH = ROOT / "tmp/physics-audit-r11-d8b-candidate-repro-02"
HISTORY = ROOT / "tmp/physics-audit-r11-d8b-candidate-repro-01"
MANIFEST = ROOT / "docs/research/physics-audit-2026-10-14/remediation/R11/next-candidate/materialized-20261015-07-01/post-overlay-initial.json"
OUT = ROOT / "docs/research/physics-audit-2026-10-14/remediation/R11/d8b-candidate-diagnostic/execution/04-regeneration-verification.json"
CANDIDATES = [
    "research/flight-robustness/d8b-r2/candidates/steep.json",
    "research/flight-robustness/d8b-r2/candidates/intermediate.json",
    "research/flight-robustness/d8b-r2/candidates/retained.json",
]
PINNED = [
    "app/data/aircraft/jensen_ugly_stik_60.json",
    "app/physics/aircraft_data.gd",
    "app/tests/wing_polar_fixture.gd",
    "app/tests/test_pullup_cli.py",
    "app/project.godot",
    "research/flight-robustness/d8b-r2/make_candidates.gd",
]


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def tree_hashes(directory: Path) -> dict[str, str]:
    return {p.relative_to(directory).as_posix(): sha256(p) for p in directory.rglob("*") if p.is_file()}


def diff(a: Any, b: Any, path: str = "") -> list[dict[str, Any]]:
    if isinstance(a, (int, float)) and not isinstance(a, bool) and isinstance(b, (int, float)) and not isinstance(b, bool):
        return [] if a == b else [{"path": path, "before": a, "after": b}]
    if isinstance(a, dict) and isinstance(b, dict):
        result = []
        for key in sorted(set(a) | set(b)):
            child = f"{path}/{key}"
            if key not in a or key not in b:
                result.append({"path": child, "before_present": key in a, "after_present": key in b})
            else:
                result.extend(diff(a[key], b[key], child))
        return result
    if isinstance(a, list) and isinstance(b, list):
        if len(a) != len(b):
            return [{"path": path, "before_length": len(a), "after_length": len(b)}]
        result = []
        for i, (left, right) in enumerate(zip(a, b)):
            result.extend(diff(left, right, f"{path}/{i}"))
        return result
    return [] if a == b else [{"path": path, "before": a, "after": b}]


def without_polar(document: dict[str, Any]) -> dict[str, Any]:
    copied = json.loads(json.dumps(document))
    copied.get("aero", {}).pop("wing_polar", None)
    return copied


def main() -> int:
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    frozen = {row["path"]: row for row in manifest["entries"]}
    pinned_hashes = {path: frozen[path]["sha256"] for path in PINNED}
    pinned_actual = {path: sha256(SCRATCH / path) for path in PINNED}
    pinned_match = pinned_actual == pinned_hashes

    base = json.loads((SCRATCH / "app/data/aircraft/jensen_ugly_stik_60.json").read_text(encoding="utf-8"))
    candidates = []
    for relative in CANDIDATES:
        generated_path = SCRATCH / relative
        historical_path = HISTORY / relative
        generated = json.loads(generated_path.read_text(encoding="utf-8"))
        historical = json.loads(historical_path.read_text(encoding="utf-8"))
        nonpolar = diff(without_polar(generated), without_polar(base))
        polar_delta = diff(historical.get("aero", {}).get("wing_polar"), generated.get("aero", {}).get("wing_polar"), "/aero/wing_polar")
        candidates.append({
            "path": relative,
            "before_sha256": sha256(historical_path),
            "after_sha256": sha256(generated_path),
            "bytes_changed": historical_path.read_bytes() != generated_path.read_bytes(),
            "nonpolar_dictionary_matches_frozen_catalog": len(nonpolar) == 0,
            "nonpolar_differences": nonpolar,
            "polar_unchanged_vs_frozen_candidate": len(polar_delta) == 0,
            "polar_differences_vs_frozen_candidate": polar_delta,
        })

    app_manifest = {p: row["sha256"] for p, row in frozen.items() if p.startswith("app/")}
    research_prefix = "research/flight-robustness/d8b-r2/"
    d8b_manifest = {p: row["sha256"] for p, row in frozen.items() if p.startswith(research_prefix)}
    allowed_changes = set(CANDIDATES)
    generated_exclusions = ("app/.godot/", "app/tests/__pycache__/")
    manifest_targets = {**app_manifest, **d8b_manifest}
    mismatches = []
    for relative, expected in manifest_targets.items():
        if relative in allowed_changes or relative.startswith(generated_exclusions):
            continue
        target = SCRATCH / relative
        if not target.is_file():
            mismatches.append({"path": relative, "problem": "missing"})
        else:
            actual = sha256(target)
            if actual != expected:
                mismatches.append({"path": relative, "expected": expected, "actual": actual})
    extra_source_files = []
    for directory, prefix in ((SCRATCH / "app", "app/"), (SCRATCH / "research/flight-robustness/d8b-r2", research_prefix)):
        for path in directory.rglob("*"):
            if not path.is_file():
                continue
            relative = prefix + path.relative_to(directory).as_posix()
            if relative.startswith(generated_exclusions) or relative in allowed_changes:
                continue
            if relative not in manifest_targets:
                extra_source_files.append(relative)

    godot_cache = SCRATCH / "app/.godot"
    cache_files = sum(1 for path in godot_cache.rglob("*") if path.is_file()) if godot_cache.exists() else 0
    receipt = {
        "format": "d8b-r2-regeneration-verification-v1",
        "scope": "static post-run verification of isolated copy; no production or frozen-07 writes",
        "scratch_root": "tmp/physics-audit-r11-d8b-candidate-repro-02",
        "history_root": "tmp/physics-audit-r11-d8b-candidate-repro-01 (unexecuted initial frozen copy)",
        "manifest_sha256": sha256(MANIFEST),
        "pinned_frozen_inputs_match": pinned_match,
        "pinned_source_hashes": {path: {"expected": pinned_hashes[path], "actual": pinned_actual[path]} for path in PINNED},
        "candidates": candidates,
        "non_candidate_source_drift": mismatches,
        "unexpected_source_files": sorted(extra_source_files),
        "generated_import_cache": {"app_dot_godot_excluded_from_source_copy": True, "generated_file_count_after_import": cache_files},
    }
    rendered = json.dumps(receipt, indent=2, ensure_ascii=False) + "\n"
    if OUT.exists():
        raise SystemExit(f"refusing to overwrite existing verification receipt: {OUT}")
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(rendered, encoding="utf-8", newline="\n")
    print(rendered, end="")
    return 0 if pinned_match and not mismatches and not extra_source_files and all(
        item["nonpolar_dictionary_matches_frozen_catalog"] for item in candidates
    ) else 1


if __name__ == "__main__":
    raise SystemExit(main())
