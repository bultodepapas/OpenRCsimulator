"""F4U-05: sample the delivered GearRetract action for the shared retractable-gear rig.

Runs inside Blender 5.2.2 LTS on the frozen game source (g2.1 since F4U-19) and never saves it:

    blender -b --factory-startup --disable-autoexec \
      assets/source-deliveries/f4u-corsair-g2-1/f4u_corsair/g2_1/source/aircraft_game.blend \
      --python research/f4u-corsair/F4U-05/sample_gear.py -- assets/aircraft/f4u-corsair-250/gear-samples.json

Writes, in the glTF/Godot model frame (+X right, +Y up, -Z nose, origin D0):
- 101 uniform samples of every animated carrier's parent-local pose, sample 0 stowed (frame 100), sample 100 down
  and locked (frame 0), as the rig binds the imported asset at its first sample;
- each wheel's centre (its spin helper's origin) per sample;
- the interpolation error of those samples against Blender's own evaluation at the 100 half-frame midpoints:
  rigid transforms compared on every gear mesh's bounding-box corners (an upper bound on its vertex error) and
  carrier rotations as angles.
compile_model.py checks these samples against the GLB and turns them into the rig.
"""
import bpy
import hashlib
import json
import math
import sys
from mathutils import Matrix, Quaternion, Vector

out_path = sys.argv[sys.argv.index("--") + 1]
scene = bpy.context.scene
ob = bpy.data.objects
STOWED, DOWN, N = 100, 0, 101
# Blender Z-up (+Y nose) to glTF Y-up (-Z nose): (x, y, z) -> (x, z, -y), applied once per world matrix.
C = Matrix(((1, 0, 0, 0), (0, 0, 1, 0), (0, -1, 0, 0), (0, 0, 0, 1)))
C_INV = C.inverted()
action = bpy.data.actions["GearRetract"]
carriers = sorted(o.name for o in ob if o.animation_data and o.animation_data.action == action)
helpers = {"left": ("gear_spin_left", "gear_compression_left", None),
           "right": ("gear_spin_right", "gear_compression_right", None),
           "tail": ("gear_spin_tail", "gear_compression_tail", "gear_steer_tail")}
gear_meshes = sorted(o.name for o in ob if o.type == "MESH" and o.get("openrc_section") == "gear")


def world(name):
    return C @ ob[name].matrix_world @ C_INV


def local(name):
    parent = ob[name].parent
    return (world(parent.name).inverted() if parent else Matrix.Identity(4)) @ world(name)


def pose(matrix):
    q = matrix.to_quaternion().normalized()
    return {"translation": [round(v, 10) for v in matrix.translation], "rotation_wxyz": [round(v, 10) for v in (q.w, q.x, q.y, q.z)]}


def at(frame):
    scene.frame_set(int(math.floor(frame)), subframe=frame - math.floor(frame))
    bpy.context.view_layer.update()


samples, centres = [], {role: [] for role in helpers}
for index in range(N):
    at(STOWED - index * (STOWED - DOWN) / (N - 1))
    samples.append({"extension": index / (N - 1), "nodes": {name: pose(local(name)) for name in carriers}})
    for role, (spin, _, _) in helpers.items():
        centres[role].append([round(v, 10) for v in world(spin).translation])


def compose(name, poses, cache):
    """Model-frame matrix of `name` from sampled carrier poses and the static locals of everything else."""
    if name in cache:
        return cache[name]
    parent = ob[name].parent
    head = compose(parent.name, poses, cache) if parent else Matrix.Identity(4)
    if name in poses:
        p = poses[name]
        own = Matrix.Translation(p[0]) @ p[1].to_matrix().to_4x4()
    else:
        own = static_local[name]
    cache[name] = head @ own
    return cache[name]


at(STOWED)
static_local = {o.name: local(o.name) for o in ob if o.type in ("MESH", "EMPTY")}
# Local bounding-box corners carried into the glTF basis, so model-frame matrices apply to them directly.
corners = {name: [C.to_3x3() @ Vector(c) for c in ob[name].bound_box] for name in gear_meshes}
max_vertex, max_angle, worst = 0.0, 0.0, ("", "")
for index in range(N - 1):
    a, b = samples[index]["nodes"], samples[index + 1]["nodes"]
    poses = {}
    for name in carriers:
        ta, tb = a[name]["translation"], b[name]["translation"]
        qa, qb = Quaternion(a[name]["rotation_wxyz"]), Quaternion(b[name]["rotation_wxyz"])
        poses[name] = ([0.5 * (x + y) for x, y in zip(ta, tb)], qa.slerp(qb, 0.5).normalized())
    at(STOWED - (index + 0.5) * (STOWED - DOWN) / (N - 1))
    cache = {}
    for name in carriers:
        angle = poses[name][1].rotation_difference(local(name).to_quaternion()).angle
        if angle > max_angle:
            max_angle, worst = angle, (worst[0], name)
    for name in gear_meshes:
        interpolated, actual = compose(name, poses, cache), world(name)
        for corner in corners[name]:
            error = (interpolated @ corner - actual @ corner).length
            if error > max_vertex:
                max_vertex, worst = error, (name, worst[1])

blend_sha = hashlib.sha256(open(bpy.data.filepath, "rb").read()).hexdigest()
out = {
    "format": "openrc-f4u-gear-samples v1",
    "step": "F4U-05",
    "generator": "research/f4u-corsair/F4U-05/sample_gear.py",
    "blender": bpy.app.version_string,
    "source_blend_sha256": blend_sha,
    "action": action.name,
    "frames": {"stowed": STOWED, "down": DOWN},
    "pose_space": "parent_local",
    "carriers": carriers,
    "gear_meshes": gear_meshes,
    "samples": samples,
    "wheel_centres_model": centres,
    "interpolation": {
        "uniform_samples": N,
        "max_midpoint_vertex_error_m": max_vertex,
        "max_midpoint_rotation_error_deg": math.degrees(max_angle),
        "worst_mesh_and_carrier": list(worst),
        "measurement": "Blender evaluation at the 100 half-frame midpoints against linear translation and quaternion slerp of the neighbouring samples, composed through the hierarchy; mesh error on bounding-box corners (upper bound on vertex error)",
    },
}
with open(out_path, "w", encoding="utf-8", newline="\n") as handle:
    handle.write(json.dumps(out, indent=1) + "\n")
print("GEAR_SAMPLES", len(carriers), "carriers", N, "samples; midpoint error %.6f m, %.4f deg" % (max_vertex, math.degrees(max_angle)))
