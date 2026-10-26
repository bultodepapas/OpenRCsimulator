#!/usr/bin/env python3
"""X8-02: install the delivered Skywalker X8 skin GLBs and licence note as runtime assets.

Copies each frozen skin GLB (assets/aircraft/skywalker-x8/source-manifest.json `skin_glbs`, default first) byte for
byte to app/assets/aircraft/skywalker-x8/ and the delivery's LICENSE.txt beside them. A new import sidecar carries
only the [remap] importer and the shared imported-aircraft [params] block (the Avanti and F4U settings: no animation,
uncompressed vertex data, embedded textures); Godot's import adds its uid and destination:

    python3 research/skywalker-x8/X8-02/install_assets.py           # copies missing files, writes missing sidecars
    "$(app/get-godot.sh)" --headless --path app --audio-driver Dummy --import
    python3 research/skywalker-x8/X8-02/install_assets.py --check   # fails on any difference

Python standard library only.
"""
import hashlib
import json
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
MANIFEST = ROOT / "assets/aircraft/skywalker-x8/source-manifest.json"
RUNTIME = ROOT / "app/assets/aircraft/skywalker-x8"
DEFAULT_SKIN = "abisal"
PARAMS = """[params]
nodes/root_type=""
nodes/root_name=""
nodes/root_script=null
mesh_library/use_node_names_as_mesh_names=false
array_mesh/deduplicate_surfaces=true
nodes/apply_root_scale=true
nodes/root_scale=1.0
nodes/import_as_skeleton_bones=false
nodes/use_name_suffixes=true
nodes/use_node_type_suffixes=true
meshes/ensure_tangents=true
meshes/generate_lods=true
meshes/create_shadow_meshes=true
meshes/light_baking=1
meshes/lightmap_texel_size=0.2
meshes/force_disable_compression=true
skins/use_named_skins=true
animation/import=false
animation/fps=30
animation/trimming=false
animation/remove_immutable_tracks=true
animation/import_rest_as_RESET=false
import_script/path=""
materials/extract=0
materials/extract_format=0
materials/extract_path=""
_subresources={}
gltf/naming_version=2
gltf/embedded_image_handling=2
gltf/texture_map_mode=1""".splitlines()
# Defaults that Godot 4.8-beta1 writes into a new sidecar on import (the older Avanti/F4U sidecars predate them).
ENGINE_ADDED = {"mesh_library/create_categories_from_hierarchy=false"}


def runtime_glb(skin: str) -> Path:
    return RUNTIME / ("skywalker_x8.glb" if skin == DEFAULT_SKIN else f"skywalker_x8_{skin}.glb")


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def params(sidecar: Path) -> list:
    lines = sidecar.read_text(encoding="utf-8").splitlines()
    return [line for line in lines[lines.index("[params]"):] if line.strip()] if "[params]" in lines else []


def main() -> int:
    check = "--check" in sys.argv
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    delivery = ROOT / manifest["delivery_root"]
    skins = manifest["skin_glbs"]
    if next(iter(skins)) != DEFAULT_SKIN:
        sys.exit(f"the default skin must be first in source-manifest.json: {list(skins)}")
    problems = []
    RUNTIME.mkdir(parents=True, exist_ok=True)
    licence = manifest["key_files"]["license"]
    pairs = [(delivery / licence["path"], RUNTIME / "LICENSE.txt", licence["sha256"])]
    pairs += [(delivery / record["path"], runtime_glb(skin), record["sha256"]) for skin, record in skins.items()]
    for source, target, digest in pairs:
        if sha256(source) != digest:
            problems.append(f"frozen {source.relative_to(delivery).as_posix()} differs from source-manifest.json")
            continue
        if not target.exists() or sha256(target) != digest:
            if check:
                problems.append(f"{target.relative_to(ROOT).as_posix()} is not the delivered {source.relative_to(delivery).as_posix()}")
                continue
            shutil.copyfile(source, target)
            print(f"copied {source.relative_to(delivery).as_posix()} -> {target.relative_to(ROOT).as_posix()}")
        if target.suffix != ".glb":
            continue
        sidecar = Path(str(target) + ".import")
        if not sidecar.exists():
            if check:
                problems.append(f"{sidecar.relative_to(ROOT).as_posix()} is missing")
                continue
            text = '[remap]\n\nimporter="scene"\nimporter_version=1\ntype="PackedScene"\n\n' + "\n".join(PARAMS) + "\n"
            sidecar.write_text(text, encoding="utf-8", newline="\n")
            print(f"wrote {sidecar.relative_to(ROOT).as_posix()} (run Godot --import to assign its uid)")
        elif [line for line in params(sidecar) if line not in ENGINE_ADDED] != PARAMS:
            problems.append(f"{sidecar.relative_to(ROOT).as_posix()} import settings differ from the shared imported-aircraft settings")
        elif check and "uid=" not in sidecar.read_text(encoding="utf-8"):
            problems.append(f"{sidecar.relative_to(ROOT).as_posix()} has no uid (run Godot --import)")
    listed = {target.name for _, target, _ in pairs} | {target.name + ".import" for _, target, _ in pairs[1:]}
    strays = sorted(p.name for p in RUNTIME.iterdir() if p.name not in listed)
    if strays:
        problems.append(f"unexpected runtime files in {RUNTIME.relative_to(ROOT).as_posix()}: {strays}")
    if problems:
        sys.exit("\n".join(problems))
    print(f"{len(skins)} skin GLBs and LICENSE.txt match the frozen r4 delivery with the shared import settings")
    return 0


if __name__ == "__main__":
    sys.exit(main())
