extends SceneTree
const Model=preload("res://aircraft/hx700_model.gd")
const Data=preload("res://physics/rotorcraft_data.gd")
const Presentation=preload("res://render/rotor/heli_crash_presentation.gd")
const NightLights=preload("res://render/rotor/heli_night_lights.gd")
var checks: int=0
var failures: int=0
func check(label: String,ok: bool) -> void:
 checks+=1
 if not ok: failures+=1; print("FAIL ",label)
func _initialize() -> void: run.call_deferred()
func run() -> void:
 var model: Dictionary=Model.build()
 root.add_child(model.root)
 var context: Dictionary=Data.load_file("res://data/aircraft/xcell_60_research.json").context
 var p=Presentation.new(); root.add_child(p)
 check("source model prepares",p.configure(model,context))
 var kit: Node3D=NightLights.attach(model)
 kit.set_mode("all"); kit.update_visual(-20,.6)
 p.set_night_kit(kit)
 var report: Dictionary={component="main_rotor",surface="grass",normal_speed_mps=2.0,tangent_speed_mps=12.0,normal_energy_j=8.0,effective_mass_kg=2.0,
  point_world_ned=PackedFloat64Array([0,0,-.4]),ground_point_world_ned=PackedFloat64Array([0,0,-.4]),normal_world_ned=PackedFloat64Array([0,0,-1]),ground_normal_world_ned=PackedFloat64Array([0,0,-1]),
  velocity_world_ned=PackedFloat64Array([4,0,2]),point_velocity_world_ned=PackedFloat64Array([12,0,2]),body_angular_velocity=PackedFloat64Array([0,0,0]),main_omega_rad_s=167.0,tail_omega_rad_s=778.0,
  severity={"valid":true,"class":2,"severity":.25,"component":"main_rotor","component_group":"propeller","surface":"grass"}}
 var pose: Transform3D=Transform3D(Basis.IDENTITY,Vector3(0,.5,0))
 model.root.transform=pose
 var count: int=p.get_tree().get_node_count()
 for repeat: int in 5:
  p.start(report,pose,model.cg_model_m,Vector3(1,0,0))
  check("crash activates once with no thermal fire %d"%repeat,p.active and not p.effects.flame.emitting and not p.effects.smoke.emitting and p.effects.fire_strength()==0.0)
  check("fracture dust and blade chips start at the elevated contact",p._composite_dust.emitting and p.effects.blade_chips.emitting and p.effects.dust.global_position.y>.4)
  var optic: Node3D=p._surviving_optics[0]
  var part: Node3D=optic.get_parent()
  var before: Vector3=optic.global_position
  part.global_position+=Vector3(.15,0,0)
  check("stationary night optics follow real wreck parts",part.name=="Carenado" and optic.global_position.is_equal_approx(before+Vector3(.15,0,0)) and not p.wreck.find_child("Surviving_MainBladeLeds",true,false))
  part.global_position-=Vector3(.15,0,0)
  p.update(.05,false)
  var age: float=p._age
  p.update(.05,true)
  check("pause freezes particles and effect time",p._age==age and p.effects.dust.speed_scale==0.0 and p._composite_dust.speed_scale==0.0)
  p.update(.05,false)
  check("resume restores particle clock",p._age>age and p._composite_dust.speed_scale==1.0)
  check("bounded particle pool",p.stats().effects.particles<=1024)
  p.reset()
  check("restart hides pooled effects and removes active debris",not p.active and not p._composite_dust.visible and not p.effects.dust.visible and p.wreck.active_body_count()==0 and p._surviving_optics.is_empty())
  check("repeated impacts do not accumulate nodes",p.get_tree().get_node_count()==count)
 report.component="fuselage"
 report.severity={"valid":true,"class":1,"severity":.05,"component":"fuselage","component_group":"fuselage","surface":"runway"}
 report.surface="runway"
 p.start(report,pose,model.cg_model_m,Vector3.ZERO)
 check("small paved impact makes neither dirt plume nor fracture smoke",not p.effects.dust.emitting and not p._composite_dust.emitting and not p.effects.blade_chips.emitting)
 report.component="main_rotor"
 report.severity={"valid":true,"class":3,"severity":.5,"component":"main_rotor","component_group":"propeller","surface":"runway","tangential_speed_mps":60.0}
 kit.set_mode("off"); kit.update_visual(-20,.6)
 p.start(report,pose,model.cg_model_m,Vector3.ZERO)
 check("blade envelope does not invent metal sparks",not p.effects.sparks.emitting and not p.effects.sparks.visible)
 check("disabled night kit leaves no surviving optics",p._surviving_optics.is_empty())
 p.free(); model.root.free()
 print("HELI-33 crash presentation: %d checks, %d failed"%[checks,failures])
 quit(0 if failures==0 else 1)
