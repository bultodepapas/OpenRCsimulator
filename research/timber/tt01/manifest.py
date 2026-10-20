#!/usr/bin/env python3
"""TT-01: freeze the identity of the Turbo Timber Evolution r2 delivery.

Hashes every file of the author's exact nested r2 game delivery
`assets/source-deliveries/turbo-timber-evolution-r2/turbo_timber_evolution_r2/r2/`
and writes assets/aircraft/turbo-lumber-evolution/source-manifest.json: the SHA-256 and size of each file, the
key files by role, the visual revision string (r2 plus the first 12 hex digits of the GLB hash) and the git commit
that last touched the delivery. Downstream generators (build_geometry.py, check_asset.py, compile_geometry.py)
read this manifest to prove that they describe these exact bytes.

    python3 research/timber/tt01/manifest.py           # writes the manifest
    python3 research/timber/tt01/manifest.py --check   # fails if any delivery file changed (hashes and sizes only)

Python standard library only. The git commit is informational: `--check` never compares it, so a shallow clone or
an export without history still verifies the bytes.
"""
import hashlib
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
DELIVERY = ROOT / "assets/source-deliveries/turbo-timber-evolution-r2/turbo_timber_evolution_r2/r2"
TARGET = ROOT / "assets/aircraft/turbo-lumber-evolution/source-manifest.json"
KEY_FILES = {
    "glb": "export/aircraft.glb",
    "demo_glb": "export/aircraft_demo.glb",
    "metadata": "metadata.json",
    "export_map": "export-map.json",
    "verification": "verification.json",
    "blend": "source/aircraft_game.blend",
    "license": "LICENSE.txt",
    "readme": "README.md",
    "changelog": "CHANGELOG.md",
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


IGNORED_DIRS = {"__pycache__", ".git"}
IGNORED_SUFFIXES = {".pyc", ".pyo", ".swp"}
IGNORED_NAMES = {".DS_Store", "Thumbs.db"}


def file_table() -> list:
    """Every delivery file, except caches and editor leftovers that running the delivery's own scripts can create."""
    rows = []
    paths = (path for path in DELIVERY.rglob("*") if path.is_file())
    # pathlib sorts case-insensitively on Windows but case-sensitively on POSIX.
    # Sort relative path components explicitly to preserve the frozen order.
    for path in sorted(
        paths,
        key=lambda item: (
            tuple(part.casefold() for part in item.relative_to(DELIVERY).parts),
            item.relative_to(DELIVERY).as_posix(),
        ),
    ):
        rel = path.relative_to(DELIVERY)
        if IGNORED_DIRS & set(rel.parts[:-1]) or path.suffix in IGNORED_SUFFIXES or path.name in IGNORED_NAMES or path.name.endswith("~"):
            continue
        rows.append({"path": rel.as_posix(), "bytes": path.stat().st_size, "sha256": sha256(path)})
    return rows


def git_commit() -> str:
    try:
        out = subprocess.run(["git", "log", "-1", "--format=%H", "--", str(DELIVERY.relative_to(ROOT))],
                             cwd=ROOT, capture_output=True, text=True, check=True).stdout.strip()
        return out or "untracked"
    except (OSError, subprocess.CalledProcessError):
        return "unknown"


def build() -> dict:
    files = file_table()
    by_path = {row["path"]: row for row in files}
    missing = [rel for rel in KEY_FILES.values() if rel not in by_path]
    if missing:
        sys.exit("delivery is missing key files: %s" % missing)
    metadata = json.loads((DELIVERY / KEY_FILES["metadata"]).read_text(encoding="utf-8"))
    revision = metadata["aircraft"]["revision"]
    glb_hash = by_path[KEY_FILES["glb"]]["sha256"]
    return {
        "format": "openrc-timber-source-manifest v1",
        "step": "TT-01",
        "generator": "research/timber/tt01/manifest.py",
        "delivery_root": DELIVERY.relative_to(ROOT).as_posix(),
        "source_alias": metadata["aircraft"]["id"],
        "catalog_id": "turbo-lumber-evolution",
        "delivery_revision": revision,
        "visual_revision": "%s-%s" % (revision, glb_hash[:12]),
        "terms": "NOT SET (r2 LICENSE.txt: internal evaluation only); owner decision D1 pending, blocks TT-17 packaging",
        "git_commit_informational": git_commit(),
        "key_files": {role: {"path": rel, "sha256": by_path[rel]["sha256"], "bytes": by_path[rel]["bytes"]} for role, rel in KEY_FILES.items()},
        "file_count": len(files),
        "total_bytes": sum(row["bytes"] for row in files),
        "files": files,
    }


def main() -> None:
    manifest = build()
    text = json.dumps(manifest, indent=2, ensure_ascii=False) + "\n"
    if "--check" in sys.argv:
        if not TARGET.exists():
            sys.exit("missing %s: run manifest.py" % TARGET.relative_to(ROOT))
        stored = json.loads(TARGET.read_text(encoding="utf-8"))
        if (stored.get("delivery_root") != manifest["delivery_root"] or stored["files"] != manifest["files"]
                or stored["visual_revision"] != manifest["visual_revision"]):
            sys.exit("Timber r2 delivery bytes differ from %s: a new revision needs a new manifest entry and a re-run of "
                     "the geometry pipeline" % TARGET.relative_to(ROOT))
        print("Timber r2 delivery: %d files, %d bytes, visual revision %s: identical to the manifest"
              % (manifest["file_count"], manifest["total_bytes"], manifest["visual_revision"]))
    else:
        TARGET.write_bytes(text.encode("utf-8"))
        print("wrote %s (%d files, %d bytes, visual revision %s)"
              % (TARGET.relative_to(ROOT), manifest["file_count"], manifest["total_bytes"], manifest["visual_revision"]))


if __name__ == "__main__":
    main()
