"""Read-only inventory of an open .blend. Run: blender -b -Y --factory-startup FILE --python inspect_blend.py -- OUT.json"""
import bpy, json, sys, math
from mathutils import Vector

out_path = sys.argv[sys.argv.index("--") + 1]
dg = bpy.context.evaluated_depsgraph_get()

def mat(m):
    return [[round(v, 6) for v in row] for row in m]

def props(idb):
    r = {}
    for k in idb.keys():
        if k.startswith("_"):
            continue
        try:
            v = idb[k]
            r[k] = v if isinstance(v, (int, float, str, bool)) else str(v)
        except Exception as e:
            r[k] = f"<err {e}>"
    return r

def coll_tree(c, depth=0):
    return {
        "name": c.name,
        "objects": [o.name for o in c.objects],
        "hide_render": c.hide_render,
        "hide_viewport": c.hide_viewport,
        "children": [coll_tree(ch, depth + 1) for ch in c.children],
    }

def layer_coll_state(lc, acc):
    acc[lc.collection.name] = {"exclude": lc.exclude, "hide_viewport": lc.hide_viewport}
    for ch in lc.children:
        layer_coll_state(ch, acc)

data = {"file": bpy.data.filepath, "version_file": list(bpy.data.version), "app": bpy.app.version_string}
sc = bpy.context.scene
data["scenes"] = [s.name for s in bpy.data.scenes]
data["scene"] = {
    "name": sc.name,
    "unit_system": sc.unit_settings.system,
    "scale_length": sc.unit_settings.scale_length,
    "length_unit": sc.unit_settings.length_unit,
    "frame_start": sc.frame_start, "frame_end": sc.frame_end, "frame_current": sc.frame_current,
    "camera": sc.camera.name if sc.camera else None,
    "props": props(sc),
}
data["collections"] = coll_tree(sc.collection)
lcs = {}
for vl in sc.view_layers:
    layer_coll_state(vl.layer_collection, lcs)
data["layer_collections"] = lcs

objs = []
world_min = Vector((1e9,) * 3); world_max = Vector((-1e9,) * 3)
tri_total = 0
surf_total = 0
for o in bpy.data.objects:
    e = {
        "name": o.name, "type": o.type, "parent": o.parent.name if o.parent else None,
        "parent_type": o.parent_type, "parent_bone": o.parent_bone or None,
        "children": [c.name for c in o.children],
        "collections": [c.name for c in o.users_collection],
        "loc": [round(v, 6) for v in o.location],
        "rot_mode": o.rotation_mode,
        "rot_euler_deg": [round(math.degrees(v), 4) for v in o.rotation_euler],
        "rot_quat": [round(v, 6) for v in o.rotation_quaternion],
        "scale": [round(v, 6) for v in o.scale],
        "matrix_world": mat(o.matrix_world),
        "matrix_parent_inverse_identity": o.matrix_parent_inverse == o.matrix_parent_inverse.Identity(4) if hasattr(o.matrix_parent_inverse, "Identity") else None,
        "hide_viewport": o.hide_viewport, "hide_render": o.hide_render, "hide_get": o.hide_get() if o.name in bpy.context.view_layer.objects else None,
        "in_view_layer": o.name in bpy.context.view_layer.objects,
        "props": props(o),
        "data_name": o.data.name if o.data else None,
        "data_users": o.data.users if o.data else None,
        "modifiers": [{"name": m.name, "type": m.type, "show_render": m.show_render, "show_viewport": m.show_viewport} for m in o.modifiers],
        "constraints": [{"name": c.name, "type": c.type, "target": getattr(getattr(c, "target", None), "name", None)} for c in o.constraints],
        "anim": None,
        "dims": [round(v, 6) for v in o.dimensions],
        "instance_type": o.instance_type,
        "instance_collection": o.instance_collection.name if o.instance_collection else None,
    }
    try:
        e["matrix_parent_inverse"] = mat(o.matrix_parent_inverse)
    except Exception:
        pass
    if o.animation_data:
        ad = o.animation_data
        e["anim"] = {
            "action": ad.action.name if ad.action else None,
            "drivers": [{"path": d.data_path, "index": d.array_index, "expr": d.driver.expression,
                         "vars": [[t.id.name if t.id else None for t in v.targets] for v in d.driver.variables]} for d in ad.drivers],
        }
    if o.type == "MESH" and o.data:
        try:
            eo = o.evaluated_get(dg)
            me = eo.to_mesh()
            me.calc_loop_triangles()
            ntri = len(me.loop_triangles)
            used = set(t.material_index for t in me.loop_triangles)
            e["eval_tris"] = ntri
            e["eval_verts"] = len(me.vertices)
            e["materials_used"] = sorted({(o.material_slots[i].material.name if i < len(o.material_slots) and o.material_slots[i].material else None) or "<none>" for i in used}, key=str)
            e["uv_layers"] = [u.name for u in me.uv_layers]
            e["color_attrs"] = [a.name for a in me.color_attributes]
            mw = o.matrix_world
            lo = Vector((1e9,) * 3); hi = Vector((-1e9,) * 3)
            for v in me.vertices:
                w = mw @ v.co
                lo = Vector(map(min, lo, w)); hi = Vector(map(max, hi, w))
            if me.vertices:
                e["world_bbox"] = [[round(x, 5) for x in lo], [round(x, 5) for x in hi]]
            visible = e["in_view_layer"] and not o.hide_render
            e["render_visible"] = visible
            if visible and me.vertices:
                world_min = Vector(map(min, world_min, lo)); world_max = Vector(map(max, world_max, hi))
                tri_total += ntri
                surf_total += len(used)
            eo.to_mesh_clear()
        except Exception as ex:
            e["eval_error"] = str(ex)
        e["material_slots"] = [s.material.name if s.material else None for s in o.material_slots]
        e["mesh_tris_raw"] = sum(len(p.vertices) - 2 for p in o.data.polygons)
        e["shade_smooth_frac"] = round(sum(p.use_smooth for p in o.data.polygons) / max(1, len(o.data.polygons)), 3)
    if o.type == "ARMATURE":
        e["bones"] = [{"name": b.name, "parent": b.parent.name if b.parent else None,
                       "head": [round(v, 5) for v in b.head_local], "tail": [round(v, 5) for v in b.tail_local]} for b in o.data.bones]
    if o.type == "EMPTY":
        e["empty_display"] = [o.empty_display_type, o.empty_display_size]
    objs.append(e)
data["objects"] = objs
data["render_visible_mesh_bbox"] = [[round(x, 5) for x in world_min], [round(x, 5) for x in world_max]]
data["render_visible_tris"] = tri_total
data["render_visible_surfaces"] = surf_total

mats = []
for m in bpy.data.materials:
    me = {"name": m.name, "users": m.users, "use_nodes": m.use_nodes, "blend_method": getattr(m, "blend_method", None),
          "backface_culling": m.use_backface_culling, "props": props(m)}
    if m.use_nodes and m.node_tree:
        me["nodes"] = sorted({n.bl_idname for n in m.node_tree.nodes})
        me["images"] = sorted({n.image.name for n in m.node_tree.nodes if n.bl_idname == "ShaderNodeTexImage" and n.image})
        out = [n for n in m.node_tree.nodes if n.bl_idname == "ShaderNodeOutputMaterial" and n.is_active_output]
        if out and out[0].inputs["Surface"].links:
            me["surface_from"] = out[0].inputs["Surface"].links[0].from_node.bl_idname
    mats.append(me)
data["materials"] = mats
data["images"] = [{"name": i.name, "size": list(i.size), "packed": bool(i.packed_file), "filepath": i.filepath, "users": i.users,
                   "source": i.source, "colorspace": i.colorspace_settings.name} for i in bpy.data.images]
data["libraries"] = [{"name": l.name, "filepath": l.filepath} for l in bpy.data.libraries]
data["texts"] = [{"name": t.name, "lines": len(t.lines), "use_module": t.use_module,
                  "head": "\n".join(l.body for l in t.lines[:400])} for t in bpy.data.texts]
data["actions"] = [{"name": a.name, "users": a.users, "frame_range": list(a.frame_range)} for a in bpy.data.actions]
data["cameras"] = [c.name for c in bpy.data.cameras]
data["lights"] = [l.name for l in bpy.data.lights]
data["node_groups"] = [{"name": g.name, "type": g.bl_idname, "users": g.users} for g in bpy.data.node_groups]
data["counts"] = {k: len(getattr(bpy.data, k)) for k in ["objects", "meshes", "materials", "images", "collections", "texts", "actions", "armatures", "curves", "node_groups"]}
with open(out_path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=1, ensure_ascii=False)
print("WROTE", out_path, data["counts"], "tris", tri_total)
