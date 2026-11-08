extends SceneTree
const Session=preload("res://sim/helicopter_flight_session.gd")
const Activity=preload("res://helicopter_main.gd")
const Electronics=preload("res://physics/rotorcraft/electronics.gd")
const Field=preload("res://data/field_loader.gd")
const OUT="C:/DEVELOPMENT/OpenRCsimulator/tmp/audit4-20261107-heli-mode"

func _initialize() -> void:
 Engine.physics_ticks_per_second=240
 _run.call_deferred()

func _controls(session: Node, mode: String) -> Dictionary:
 var state: PackedFloat64Array=session.sim.state.duplicate()
 state.append_array(session.sim.continuous.slice(0,6))
 var c: Dictionary=session.commands
 return Electronics.fast_evaluate(session.aircraft.context.electronics_model,state,PackedFloat64Array([-c.pitch,c.roll,c.yaw,2.0*c.throttle-1.0]),mode,session.trainer_enabled,session._trim)

func _apply_input(session: Node,raw: Dictionary,sign_value: float,count: int,inputs: Array,hashes: Array) -> bool:
 raw.throttle=sign_value
 for i: int in count:
  session._physics_process(session.sim.dt())
  var before: int=session.sim.tick
  session.sim.step()
  if not session.is_flyable() or session.sim.tick!=before+1: return false
  inputs.append(session.sim.inputs.duplicate())
  hashes.append(var_to_bytes([session.sim.state,session.sim.continuous,session.sim.aux,session.sim.inputs,session.shaft_phase,session.flight_mode]).hex_encode().sha256_text())
 return true

func _case(session: Node,flight: Node) -> Dictionary:
 var raw: Dictionary={roll=0.0,pitch=0.0,yaw=0.0,throttle=0.0}
 session.read_raw=func() -> Dictionary: return raw.duplicate()
 var inputs: Array=[]
 var hashes: Array=[]
 var ok: bool=_apply_input(session,raw,1.0,372,inputs,hashes)
 raw.throttle=0.0
 var preview_from: Dictionary=_controls(session,"normal")
 var preview_to: Dictionary=_controls(session,"idle_up")
 flight.controller_action("helicopter_mode")
 var first: Dictionary={tick=session.sim.tick,stick=session.commands.throttle,mode=session.flight_mode,pending=session.pending_mode,message=session.pause_reason,from_deg=rad_to_deg(preview_from.collective_75_rad),to_deg=rad_to_deg(preview_to.collective_75_rad)}
 ok=_apply_input(session,raw,-1.0,460,inputs,hashes) and ok
 raw.throttle=0.0
 var actual_from: Dictionary=_controls(session,"normal")
 var actual_to: Dictionary=_controls(session,"idle_up")
 flight.controller_action("helicopter_mode")
 var second: Dictionary={tick=session.sim.tick,stick=session.commands.throttle,mode=session.flight_mode,pending=session.pending_mode,message=session.pause_reason,from_deg=rad_to_deg(actual_from.collective_75_rad),to_deg=rad_to_deg(actual_to.collective_75_rad)}
 ok=ok and first.mode=="normal" and first.pending=="idle_up" and second.mode=="idle_up" and second.pending.is_empty()
 return {ok=ok,first=first,second=second,inputs=inputs,hashes=hashes}

func _run() -> void:
 var session=Session.new()
 session.physics_enabled=false
 session.input_enabled=true
 root.add_child(session)
 var flight=Activity.new()
 flight.session=session
 var ready: bool=session.setup() and session.set_field(Field.load_from().field) and session.set_start_choice("ground") and session.reset()
 if not ready: printerr("setup failed: ",session.start_error); flight.free(); session.free(); quit(1); return
 var initial: Dictionary=session.checkpoint()
 var a: Dictionary=_case(session,flight)
 var replayed: bool=session.restore_checkpoint(initial).get("ok",false)
 session.resume()
 var b: Dictionary=_case(session,flight)
 replayed=replayed and var_to_bytes(a)==var_to_bytes(b)
 var tape: FileAccess=FileAccess.open(OUT.path_join("baseline.tape"),FileAccess.WRITE)
 tape.store_var({format="helicopter-mode input tape v1",initial=initial,inputs=a.inputs,hashes=a.hashes,first_tick=a.first.tick,second_tick=a.second.tick})
 tape.close()
 var report: Dictionary={format="helicopter-mode stale confirmation baseline v1",ok=ready and a.ok and replayed,exact_replay=replayed,engine=Engine.get_version_info().string,session_sha256=FileAccess.get_sha256("res://sim/helicopter_flight_session.gd"),electronics_sha256=FileAccess.get_sha256("res://physics/rotorcraft/electronics.gd"),ticks=a.inputs.size(),first=a.first,second=a.second,tape_sha256=FileAccess.get_sha256(OUT.path_join("baseline.tape"))}
 var file: FileAccess=FileAccess.open(OUT.path_join("baseline.json"),FileAccess.WRITE)
 file.store_string(JSON.stringify(report,"\t",true,true)); file.close()
 print("H04 BASELINE stale accepted=",a.ok," exact replay=",replayed," first=",a.first," second=",a.second)
 flight.free(); session.free(); quit(0 if report.ok else 1)
