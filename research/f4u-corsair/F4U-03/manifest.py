#!/usr/bin/env python3
"""F4U-03: freeze the identity of the current F4U Corsair delivery (g2.2 since F4U-20; g2.1 from F4U-19, g1.13 from
F4U-15, g1.3 before).

Hashes every file of the author's nested game delivery
`assets/source-deliveries/f4u-corsair-g2-2/f4u_corsair/g2_2/` and writes
assets/aircraft/f4u-corsair-250/source-manifest.json: the SHA-256 and size of each file, the key files by role, the
visual revision string (the revision plus the first 12 hex digits of the GLB hash), the livery GLBs and the delivery's
request revision and scale from metadata.json. The livery GLBs are the delivered metadata's `liveries`, in its
order. It also proves that the copy equals the author's own SHA256SUMS.txt, except for the files the repository
deliberately omits (OMITTED: the texture folder, whose runtime images are packed in the .blend and GLBs, the
previews, the other liveries' .blend sources and the author's UV cache); those are listed with the author's hashes. Downstream generators (F4U-05/06) read this manifest to show that they describe these exact bytes.

    python3 research/f4u-corsair/F4U-03/manifest.py           # writes the manifest
    python3 research/f4u-corsair/F4U-03/manifest.py --check   # fails if any delivery file changed

Python standard library only. The git commit that last touched the delivery is not recorded, so a shallow clone or
an export without history still verifies the bytes.
"""
import fnmatch
import hashlib
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
DELIVERY = ROOT / "assets/source-deliveries/f4u-corsair-g2-2/f4u_corsair/g2_2"
TARGET = ROOT / "assets/aircraft/f4u-corsair-250/source-manifest.json"
KEY_FILES = {
    "glb": "export/aircraft.glb",
    "metadata": "metadata.json",
    "export_map": "export-map.json",
    "blend": "source/aircraft_game.blend",
    "license": "LICENSE.txt",
    "provenance": "PROVENANCE.md",
    "readme": "README.md",
    "changelog": "CHANGELOG.md",
    "author_manifest": "SHA256SUMS.txt",
}
# Delivered but not copied into the repository; the author's hashes stay in the source manifest. The other liveries'
# .blend sources are added from metadata.json (every livery's `blend` except the default's).
OMITTED = ["textures/*", "previews/*", "source/scripts/uv-layout.json"]
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
    author = {}
    for line in (DELIVERY / KEY_FILES["author_manifest"]).read_text(encoding="utf-8").splitlines():
        if line.strip():
            digest, path = line.split(maxsplit=1)
            author[path.lstrip("*")] = digest
    meta = json.loads((DELIVERY / KEY_FILES["metadata"]).read_text(encoding="utf-8"))
    liveries = meta["liveries"]
    assert liveries[0]["id"] == meta["default_livery"] and liveries[0]["glb"] == KEY_FILES["glb"], "default livery first"
    rules = OMITTED + [r["blend"] for r in liveries[1:]]
    omitted = sorted(p for p in author if any(fnmatch.fnmatch(p, pattern) for pattern in rules))
    present_omitted = sorted(p for p in omitted if p in by_path)
    if present_omitted:
        sys.exit(f"files the manifest declares omitted are present: {present_omitted}")
    mismatched = sorted(p for p, h in author.items() if p not in omitted and by_path.get(p, {}).get("sha256") != h)
    unlisted = sorted(set(by_path) - set(author) - {KEY_FILES["author_manifest"]})
    if mismatched or unlisted:
        sys.exit(f"delivery differs from the author's manifest: mismatched {mismatched}, unlisted {unlisted}")
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
        "terms": "project's own model; no licence required (owner decision F4U-13, 2026-10-23, docs/DECISIONS.md)",
        "author_manifest": f"{len(author) - len(omitted)} of {len(author)} entries of {KEY_FILES['author_manifest']} match; {len(omitted)} omitted by rule",
        "omitted_rule": rules,
        "omitted": [{"path": p, "sha256": author[p]} for p in omitted],
        "livery_glbs": {r["id"]: dict(path=r["glb"], **{k: by_path[r["glb"]][k] for k in ("sha256", "bytes")}) for r in liveries},
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
        print(f"{TARGET.relative_to(ROOT).as_posix()} matches the {DELIVERY.name.replace('_', '.')} delivery")
        return 0
    TARGET.write_text(text, encoding="utf-8", newline="\n")
    print(f"wrote {TARGET.relative_to(ROOT).as_posix()}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
