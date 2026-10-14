#!/usr/bin/env python3
"""HELI-25c: freeze a neutral, controller-free inspection asset; never save Blender input.

Run in factory-startup Blender 5.2.2 with --disable-autoexec and the audited
NEW HELI source open. Output stays under .tools; installation is a separate step.
This profile admits neutral inspection only, not flight or actuator dynamics.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import math
import re
import sys
from pathlib import Path

import bpy
from mathutils import Matrix, Quaternion, Vector

REPO = Path(__file__).resolve().parents[3]
SOURCE = REPO / "NEW HELI/HX-700_Helicoptero_RC_1.blend"
SOURCE_SHA = "1919de349b74286bc36770ab2d7d08f743fd8a4062608d488c7e4e276103725f"
ASSET_PATH = "res://assets/aircraft/hx-700/articulated/hx-700.glb"
CORE = {
    "HX-700": ("root", "root"),
    "Pivote_Rotor_Principal": ("main.shaft", "main_shaft"),
    "Pivote_Rotor_Cola": ("tail.shaft", "tail_shaft"),
    "Plato_Exterior": ("swash.fixed", "fixed_swash"),
    "Plato_Interior": ("swash.rotating", "rotating_swash"),
    "Brazo_Servo_Delantero_Izq": ("actuator.cyclic.front_left", "actuator_output"),
    "Brazo_Servo_Delantero_Der": ("actuator.cyclic.front_right", "actuator_output"),
    "Brazo_Servo_Trasero": ("actuator.cyclic.rear", "actuator_output"),
    "Brazo_Servo_Cola": ("actuator.tail", "actuator_output"),
    "Corredera_Cola": ("tail.slider", "tail_slider"),
    "Yugo_Cola": ("tail.yoke", "tail_yoke"),
    "Palanca_Acodada_Cola": ("tail.bellcrank", "tail_bellcrank"),
}
for prefix, source_prefix in (("main", "Principal"), ("tail", "Cola")):
    for blade in ("A", "B"):
        CORE[f"Pala_{source_prefix}_{blade}"] = (f"{prefix}.blade.{blade.lower()}", f"{prefix}_blade")
        name = f"Portapalas_{blade}" if prefix == "main" else f"Portapalas_Cola_{blade}"
        CORE[name] = (f"{prefix}.grip.{blade.lower()}", f"{prefix}_grip")


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def slug(name):
    return re.sub(r"[^a-z0-9]+", "_", name.lower()).strip("_")


def gltf_matrix(node):
    if "matrix" in node:
        return Matrix([node["matrix"][i::4] for i in range(4)])
    q = node.get("rotation", [0, 0, 0, 1])
    return Matrix.LocRotScale(Vector(node.get("translation", [0, 0, 0])),
                              Quaternion((q[3], q[0], q[1], q[2])),
                              Vector(node.get("scale", [1, 1, 1])))


def write_json(path, data):
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False, allow_nan=False) + "\n", encoding="utf-8", newline="\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", required=True, type=Path)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])
    out = args.out.resolve()
    out.relative_to((REPO / ".tools").resolve())
    if out.exists() and any(out.iterdir()):
        raise ValueError("Use a fresh output directory; existing outputs are never replaced.")
    source = Path(bpy.data.filepath).resolve()
    if source != SOURCE.resolve() or sha256(source) != SOURCE_SHA:
        raise ValueError("Source differs from HELI-25b; audit the new delivery first.")
    if bpy.app.version[:3] != (5, 2, 2):
        raise ValueError("The reviewed exporter requires Blender 5.2.2.")
    out.mkdir(parents=True, exist_ok=True)
    spec = importlib.util.spec_from_file_location("hx_inventory", Path(__file__).with_name("inventory_hx700.py"))
    inventory = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(inventory)
    root = bpy.data.objects["HX-700"]
    settings = bpy.data.objects["Ajustes_Mecanicos"]
    bpy.context.scene.frame_set(1)
    for obj in (root, settings):
        if obj.animation_data:
            obj.animation_data_clear()
    # Preserve authored neutral adjustments, remove demonstration inputs.
    for key in ("giro_rotor", "velocidad_rotor", "paso_colectivo", "ciclico_alabeo",
                "ciclico_cabeceo", "paso_cola", "palas_plegadas", "bateria_extraida",
                "carenado_retirado", "rueda_libre_deslizamiento", "transmision_abierta", "mostrar_fuerzas"):
        root[key] = 0.0
    root.update_tag()
    settings.update_tag()
    bpy.context.view_layer.update()
    descendants = [root] + inventory.descendants(root)
    selected = [o for o in descendants if
                (o.type == "MESH" and not o.name.startswith("Flecha_")) or
                o.name in CORE or o.name.startswith(("Rotula_", "Rosca_"))]
    ids = dict(CORE)
    rods = json.loads(bpy.data.texts["RIG_BIELETAS.json"].as_string())
    for rod in rods:
        rid = "linkage." + slug(rod["nombre"])
        for field, suffix in (("terminal_1", "a"), ("terminal_2", "b")):
            ids[rod[field]] = (rid + "." + suffix, "link_endpoint")
    names = {o.name for o in selected}
    if set(ids) - names:
        raise ValueError("Missing semantic bindings: " + str(set(ids) - names))
    if any(o.parent and o.parent.name not in names for o in selected):
        raise ValueError("Selected object has a filtered parent.")
    # The inspection tier omits decorative bevel/normal modifiers, but retains
    # functional curve deformation and canopy thickness. It is not a final flight LOD.
    omitted = []
    for obj in selected:
        for modifier in obj.modifiers:
            if modifier.type in {"BEVEL", "WEIGHTED_NORMAL"}:
                modifier.show_viewport = False
                modifier.show_render = False
                omitted.append({"node": obj.name, "modifier": modifier.type})
    bpy.context.view_layer.update()
    deps = bpy.context.evaluated_depsgraph_get()
    deps.update()
    invalid = [(o.name, d.data_path) for o in descendants if o.animation_data
               for d in o.animation_data.drivers if not d.driver.is_valid]
    if invalid:
        raise ValueError("Neutral rig has invalid drivers: " + str(invalid))
    records = {}
    for obj in selected:
        evaluated = obj.evaluated_get(deps)
        name = obj.name
        mesh = bpy.data.meshes.new_from_object(evaluated, preserve_all_data_layers=True, depsgraph=deps) if obj.type == "MESH" else None
        records[name] = (obj.parent.name if obj.parent else "", evaluated.matrix_world.copy(), mesh)
        ids.setdefault(name, (("visual." if mesh else "anchor.") + slug(name), "mesh" if mesh else "frame"))
    if len({v[0] for v in ids.values()}) != len(ids):
        raise ValueError("Semantic ID collision.")
    # Independent geometric closure before creating or exporting frozen nodes.
    for rod in rods:
        a, b = (records[rod[k]][1].translation for k in ("terminal_1", "terminal_2"))
        expected = (rod["largo_mm"] + float(settings[rod["ajuste"]])) / 1000.0
        if not math.isfinite(expected) or expected <= 0 or abs((b - a).length - expected) > 2e-6:
            raise ValueError("Neutral linkage does not close: " + rod["nombre"])
    for obj in selected:
        obj.name = "_SOURCE_" + obj.name
    collection = bpy.data.collections.new("OpenRC_Neutral_Inspection")
    bpy.context.scene.collection.children.link(collection)
    frozen = {}
    for name, (_, _, mesh) in records.items():
        obj = bpy.data.objects.new(name, mesh)
        collection.objects.link(obj)
        obj["openrc_binding_id"], obj["openrc_binding_role"] = ids[name]
        frozen[name] = obj
    for name, (parent, world, _) in records.items():
        obj = frozen[name]
        if parent:
            obj.parent = frozen[parent]
            obj.matrix_parent_inverse = Matrix.Identity(4)
            obj.matrix_basis = records[parent][1].inverted() @ world
        else:
            obj.matrix_basis = world
    for obj in bpy.context.scene.objects:
        obj.select_set(False)
    for obj in frozen.values():
        obj.select_set(True)
    bpy.context.view_layer.objects.active = frozen["HX-700"]
    bpy.context.view_layer.update()
    asset = out / "hx-700.glb"
    result = bpy.ops.export_scene.gltf(
        filepath=str(asset), check_existing=False, export_format="GLB", use_selection=True,
        export_animations=False, export_skins=False, export_morph=False, export_lights=False,
        export_cameras=False, export_apply=False, export_extras=True, export_materials="EXPORT",
        export_yup=True, export_draco_mesh_compression_enable=False)
    if "FINISHED" not in result:
        raise RuntimeError("GLB export failed.")
    gltf = inventory.read_glb_json(asset)
    nodes = gltf["nodes"]
    exported_names = [n.get("name") for n in nodes]
    if len(exported_names) != len(names) or set(exported_names) != names:
        raise ValueError("GLB did not preserve exact node/anchor set.")
    parents = {child: i for i, n in enumerate(nodes) for child in n.get("children", [])}
    bindings = []
    for i, node in enumerate(nodes):
        name = node["name"]
        mat = gltf_matrix(node)
        values = [float(mat[row][col]) for col in range(4) for row in range(3)]
        bindings.append({"id": ids[name][0], "role": ids[name][1], "node": name,
                         "parent_id": ids[nodes[parents[i]]["name"]][0] if i in parents else "",
                         "rest_transform": values})
    profile = {
        "schema": "openrc-rotorcraft-construction", "version": 1,
        "profile_id": "hx-700-articulated-r1", "purpose": "neutral-mechanical-preview",
        "source": {"path": str(SOURCE.relative_to(REPO)).replace("\\", "/"), "sha256": SOURCE_SHA,
                   "blender_version": bpy.app.version_string},
        "asset": {"path": ASSET_PATH, "sha256": sha256(asset)},
        "coordinates": "gltf-y-up-metres", "bindings": sorted(bindings, key=lambda b: b["id"]),
        "linkages": [{"id": "linkage." + slug(r["nombre"]), "endpoint_a": ids[r["terminal_1"]][0],
                      "endpoint_b": ids[r["terminal_2"]][0],
                      "length_m": (r["largo_mm"] + float(settings[r["ajuste"]])) / 1000.0} for r in rods]}
    write_json(out / "construction.json", profile)
    # This oracle is sampled directly from the evaluated Blender source before
    # freezing. It is independent of glTF's serialized local transforms.
    conversion = Matrix(((1, 0, 0, 0), (0, 0, 1, 0), (0, -1, 0, 0), (0, 0, 0, 1)))
    reference = []
    for name, (_, world, _) in records.items():
        converted = conversion @ world @ conversion.inverted()
        reference.append({"id": ids[name][0], "world_transform": [float(converted[r][c]) for c in range(4) for r in range(3)]})
    write_json(out / "neutral-reference.json", {"source_sha256": SOURCE_SHA,
               "coordinates": "gltf-y-up-metres", "frames": sorted(reference, key=lambda r: r["id"])})
    primitives = [p for m in gltf.get("meshes", []) for p in m["primitives"]]
    if gltf.get("animations") or gltf.get("cameras") or gltf.get("skins"):
        raise ValueError("Inspection GLB contains forbidden runtime controllers.")
    if any("uri" in image for image in gltf.get("images", [])):
        raise ValueError("External images are not admitted.")
    if sha256(source) != SOURCE_SHA:
        raise ValueError("Source changed during export.")
    report = {"step": "HELI-25c", "source_sha256": SOURCE_SHA, "source_unchanged": True,
              "blender_version": bpy.app.version_string, "glb_sha256": sha256(asset),
              "profile_sha256": sha256(out / "construction.json"), "size_bytes": asset.stat().st_size,
              "node_count": len(nodes), "mesh_count": len(gltf.get("meshes", [])),
              "material_surface_count": len(primitives), "image_count": len(gltf.get("images", [])),
              "triangle_count": sum(gltf["accessors"][p["indices"]]["count"] // 3 for p in primitives),
              "omitted_decorative_modifiers": omitted,
              "geometry_policy": "evaluated functional modifiers, no decorative bevel/weighted-normal modifiers",
              "flight_admitted": False}
    write_json(out / "export-report.json", report)
    print("HELI-25c", json.dumps({k: v for k, v in report.items() if k != "omitted_decorative_modifiers"}))


if __name__ == "__main__":
    main()
