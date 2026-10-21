"""Recompute the profile loader's normalized physics/sim/failures source identity for two app trees."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import sys


SOURCE_DIRS = ("physics", "sim", "failures")


def sources(root: Path) -> dict[str, tuple[bytes, bytes]]:
    result: dict[str, tuple[bytes, bytes]] = {}
    for directory in SOURCE_DIRS:
        for path in sorted((root / directory).rglob("*.gd")):
            if not path.is_file():
                continue
            relative = path.relative_to(root).as_posix()
            raw = path.read_bytes()
            text = raw.decode("utf-8")
            normalized = text.replace("\r\n", "\n").replace("\r", "\n").encode("utf-8")
            result["res://" + relative] = (raw, normalized)
    return result


def identity(items: dict[str, tuple[bytes, bytes]]) -> str:
    digest = hashlib.sha256()
    for path in sorted(items):
        digest.update(path.encode("utf-8"))
        digest.update(items[path][1])
    return digest.hexdigest()


def file_manifest(items: dict[str, tuple[bytes, bytes]]) -> dict[str, dict[str, str | int]]:
    return {
        path: {
            "raw_sha256": hashlib.sha256(raw).hexdigest(),
            "normalized_sha256": hashlib.sha256(normalized).hexdigest(),
            "bytes": len(raw),
        }
        for path, (raw, normalized) in sorted(items.items())
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", required=True, type=Path)
    parser.add_argument("--candidate", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    baseline_root = args.baseline.resolve()
    candidate_root = args.candidate.resolve()
    if not baseline_root.is_dir() or not candidate_root.is_dir():
        parser.error("both app roots must exist")
    if args.output.exists():
        parser.error("output path must be new")
    base = sources(baseline_root)
    candidate = sources(candidate_root)
    if not base or not candidate:
        parser.error("source collection is empty")
    changed = [path for path in sorted(set(base) | set(candidate))
               if path not in base or path not in candidate or base[path][1] != candidate[path][1]]
    report = {
        "format": "openrc-solver-source-manifest v1",
        "normalization": "utf8-lf",
        "source_directories": list(SOURCE_DIRS),
        "baseline": {
            "app_root": str(baseline_root),
            "source_count": len(base),
            "sha256": identity(base),
            "files": file_manifest(base),
        },
        "candidate": {
            "app_root": str(candidate_root),
            "source_count": len(candidate),
            "sha256": identity(candidate),
            "files": file_manifest(candidate),
        },
        "normalized_source_changes": changed,
        "missing_from_candidate": sorted(set(base) - set(candidate)),
        "added_to_candidate": sorted(set(candidate) - set(base)),
    }
    if report["missing_from_candidate"] or report["added_to_candidate"]:
        print("source file sets differ", file=sys.stderr)
        return 1
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(json.dumps({
        "baseline_sha256": report["baseline"]["sha256"],
        "candidate_sha256": report["candidate"]["sha256"],
        "source_count": len(base),
        "normalized_source_changes": changed,
        "output": str(args.output.resolve()),
    }, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
