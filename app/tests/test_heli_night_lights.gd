# HELI-30: real-model kit, daylight isolation, modes, phase and lighting bounds.
extends SceneTree
const Model=preload("res://aircraft/hx700_model.gd")
const Lights=preload("res://render/rotor/heli_night_lights.gd")
const Rotor=preload("res://render/rotor/heli_night_rotor.gd")
const Flight=preload("res://helicopter_main.gd")
const Home=preload("res://ui/home_scene.gd")
const Conditions=preload("res://render/world/conditions.gd")
var checks:=0
var failures:=0
func check(label: String,ok: bool) -> void:
 checks+=1
 if not ok: failures+=1; printerr("FAIL ",label)
func _initialize() -> void: run.call_deferred()
func run() -> void:
 check("invalid aircraft has no kit",Lights.attach({})==null)
 var model: Dictionary=Model.build()
 root.add_child(model.root)
 var original_pose: Transform3D=model.root.transform
 var kit: Node3D=Lights.attach(model)
 check("kit attaches once to this aircraft",kit!=null and Lights.attach(model)==kit and kit.get_parent()==model.root)
 check("default auto has no daylight contribution",kit.mode=="auto" and not kit.visible and kit.active_mode=="off")
 check("twilight monotone endpoints",Lights.night_factor(3)==0 and Lights.night_factor(-4)==1 and Lights.night_factor(0)<Lights.night_factor(-1))
 check("invalid solar value remains dark",Lights.night_factor(NAN)==0)
 check("fixed TOD uses geometric elevation, not the clamped sun",Lights.sun_elevation({solar={elevation_deg=-20},sun_elevation_deg=.05})==-20)
 check("legacy world elevation remains live",Lights.sun_elevation({}, {sun_elevation_deg=-8})==-8)
 var state: Dictionary={omega_rad_s=167.0,tail_omega_rad_s=778.0,a1=.02,b1=-.03}
 var original_state: Dictionary=state.duplicate(true)
 kit.update_visual(-20,2000,state,1.2,2.4,true)
 check("night exposes both rotors, body and ground lamp",kit.visible and kit._rotors.size()==2 and kit._landing.visible and kit._beacon.visible)
 check("navigation follows aircraft coordinates",kit.get_node("nav_port").position.x<0 and kit.get_node("nav_starboard").position.x>0 and kit.get_node("nav_tail").position.z>0)
 check("landing cone aims forward and down",(-kit._landing.basis.z).y<-.5 and (-kit._landing.basis.z).z<-.5 and not kit._landing.shadow_enabled)
 check("local lights are exposure bounded",kit._landing.light_energy*2000<=.12001 and kit._frame_fill.light_energy*2000<=.18001)
 check("canopy strip follows multiple surface stations",kit.get_node("canopy_port").mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()>=72)
 var main: Node3D=kit.get_node("MainBladeLeds")
 var main_upper: PackedVector3Array=main._top_mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
 var main_lower: PackedVector3Array=main._bottom_mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
 var skin_upper: float=-INF
 var skin_lower: float=INF
 for blade: Node3D in model.main_rotor_mount.find_children("Pala_Principal_*","MeshInstance3D",true,false):
  var transform_value: Transform3D=model.main_rotor_mount.global_transform.affine_inverse()*blade.global_transform
  for surface: int in blade.mesh.get_surface_count():
   for vertex: Vector3 in blade.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
    var point: Vector3=transform_value*vertex
    if Vector2(point.x,point.y).length()<main.radius_local_m*.5: continue
    skin_upper=maxf(skin_upper,point.z); skin_lower=minf(skin_lower,point.z)
 check("stopped main LEDs clear the measured outer blade skin",is_finite(skin_upper) and main_upper[0].z>skin_upper+.001 and main_lower[0].z<skin_lower-.001)
 var expected_phase: float=fposmod(-1.2+main.rest_phase_offset_rad,TAU)
 check("LED phase uses accepted shaft phase and visual sign",is_equal_approx(main.current_phase_rad,expected_phase) and main.current_omega_rad_s==-167)
 for i: int in 60: kit.update_visual(-20,2000,state,1.2,2.4,true)
 check("pause and repeated presentation hold phase",is_equal_approx(main.current_phase_rad,expected_phase))
 check("presentation never changes input telemetry or aircraft body pose",state==original_state and model.root.transform==original_pose)
 kit.update_visual(-.5,2000,state,1.2,2.4)
 check("dusk fades both capped body lights and rotor",is_equal_approx(main.gain,.5) and is_equal_approx(kit._optics[0].material.get_shader_parameter("display_cap"),.325))
 check("unknown mode is rejected",not kit.set_mode("broken") and kit.mode=="auto")
 var flight: Node=Flight.new()
 flight._night_kit=kit
 check("controller light action works",flight.controller_action("lights_cycle") and kit.mode=="all")
 var event=InputEventKey.new()
 event.physical_keycode=KEY_L; event.pressed=true
 flight._unhandled_input(event)
 kit.update_visual(-20,2000,state)
 check("keyboard L reaches navigation-only mode",kit.mode=="nav" and kit.get_node("nav_port").visible and not kit.get_node("canopy_port").visible and not main.visible and not kit._landing.visible)
 check("disarmed beacon stays off",not kit._beacon.visible)
 kit.cycle_mode(); kit.update_visual(-20,2000,state)
 check("off hides every contribution",kit.mode=="off" and not kit.visible and not kit._landing.visible and not kit._frame_fill.visible)
 kit.cycle_mode(); kit.update_visual(45,.6,state)
 check("mode cycle returns to automatic daylight off",kit.mode=="auto" and not kit.visible)
 var other_model: Dictionary=Model.build()
 root.add_child(other_model.root)
 var other: Node3D=Lights.attach(other_model)
 check("instances own isolated materials",other._optics[0].material!=kit._optics[0].material and other.mode=="auto")
 # Measured presentation cost, separate from any physics performance claim.
 var begin: int=Time.get_ticks_usec()
 for i: int in 1000: kit.update_visual(-20,2000,state,float(i)/60,float(i)/13,true)
 print("HELI night update mean us: ",(Time.get_ticks_usec()-begin)/1000.0)
 flight._night_kit=null; flight.free()
 model.root.free(); other_model.root.free()
 Conditions.session_preset="night"
 var home=Home.new("xcell-60-research")
 root.add_child(home)
 var home_kit: Node3D=home.airplane.root.get_node("HelicopterNightKit")
 check("night Home uses helicopter kit",home_kit.visible and home_kit.active_mode=="all")
 home.show_aircraft("gp-extra-300s-60")
 check("cached helicopter is hidden",not home_kit.is_visible_in_tree())
 home.show_aircraft("xcell-60-research")
 check("returning Home retains one helicopter kit",home.airplane.root.get_node("HelicopterNightKit")==home_kit and home_kit.is_visible_in_tree())
 home.free()
 Conditions.session_preset=""
 print("HELI night lights: %d checks, %d failed"%[checks,failures])
 quit(0 if failures==0 else 1)
