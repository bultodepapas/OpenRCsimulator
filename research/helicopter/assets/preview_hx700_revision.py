import bpy,json,importlib.util,argparse,sys
from pathlib import Path
repo=next(p for p in Path(__file__).resolve().parents if (p/"app/project.godot").is_file())
spec=importlib.util.spec_from_file_location("hx_audit",repo/"research/helicopter/assets/inventory_hx700.py")
util=importlib.util.module_from_spec(spec);spec.loader.exec_module(util)
parser=argparse.ArgumentParser()
parser.add_argument("--out",type=Path,required=True)
args=parser.parse_args(sys.argv[sys.argv.index("--")+1:])
out=args.out.resolve();out.mkdir(parents=True,exist_ok=True)
root=bpy.data.objects["HX-700"]; source=Path(bpy.data.filepath); digest=util.sha256_file(source)
for obj in (root,bpy.data.objects["Ajustes_Mecanicos"]):
 if obj.animation_data: obj.animation_data.action=None
root["giro_rotor"]=0.0; root["velocidad_rotor"]=0.0
root["paso_colectivo"]=0.0;root["ciclico_alabeo"]=0.0;root["ciclico_cabeceo"]=0.0;root["paso_cola"]=0.0
root.update_tag(); bpy.context.view_layer.update()
objects=util.descendants(root); names={o.name for o in objects}|{root.name}
export=util.export_preview(out,source,root,objects,names)
gltf=util.read_glb_json(out/"hx700-preview.glb")
primitives=[p for mesh in gltf.get("meshes",[]) for p in mesh.get("primitives",[])]
export["material_surface_count"]=len(primitives)
export["indexed_triangle_count"]=sum(gltf["accessors"][p["indices"]]["count"]//3
                                      for p in primitives if p.get("mode",4)==4 and "indices" in p)
(out/"export.json").write_text(json.dumps(export,indent=2)+"\n",encoding="utf-8")
scene=bpy.context.scene
scene.render.engine="BLENDER_WORKBENCH"
scene.render.resolution_x=1000;scene.render.resolution_y=700;scene.render.resolution_percentage=100
scene.render.image_settings.file_format="PNG"
scene.display.shading.light="STUDIO";scene.display.shading.color_type="RANDOM"
scene.display.shading.background_type="WORLD";scene.world.color=(0.2,0.2,0.2)
scene.display.shading.show_shadows=True;scene.display.shading.show_cavity=True
for obj in scene.objects:
 if obj.name not in names and obj.type!="CAMERA":obj.hide_render=True
for view,camera,remove in [("assembled","Cam_Principal_3-4",False),("mechanics","Cam_Varillaje",True)]:
 root["carenado_retirado"]=1.0 if remove else 0.0;root.update_tag();bpy.context.view_layer.update()
 for name in ("Carenado","Carenado_Gomas"):bpy.data.objects[name].hide_render=remove
 scene.camera=bpy.data.objects[camera]
 scene.render.filepath=str(out/f"{view}.png")
 bpy.ops.render.render(write_still=True)
print("PREVIEW",json.dumps({k:export[k] for k in ("path","sha256","size_bytes","node_count","material_surface_count","indexed_triangle_count")}),"unchanged",digest==util.sha256_file(source))
