#!/usr/bin/env python3
"""X8-00: freeze the identity of the Skywalker X8 game delivery r4.

Hashes every file of the author's nested delivery `assets/source-deliveries/skywalker-x8-r4/skywalker_x8/r4/` and
writes assets/aircraft/skywalker-x8/source-manifest.json: the SHA-256 and size of each file, the key files by role, the
visual revision string (the revision plus the first 12 hex digits of the default skin's GLB hash) and the skin GLBs in
the delivered metadata's `skin_order`. It also proves that the copy equals the author's own SHA256SUMS.txt, except for
the files the repository deliberately omits (OMITTED: every image, because the runtime textures are packed in the GLBs
and the default skin's in the .blend, and the reference-only animation demo); those are listed with the author's
hashes. The authoritative zip is kept outside Git under `references/source-deliveries/` (ignored); its hash is pinned
here so a later copy can be checked. Downstream generators read this manifest to show that they describe these exact
bytes.

    python3 research/skywalker-x8/X8-00/manifest.py           # writes the manifest
    python3 research/skywalker-x8/X8-00/manifest.py --check   # fails if any delivery file changed

Python standard library only.
"""
import fnmatch
import hashlib
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
DELIVERY = ROOT / "assets/source-deliveries/skywalker-x8-r4/skywalker_x8/r4"
TARGET = ROOT / "assets/aircraft/skywalker-x8/source-manifest.json"
ZIP = {"name": "skywalker_x8_r4.zip", "bytes": 201104969,
       "sha256": "52c9283bc873537aa7a618c47ed452929b9ba1cc057921a0e147d282a6eb0f49",
       "local_copy": "references/source-deliveries/skywalker_x8_r4.zip (ignored by Git)"}
KEY_FILES = {
    "glb": "export/aircraft.glb",
    "metadata": "metadata.json",
    "export_map": "export-map.json",
    "verification": "verification.json",
    "blend": "source/aircraft_game.blend",
    "generator": "source/scripts/x8_skywalker_blender.py",
    "license": "LICENSE.txt",
    "readme": "README.md",
    "changelog": "CHANGELOG.md",
    "author_manifest": "SHA256SUMS.txt",
}
# Delivered but not copied into the repository; the author's hashes stay in the source manifest.
OMITTED = ["textures/*", "previews/*", "*.png", "*.jpg"]
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
    skins = {skin["id"]: skin for skin in meta["skins"]}
    order = meta["skin_order"]
    assert order[0] == meta["default_skin"] and skins[order[0]]["glb"]["path"] == KEY_FILES["glb"], "default skin first"
    omitted = sorted(p for p in author if any(fnmatch.fnmatch(p, pattern) for pattern in OMITTED))
    present_omitted = sorted(p for p in omitted if p in by_path)
    if present_omitted:
        sys.exit(f"files the manifest declares omitted are present: {present_omitted}")
    mismatched = sorted(p for p, h in author.items() if p not in omitted and by_path.get(p, {}).get("sha256") != h)
    unlisted = sorted(set(by_path) - set(author) - {KEY_FILES["author_manifest"]})
    if mismatched or unlisted:
        sys.exit(f"delivery differs from the author's manifest: mismatched {mismatched}, unlisted {unlisted}")
    for skin_id in order:
        glb = skins[skin_id]["glb"]
        if by_path[glb["path"]]["sha256"] != glb["sha256"] or by_path[glb["path"]]["bytes"] != glb["bytes"]:
            sys.exit(f"skin {skin_id}: GLB differs from metadata.json")
    glb = by_path[KEY_FILES["glb"]]
    return {
        "format": "openrc-skywalker-x8-source-manifest v1",
        "step": "X8-00",
        "generator": "research/skywalker-x8/X8-00/manifest.py",
        "delivery_root": DELIVERY.relative_to(ROOT).as_posix(),
        "catalog_id": "skywalker-x8",
        "delivery_revision": meta["aircraft"]["revision"],
        "visual_revision": f"{meta['aircraft']['revision']}-{glb['sha256'][:12]}",
        "master": {"revision": "v3.1", "sha256": meta["master_reference"]["sha256"],
                   "generator_sha256": meta["master_reference"]["generator_sha256"]},
        "terms": "not set by the owner (LICENSE.txt: 'Asset terms NOT YET SET'); see docs/X8-PLAN.md",
        "zip": ZIP,
        "author_manifest": f"{len(author) - len(omitted)} of {len(author)} entries of {KEY_FILES['author_manifest']} match; {len(omitted)} omitted by rule",
        "omitted_rule": OMITTED,
        "omitted": [{"path": p, "sha256": author[p]} for p in omitted],
        "skin_glbs": {skin_id: dict(path=skins[skin_id]["glb"]["path"], label=skins[skin_id]["label"],
                                    **{k: by_path[skins[skin_id]["glb"]["path"]][k] for k in ("sha256", "bytes")})
                      for skin_id in order},
        "key_files": {role: dict(path=path, **{k: by_path[path][k] for k in ("sha256", "bytes")}) for role, path in KEY_FILES.items()},
        "file_count": len(rows),
        "total_bytes": sum(row["bytes"] for row in rows),
        "files": rows,
    }


def main() -> int:
    text = json.dumps(build(), indent=1) + "\n"
    if "--check" in sys.argv:
        if not TARGET.exists() or TARGET.read_text(encoding="utf-8") != text:
            print(f"stale or missing: {TARGET.relative_to(ROOT).as_posix()} (run research/skywalker-x8/X8-00/manifest.py)")
            return 1
        print(f"{TARGET.relative_to(ROOT).as_posix()} matches the {DELIVERY.name} delivery")
        return 0
    TARGET.parent.mkdir(parents=True, exist_ok=True)
    TARGET.write_text(text, encoding="utf-8", newline="\n")
    print(f"wrote {TARGET.relative_to(ROOT).as_posix()}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
