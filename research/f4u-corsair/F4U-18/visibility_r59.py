"""F4U-18: which R59 triangles a player can ever see, and how large each part gets on a 1080p screen. Never saves.

Casts primary rays (Blender BVHTree) through the whole render-visible aircraft from the simulator's close cameras,
in four rig poses: on the ground (gear down), in flight (gear up), landing configuration with every surface deflected,
and wings folded. Glazing is transparent: rays continue through it. Cameras, scaled to 1/4.5 model metres:
  close  1.5 m from six focus points (nose, cockpit, left main gear, tail, left wingtip, right wing root):
         the orbit camera's minimum (1.7 m), the Workshop's 4x zoom and the close-up view (2.5 m);
  hero   4 m from the aircraft centre: the Home backdrop and the Workshop at 1x.
Each view is 45° vertical FOV, 16:9, sampled at 256x144 (close) or 320x180 (hero) rays, so one ray stands for
56 or 36 pixels of a 1080p frame. Azimuth every 30°; elevation -45…75° in flight poses, 5…75° on the ground.

Per triangle: hit by a ray, and seen at cell level (its centroid shares a 4 cm full-size cube with a hit; dense
meshes have triangles smaller than the ray spacing). Per R59 object: the largest screen coverage in any close and
any hero view, in 1080p pixels. Detail under about one ray spacing (6-7 px) is not resolved.

One pose per run; visibility_merge.py combines the runs:

    blender -b -Y --factory-startup F4U_Corsair_R59.blend --python visibility_r59.py -- OUT_DIR POSE [--quick]
    python research/f4u-corsair/F4U-18/visibility_merge.py OUT_DIR OUT.json [EXPORT_MAP.json]
"""
import bpy, json, math, os, sys, time
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import r59_pose

args = sys.argv[sys.argv.index("--") + 1:]
out_dir, pose_name = args[0], args[1]
quick = "--quick" in args
SCALE = 4.5  # model metres -> R59 full-size metres
GLASS_MATERIALS = {"Cabina R7 | cristal fisico", "R26 | cubierta transparente"}
CELL = 0.04  # full-size metres (8.9 mm on the model), about one ray spacing at the close views
FOV_V = math.radians(45.0)
ASPECT = 16 / 9
CLASSES = {"close": {"distance": 1.5, "rays": (256, 144)}, "hero": {"distance": 4.0, "rays": (320, 180)}}
if quick:
    CLASSES = {"close": {"distance": 1.5, "rays": (64, 36)}, "hero": {"distance": 4.0, "rays": (80, 45)}}
# R59 root frame, full size: +X aft, +Y right, +Z up (F4U-00 landmarks).
FOCUS = {"nose": (-4.6, 0.0, 2.42), "cockpit": (-0.1, 0.0, 3.25), "left_main_gear": (-2.65, -1.94, 0.95),
         "tail": (4.0, 0.0, 2.7), "left_wingtip": (-1.9, -5.4, 2.3), "right_wing_root": (-2.2, 1.6, 1.95)}
POSES = {
    "ground": {"ground": True, "controls": {}},
    "flight": {"ground": False, "controls": {"tren_retraccion": 1.0}},
    "deflected": {"ground": False, "controls": {"flaps_deg": 50.0, "alerones_deg": 25.0, "elevadores_deg": -25.0,
                                                "timon_deg": 35.0, "compensador_deg": 10.0}},
    "folded": {"ground": True, "controls": {}, "fold": 1.0},
}


def pose(spec):
    r59_pose.pose_neutral()
    ob = bpy.data.objects
    root = ob[r59_pose.ROOT]
    for key, value in spec["controls"].items():
        root[key] = type(root[key])(value)
    wings = ob["R51 | CONTROL ALAS"]
    if spec.get("fold"):
        for side in ("izquierda", "derecha"):
            wings[f"plegado_{side}"] = spec["fold"]
            wings[f"bloqueo_{side}"] = 0.0
    driven = [o for o in ob if o.animation_data and o.animation_data.drivers]
    for _ in range(3):
        for o in [root, wings] + driven:
            o.update_tag()
        bpy.context.scene.frame_set(bpy.context.scene.frame_current)
        bpy.context.view_layer.update()
    return bpy.context.evaluated_depsgraph_get()


def geometry(deps):
    names, verts, tris, owner, glass, areas = [], [], [], [], [], []
    offset = 0
    for o, evaluated, path in r59_pose.aircraft_objects(deps):
        try:
            mesh = evaluated.to_mesh()
        except Exception:
            continue
        if mesh is None or not mesh.vertices:
            evaluated.to_mesh_clear()
            continue
        mesh.calc_loop_triangles()
        count = len(mesh.loop_triangles)
        co = np.empty(len(mesh.vertices) * 3)
        mesh.vertices.foreach_get("co", co)
        co = co.reshape(-1, 3)
        m = np.array(evaluated.matrix_world)
        co = co @ m[:3, :3].T + m[:3, 3]
        t = np.empty(count * 3, dtype=np.int64)
        mesh.loop_triangles.foreach_get("vertices", t)
        t = t.reshape(-1, 3)
        mi = np.empty(count, dtype=np.int64)
        mesh.loop_triangles.foreach_get("material_index", mi)
        slots = [s.material.name if s.material else "" for s in o.material_slots]
        is_glass = np.array([(slots[i] if i < len(slots) else "") in GLASS_MATERIALS for i in mi], dtype=bool)
        a = co[t]
        area = 0.5 * np.linalg.norm(np.cross(a[:, 1] - a[:, 0], a[:, 2] - a[:, 0]), axis=1)
        object_id = len(names)
        names.append((o.name, path[0] if path else ""))
        verts.append(co)
        tris.append(t + offset)
        owner.append(np.full(count, object_id, dtype=np.int32))
        glass.append(is_glass)
        areas.append(area)
        offset += len(co)
        evaluated.to_mesh_clear()
    return (names, np.concatenate(verts), np.concatenate(tris), np.concatenate(owner), np.concatenate(glass),
            np.concatenate(areas))


def views(spec, centre, ground_z):
    elevations = [5, 20, 45, 75] if spec["ground"] else [-45, -20, 5, 20, 45, 75]
    for cls, setting in CLASSES.items():
        focuses = FOCUS.items() if cls == "close" else [("centre", centre)]
        for focus_name, focus in focuses:
            for az in range(0, 360, 30):
                for el in elevations:
                    d = setting["distance"] * SCALE
                    ra, re = math.radians(az), math.radians(el)
                    eye = Vector(focus) + d * Vector((math.cos(re) * math.cos(ra), math.cos(re) * math.sin(ra), math.sin(re)))
                    if spec["ground"] and eye.z < ground_z + 0.2:
                        continue
                    yield cls, f"{focus_name}/{az}/{el}", eye, Vector(focus), setting["rays"]


def directions(eye, target, rays):
    forward = (target - eye).normalized()
    right = forward.cross(Vector((0, 0, 1)))
    right = right.normalized() if right.length > 1e-6 else Vector((0, 1, 0))
    up = right.cross(forward).normalized()
    w, h = rays
    th = math.tan(FOV_V / 2)
    tw = th * ASPECT
    xs = (np.arange(w) + 0.5) / w * 2 - 1
    ys = (np.arange(h) + 0.5) / h * 2 - 1
    gx, gy = np.meshgrid(xs * tw, ys * th)
    f, r, u = np.array(forward), np.array(right), np.array(up)
    dirs = f + gx.reshape(-1, 1) * r + gy.reshape(-1, 1) * u
    return dirs / np.linalg.norm(dirs, axis=1, keepdims=True)


t0 = time.time()
spec = POSES[pose_name]
deps = pose(spec)
names, verts, tris, owner, glass, areas = geometry(deps)
hit = np.zeros(len(tris), dtype=bool)
max_px = {cls: np.zeros(len(names), dtype=np.int64) for cls in CLASSES}
bvh = BVHTree.FromPolygons(verts.tolist(), tris.tolist(), all_triangles=True)
lo, hi = verts.min(axis=0), verts.max(axis=0)
centre = tuple((lo + hi) / 2)
ground_z = float(lo[2])
n_views = n_rays = 0
for cls, label, eye, target, rays in views(spec, centre, ground_z):
    counts = np.zeros(len(names), dtype=np.int64)
    px = 1920 * 1080 / (rays[0] * rays[1])
    for d in directions(eye, target, rays).tolist():
        origin, direction = eye, Vector(d)
        for _ in range(4):
            loc, _normal, index, _dist = bvh.ray_cast(origin, direction, 200.0)
            if index is None:
                break
            hit[index] = True
            if not glass[index]:
                counts[owner[index]] += 1
                break
            origin = loc + direction * 1e-4
    n_views += 1
    n_rays += rays[0] * rays[1]
    max_px[cls] = np.maximum(max_px[cls], (counts * px).astype(np.int64))
# Ray-hit triangles undercount dense meshes: a triangle smaller than the ray spacing is often missed although its
# surroundings are hit. A triangle is also counted as seen when its centroid shares a CELL-sized cube with a hit.
keys = np.floor(verts[tris].mean(axis=1) / CELL).astype(np.int64)
keys -= keys.min(axis=0)
span = keys.max(axis=0) + 1
flat = (keys[:, 0] * span[1] + keys[:, 1]) * span[2] + keys[:, 2]
cell_hit = np.isin(flat, np.unique(flat[hit]))
os.makedirs(out_dir, exist_ok=True)
np.savez_compressed(os.path.join(out_dir, f"{pose_name}.npz"), hit=hit, cell_hit=cell_hit, owner=owner,
                    area=areas.astype(np.float32), max_px_close=max_px["close"], max_px_hero=max_px["hero"])
with open(os.path.join(out_dir, f"{pose_name}.json"), "w", encoding="utf-8") as f:
    json.dump({"file": bpy.data.filepath, "pose": pose_name, "spec": spec, "views": n_views, "rays": n_rays,
               "seconds": round(time.time() - t0, 1), "classes": {k: {"distance_model_m": v["distance"],
               "rays": v["rays"], "px_per_ray_1080p": 1920 * 1080 / (v["rays"][0] * v["rays"][1])}
               for k, v in CLASSES.items()}, "objects": [{"name": n, "collection": c} for n, c in names]},
              f, indent=1, ensure_ascii=False)
print("POSE", pose_name, n_views, "views", n_rays, "rays", int(hit.sum()), "of", len(hit), "triangles hit",
      round(time.time() - t0, 1), "s", flush=True)
