"""Read-only Blender delivery inventory; never save the input .blend."""
import bpy
import argparse
import importlib.util
import json
import sys
from pathlib import Path

ROOT=next(p for p in Path(__file__).resolve().parents if (p/"app/project.godot").is_file())
spec=importlib.util.spec_from_file_location("hx_audit",ROOT/"research/helicopter/assets/inventory_hx700.py")
util=importlib.util.module_from_spec(spec)
spec.loader.exec_module(util)

def simple(value):
    if value is None or isinstance(value,(str,bool,int,float)): return value
    if hasattr(value,"name"): return value.name
    try: return [float(v) for v in value]
    except (TypeError,ValueError): return str(value)

def constraint(c):
    values={"name":c.name,"type":c.type}
    for prop in c.bl_rna.properties:
        if prop.identifier=="rna_type": continue
        try: values[prop.identifier]=simple(getattr(c,prop.identifier))
        except (AttributeError,TypeError): pass
    return values

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--out",type=Path,required=True)
    args=parser.parse_args(sys.argv[sys.argv.index("--")+1:])
    out=args.out.resolve(); out.mkdir(parents=True,exist_ok=True)
    source=Path(bpy.data.filepath)
    before=util.sha256_file(source)
    scene=bpy.context.scene
    deps=bpy.context.evaluated_depsgraph_get()
    objects=[]; points=[]
    for obj in sorted(scene.objects,key=lambda v:v.name):
        row={"name":obj.name,"type":obj.type,"parent":obj.parent.name if obj.parent else None,
             "parent_type":obj.parent_type,"parent_bone":obj.parent_bone,
             "matrix_local":[list(r) for r in obj.matrix_local],"matrix_world":[list(r) for r in obj.matrix_world],
             "rotation_mode":obj.rotation_mode,"properties":util.property_values(obj),
             "constraints":[constraint(c) for c in obj.constraints],"modifiers":[{"name":m.name,"type":m.type} for m in obj.modifiers],
             "hidden_render":obj.hide_render,"hidden_viewport":obj.hide_viewport,
             "collections":[c.name for c in obj.users_collection]}
        anim=obj.animation_data
        row["animation"]={"action":anim.action.name if anim and anim.action else None,
                          "drivers":util.driver_records(anim),
                          "nla_tracks":[t.name for t in anim.nla_tracks] if anim else []}
        if obj.type=="MESH":
            evaluated=obj.evaluated_get(deps); mesh=evaluated.to_mesh()
            mesh.calc_loop_triangles()
            world=[evaluated.matrix_world@v.co for v in mesh.vertices]
            row["mesh"]={"vertices":len(obj.data.vertices),"triangles":len(mesh.loop_triangles),
                         "bounds_world":util.bounds(world),"materials":[m.name if m else None for m in obj.data.materials],
                         "shape_keys":[k.name for k in obj.data.shape_keys.key_blocks] if obj.data.shape_keys else []}
            points.extend(world); evaluated.to_mesh_clear()
        elif obj.type=="ARMATURE":
            row["bones"]=[{"name":b.name,"parent":b.parent.name if b.parent else None,
                            "head":list(b.head_local),"tail":list(b.tail_local),"deform":b.use_deform,
                            "properties":util.property_values(b)} for b in obj.data.bones]
            row["pose"]=[{"name":b.name,"constraints":[constraint(c) for c in b.constraints],"properties":util.property_values(b)} for b in obj.pose.bones]
        objects.append(row)
    texts=[]
    for index,txt in enumerate(bpy.data.texts):
        path=out/f"embedded-{index:02d}-{Path(txt.name).name.replace(':','_')}"
        path.write_text(txt.as_string(),encoding="utf-8")
        texts.append({"name":txt.name,"file":path.name,"sha256":util.sha256_file(path),"length":len(txt.as_string())})
    types={}
    for obj in objects: types[obj["type"]]=types.get(obj["type"],0)+1
    data={"format":"openrc-heli-delivery-audit v1","source":{"path":str(source),"sha256":before,"bytes":source.stat().st_size},
          "blender":bpy.app.version_string,"autoexec_enabled":bpy.context.preferences.filepaths.use_scripts_auto_execute,
          "scene":{"name":scene.name,"frame":scene.frame_current,"frames":[scene.frame_start,scene.frame_end],"fps":scene.render.fps,
                   "units":{"system":scene.unit_settings.system,"scale_length":scene.unit_settings.scale_length,"length_unit":scene.unit_settings.length_unit},"properties":util.property_values(scene)},
          "counts":{"objects":len(objects),"types":types,"triangles":sum(o.get("mesh",{}).get("triangles",0) for o in objects)},
          "bounds_all_meshes":util.bounds(points),"texts":texts,"objects":objects,
          "images":[{"name":v.name,"path":v.filepath,"packed":bool(v.packed_file)} for v in bpy.data.images]}
    data["source"]["unchanged"]=before==util.sha256_file(source)
    (out/"inventory.json").write_text(json.dumps(data,indent=2,ensure_ascii=False)+"\n",encoding="utf-8")
    print("DELIVERY AUDIT",json.dumps({"source":data["source"],"counts":data["counts"],"texts":texts},ensure_ascii=False))

if __name__=="__main__": main()
