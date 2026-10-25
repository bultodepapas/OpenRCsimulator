"""F4U-21: inventory of the R59 master's rig controls, read-only. Never saves.

For every custom property on the root and on the control empties, lists the objects whose drivers read it (directly
or through another driven property), with their top collection and the transform channels driven. Shows which
extra movements R59 models (cowl flaps, canopy, tailhook, wing-fold struts and locks, trims...) and which parts move.

    blender -b -Y --factory-startup F4U_Corsair_R59.blend --python inventory_rig.py -- OUT.json
"""
import bpy, json, os, sys
from collections import defaultdict

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "F4U-18"))
import r59_pose

out_path = sys.argv[sys.argv.index("--") + 1]
paths = r59_pose.collection_paths(bpy.context.scene)
controls = {}
for o in bpy.data.objects:
    keys = [k for k in o.keys() if not k.startswith("_") and isinstance(o[k], (int, float, bool))]
    if keys and (o.name == r59_pose.ROOT or "CONTROL" in o.name or "CABINA" in o.name or o.type == "EMPTY"):
        controls[o.name] = {k: o[k] for k in keys}

# Driver edges: (source object, property path) -> driven (object, channel).
readers = defaultdict(list)
for o in bpy.data.objects:
    if not (o.animation_data and o.animation_data.drivers):
        continue
    for fc in o.animation_data.drivers:
        channel = f"{fc.data_path}[{fc.array_index}]"
        for var in fc.driver.variables:
            for target in var.targets:
                if target.id is None:
                    continue
                prop = target.data_path or (target.transform_type if var.type == "TRANSFORMS" else "")
                readers[(target.id.name, prop)].append((o.name, channel))


def top(name):
    o = bpy.data.objects.get(name)
    if o is None or not o.users_collection:
        return ""
    path = paths.get(o.users_collection[0].name, [o.users_collection[0].name])
    return path[0] if path else ""


result = {"file": bpy.data.filepath, "controls": {}}
for owner, props in sorted(controls.items()):
    for prop, value in sorted(props.items()):
        driven = set()
        frontier = [(owner, f'["{prop}"]'), (owner, prop)]
        seen = set()
        while frontier:
            key = frontier.pop()
            if key in seen:
                continue
            seen.add(key)
            for name, channel in readers.get(key, []):
                driven.add((name, channel))
                # A driven custom property can feed further drivers.
                if channel.startswith('["'):
                    frontier.append((name, channel.split("[")[0] + "[" + channel.split("[")[1]))
        if not driven:
            continue
        objects = sorted({n for n, _ in driven})
        by_top = defaultdict(int)
        for n in objects:
            by_top[top(n)] += 1
        channels = sorted({c.split("[")[0] for _, c in driven})
        result["controls"][f"{owner} :: {prop}"] = {"value": value, "driven_objects": len(objects), "channels": channels,
                                                    "by_collection": dict(sorted(by_top.items(), key=lambda kv: -kv[1])),
                                                    "examples": objects[:12]}
with open(out_path, "w", encoding="utf-8") as f:
    json.dump(result, f, indent=1, ensure_ascii=False)
for k, v in result["controls"].items():
    print(f"{v['driven_objects']:>5} objects  {k} = {v['value']}  {v['channels']}  {list(v['by_collection'].items())[:3]}")
