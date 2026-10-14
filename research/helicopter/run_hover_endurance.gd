# HELI-23: actual preset and field, unassisted collective, ten simulated minutes.
extends SceneTree
const Session=preload("res://sim/helicopter_flight_session.gd")
const Field=preload("res://data/field_loader.gd")
const M=preload("res://physics/math3d.gd")
func _initialize() -> void: run.call_deferred()
func run() -> void:
 var session: Node=Session.new()
 session.input_enabled=false
 session.physics_enabled=false
 root.add_child(session)
 var loaded: Dictionary=Field.load_from(Field.DEFAULT_PATH)
 if not loaded.ok or not session.setup() or not session.set_field(loaded.field) or not session.reset():
  printerr("ERROR: endurance startup failed ",session.start_error)
  quit(1)
  return
 var start: PackedFloat64Array=session.sim.state.duplicate()
 var max_drift: float=0.0
 var minimum_omega: float=session.sim.continuous[0]
 var maximum_omega: float=minimum_omega
 var begun: int=Time.get_ticks_usec()
 for tick: int in 144000:
  session.sim.step()
  if not session.is_flyable():
   printerr("ERROR: endurance fault at tick ",session.sim.tick,": ",session.pause_reason)
   quit(1)
   return
  var drift: float=M.norm(M.v3(session.sim.state[0]-start[0],session.sim.state[1]-start[1],session.sim.state[2]-start[2]))
  max_drift=maxf(max_drift,drift)
  minimum_omega=minf(minimum_omega,session.sim.continuous[0])
  maximum_omega=maxf(maximum_omega,session.sim.continuous[0])
  if session.sim.tick%24000==0: print("HELI-23 endurance tick=",session.sim.tick," max_drift_m=",max_drift)
 var result: Dictionary={"format":"openrc-helicopter-endurance v1","ticks":session.sim.tick,"seconds":session.sim.time(),"max_drift_m":max_drift,"minimum_omega_rad_s":minimum_omega,"maximum_omega_rad_s":maximum_omega,"wall_seconds":(Time.get_ticks_usec()-begun)/1e6,"aircraft_sha256":session.aircraft.input_identity.sha256,"ground_surfaces":session.ground_surfaces.size(),"ok":max_drift<.02}
 var output: String="user://helicopter-endurance.json"
 for arg: String in OS.get_cmdline_user_args():
  if arg.begins_with("--out="): output=arg.trim_prefix("--out=")
 var file: FileAccess=FileAccess.open(output,FileAccess.WRITE)
 if file==null:
  printerr("ERROR: cannot save endurance evidence")
  quit(1)
  return
 file.store_string(JSON.stringify(result,"  ",true,true)+"\n")
 print("HELI-23 endurance ",JSON.stringify(result,"",true,true))
 quit(0 if result.ok else 1)
