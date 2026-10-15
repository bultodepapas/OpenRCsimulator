#!/usr/bin/env python3
"""Classify generated post-run files and verify exact source-manifest preservation."""

from __future__ import annotations

import datetime as dt
import hashlib
import json
from pathlib import Path


BASE = Path("/mnt/c/DEVELOPMENT/OpenRCsimulator/docs/research/physics-audit-2026-10-14/remediation/R11/next-candidate")
ROOT_EVIDENCE = Path("/mnt/c/DEVELOPMENT/OpenRCsimulator/docs/research/physics-audit-2026-10-14/remediation/R11/native-package-staging/derived-package-20261015-08")
SPECS = [
    {
        "label": "07",
        "raw": BASE / "materialized-20261015-07-01/post-run-source-01.json",
        "baseline": BASE / "materialized-20261015-07-01/post-overlay-initial.json",
        "receipt": BASE / "materialized-20261015-07-01/materialization-receipt.json",
    },
    {
        "label": "08",
        "raw": BASE / "materialized-20261015-08/post-run-source-01.json",
        "baseline": ROOT_EVIDENCE / "candidate-after-overlays.json",
        "receipt": ROOT_EVIDENCE / "materialization-receipt.json",
    },
]
OUT = BASE / "materialized-20261015-08/postrun-classification-01.json"


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def classify(path: str) -> str:
    if path.endswith(".uid"):
        return "Godot-generated UID sidecar"
    if "/__pycache__/" in path and path.endswith(".pyc"):
        return "Python bytecode cache"
    if path.startswith("tmp/flight-log-"):
        return "ignored flight-recorder test scratch"
    if path.startswith("tmp/package-editor-sidecar-runner-01/"):
        return "retained package diagnostic runner support"
    return "unclassified"


def main() -> None:
    reports = []
    for spec in SPECS:
        raw = json.loads(spec["raw"].read_text(encoding="utf-8"))
        baseline = json.loads(spec["baseline"].read_text(encoding="utf-8"))
        receipt = json.loads(spec["receipt"].read_text(encoding="utf-8"))
        generated: dict[str, list[dict[str, object]]] = {}
        for row in raw["added"]:
            category = classify(str(row["path"]))
            generated.setdefault(category, []).append({
                "path": row["path"],
                "size_bytes": row.get("size_bytes"),
                "sha256": row.get("sha256"),
            })
        if spec["label"] == "07":
            recorded = receipt["target_git_state_after_overlays"]
        else:
            recorded = receipt["git_identity"]["candidate_after_overlays"]
        current_git = raw["git_state_after_run"]
        status_unchanged = (
            recorded["head"] == current_git["head"]
            and recorded["status_porcelain_v1_untracked_all"] == current_git["status_porcelain_v1_untracked_all"]
            and current_git["staged_diff_exit"] == 0
            and recorded.get("staged_diff_exit", 0) == 0
        )
        exact_source_preserved = (
            raw["missing"] == []
            and raw["changed"] == []
            and raw["baseline_tree_sha256"] == baseline["tree_sha256"]
            and raw["baseline_entry_count"] == baseline["entry_count"]
        )
        unclassified = generated.get("unclassified", [])
        reports.append({
            "candidate": spec["label"],
            "candidate_root": raw["root"],
            "baseline_manifest": str(spec["baseline"]),
            "baseline_manifest_sha256": sha256_file(spec["baseline"]),
            "baseline_source_tree_sha256": baseline["tree_sha256"],
            "postrun_observed_source_tree_sha256_including_additions": raw["postrun_source_tree_sha256"],
            "baseline_entry_count": baseline["entry_count"],
            "missing_manifested_files": raw["missing"],
            "changed_manifested_files": raw["changed"],
            "all_manifested_source_bytes_modes_and_paths_preserved": exact_source_preserved,
            "generated_or_diagnostic_additions": generated,
            "unclassified_additions": unclassified,
            "git_head_status_and_staging_unchanged_since_materialization": status_unchanged,
            "postrun_git_head": current_git["head"],
            "postrun_git_status_entries": len(current_git["status_porcelain_v1_untracked_all"]),
            "postrun_git_index_sha256": current_git["index_sha256"],
        })
    payload = {
        "format": "openrc-r11-postrun-addition-classification-v1",
        "captured_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
        "method": "Use immutable baseline entry hashes/modes plus post-run full tree walk; additions are separately hashed and classified. No candidate files were deleted or rewritten.",
        "candidates": reports,
        "all_candidates_preserve_manifested_source": all(x["all_manifested_source_bytes_modes_and_paths_preserved"] for x in reports),
        "all_additions_classified": all(not x["unclassified_additions"] for x in reports),
        "all_git_states_unchanged": all(x["git_head_status_and_staging_unchanged_since_materialization"] for x in reports),
    }
    OUT.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps({k: payload[k] for k in ("all_candidates_preserve_manifested_source", "all_additions_classified", "all_git_states_unchanged")}, indent=2))
    for row in reports:
        print(json.dumps({"candidate": row["candidate"], "counts": {k: len(v) for k, v in row["generated_or_diagnostic_additions"].items()}, "unknown": len(row["unclassified_additions"]), "git_status_unchanged": row["git_head_status_and_staging_unchanged_since_materialization"]}, sort_keys=True))
    if not payload["all_candidates_preserve_manifested_source"] or not payload["all_additions_classified"] or not payload["all_git_states_unchanged"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
