"""Installs the people packaged by rebuild_people.sh into app/ and refreshes their records.

Copies the 11 GLBs and the two shared atlases and writes each atlas's import settings by its material role:
VRAM-compressed with mipmaps, normal map or not, and size-limited to 2048 (diffuse) or 1024 (normal), which is
indistinguishable at 5 m. It removes atlases no GLB references any more, refreshes the people entries of
RUNTIME_MANIFEST.json and the outfit hashes and runtime textures in HUMAN_SOURCES.json, then runs test_outfits.py.
Afterwards, import once and run the people tests (tools/scenery/population/README.md).
If that import updates the tracked sidecars, `--refresh-manifest` refreshes only the existing people file hashes;
it refuses missing or unexpected runtime files and does not install or remove assets.
    python3 tools/scenery/population/install_people.py
    python3 tools/scenery/population/install_people.py --refresh-manifest
"""
import hashlib
import json
import shutil
import struct
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
PACKAGED = ROOT / ".tools/sc-hum-authoring/packaged-people/people"
PEOPLE = ROOT / "app/assets/scenery/population/people"
RUNTIME_ROOT = ROOT / "app/assets/scenery/population"
RUNTIME_MANIFEST = ROOT / "assets/scenery/population/RUNTIME_MANIFEST.json"
HUMAN_SOURCES = ROOT / "assets/scenery/population/HUMAN_SOURCES.json"
OUTFITS = ROOT / "tools/scenery/population/outfits"
IMPORT = """[remap]

importer="texture"
type="CompressedTexture2D"

[deps]

source_file="res://assets/scenery/population/people/textures/{name}"

[params]

compress/mode=2
compress/high_quality=false
compress/lossy_quality=0.7
compress/uastc_level=0
compress/rdo_quality_loss=0.0
compress/hdr_compression=1
compress/normal_map={normal}
compress/channel_pack=0
mipmaps/generate=true
mipmaps/limit=-1
roughness/mode=0
roughness/src_normal=""
process/channel_remap/red=0
process/channel_remap/green=1
process/channel_remap/blue=2
process/channel_remap/alpha=3
process/fix_alpha_border=true
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
process/size_limit={limit}
detect_3d/compress_to=0
"""


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


class ManifestRefreshError(ValueError):
    """The installed people files do not match the manifest's expected inventory."""


def _is_people_path(path):
    return isinstance(path, str) and path.replace("\\", "/").startswith("people/")


def _people_file_records():
    people_root = RUNTIME_ROOT / "people"
    records = []
    for path in sorted(people_root.rglob("*")):
        if path.is_file():
            records.append({
                "path": path.relative_to(RUNTIME_ROOT).as_posix(),
                "bytes": path.stat().st_size,
                "sha256": sha256(path),
            })
    return records


def _refresh_people_file_inventory(manifest, *, require_existing_paths=False):
    files = manifest.get("files")
    if not isinstance(files, list):
        raise ManifestRefreshError("RUNTIME_MANIFEST.json must contain a files array")

    for record in files:
        if not isinstance(record, dict) or not isinstance(record.get("path"), str):
            raise ManifestRefreshError("RUNTIME_MANIFEST.json contains a file entry without a path")

    records = _people_file_records()
    records_by_path = {record["path"]: record for record in records}
    if require_existing_paths:
        expected_paths = [
            record["path"].replace("\\", "/")
            for record in files
            if _is_people_path(record["path"])
        ]
        if not expected_paths:
            raise ManifestRefreshError("RUNTIME_MANIFEST.json has no expected people file paths")
        if len(expected_paths) != len(set(expected_paths)):
            raise ManifestRefreshError("RUNTIME_MANIFEST.json contains duplicate people file paths")

        expected = set(expected_paths)
        actual = set(records_by_path)
        missing = sorted(expected - actual)
        unexpected = sorted(actual - expected)
        if missing or unexpected:
            details = []
            if missing:
                details.append("missing: " + ", ".join(missing))
            if unexpected:
                details.append("unexpected: " + ", ".join(unexpected))
            raise ManifestRefreshError(
                "refusing to refresh people hashes because the runtime inventory changed (" + "; ".join(details) + ")"
            )

        refreshed = []
        for record in files:
            path = record["path"].replace("\\", "/")
            refreshed.append(records_by_path[path] if path in expected else record)
        manifest["files"] = refreshed
        return manifest

    nonpeople = [record for record in files if not _is_people_path(record["path"])]
    manifest["files"] = sorted(nonpeople + records, key=lambda record: record["path"])
    return manifest


def _write_runtime_manifest(manifest):
    payload = json.dumps(manifest, indent=2, ensure_ascii=False) + "\n"
    with RUNTIME_MANIFEST.open("w", encoding="utf-8", newline="\n") as stream:
        stream.write(payload)


def refresh_manifest_only():
    """Refresh people hashes without installing, deleting, or regenerating runtime assets."""
    manifest = json.loads(RUNTIME_MANIFEST.read_text(encoding="utf-8"))
    _refresh_people_file_inventory(manifest, require_existing_paths=True)
    _write_runtime_manifest(manifest)


def atlas_roles(glb):
    """{texture file name: 'diffuse' | 'normal'} from a GLB's material."""
    data = glb.read_bytes()
    length = struct.unpack_from("<I", data, 12)[0]
    document = json.loads(data[20:20 + length])
    uris = [document["images"][texture["source"]]["uri"] for texture in document["textures"]]
    roles = {}
    for material in document["materials"]:
        if "normalTexture" in material:
            roles[Path(uris[material["normalTexture"]["index"]]).name] = "normal"
        base = material.get("pbrMetallicRoughness", {}).get("baseColorTexture")
        if base:
            roles[Path(uris[base["index"]]).name] = "diffuse"
    return roles


def main(argv=None):
    args = sys.argv[1:] if argv is None else list(argv)
    if args == ["--refresh-manifest"]:
        try:
            refresh_manifest_only()
        except ManifestRefreshError as error:
            raise SystemExit(str(error))
        return 0
    if args:
        raise SystemExit("usage: install_people.py [--refresh-manifest]")

    glbs = sorted(PACKAGED.glob("*.glb"))
    if len(glbs) != 11:
        sys.exit("expected 11 packaged GLBs in %s; run rebuild_people.sh" % PACKAGED)
    roles = {}
    for glb in glbs:
        roles.update(atlas_roles(glb))
    for glb in glbs:
        shutil.copyfile(glb, PEOPLE / glb.name)
    textures = PEOPLE / "textures"
    for name, role in roles.items():
        target = textures / name
        if not target.exists():
            shutil.copyfile(PACKAGED / "textures" / name, target)
            normal = role == "normal"
            (textures / (name + ".import")).write_text(IMPORT.format(name=name, normal=int(normal), limit=1024 if normal else 2048))
            print("new atlas", role, name)
    for stale in sorted(textures.glob("*.png")):
        if stale.name not in roles:
            stale.unlink()
            (textures / (stale.name + ".import")).unlink(missing_ok=True)
            print("removed atlas", stale.name)

    manifest = json.loads(RUNTIME_MANIFEST.read_text())
    for record in sorted(PACKAGED.glob("*.source.json")):
        entry = json.loads(record.read_text())
        key = "people/" + record.name[:-len(".source.json")]
        entry["output"] = "people/" + entry["output"]
        for image in entry["images"]:
            image["path"] = "people/" + image["path"]
        entry["step"] = manifest["assets"].get(key, {}).get("step", "SC-HUM-07 outfit variant (shared people atlas)")
        manifest["assets"][key] = entry
    _refresh_people_file_inventory(manifest)
    _write_runtime_manifest(manifest)

    sources = json.loads(HUMAN_SOURCES.read_text())
    outfits = sources["sc_hum_07_outfits"]
    outfits["outfit_specs_sha256"] = {f.name: sha256(f) for f in sorted(OUTFITS.glob("*.json"))}
    outfits["runtime_textures"] = sorted(roles, key=lambda name: roles[name])
    HUMAN_SOURCES.write_text(json.dumps(sources, indent=2, ensure_ascii=False) + "\n")
    return subprocess.call([sys.executable, str(ROOT / "tools/scenery/population/test_outfits.py")])


if __name__ == "__main__":
    sys.exit(main())
