"""Verify local evidence links and index this audit's artifacts without editing production."""
from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path
from urllib.parse import unquote

ROOT = Path(__file__).resolve().parents[2]
DOCS = ROOT / "docs/research/physics-audit-2026-10-14"
SCRIPTS = ROOT / "research/physics-audit-2026-10-14"
MANIFEST = DOCS / "artifact-manifest.json"


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    evidence = {}
    for folder in (DOCS, SCRIPTS):
        for path in sorted(folder.rglob("*")):
            if not path.is_file() or path == MANIFEST or "__pycache__" in path.parts:
                continue
            evidence[path.relative_to(ROOT).as_posix()] = {
                "sha256": digest(path), "bytes": path.stat().st_size,
            }
    # Supplement the before/after runtime identity with current test/tool/config hashes.
    # These are captured at audit close, not claimed to be pre-run snapshots.
    support = set()
    for folder, suffixes in (("app/tests", {".gd"}), ("app/tools", {".gd"}),
                             ("tools/flight_log", {".py"}), ("app/data", {".json"})):
        support.update(path for path in (ROOT / folder).rglob("*")
                       if path.is_file() and path.suffix in suffixes)
    result = {
        "audit_date": "2026-10-14",
        "scope": "Hashes identify retained artifacts; they are not a complete source checkout.",
        "artifact_sha256": evidence,
        "supplemental_close_time_source_sha256": {
            path.relative_to(ROOT).as_posix(): digest(path) for path in sorted(support)
        },
        "superseded_evidence": {
            "docs/research/physics-audit-2026-10-14/aero/checks/probe.log":
                "Initial diagnostic had an incorrect wind-axis lift transform; do not use its CL values. See aero/README.md and corrected-probe.log."
        },
    }
    MANIFEST.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    broken = []
    link_count = 0
    for folder in (DOCS, SCRIPTS):
        for path in folder.rglob("*.md"):
            for target in re.findall(r"\]\(([^)]+)\)", path.read_text(encoding="utf-8")):
                target = target.strip("<>").split("#", 1)[0]
                if not target or re.match(r"[a-z]+://", target, re.I):
                    continue
                target_path = Path(unquote(target))
                resolved = target_path if target_path.is_absolute() else path.parent / target_path
                link_count += 1
                if not resolved.exists():
                    broken.append({"document": path.relative_to(ROOT).as_posix(), "target": target})
    print(json.dumps({"artifact_count": len(evidence), "support_source_count": len(support),
                      "local_links_checked": link_count, "broken_links": broken}))
    if broken:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
