# HELI-33 native production-route aftermath review. Requires a real renderer.
extends SceneTree
const Main=preload("res://helicopter_main.gd")
const Fixtures=preload("fixtures.gd")
const Config=preload("res://environment/time_of_day_config.gd")
const Frames=preload("res://render/frames.gd")
var directory: String="user://heli-crashes"
var quick: bool=false
func _initialize() -> void: run.call_deferred()
func run() -> void:
 for arg: String in OS.get_cmdline_user_args():
  if arg.begins_with("--out-dir="): directory=arg.trim_prefix("--out-dir=")
  if arg=="--quick": quick=true
 directory=ProjectSettings.globalize_path(directory)
 DirAccess.make_dir_recursive_absolute(directory)
 var manifest: Array=[]
 var ok: bool=true
 for hour: int in ([12] if quick else [12,0]):
  var flight=Main.new()
  flight.external_controller_selection=true
  flight.interactive_start=true
  flight.lighting_config=Config.defaults()
  flight.lighting_config.mode="astronomical"
  flight.lighting_config.local_seconds=hour*3600
  flight.night_options={field_lighting="airfield",campfire=false}
  flight.set_user_args(PackedStringArray(["--start=airborne","--view=pilot"]))
  root.add_child(flight)
  flight.set_process(false)
  flight.session.physics_enabled=false
  flight.session.input_enabled=false
  for scenario: String in (["nose","fence"] if quick else ["main","tail","hard","nose","fence","severe"]):
   var hit: bool=Fixtures.trigger(flight.session,scenario)
   print("FIXTURE ",hour," ",scenario," hit=",hit," reason=",flight.session.pause_reason)
   if not hit: ok=false; continue
   flight._hud_layer.visible=false
   flight._present(0.0,1.0)
   if scenario=="severe" and int(flight._crash_presentation.wreck.severity.get("class",0))!=4:
    ok=false; print("FAIL severe fixture did not exercise C4 breakup")
   print("CAPTURE_START ",scenario," report=",flight.session.crash.body.slice(0,3)," core=",flight._crash_presentation.focus_position())
   if quick:
    var core: RigidBody3D=flight._crash_presentation.wreck._core_body
    print("SERVER_INITIAL ",scenario," ",PhysicsServer3D.body_get_state(core.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM)," shape=",flight._crash_presentation.wreck._shape_nodes[0].shape.size)
   var accepted: PackedByteArray=var_to_bytes([flight.session.sim.state,flight.session.sim.continuous,flight.session.sim.tick])
   var clock_s: float=0.0
   for at: float in [.04,.24,.8,2.0]:
    while clock_s<at:
     await physics_frame
     flight._present(1.0/Engine.physics_ticks_per_second,1.0)
     if quick and clock_s<.013:
      var core: RigidBody3D=flight._crash_presentation.wreck._core_body
      print("SERVER_STEP ",scenario," ",clock_s," node=",core.global_position," server=",PhysicsServer3D.body_get_state(core.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM))
     clock_s+=1.0/Engine.physics_ticks_per_second
    var focus: Vector3=flight._crash_presentation.focus_position()
    if focus.distance_to(Frames.ned_to_render(flight.session.crash.body.slice(0,3)))>2.0+40.0*clock_s:
     ok=false; print("FAIL wreck teleported ",scenario," at=",clock_s," focus=",focus)
    if scenario=="fence": print("CAPTURE_FENCE ",at," ",focus)
    var anchor: Vector3=Frames.ned_to_render(flight.session.crash.ground_point_world_ned)
    if scenario=="fence": anchor=focus-Vector3.UP*.12
    flight._camera.position=anchor+Vector3(2.2,1.7,-2.5)
    flight._camera.look_at(anchor+Vector3(0,.12,0))
    flight._camera.fov=48.0
    await RenderingServer.frame_post_draw
    await RenderingServer.frame_post_draw
    var filename: String="%02d-%s-%04d.png"%[hour,scenario,int(at*1000)]
    var error: Error=root.get_texture().get_image().save_png(directory+"/"+filename)
    manifest.append({image=filename,at_s=clock_s,impact=flight.session.crash,stats=flight._crash_presentation.stats(),focus=[focus.x,focus.y,focus.z],error=error})
    if error!=OK: ok=false
    if at==.24:
     var key:=InputEventKey.new()
     key.physical_keycode=KEY_P; key.pressed=true
     flight._unhandled_input(key)
     flight._present(0.0,1.0)
     await physics_frame
     var frozen: Array=[]
     for body: RigidBody3D in flight._crash_presentation.wreck._bodies:
      frozen.append(body.global_transform)
     var age: float=flight._crash_presentation._age
     for pause_frame: int in 8:
      await physics_frame
      flight._present(1.0/Engine.physics_ticks_per_second,1.0)
     for index: int in frozen.size():
      if not flight._crash_presentation.wreck._bodies[index].global_transform.is_equal_approx(frozen[index]):
       ok=false; print("FAIL paused wreck moved")
     if flight._crash_presentation._age!=age or not flight._crash_presentation.stats().wreck.paused:
      ok=false; print("FAIL P did not freeze aftermath")
     flight._unhandled_input(key)
     flight._present(0.0,1.0)
     if flight._crash_presentation.stats().wreck.paused:
      ok=false; print("FAIL P did not resume aftermath")
   if var_to_bytes([flight.session.sim.state,flight.session.sim.continuous,flight.session.sim.tick])!=accepted:
    ok=false; print("FAIL wreck modified accepted flight state")
   if flight._airplane.root.visible or flight._rotors.visible or flight._night_kit.visible:
    ok=false; print("FAIL original flight visuals still visible")
   flight.session.reset()
   flight._present(0.0,1.0)
   if flight._crash_presentation.active or not flight._airplane.root.visible or not flight._rotors.visible:
    ok=false; print("FAIL restart did not restore flight visuals")
  flight.free()
 var file=FileAccess.open(directory+"/captures.json",FileAccess.WRITE)
 file.store_string(JSON.stringify({ok=ok,cases=manifest},"\t",true,true)); file.close()
 print("HELI-33 CAPTURES ",ok)
 quit(0 if ok else 1)
