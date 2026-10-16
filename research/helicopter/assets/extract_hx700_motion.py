"""Extract mechanical transform recipes and independent pose oracles from the pinned source.

Run in a disposable Blender process with --disable-autoexec; never saves the blend.
The source's aerodynamic/engine calculations are not exported as flight models.
"""
import argparse
import hashlib
import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Matrix

ROOT = Path(__file__).resolve().parents[3]
SHA = "1919de349b74286bc36770ab2d7d08f743fd8a4062608d488c7e4e276103725f"
C = Matrix(((1, 0, 0, 0), (0, 0, 1, 0), (0, -1, 0, 0), (0, 0, 0, 1)))


def values(mat):
    return [float(mat[r][c]) for c in range(4) for r in range(3)]


def require_source_sha256(source, stage):
    actual = hashlib.sha256(source.read_bytes()).hexdigest()
    if actual != SHA:
        raise ValueError(f"HX-700 Blender source SHA-256 changed {stage}: expected {SHA}, got {actual}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", required=True, type=Path)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])
    out = args.out.resolve()
    out.relative_to((ROOT / ".tools").resolve())
    if out.exists() and any(out.iterdir()):
        raise ValueError("Use a fresh output directory under .tools.")
    source = Path(bpy.data.filepath)
    require_source_sha256(source, "before extraction")
    profile = json.loads((ROOT / "assets/aircraft/hx-700/articulated/construction.json").read_text())
    root = bpy.data.objects["HX-700"]
    for name in ("HX-700", "Ajustes_Mecanicos"):
        bpy.data.objects[name].animation_data_clear()
    bpy.context.scene.frame_set(1)
    keys = ["giro_rotor", "velocidad_rotor", "paso_colectivo", "ciclico_alabeo", "ciclico_cabeceo", "paso_cola"]
    for key in keys:
        root[key] = 0.0
    root.update_tag()
    bpy.context.view_layer.update()
    recipes = []
    # The exporter freezes evaluated meshes, but keeps their original parent graph.
    # Nonidentity parent inverses must precede the authored XYZ transform.
    for binding in profile["bindings"]:
        obj = bpy.data.objects[binding["node"]]
        drivers = [d for d in obj.animation_data.drivers if d.data_path in ("location", "rotation_euler", "scale")] if obj.animation_data else []
        if not drivers:
            continue
        if obj.rotation_mode != "XYZ" or obj.constraints:
            raise ValueError(f"Unsupported driven transform on {obj.name}: rotation_mode={obj.rotation_mode}, constraints={len(obj.constraints)}")
        recipes.append({"id": binding["id"], "node": obj.name,
                        "parent_inverse": values(C @ obj.matrix_parent_inverse @ C.inverted()),
                        "location": list(obj.location), "rotation_euler": list(obj.rotation_euler),
                        "scale": list(obj.scale)})
    # Record the original expressions and their explicit property dependencies.
    objects = {}
    for obj in bpy.data.objects:
        props = {k: float(obj[k]) for k in obj.keys() if isinstance(obj[k], (int, float))}
        drivers = []
        if obj.animation_data:
            for fcurve in obj.animation_data.drivers:
                d = fcurve.driver
                variables = {}
                for var in d.variables:
                    if var.type != "SINGLE_PROP" or len(var.targets) != 1:
                        raise ValueError(f"Unsupported driver variable on {obj.name}.{fcurve.data_path}: {var.name} ({var.type})")
                    target = var.targets[0]
                    if target.id is None or not target.data_path:
                        raise ValueError(f"Incomplete single-property driver target on {obj.name}.{fcurve.data_path}: {var.name}")
                    variables[var.name] = [target.id.name, target.data_path]
                drivers.append({"path": fcurve.data_path, "index": fcurve.array_index,
                                "expression": d.expression, "variables": variables})
        if props or drivers:
            objects[obj.name] = {"properties": props, "drivers": drivers}
    samples = []
    cases = [(0, 0, 0, 0), (10, 0, 0, 0), (-10, 0, 0, 0),
             (0, 8, 0, 0), (0, -8, 0, 0), (0, 0, 8, 0), (0, 0, -8, 0),
             (0, 0, 0, 15), (0, 0, 0, -15), (8, 6, 6, 10), (-8, -6, 6, -10)]
    for case in cases:
        for phase in (0, math.pi / 2, math.pi, 3 * math.pi / 2):
            for key, value in zip(keys, (phase, 0.0, *case)):
                root[key] = value
            root.update_tag()
            bpy.context.view_layer.update()
            deps = bpy.context.evaluated_depsgraph_get()
            deps.update()
            frames = {b["id"]: values(C @ bpy.data.objects[b["node"]].evaluated_get(deps).matrix_world @ C.inverted())
                      for b in profile["bindings"] if b["role"] in
                      ("actuator_output", "main_blade", "tail_blade", "main_grip", "tail_grip", "fixed_swash", "rotating_swash", "tail_slider", "tail_yoke", "tail_bellcrank", "main_shaft", "tail_shaft", "link_endpoint")}
            samples.append({"inputs": list(case) + [phase], "frames": frames})
    require_source_sha256(source, "after extraction and before writing artifacts")
    out.mkdir(parents=True, exist_ok=True)
    for name, data in (("motion-source.json", {"source_sha256": SHA, "recipes": recipes, "objects": objects}),
                       ("motion-oracle.json", {"source_sha256": SHA, "samples": samples})):
        (out / name).write_text(json.dumps(data, indent=2, ensure_ascii=False, allow_nan=False) + "\n", encoding="utf-8", newline="\n")
    print("Motion recipes:", len(recipes), "oracle poses:", len(samples), "source unchanged")


if __name__ == "__main__":
    main()
