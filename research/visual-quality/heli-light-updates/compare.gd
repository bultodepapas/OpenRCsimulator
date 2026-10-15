extends SceneTree
const Model=preload("res://aircraft/hx700_model.gd")
const Exposure=preload("res://render/world/exposure.gd")
const Clock=preload("res://render/shader_clock.gd")
var reference: Script
var candidate: Script
var output: String
var reverse:=false

func _initialize() -> void:
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--reference="): reference=load(arg.trim_prefix("--reference="))
  if arg.begins_with("--candidate="): candidate=load(arg.trim_prefix("--candidate="))
  if arg.begins_with("--out="): output=arg.trim_prefix("--out=")
  reverse=reverse or arg=="--reverse"
 _run.call_deferred()

func _snapshot(kit: Node3D) -> PackedByteArray:
 var values: Array=[kit.visible,kit.active_mode,kit._beacon.visible,kit._landing.visible,kit._landing.light_energy,kit._frame_fill.visible,kit._frame_fill.light_energy]
 for optic: Dictionary in kit._optics:
  values.append([optic.node.visible,optic.material.get_shader_parameter("radiance"),optic.material.get_shader_parameter("display_cap")])
 for binding: Dictionary in kit._rotors:
  var light: Node3D=binding.node
  values.append([light.visible,light.transform,light.gain,light.current_phase_rad,light.current_omega_rad_s])
  for material: ShaderMaterial in [light.top_material,light.bottom_material]:
   values.append([material.get_shader_parameter("effect_gain"),material.get_shader_parameter("phase_rad"),material.get_shader_parameter("omega_rad_s"),material.get_shader_parameter("shutter_s")])
 return var_to_bytes(values)

func _run() -> void:
 Exposure.register(); Clock.register()
 var model: Dictionary=Model.build()
 var kits: Array[Node3D]=[]
 for script: Script in [reference,candidate]:
  var kit: Node3D=script.new()
  kit.model=model
  kit._build()
  kits.append(kit)
 var valid:=true
 var exact_pairs:=0
 # Per-frame equivalence includes exact dusk changes, stable runs, invalid input,
 # mode transitions with unchanged factors, exposure, arming and live mount motion.
 for index: int in 1024:
  var sun: float=[45.0,-20.0,-.5,NAN,INF,-INF,3.0,-4.0,-.5000000001,float(index%700)/100.0-4.0][index%10]
  var exposure: float=[.6,2000.0,0.0,-1.0,NAN,INF,2.0][index%7]
  var telemetry: Dictionary={omega_rad_s=float(index)-500.0,tail_omega_rad_s=-float(index)*3.0}
  var before:=var_to_bytes(telemetry)
  model.main_rotor_mount.rotation.x=float(index)*.001
  model.tail_rotor.rotation.y=-float(index)*.002
  for kit: Node3D in kits:
   kit.set_mode(["auto","all","nav","off"][(index>>5)%4])
   kit.update_visual(sun,exposure,telemetry,float(index)*.01,-float(index)*.03,index%3==0)
  valid=valid and _snapshot(kits[0])==_snapshot(kits[1]) and before==var_to_bytes(telemetry)
  exact_pairs+=1
 # Adding optics after a cached update must not leave their default brightness.
 for kit: Node3D in kits:
  kit.set_mode("auto"); kit.update_visual(-.5,.6)
  kit._add_sprite("late_sprite",Color.WHITE,Vector3.ZERO,.01,true)
  kit._add_strip("late_strip",PackedVector3Array([Vector3.ZERO,Vector3.RIGHT]),Color.WHITE,Vector3.UP)
  kit.update_visual(-.5,.6)
 valid=valid and _snapshot(kits[0])==_snapshot(kits[1])
 exact_pairs+=1
 # Remove late optics before timing the unmodified production kit size.
 for kit: Node3D in kits:
  for count: int in 2:
   var optic: Dictionary=kit._optics.pop_back()
   optic.node.free()
 var rows: Array=[]
 var telemetry: Dictionary={omega_rad_s=167.0,tail_omega_rad_s=778.0}
 for workload: String in ["night","day","fixed_dusk","changing_dusk"]:
  for pair: int in 6:
   for variant: int in ([0,1] if (pair%2==0)!=reverse else [1,0]):
    var kit: Node3D=kits[variant]
    kit.set_mode("auto")
    var begin:=Time.get_ticks_usec()
    for frame: int in 4000:
     var sun: float=-20.0
     if workload=="day": sun=45.0
     elif workload=="fixed_dusk": sun=-.5
     elif workload=="changing_dusk": sun=float(frame%700)/100.0-4.0
     kit.update_visual(sun,2000.0,telemetry,float(frame)/60.0,float(frame)/13.0,true)
    rows.append({workload=workload,pair=pair,variant=variant,usec_per_update=float(Time.get_ticks_usec()-begin)/4000.0})
   valid=valid and _snapshot(kits[0])==_snapshot(kits[1])
   exact_pairs+=1
 FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({valid=valid,exact_pairs=exact_pairs,rows=rows},"\t"))
 print("Helicopter light updates: ",exact_pairs," exact pairs; valid=",valid)
 for kit: Node3D in kits: kit.free()
 model.root.free()
 await process_frame
 await process_frame
 quit(0 if valid else 1)
