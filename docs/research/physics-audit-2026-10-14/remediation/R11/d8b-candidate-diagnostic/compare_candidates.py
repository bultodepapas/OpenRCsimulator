#!/usr/bin/env python3
"""Static D8b-R2 candidate/source comparison; does not run Godot or write inputs."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[6]
MATERIALIZED = ROOT / "docs/research/physics-audit-2026-10-14/remediation/R11/next-candidate/materialized-20261015-07-01"
MANIFEST = MATERIALIZED / "post-overlay-initial.json"
BASE = ROOT / "app/data/aircraft/jensen_ugly_stik_60.json"
CANDIDATE_DIR = ROOT / "research/flight-robustness/d8b-r2/candidates"
EXPECTED = {
    "app/data/aircraft/jensen_ugly_stik_60.json": "bdcf4d64c45676a112d837513ee1eef7ed017c39fa8b39b21236cd801950f723",
    "app/physics/aircraft_data.gd": "40a574c5c049179941372d7c355cb53f1ede4588154201070618c8108bd353b9",
    "app/tests/wing_polar_fixture.gd": "13d9f43b6cbbb1e70a1ceac4a7bc8c87b982faf8a1722d09df34f011fc68e88b",
    "research/flight-robustness/d8b-r2/make_candidates.gd": "636f0bcf8c4c1166bac90b450bc18a01e8e131d3c6ae6595231f5131a126e4b2",
    "research/flight-robustness/d8b-r2/candidates/steep.json": "ee8e7cc612f0e374dbe7587215ead5b978f6d7c0d81fa15680abcd4f9e5cc9fe",
    "research/flight-robustness/d8b-r2/candidates/intermediate.json": "46c999b7d84ea1c1c6d5dfc181cdd47efa3c0eeb63799ddb4d5a1f44376b578e",
    "research/flight-robustness/d8b-r2/candidates/retained.json": "dba2f262a17b08250a5f74d1c8cbf88f3fd123ed22b4c5161a672f3b99afc45b",
}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def remove_polar(document: dict[str, Any]) -> dict[str, Any]:
    copied = json.loads(json.dumps(document))
    copied.get("aero", {}).pop("wing_polar", None)
    return copied


def differences(left: Any, right: Any, path: str = "") -> list[dict[str, Any]]:
    # JSON/Godot parse integral and decimal spellings as numeric values; compare
    # numeric value rather than Python's int-vs-float representation.
    if isinstance(left, (int, float)) and not isinstance(left, bool) and isinstance(right, (int, float)) and not isinstance(right, bool):
        return [] if left == right else [{"path": path, "candidate": left, "catalog": right}]
    if isinstance(left, dict) and isinstance(right, dict):
        result: list[dict[str, Any]] = []
        for key in sorted(set(left) | set(right)):
            child = f"{path}/{key}"
            if key not in left or key not in right:
                result.append({"path": child, "candidate_present": key in left, "catalog_present": key in right})
            else:
                result.extend(differences(left[key], right[key], child))
        return result
    if isinstance(left, list) and isinstance(right, list):
        if len(left) != len(right):
            return [{"path": path, "candidate_length": len(left), "catalog_length": len(right)}]
        result = []
        for index, (a, b) in enumerate(zip(left, right)):
            result.extend(differences(a, b, f"{path}/{index}"))
        return result
    return [] if left == right else [{"path": path, "candidate": left, "catalog": right}]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", type=Path, help="optional new receipt path; refuses to overwrite")
    args = parser.parse_args()

    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    frozen_entries = {item["path"]: item for item in manifest["entries"]}
    for relative, expected_hash in EXPECTED.items():
        frozen = frozen_entries.get(relative)
        if frozen is None or frozen["sha256"] != expected_hash:
            raise SystemExit(f"frozen manifest identity mismatch: {relative}")
    for relative in (
        "app/data/aircraft/jensen_ugly_stik_60.json",
        "research/flight-robustness/d8b-r2/candidates/steep.json",
        "research/flight-robustness/d8b-r2/candidates/intermediate.json",
        "research/flight-robustness/d8b-r2/candidates/retained.json",
    ):
        actual = sha256(ROOT / relative)
        if actual != EXPECTED[relative]:
            raise SystemExit(f"workspace bytes no longer match frozen snapshot: {relative}: {actual}")

    catalog = json.loads(BASE.read_text(encoding="utf-8"))
    rows = []
    for name in ("steep", "intermediate", "retained"):
        path = CANDIDATE_DIR / f"{name}.json"
        candidate = json.loads(path.read_text(encoding="utf-8"))
        rows.append({
            "name": name,
            "sha256": sha256(path),
            "bytes": path.stat().st_size,
            "non_polar_differences": differences(remove_polar(candidate), remove_polar(catalog)),
        })

    receipt = {
        "format": "d8b-r2-candidate-static-diagnostic-v1",
        "scope": "read-only byte identity and semantic JSON comparison; no Godot, runtime, flight, or physical validation",
        "frozen_snapshot": str(MATERIALIZED.relative_to(ROOT).as_posix()),
        "snapshot_manifest_sha256": sha256(MANIFEST),
        "source_identities": {relative: digest for relative, digest in EXPECTED.items()},
        "candidates": rows,
    }
    rendered = json.dumps(receipt, indent=2, ensure_ascii=False) + "\n"
    if args.out:
        output = args.out if args.out.is_absolute() else ROOT / args.out
        if output.exists():
            raise SystemExit(f"refusing to overwrite existing receipt: {output}")
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(rendered, encoding="utf-8", newline="\n")
    print(rendered, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
