"""Pose-only checks in a disposable background process; does not save Blender input."""
import bpy, json, math, sys, importlib.util, argparse
from pathlib import Path
root_path=next(p for p in Path(__file__).resolve().parents if (p/"app/project.godot").is_file())
spec=importlib.util.spec_from_file_location("audit_delivery",root_path/"research/helicopter/assets/audit_hx700_revision.py")
audit=importlib.util.module_from_spec(spec); spec.loader.exec_module(audit)
parser=argparse.ArgumentParser()
parser.add_argument("--out",type=Path,required=True)
args=parser.parse_args(sys.argv[sys.argv.index("--")+1:])
out=args.out.resolve();out.mkdir(parents=True,exist_ok=True)
source=Path(bpy.data.filepath); digest=audit.util.sha256_file(source)
root=bpy.data.objects["HX-700"]; settings=bpy.data.objects["Ajustes_Mecanicos"]
for ob in (root,settings):
    if ob.animation_data: ob.animation_data.action=None
roots={k:root[k] for k in root.keys()}; adjustments={k:settings[k] for k in settings.keys()}
rods=json.loads(bpy.data.texts["RIG_BIELETAS.json"].as_string())
cases=[("neutral",{}), ("collective_plus",{"paso_colectivo":10.0}), ("collective_minus",{"paso_colectivo":-10.0}),
       ("roll_plus",{"ciclico_alabeo":8.0}), ("pitch_plus",{"ciclico_cabeceo":8.0}),
       ("tail_plus",{"paso_cola":15.0}), ("tail_minus",{"paso_cola":-15.0}),
       ("mixed",{"paso_colectivo":8.0,"ciclico_alabeo":6.0,"ciclico_cabeceo":6.0,"paso_cola":10.0}),
       ("tracking_offset",{"adj:ajuste_bieleta_cabeza_A":1.0}),
       ("servo_limit",{"paso_colectivo":13.0,"ciclico_alabeo":10.0,"ciclico_cabeceo":10.0}),
       ("tail_rod_offset",{"adj:ajuste_varilla_cola":1.5}),
       ("cyclic_servo_saturation",{"paso_colectivo":13.0,"ciclico_alabeo":8.0,"adj:limite_servos_ciclicos":15.0}),
       ("tail_servo_saturation",{"paso_cola":20.0,"adj:limite_servo_cola":10.0}),
       ("unreachable_rod",{"adj:ajuste_varilla_delantera_izq":100.0})]
results=[]
for name,inputs in cases:
  for phase in ([0,math.pi/2,math.pi,3*math.pi/2] if name in ("neutral","roll_plus","pitch_plus","mixed") else [0]):
    for k,v in roots.items(): root[k]=v
    for k,v in adjustments.items(): settings[k]=v
    root["giro_rotor"]=phase; root["velocidad_rotor"]=0.0
    for k,v in inputs.items():
      if k.startswith("adj:"): settings[k[4:]]=v
      else: root[k]=v
    root.update_tag(); settings.update_tag(); bpy.context.view_layer.update()
    deps=bpy.context.evaluated_depsgraph_get(); deps.update()
    rod_rows=[]
    for rod in rods:
      a=bpy.data.objects[rod["terminal_1"]].evaluated_get(deps).matrix_world.translation
      b=bpy.data.objects[rod["terminal_2"]].evaluated_get(deps).matrix_world.translation
      nominal=rod["largo_mm"]+float(settings[rod["ajuste"]])
      rod_rows.append({"name":rod["nombre"],"actual_mm":(b-a).length*1000,"target_mm":nominal,"error_mm":(b-a).length*1000-nominal})
    telemetry=audit.util.property_values(bpy.data.objects["Telemetria_Mecanica"].evaluated_get(deps))
    results.append({"case":name,"phase_rad":phase,"inputs":inputs,"telemetry":telemetry,"rods":rod_rows,
                    "invalid_drivers":[{"object":o.name,"path":c.data_path} for o in bpy.context.scene.objects if o.animation_data for c in o.animation_data.drivers if not c.driver.is_valid]})
(out/"pose-probes.json").write_text(json.dumps({"source_sha256":digest,"unchanged":digest==audit.util.sha256_file(source),"samples":results},indent=2)+"\n",encoding="utf-8")
print("POSE PROBES",len(results),"unchanged",digest==audit.util.sha256_file(source))
