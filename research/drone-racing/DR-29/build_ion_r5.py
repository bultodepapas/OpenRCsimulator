"""DR-29/30: owner-supplied ION R5 visual -> the existing experimental FPV vehicle.

Run with Blender 5.2.2 (no add-ons):
  blender --background --factory-startup --python-exit-code 1 --python this.py
Use -- --check to regenerate in a temporary directory and compare shipped bytes.
The delivery is read-only. This adapter changes no flight data or solver law.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import sys
import tempfile

import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / "FPV/ION_R5.blend"
DATA = ROOT / "app/data/multirotors/openrc-fpv5-x1.json"
OUTPUT = ROOT / "app/assets/multirotors/ion-r5/ion_r5.glb"
MANIFEST = OUTPUT.with_name("manifest.json")
ORDER = {1: "RR", 2: "FR", 3: "RL", 4: "FL"}
MOTOR_HEIGHT = 0.020  # Existing visual's mount-to-prop-plane contract, metres.
BODY_BUDGET = 44000
ROTOR_BUDGET = 1600
PROP_BUDGET = 1600


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def rounded(values):
    return [round(float(v), 9) for v in values]


def empty(name, parent, position):
    obj = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(obj)
    obj.parent = parent
    obj.location = position
    return obj


def pbr_material(source, cache):
    """Keep native colours/metal/roughness/emission; omit Blender-only procedural nodes."""
    if source.name in cache:
        return cache[source.name]
    src = next(n for n in source.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    mat = bpy.data.materials.new("ION_" + source.name.split(" ")[0] + "_%02d" % len(cache))
    mat.use_nodes = True
    node = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    for key in ("Base Color", "Metallic", "Roughness", "Emission Color", "Emission Strength"):
        node.inputs[key].default_value = src.inputs[key].default_value
    cache[source.name] = mat
    return mat


def merged_mesh(name, entries, parent, origin, transform_point, budget, materials, depsgraph):
    """Evaluate fonts/curves/modifiers, flatten by moving part, then simplify once."""
    vertices, faces, face_materials, smooth = [], [], [], []
    slots, slot_indices = [], {}
    for obj in sorted(entries, key=lambda o: o.name):
        evaluated = obj.evaluated_get(depsgraph)
        mesh = evaluated.to_mesh()
        start = len(vertices)
        vertices.extend(transform_point(obj, obj.matrix_world @ v.co) - origin for v in mesh.vertices)
        for polygon in mesh.polygons:
            faces.append(tuple(start + i for i in polygon.vertices))
            material = obj.data.materials[polygon.material_index] if len(obj.data.materials) else None
            if material is None:
                raise ValueError("No material: " + obj.name)
            mapped = pbr_material(material, materials)
            if mapped.name not in slot_indices:
                slot_indices[mapped.name] = len(slots)
                slots.append(mapped)
            face_materials.append(slot_indices[mapped.name])
            smooth.append(polygon.use_smooth)
        evaluated.to_mesh_clear()
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(vertices, [], faces)
    for material in slots:
        mesh.materials.append(material)
    for polygon, index, shading in zip(mesh.polygons, face_materials, smooth):
        polygon.material_index = index
        polygon.use_smooth = shading
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    obj.parent = parent
    # Vertices were expressed relative to the group's pivot; the object sits on that pivot.
    obj.location = Vector()
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    tris = sum(len(p.vertices) - 2 for p in mesh.polygons)
    if tris > budget:
        modifier = obj.modifiers.new("Runtime budget", "DECIMATE")
        modifier.ratio = (budget - 16) / tris
        bpy.ops.object.modifier_apply(modifier=modifier.name)
    obj.select_set(False)
    obj.data.calc_loop_triangles()
    return obj, {"triangles": len(obj.data.loop_triangles), "surfaces": len(slots)}


def generate(out, manifest):
    source_hash = sha(SOURCE)
    data = json.loads(DATA.read_text(encoding="utf-8"))
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE), load_ui=False, use_scripts=False)
    scene = bpy.context.scene
    scene.frame_set(25)  # Authored RACE light state; no animation is exported.
    aircraft = bpy.data.objects["ION R5 | Aircraft origin"]
    original = [o for o in aircraft.children_recursive
                if o.type in {"MESH", "CURVE", "FONT"} and not o.hide_render and not o.name.startswith("QA |")]
    source_rotors = {rid: next(o for o in aircraft.children_recursive
                             if o.name.startswith(label + " | ROTOR")) for rid, label in ORDER.items()}
    blades = {rid: next(o for o in source_rotors[rid].children_recursive if " | Blades" in o.name)
              for rid in ORDER}
    depsgraph = bpy.context.evaluated_depsgraph_get()
    # Match the unchanged simulation's hub spacing, disc diameter and flat-ground support.
    hubs = [Vector(r["hub_frd"]["value"]) for r in data["rotors"]]
    centre = sum(hubs, Vector()) / 4
    target = {int(r["id"]): Vector((h[1] - centre[1], h[0] - centre[0], MOTOR_HEIGHT))
              for r, h in zip(data["rotors"], hubs)}
    source_half = abs(source_rotors[1].matrix_world.translation.x)
    xy_scale = abs(target[1].x) / source_half
    prop_mesh = blades[1].evaluated_get(depsgraph).to_mesh()
    prop_plane = sum((blades[1].matrix_world @ v.co).z for v in prop_mesh.vertices) / len(prop_mesh.vertices)
    source_radius = max(((blades[1].matrix_world @ v.co) - source_rotors[1].matrix_world.translation).xy.length
                        for v in prop_mesh.vertices)
    blades[1].evaluated_get(depsgraph).to_mesh_clear()
    minimum = math.inf
    for obj in original:
        evaluated = obj.evaluated_get(depsgraph)
        mesh = evaluated.to_mesh()
        minimum = min(minimum, min((obj.matrix_world @ v.co).z for v in mesh.vertices))
        evaluated.to_mesh_clear()
    foot_depth = max(float(p[2]) for p in data["contacts"]["feet"]["value"]) - centre[2]
    z_scale = foot_depth / (prop_plane - minimum)
    z_offset = MOTOR_HEIGHT - prop_plane * z_scale
    moving = {o for r in source_rotors.values() for o in r.children_recursive}
    fixed = [o for o in original if o not in moving]
    # Retain original scene until evaluated data have been copied; export only the new selected hierarchy.
    bpy.ops.object.select_all(action="DESELECT")
    root = empty("airframe_root", None, Vector())
    root["openrc_complete_rotors"] = True
    materials, audit, exported = {}, {}, [root]

    def body_point(_obj, p):
        return Vector((p.x * xy_scale, p.y * xy_scale, p.z * z_scale + z_offset))

    body, audit["body"] = merged_mesh("ION_R5_body", fixed, root, Vector(), body_point,
                                      BODY_BUDGET, materials, depsgraph)
    exported.append(body)
    for rid, label in ORDER.items():
        source_hub = source_rotors[rid].matrix_world.translation.copy()
        rotor_data = next(r for r in data["rotors"] if int(r["id"]) == rid)
        pivot = empty("propeller_%d" % rid, root, target[rid] - Vector((0, 0, MOTOR_HEIGHT)))
        exported.append(pivot)
        marker = empty("motor_%d" % rid, root, pivot.location)
        exported.append(marker)
        # Bell and blade remain separate meshes so PropellerBlur never fades the motor hardware.
        rotor_objects = [o for o in original if o in source_rotors[rid].children_recursive and o != blades[rid]]
        source_spin = 1 if source_rotors[rid]["Direction seen from +Z"] == "CCW" else -1
        mirror = source_spin != int(rotor_data["spin"])
        prop_scale = 0.5 * rotor_data["diameter"]["value"] / source_radius

        def rotor_point(obj, p):
            offset = p - source_hub
            if obj == blades[rid]:
                offset.x *= -prop_scale if mirror else prop_scale
                offset.y *= prop_scale
            return Vector((target[rid].x + offset.x, target[rid].y + offset.y,
                           p.z * z_scale + z_offset))

        bell, audit["bell_%d" % rid] = merged_mesh("ION_R5_bell_%d" % rid, rotor_objects, pivot,
                                                   pivot.location.copy(), rotor_point, ROTOR_BUDGET, materials, depsgraph)
        prop, audit["blades_%d" % rid] = merged_mesh("ION_R5_blades_%d" % rid, [blades[rid]], pivot,
                                                     pivot.location.copy(), rotor_point, PROP_BUDGET, materials, depsgraph)
        # A reflection changes winding. Reverse it to retain outward faces and the authored handed shape.
        if mirror:
            import bmesh
            bm = bmesh.new()
            bm.from_mesh(prop.data)
            bmesh.ops.reverse_faces(bm, faces=list(bm.faces))
            bm.to_mesh(prop.data)
            bm.free()
        exported.extend([bell, prop])
    # The onboard lens belongs to this visual, not the old OpenRacer camera pivot in the flight document.
    lens = next(o for o in original if o.name == "CAM | Convex coated front element")
    evaluated = lens.evaluated_get(depsgraph)
    mesh = evaluated.to_mesh()
    lens_centre = sum((lens.matrix_world @ v.co for v in mesh.vertices), Vector()) / len(mesh.vertices)
    evaluated.to_mesh_clear()
    cam = empty("camera_mount", root, body_point(lens, lens_centre) + Vector((0, 0.002, 0.002)))
    exported.append(cam)
    for obj in exported:
        obj.select_set(True)
    out.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=str(out), export_format="GLB", use_selection=True,
                              export_yup=True, export_apply=True, export_animations=False,
                              export_cameras=False, export_lights=False, export_extras=True)
    total = sum(v["triangles"] for v in audit.values())
    if total > 60000:
        raise ValueError("Triangle budget exceeded: %d" % total)
    receipt = {
        "step": "DR-29/30 ION R5 visual integration", "blender": bpy.app.version_string,
        "source": "FPV/ION_R5.blend", "source_sha256": source_hash,
        "physics": "app/data/multirotors/openrc-fpv5-x1.json", "physics_sha256": sha(DATA),
        "output": "app/assets/multirotors/ion-r5/ion_r5.glb", "sha256": sha(out), "bytes": out.stat().st_size,
        "source_diagonal_m": round(source_half * 2 * math.sqrt(2), 9),
        "horizontal_scale": round(xy_scale, 9), "vertical_scale": round(z_scale, 9),
        "source_blade_plane_m": round(prop_plane, 9), "source_lowest_m": round(minimum, 9),
        "motor_height_m": MOTOR_HEIGHT, "triangles": total, "materials": len(materials), "meshes": audit,
        "camera_mount_blender_m": rounded(cam.location),
        "limits": "Owner-supplied illustrative visual adapted to existing estimated physics; no ION R5 physical validation or new asset licence inferred. Procedural shading reduced to PBR constants."
    }
    manifest.write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8", newline="\n")
    assert sha(SOURCE) == source_hash, "Delivery was changed"
    print(json.dumps(receipt, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    if args.check:
        with tempfile.TemporaryDirectory(prefix="ion-r5-") as scratch:
            out = Path(scratch) / OUTPUT.name
            manifest = Path(scratch) / MANIFEST.name
            generate(out, manifest)
            if out.read_bytes() != OUTPUT.read_bytes() or manifest.read_bytes() != MANIFEST.read_bytes():
                raise SystemExit("ION R5 generated files differ; regenerate with the pinned Blender")
        print("ION R5 generator check passed")
    else:
        generate(OUTPUT, MANIFEST)
