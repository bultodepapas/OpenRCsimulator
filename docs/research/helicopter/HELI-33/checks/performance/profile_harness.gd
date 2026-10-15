# HELI-33: warm native CPU timings, not a GPU or release performance acceptance.
extends SceneTree
const Session=preload("res://sim/helicopter_flight_session.gd")
const Field=preload("res://data/field_loader.gd")
const CollisionSetup=preload("res://scenery/collision_setup.gd")
const Detector=preload("res://physics/rotorcraft/impact_detector.gd")
func _initialize() -> void: run.call_deferred()
func summary(values: Array) -> Dictionary:
 var sorted: Array=values.duplicate(); sorted.sort()
 return {p50_us=sorted[int(sorted.size()*.5)],p95_us=sorted[int(sorted.size()*.95)],p99_us=sorted[int(sorted.size()*.99)],max_us=sorted.back(),raw_us=values}
func run() -> void:
 var out: String="user://heli-crash-profile.json"
 for arg: String in OS.get_cmdline_user_args():
  if arg.begins_with("--out="): out=arg.trim_prefix("--out=")
 var results: Array=[]
 var ok: bool=true
 var field: Dictionary=Field.load_from(Field.DEFAULT_PATH).field
 var world: Dictionary=CollisionSetup.build(field)
 for mode: String in ["ground","airborne"]:
  for obstacles: bool in [false,true]:
   var s=Session.new(); s.physics_enabled=false; s.input_enabled=false; root.add_child(s)
   ok=s.setup() and s.set_field(field) and s.set_start_choice(mode) and s.set_collision_world(world.world if obstacles else {}) and s.reset() and ok
   var ticks: Array=[]
   var detector: Array=[]
   for tick: int in 600:
    var began: int=Time.get_ticks_usec()
    s.sim.step()
    var elapsed: int=Time.get_ticks_usec()-began
    if not s.is_flyable(): ok=false; break
    began=Time.get_ticks_usec()
    var detected: Dictionary=Detector.evaluate(s.sim.previous,s.sim.state,s.sim.continuous,s.aircraft.context,s.aircraft.skids,s.ground_surfaces,s.shaft_phase,s._collision_world,s._impact_geometry)
    var detector_elapsed: int=Time.get_ticks_usec()-began
    ok=ok and detected.ok and detected.impact.is_empty()
    if tick>=100: ticks.append(elapsed); detector.append(detector_elapsed)
   var row: Dictionary={mode=mode,obstacles=obstacles,tick=summary(ticks),detector=summary(detector)}
   results.append(row)
   print("HELI-33 PROFILE ",mode," obstacles=",obstacles," tick p50/p95=",row.tick.p50_us,"/",row.tick.p95_us," detector p50/p95=",row.detector.p50_us,"/",row.detector.p95_us)
   s.free()
 var file=FileAccess.open(out,FileAccess.WRITE)
 file.store_string(JSON.stringify({ok=ok,warmup_ticks=100,sample_ticks=500,cases=results},"\t",true,true)); file.close()
 quit(0 if ok else 1)
