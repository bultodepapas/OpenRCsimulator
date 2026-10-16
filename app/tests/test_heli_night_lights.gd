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
 _check_canopy_profiles()
 _check_canopy_station_bounds()
 _check_canopy_triangle_collection()
 _check_optic_gain_updates()
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
 # controller_action requires an active session even though this light action does not use it.
 var session_stub:=Node.new()
 flight.session=session_stub
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
 flight._night_kit=null; flight.session=null; session_stub.free(); flight.free()
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

func _check_canopy_profiles() -> void:
 # Two rectangular skins: every station has exactly y=[0,1], x=[-.25,.25].
 var triangles: PackedVector3Array=[]
 for x: float in [-.25,.25]:
  triangles.append_array(PackedVector3Array([Vector3(x,0,-1),Vector3(x,1,-1),Vector3(x,1,1),Vector3(x,0,-1),Vector3(x,1,1),Vector3(x,0,1)]))
 var profiles: Array=[[1.0,.83],[-1.0,.43],[1.0,.83],[-1.0,0.0],[1.0,1.0]]
 var original: PackedByteArray=var_to_bytes([triangles,profiles])
 var lines: Array=Lights._canopy_lines(triangles,profiles)
 var matches: bool=lines.size()==profiles.size()
 var single_matches: bool=true
 for index: int in profiles.size():
  var line: PackedVector3Array=lines[index]
  matches=matches and line.size()==17
  for station: int in line.size():
   var expected: Vector3=Vector3(profiles[index][0]*.252,profiles[index][1],lerpf(-.355,.045,float(station)/16.0))
   matches=matches and line[station].is_equal_approx(expected)
  single_matches=single_matches and var_to_bytes(line)==var_to_bytes(Lights.canopy_line(triangles,profiles[index][0],profiles[index][1]))
 check("batched contours preserve profile order, duplicates, sides and skin boundaries",matches)
 check("single-line API agrees with independently batched profiles",single_matches)
 check("contour requests and source triangles remain unchanged",original==var_to_bytes([triangles,profiles]))
 var modified: PackedVector3Array=lines[0]
 modified[0]=Vector3(99,99,99)
 lines[0]=modified
 check("editing one returned contour leaves its duplicate independent",lines[2][0].is_equal_approx(Vector3(.252,.83,-.355)))
 check("an empty profile batch returns no lines",Lights._canopy_lines(triangles,[]).is_empty())
 var empty_lines: Array=Lights._canopy_lines(PackedVector3Array(),profiles)
 var empty_ok: bool=empty_lines.size()==profiles.size()
 for line: PackedVector3Array in empty_lines: empty_ok=empty_ok and line.is_empty()
 check("empty geometry preserves the requested empty-line count",empty_ok)

func _check_optic_gain_updates() -> void:
 var body:=Node3D.new()
 var kit: Node3D=Lights.attach({root=body})
 var nav: ShaderMaterial=kit.get_node("nav_port").mesh.material
 check("first daylight update initializes body uniforms to zero",nav.get_shader_parameter("radiance")==0.0 and nav.get_shader_parameter("display_cap")==0.0)
 kit.update_visual(-.5,.6)
 var dusk: float=Lights.night_factor(-.5)
 check("dusk updates both body intensity limits",nav.get_shader_parameter("radiance")==1.2*dusk and nav.get_shader_parameter("display_cap")==.65*dusk)
 kit.update_visual(-.5000000001,.6)
 var close_dusk: float=Lights.night_factor(-.5000000001)
 check("sub-epsilon dusk change still reaches the material",close_dusk!=dusk and nav.get_shader_parameter("radiance")==1.2*close_dusk)
 kit.set_mode("all"); kit.update_visual(-20,.6,{},0,0,true)
 kit.set_mode("nav"); kit.update_visual(-20,2000,{},0,0,false)
 check("unchanged gain preserves mode, exposure and arming updates",kit.get_node("nav_port").visible and not kit.get_node("skid_port").visible and not kit._beacon.visible and kit._landing.light_energy<.001 and nav.get_shader_parameter("radiance")==1.2)
 kit.set_mode("auto"); kit.update_visual(-.5,.6)
 var late: MeshInstance3D=kit._add_sprite("late_sprite",Color.WHITE,Vector3.ZERO,.01,true)
 kit._add_strip("late_strip",PackedVector3Array([Vector3.ZERO,Vector3.RIGHT]),Color.WHITE,Vector3.UP)
 kit.update_visual(-.5,.6)
 var strip: ShaderMaterial=kit.get_node("late_strip").mesh.surface_get_material(0)
 check("late optics receive the unchanged dusk gain",late.mesh.material.get_shader_parameter("radiance")==1.2*dusk and strip.get_shader_parameter("radiance")==Lights.STRIP_RADIANCE*dusk)
 kit.update_visual(NAN,.6)
 check("invalid sun clears previously illuminated body materials",not kit.visible and nav.get_shader_parameter("radiance")==0.0)
 body.free()

func _check_canopy_triangle_collection() -> void:
 var body:=Node3D.new()
 var pivot:=Node3D.new()
 var skin:=MeshInstance3D.new()
 body.add_child(pivot); pivot.add_child(skin)
 body.position=Vector3(100,200,300)
 pivot.transform=Transform3D(Basis.from_euler(Vector3(.2,-.4,.7)).scaled(Vector3(-2,.5,1.3)),Vector3(.1,-.2,.3))
 skin.transform=Transform3D(Basis.from_euler(Vector3(-.1,.3,.2)).scaled(Vector3(.3,2,1)),Vector3(-.4,.5,-.6))
 var mesh:=ArrayMesh.new()
 var points:=PackedVector3Array([Vector3.ZERO,Vector3.RIGHT,Vector3.UP,Vector3(99,99,99)])
 var arrays: Array=[]
 arrays.resize(Mesh.ARRAY_MAX)
 arrays[Mesh.ARRAY_VERTEX]=points
 arrays[Mesh.ARRAY_INDEX]=PackedInt32Array([2,1,0,0,1,2])
 mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
 arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3.FORWARD,Vector3.LEFT,Vector3.DOWN])
 arrays[Mesh.ARRAY_INDEX]=null
 mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
 skin.mesh=mesh
 var original: Array=[var_to_bytes(mesh.surface_get_arrays(0)),var_to_bytes(mesh.surface_get_arrays(1))]
 var local: Transform3D=pivot.transform*skin.transform
 var expected:=PackedVector3Array()
 for index: int in [2,1,0,0,1,2]: expected.append(local*points[index])
 for point: Vector3 in [Vector3.FORWARD,Vector3.LEFT,Vector3.DOWN]: expected.append(local*point)
 var actual: PackedVector3Array=Lights._triangles(body,skin)
 check("canopy extraction preserves indexed order and unindexed surfaces in root coordinates",var_to_bytes(actual)==var_to_bytes(expected))
 if not actual.is_empty(): actual[0]=Vector3(42,42,42)
 check("canopy output edits leave source surfaces and subsequent collections independent",original==[var_to_bytes(mesh.surface_get_arrays(0)),var_to_bytes(mesh.surface_get_arrays(1))] and var_to_bytes(Lights._triangles(body,skin))==var_to_bytes(expected))
 pivot.position.x+=.125
 var moved: PackedVector3Array=Lights._triangles(body,skin)
 check("canopy collection immediately reflects a moved parent",not moved.is_empty() and moved[0]==(pivot.transform*skin.transform)*points[2] and moved!=expected)
 body.free()

func _check_canopy_station_bounds() -> void:
 var triangles:=PackedVector3Array([Vector3(-1,0,-.25),Vector3(1,1,0),Vector3(-1,1,0),Vector3(-1,0,0),Vector3(1,1,.25),Vector3(-1,1,.25),Vector3(0,0,2),Vector3(1,0,2),Vector3(0,1,2)])
 var before:=var_to_bytes(triangles)
 var sections: Array=Lights._canopy_sections(triangles,PackedFloat64Array([-.25,0,.25]))
 check("canopy station bounds include both endpoints and reject outside triangles",sections[0].segments.size()==1 and sections[1].segments.size()==2 and sections[2].segments.size()==1 and sections[1].lo==0 and sections[1].hi==1)
 check("canopy sections preserve triangle and edge order",sections[1].segments[0]==PackedVector3Array([Vector3(1,1,0),Vector3(-1,1,0)]) and sections[1].segments[1]==PackedVector3Array([Vector3(-1,0,0),Vector3(-1,0,0)]))
 sections[0].segments.clear()
 check("station workspaces are independent and leave source geometry unchanged",sections[1].segments.size()==2 and var_to_bytes(triangles)==before)
 var boundary: float=Vector3(0,0,.1).z
 var narrow:=PackedVector3Array([Vector3(0,0,boundary),Vector3(1,1,.2),Vector3(-1,1,.2)])
 var narrow_sections: Array=Lights._canopy_sections(narrow,PackedFloat64Array([boundary-1e-10,boundary,boundary+1e-10]))
 check("canopy binary bounds retain sub-float32 station precision",narrow_sections[0].segments.is_empty() and narrow_sections[1].segments.size()==1 and narrow_sections[2].segments.size()==1)
 var invalid:=PackedVector3Array([Vector3(0,0,NAN),Vector3(1,1,-1),Vector3(-1,-1,1)])
 var fallback: Array=Lights._canopy_sections(invalid,PackedFloat64Array([-.25,0,.25]))
 var fallback_ok:=true
 for section: Dictionary in fallback: fallback_ok=fallback_ok and section.segments.size()==1 and section.segments[0].size()==3
 check("non-finite triangle coordinates retain the exhaustive edge path",fallback_ok)
