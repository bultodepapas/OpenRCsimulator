"""Installs the people packaged by rebuild_people.sh into app/ and refreshes their records.

Copies the 11 GLBs and the two shared atlases and writes each atlas's import settings by its material role:
VRAM-compressed with mipmaps, normal map or not, and size-limited to 2048 (diffuse) or 1024 (normal), which is
indistinguishable at 5 m. It removes atlases no GLB references any more, refreshes the people entries of
RUNTIME_MANIFEST.json and the outfit hashes and runtime textures in HUMAN_SOURCES.json, then runs test_outfits.py.
Afterwards, import once and run the people tests (tools/scenery/population/README.md).
    python3 tools/scenery/population/install_people.py
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


def main():
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
    files = [f for f in manifest["files"] if not f["path"].startswith("people/")]
    for path in sorted((RUNTIME_ROOT / "people").rglob("*")):
        if path.is_file():
            files.append({"path": str(path.relative_to(RUNTIME_ROOT)), "bytes": path.stat().st_size, "sha256": sha256(path)})
    manifest["files"] = sorted(files, key=lambda f: f["path"])
    RUNTIME_MANIFEST.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n")

    sources = json.loads(HUMAN_SOURCES.read_text())
    outfits = sources["sc_hum_07_outfits"]
    outfits["outfit_specs_sha256"] = {f.name: sha256(f) for f in sorted(OUTFITS.glob("*.json"))}
    outfits["runtime_textures"] = sorted(roles, key=lambda name: roles[name])
    HUMAN_SOURCES.write_text(json.dumps(sources, indent=2, ensure_ascii=False) + "\n")
    sys.exit(subprocess.call([sys.executable, str(ROOT / "tools/scenery/population/test_outfits.py")]))


if __name__ == "__main__":
    main()
