#!/usr/bin/env python3
"""Reconcile the immutable -07 and -08 candidate source manifests after tests/export."""

from __future__ import annotations

import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import stat
import subprocess


EVIDENCE = Path("/mnt/c/DEVELOPMENT/OpenRCsimulator/docs/research/physics-audit-2026-10-14/remediation/R11/next-candidate")
SPECS = [
    {
        "label": "07",
        "root": Path("/home/bulto/openrc-r11-b09-r05b-20261015-07"),
        "manifest": EVIDENCE / "materialized-20261015-07-01/post-overlay-initial.json",
        "out": EVIDENCE / "materialized-20261015-07-01/post-run-source-01.json",
    },
    {
        "label": "08",
        "root": Path("/home/bulto/openrc-r11-package-20261015-08"),
        "manifest": Path("/mnt/c/DEVELOPMENT/OpenRCsimulator/docs/research/physics-audit-2026-10-14/remediation/R11/native-package-staging/derived-package-20261015-08/candidate-after-overlays.json"),
        "out": EVIDENCE / "materialized-20261015-08/post-run-source-01.json",
    },
]


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def canonical_sha(value: object) -> str:
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def item(path: Path, rel: str) -> dict[str, object]:
    mode = f"0o{stat.S_IMODE(path.lstat().st_mode):o}"
    if path.is_symlink():
        return {"path": rel, "kind": "symlink", "target": os.readlink(path), "mode": mode}
    return {"path": rel, "kind": "file", "sha256": sha256_file(path), "size_bytes": path.stat().st_size, "mode": mode}


def walk(root: Path, excludes: tuple[str, ...]) -> list[dict[str, object]]:
    entries: list[dict[str, object]] = []
    for current, dirs, files in os.walk(root, topdown=True, followlinks=False):
        here = Path(current)
        kept: list[str] = []
        for name in sorted(dirs):
            path = here / name
            rel = path.relative_to(root).as_posix()
            if any(rel == prefix or rel.startswith(prefix + "/") for prefix in excludes):
                continue
            if path.is_symlink():
                entries.append(item(path, rel))
            else:
                kept.append(name)
        dirs[:] = kept
        for name in sorted(files):
            path = here / name
            rel = path.relative_to(root).as_posix()
            if any(rel == prefix or rel.startswith(prefix + "/") for prefix in excludes):
                continue
            entries.append(item(path, rel))
    return sorted(entries, key=lambda x: str(x["path"]))


def git_state(root: Path) -> dict[str, object]:
    def run(args: list[str]) -> subprocess.CompletedProcess[str]:
        return subprocess.run(args, cwd=root, check=False, capture_output=True, text=True)

    head = run(["git", "rev-parse", "HEAD"])
    status = run(["git", "status", "--porcelain=v1", "--untracked-files=all"])
    diff = run(["git", "diff", "--cached", "--quiet"])
    if head.returncode or status.returncode or diff.returncode not in (0, 1):
        raise RuntimeError(f"git metadata command failed at {root}: {head.stderr}{status.stderr}{diff.stderr}")
    index = root / ".git/index"
    return {
        "head": head.stdout.strip(),
        "status_porcelain_v1_untracked_all": status.stdout.splitlines(),
        "status_exit": status.returncode,
        "staged_diff_exit": diff.returncode,
        "index_sha256": sha256_file(index) if index.is_file() else None,
    }


def main() -> None:
    generated_prefixes = (".git", ".tools", "dist", "app/.godot")
    all_reports = []
    for spec in SPECS:
        root: Path = spec["root"]
        baseline = json.loads(Path(spec["manifest"]).read_text(encoding="utf-8"))
        expected_entries = baseline["entries"]
        actual_entries = walk(root, generated_prefixes)
        expected = {str(row["path"]): row for row in expected_entries}
        actual = {str(row["path"]): row for row in actual_entries}
        missing = sorted(expected.keys() - actual.keys())
        added = sorted(actual.keys() - expected.keys())
        changed = [
            {"path": path, "expected": expected[path], "actual": actual[path]}
            for path in sorted(expected.keys() & actual.keys())
            if expected[path] != actual[path]
        ]
        excluded = {
            prefix: walk(root / prefix, ()) if (root / prefix).exists() else []
            for prefix in generated_prefixes
        }
        state = git_state(root)
        report = {
            "format": "openrc-r11-postrun-source-reconciliation-v1",
            "captured_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
            "candidate": spec["label"],
            "root": str(root),
            "baseline_manifest": str(spec["manifest"]),
            "baseline_manifest_sha256": sha256_file(Path(spec["manifest"])),
            "baseline_tree_sha256": baseline["tree_sha256"],
            "baseline_entry_count": baseline["entry_count"],
            "postrun_source_tree_sha256": canonical_sha(actual_entries),
            "postrun_source_entry_count": len(actual_entries),
            "source_match": not missing and not added and not changed,
            "missing": missing,
            "added": [{"path": path, **actual[path]} for path in added],
            "changed": changed,
            "excluded_generated_or_support_paths": excluded,
            "git_state_after_run": state,
        }
        out: Path = spec["out"]
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        all_reports.append({
            "candidate": spec["label"],
            "output": str(out),
            "source_match": report["source_match"],
            "missing_count": len(missing),
            "added_count": len(added),
            "changed_count": len(changed),
            "git_status_entries": len(state["status_porcelain_v1_untracked_all"]),
            "postrun_source_tree_sha256": report["postrun_source_tree_sha256"],
        })
    print(json.dumps(all_reports, indent=2))
    if any(not r["source_match"] for r in all_reports):
        raise SystemExit(1)


if __name__ == "__main__":
    main()
