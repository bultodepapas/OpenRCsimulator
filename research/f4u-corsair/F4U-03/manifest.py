#!/usr/bin/env python3
"""F4U-03: freeze the identity of the F4U Corsair g1.3 delivery.

Hashes every file of the author's nested g1.3 game delivery
`assets/source-deliveries/f4u-corsair-g1-3/f4u_corsair/g1_3/` and writes
assets/aircraft/f4u-corsair-250/source-manifest.json: the SHA-256 and size of each file, the key files by role, the
visual revision string (g1.3 plus the first 12 hex digits of the GLB hash) and the delivery's request revision and
scale from metadata.json. It also proves that the copy equals the author's own manifest.sha256.json. Downstream
generators (F4U-05/06) read this manifest to show that they describe these exact bytes.

    python3 research/f4u-corsair/F4U-03/manifest.py           # writes the manifest
    python3 research/f4u-corsair/F4U-03/manifest.py --check   # fails if any delivery file changed

Python standard library only. The git commit that last touched the delivery is not recorded, so a shallow clone or
an export without history still verifies the bytes.
"""
import hashlib
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
DELIVERY = ROOT / "assets/source-deliveries/f4u-corsair-g1-3/f4u_corsair/g1_3"
TARGET = ROOT / "assets/aircraft/f4u-corsair-250/source-manifest.json"
KEY_FILES = {
    "glb": "export/aircraft.glb",
    "metadata": "metadata.json",
    "export_map": "export-map.json",
    "verification": "verification.json",
    "blend": "source/aircraft_game.blend",
    "license": "LICENSE.txt",
    "provenance": "PROVENANCE.md",
    "readme": "README.md",
    "changelog": "CHANGELOG.md",
    "author_manifest": "manifest.sha256.json",
}
IGNORED_DIRS = {"__pycache__", ".git"}
IGNORED_SUFFIXES = {".pyc", ".pyo", ".swp"}
IGNORED_NAMES = {".DS_Store", "Thumbs.db"}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def file_table() -> list:
    """Every delivery file, except caches and editor leftovers that running the delivery's own scripts can create."""
    rows = []
    paths = (path for path in DELIVERY.rglob("*") if path.is_file())
    # pathlib sorts case-insensitively on Windows but case-sensitively on POSIX: sort explicitly.
    for path in sorted(paths, key=lambda item: (tuple(part.casefold() for part in item.relative_to(DELIVERY).parts),
                                                 item.relative_to(DELIVERY).as_posix())):
        rel = path.relative_to(DELIVERY)
        if IGNORED_DIRS & set(rel.parts[:-1]) or path.suffix in IGNORED_SUFFIXES or path.name in IGNORED_NAMES or path.name.endswith("~"):
            continue
        rows.append({"path": rel.as_posix(), "bytes": path.stat().st_size, "sha256": sha256(path)})
    return rows


def build() -> dict:
    rows = file_table()
    by_path = {row["path"]: row for row in rows}
    author = json.loads((DELIVERY / KEY_FILES["author_manifest"]).read_text(encoding="utf-8"))
    mismatched = sorted(p for p, h in author.items() if by_path.get(p, {}).get("sha256") != h)
    unlisted = sorted(set(by_path) - set(author) - {KEY_FILES["author_manifest"]})
    if mismatched or unlisted:
        sys.exit(f"delivery differs from the author's manifest: mismatched {mismatched}, unlisted {unlisted}")
    meta = json.loads((DELIVERY / KEY_FILES["metadata"]).read_text(encoding="utf-8"))
    glb = by_path[KEY_FILES["glb"]]
    return {
        "format": "openrc-f4u-source-manifest v1",
        "step": "F4U-03",
        "generator": "research/f4u-corsair/F4U-03/manifest.py",
        "delivery_root": DELIVERY.relative_to(ROOT).as_posix(),
        "catalog_id": "f4u-corsair-250",
        "delivery_revision": meta["revision"],
        "request_revision": meta["request_revision"],
        "scale_factor": meta["scale_factor"],
        "visual_revision": f"{meta['revision']}-{glb['sha256'][:12]}",
        "master": {"revision": meta["master_revision"], "sha256": meta["master_sha256"]},
        "terms": "owner-authored (R59 lineage); shipped in OpenRC releases by owner decision 2026-10-24; g1.3 LICENSE.txt kept unchanged",
        "author_manifest": f"all {len(author)} entries of {KEY_FILES['author_manifest']} match",
        "key_files": {role: dict(path=path, **{k: by_path[path][k] for k in ("sha256", "bytes")}) for role, path in KEY_FILES.items()},
        "file_count": len(rows),
        "total_bytes": sum(row["bytes"] for row in rows),
        "files": rows,
    }


def main() -> int:
    text = json.dumps(build(), indent=1) + "\n"
    if "--check" in sys.argv:
        if not TARGET.exists() or TARGET.read_text(encoding="utf-8") != text:
            print(f"stale or missing: {TARGET.relative_to(ROOT).as_posix()} (run research/f4u-corsair/F4U-03/manifest.py)")
            return 1
        print(f"{TARGET.relative_to(ROOT).as_posix()} matches the g1.3 delivery")
        return 0
    TARGET.write_text(text, encoding="utf-8", newline="\n")
    print(f"wrote {TARGET.relative_to(ROOT).as_posix()}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
