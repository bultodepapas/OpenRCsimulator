#!/usr/bin/env python3
"""Export the tracked HX-700 Blender source to its reviewed static GLB.

From the repository root with Blender 5.2.2:

    blender --background --factory-startup \
      "assets/source-deliveries/hx-700-original/HX-700_Helicoptero_RC.blend" \
      --python research/helicopter/assets/export_hx700_static.py -- \
      --out .tools/heli25

The source file is checked before and after export and never saved. Output is
restricted to ignored .tools; use --replace-preview to replace that generated GLB.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import sys
from pathlib import Path

import bpy


REPO_ROOT = Path(__file__).resolve().parents[3]
SOURCE_BLEND = REPO_ROOT / "assets" / "source-deliveries" / "hx-700-original" / "HX-700_Helicoptero_RC.blend"
EXPECTED_SOURCE_SHA256 = "cc2301bbc4fd6aa84474fb0a33de37fe721fd2ecab6e806ceafbcc6953a795cb"
EXPECTED_GLB_SHA256 = "88424432c8cbfbc7c7278aa9c72e2188e138aa3551c2c1cf815494db281ce764"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def load_inventory_module():
    path = Path(__file__).with_name("inventory_hx700.py")
    spec = importlib.util.spec_from_file_location("hx700_inventory", path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Cannot load the reviewed export implementation: {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def main() -> int:
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=REPO_ROOT / ".tools" / "heli25")
    parser.add_argument("--replace-preview", action="store_true",
                        help="replace only hx700-preview.glb in the generated output directory")
    args = parser.parse_args(argv)

    source = Path(bpy.data.filepath).resolve(strict=True)
    if source != SOURCE_BLEND.resolve():
        raise SystemExit(f"Unexpected source file: {source}; expected {SOURCE_BLEND}")
    if sha256(source) != EXPECTED_SOURCE_SHA256:
        raise SystemExit("Tracked HX-700 Blender source hash changed; repeat the source audit first.")
    if bpy.app.version[:3] != (5, 2, 2):
        raise SystemExit(f"Blender 5.2.2 is required for the reviewed export; got {bpy.app.version_string}.")

    inventory = load_inventory_module()
    out_dir = args.out if args.out.is_absolute() else REPO_ROOT / args.out
    bpy.context.scene.frame_set(1)
    root = bpy.data.objects.get("HX-700")
    if root is None:
        raise SystemExit("The source does not contain the audited HX-700 root object.")
    model_objects = inventory.descendants(root)
    result = inventory.export_preview(
        out_dir,
        source,
        root,
        model_objects,
        {obj.name for obj in model_objects},
        replace_preview=args.replace_preview,
    )
    exported = Path(result["path"])
    if not exported.is_absolute():
        exported = REPO_ROOT / exported
    if result["sha256"] != EXPECTED_GLB_SHA256:
        raise SystemExit(f"Static GLB differs from the reviewed export: {result['sha256']}")
    if sha256(source) != EXPECTED_SOURCE_SHA256:
        raise SystemExit("The source .blend hash changed during export; do not use this output.")
    print(f"static GLB  {exported}  {result['sha256']}  {result['size_bytes']} bytes")
    print(f"source unchanged  {EXPECTED_SOURCE_SHA256}")
    print(f"nodes={result['node_count']} meshes={result['mesh_count']} animations={result['animation_count']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
