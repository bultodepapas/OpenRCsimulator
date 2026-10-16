"""Rebuild the LU-21 parked-car GLB variants with pinned Blender and inputs.

Example (run with Blender 5.2.2):
  blender --background --factory-startup --python tools/scenery/population/preprocess_cars.py -- \
    --source-dir /path/to/original-glbs --output-dir /path/to/derived-glbs --lod both

The input directory must contain the exact source filenames in
assets/scenery/population/SOURCE_MANIFEST.json. Sources are hash checked before
import and are never modified. Output files are written only to --output-dir.
Use --overwrite to replace existing outputs after a successful rebuild.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import sys
from typing import Any

import bpy
from mathutils import Matrix


EXPECTED_BLENDER = (5, 2, 2)
REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
DEFAULT_MANIFEST = REPOSITORY_ROOT / "assets" / "scenery" / "population" / "SOURCE_MANIFEST.json"


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest().upper()


def triangle_count(mesh: Any) -> int:
    return sum(max(0, len(polygon.vertices) - 2) for polygon in mesh.polygons)


def blender_script_args() -> list[str]:
    """Read only user arguments after Blender's conventional `--` delimiter."""
    if "--" in sys.argv:
        return sys.argv[sys.argv.index("--") + 1 :]
    return sys.argv[1:]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-dir", type=Path, required=True, help="Folder containing the three original GLBs")
    parser.add_argument("--output-dir", type=Path, required=True, help="Destination for derived GLBs and the report")
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST, help="Pinned source and expected-output manifest")
    parser.add_argument("--lod", choices=("close", "far", "both"), default="both")
    parser.add_argument("--overwrite", action="store_true", help="Replace derived outputs only after each export validates")
    return parser.parse_args(blender_script_args())


def load_manifest(path: Path) -> dict[str, Any]:
    manifest = json.loads(path.read_text(encoding="utf-8"))
    if manifest.get("format") != "openrc-population-source-manifest-v1":
        raise RuntimeError(f"Unsupported source manifest format: {manifest.get('format')!r}")
    evidence = manifest.get("license_evidence", {})
    evidence_path = path.parent / evidence.get("file", "")
    if not evidence_path.is_file():
        raise RuntimeError(f"Missing license evidence: {evidence_path}")
    actual_evidence_hash = sha256_file(evidence_path)
    expected_evidence_hash = str(evidence.get("sha256", "")).upper()
    if not expected_evidence_hash or actual_evidence_hash != expected_evidence_hash:
        raise RuntimeError(
            "License evidence SHA-256 mismatch: "
            f"expected {expected_evidence_hash or '<missing>'}, got {actual_evidence_hash}"
        )
    return manifest


def material_names(mesh: Any) -> set[str]:
    return {material.name.casefold() for material in mesh.materials if material is not None}


def close_ratio(name: str, materials: set[str], triangles: int) -> float | None:
    if any(token in name for token in ("sculpted_tyre", "alloy_five_spoke_rim", "lug_", "center_cap", "valve_stem", "rotor drill", "brake")):
        return 0.064
    if "interior" in materials:
        return 0.108
    if "body shell" in name:
        return 0.45
    if any(token in name for token in ("roof pressing", "roof pillar", "fender lip")):
        return 0.38
    if triangles > 500:
        return 0.108
    if triangles > 150:
        return 0.197
    return None


def far_ratio(name: str, materials: set[str], triangles: int) -> float | None:
    if any(token in name for token in ("sculpted_tyre", "alloy_five_spoke_rim", "lug_", "center_cap", "valve_stem", "rotor drill", "brake")):
        return 0.03
    if "interior" in materials:
        return 0.05
    if "body shell" in name:
        return 0.15
    if any(token in name for token in ("roof pressing", "roof pillar", "fender lip")):
        return 0.12
    if triangles > 500:
        return 0.05
    if triangles > 150:
        return 0.08
    if triangles > 50:
        return 0.15
    return None


def process_variant(
    spec: dict[str, Any],
    source_dir: Path,
    output_dir: Path,
    lod: str,
    overwrite: bool,
) -> dict[str, Any]:
    source = source_dir / spec["source_file"]
    if not source.is_file():
        raise RuntimeError(f"Missing source GLB: {source}")
    source_hash = sha256_file(source)
    if source_hash != spec["source_sha256"].upper():
        raise RuntimeError(f"{spec['id']} source SHA-256 mismatch: {source_hash}")
    if source.stat().st_size != spec["source_bytes"]:
        raise RuntimeError(f"{spec['id']} source byte count mismatch: {source.stat().st_size}")

    output_spec = spec["outputs"][lod]
    output = output_dir / output_spec["file"]
    temporary = output.with_name(output.stem + ".partial.glb")
    if output.exists() and not overwrite:
        raise RuntimeError(f"Output exists; pass --overwrite to replace it: {output}")
    if temporary.exists() and not overwrite:
        raise RuntimeError(f"Temporary output exists; remove it or pass --overwrite: {temporary}")
    if source.resolve() == output.resolve() or source.resolve() == temporary.resolve():
        raise RuntimeError("Output path resolves to the source GLB; refusing to modify source")

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(source))
    meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    imported_meshes = len(meshes)
    imported_triangles = sum(triangle_count(obj.data) for obj in meshes)
    if imported_meshes != spec["source_meshes"] or imported_triangles != spec["source_triangles"]:
        raise RuntimeError(
            f"{spec['id']} imported geometry mismatch: "
            f"{imported_meshes} meshes / {imported_triangles} triangles"
        )

    glass_material = spec["protected_glass_material"].casefold()
    protected_glass = {
        obj.name: triangle_count(obj.data)
        for obj in meshes
        if glass_material in material_names(obj.data)
    }
    if len(protected_glass) != spec["protected_glass_meshes"]:
        raise RuntimeError(f"{spec['id']} protected pane count mismatch: {len(protected_glass)}")
    pane_triangles = sum(protected_glass.values())
    if pane_triangles != spec["protected_glass_triangles"]:
        raise RuntimeError(f"{spec['id']} protected pane triangle mismatch: {pane_triangles}")
    deleted_objects = 0
    deleted_triangles = 0
    modified_objects = 0

    for obj in list(meshes):
        triangles = triangle_count(obj.data)
        name = obj.name.casefold()
        materials = material_names(obj.data)
        if glass_material in materials or (lod == "close" and "glass" in name):
            continue

        discard = False
        if "siped tread blocks" in name:
            discard = True
        elif lod == "close" and max(obj.dimensions) <= 0.02 and not materials.intersection({"paint", "clearlens", "redlens"}):
            discard = True
        elif lod == "far" and max(obj.dimensions) <= 0.05 and not materials.intersection({"paint", "clearlens", "redlens"}):
            discard = True

        if discard:
            deleted_objects += 1
            deleted_triangles += triangles
            bpy.data.objects.remove(obj, do_unlink=True)
            continue

        ratio = close_ratio(name, materials, triangles) if lod == "close" else far_ratio(name, materials, triangles)
        if lod == "far" and ratio is None:
            deleted_objects += 1
            deleted_triangles += triangles
            bpy.data.objects.remove(obj, do_unlink=True)
            continue
        if ratio is not None and triangles > 30:
            modifier = obj.modifiers.new(f"LU21 {lod} car selective LOD", "DECIMATE")
            modifier.ratio = ratio
            bpy.context.view_layer.objects.active = obj
            bpy.ops.object.modifier_apply(modifier=modifier.name)
            modified_objects += 1

    meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    for obj in meshes:
        if obj.name in protected_glass and triangle_count(obj.data) != protected_glass[obj.name]:
            raise RuntimeError(f"{spec['id']} protected pane changed during {lod} reduction: {obj.name}")
    reduced_triangles = sum(triangle_count(obj.data) for obj in meshes)
    if not meshes:
        raise RuntimeError(f"{spec['id']} produced no geometry")

    bpy.ops.object.select_all(action="DESELECT")
    for obj in meshes:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.join()
    car = bpy.context.view_layer.objects.active
    car.name = f"innerscene-{spec['id']}-selective" if lod == "close" else f"innerscene-{spec['id']}-far"
    surfaces = len(car.data.materials)
    final_triangles = triangle_count(car.data)
    if final_triangles != reduced_triangles:
        raise RuntimeError(f"{spec['id']} triangle count changed while joining materials")

    # Source nose points -X in Blender's imported Z-up space. Rotate around vertical Z
    # so the Godot-facing model has its nose toward -Z and its length along Z.
    car.data.transform(Matrix.Rotation(-math.pi / 2.0, 4, "Z"))
    car.data.update()
    if triangle_count(car.data) != final_triangles:
        raise RuntimeError(f"{spec['id']} orientation step changed triangle count")

    output_dir.mkdir(parents=True, exist_ok=True)
    if temporary.exists():
        temporary.unlink()
    bpy.ops.export_scene.gltf(
        filepath=str(temporary),
        export_format="GLB",
        use_selection=True,
        export_apply=True,
    )
    actual = {
        "triangles": final_triangles,
        "surfaces": surfaces,
        "bytes": temporary.stat().st_size,
        "sha256": sha256_file(temporary),
    }
    expected = output_spec["expected"]
    if actual != expected:
        temporary.unlink(missing_ok=True)
        raise RuntimeError(
            f"{spec['id']} {lod} output differs from the reviewed Blender 5.2.2 build: "
            f"expected {expected}, got {actual}"
        )
    os.replace(temporary, output)
    return {
        "id": spec["id"],
        "lod": lod,
        "source_file": spec["source_file"],
        "source_sha256": source_hash,
        "source_meshes": imported_meshes,
        "source_triangles": imported_triangles,
        "protected_glass_meshes": len(protected_glass),
        "protected_glass_triangles": pane_triangles,
        "deleted_objects": deleted_objects,
        "deleted_triangles": deleted_triangles,
        "modified_objects": modified_objects,
        "derived_file": output.name,
        **actual,
        "forward_axis": "-Z",
        "long_axis": "Z",
    }


def main() -> None:
    args = parse_args()
    if bpy.app.version != EXPECTED_BLENDER:
        raise RuntimeError(f"Expected Blender 5.2.2, got {bpy.app.version_string}")

    manifest_path = args.manifest.resolve()
    manifest = load_manifest(manifest_path)
    source_dir = args.source_dir.resolve()
    output_dir = args.output_dir.resolve()
    if source_dir == output_dir:
        raise RuntimeError("Keep source and output directories separate")

    lods = ("close", "far") if args.lod == "both" else (args.lod,)
    report_path = output_dir / "preprocess-report.json"
    if report_path.exists() and not args.overwrite:
        raise RuntimeError(f"Report exists; pass --overwrite to replace it: {report_path}")
    results = [
        process_variant(spec, source_dir, output_dir, lod, args.overwrite)
        for spec in manifest["sources"]
        for lod in lods
    ]
    report = {
        "format": "openrc-population-preprocess-report-v1",
        "blender_version": bpy.app.version_string,
        "manifest": str(manifest_path),
        "manifest_sha256": sha256_file(manifest_path),
        "license_evidence_sha256": manifest["license_evidence"]["sha256"].upper(),
        "results": results,
    }
    report_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print("LU21_CAR_PREPROCESS " + json.dumps(report, sort_keys=True))


if __name__ == "__main__":
    main()
