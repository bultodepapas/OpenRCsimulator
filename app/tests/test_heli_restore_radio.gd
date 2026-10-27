# Helicopter checkpoint restore leaves a stick-rate gamepad in the same state as reset():
# the integrated collective matches the restored commands, and an externally selected
# controller must show fresh neutral evidence before the restored flight continues.
extends SceneTree
const Session=preload("res://sim/helicopter_flight_session.gd")
const Profile=preload("res://input/controller_profile.gd")
const PAD: int=990
const THROTTLE_AXIS: int=1 # Gamepad Mode 2 collective, inverted: -1 is full up.
var checks: int=0
var failures: int=0
var stick: PackedFloat64Array=PackedFloat64Array([0,0,0,0,0,0,0,0,0,0])

func check(label: String,ok: bool,detail: String="") -> void:
 checks+=1
 if not ok: failures+=1; print("FAIL ",label,(" — "+detail) if not detail.is_empty() else "")

func _initialize() -> void: _run.call_deferred()

func make_session(external: bool) -> Node:
 var session: Node=Session.new()
 session.physics_enabled=false
 session.external_controller_selection=external
 session.profiles_path="user://heli-restore-radio-no-profile.cfg"
 session.read_axis=func(_id: int,axis: int) -> float: return stick[axis]
 session.read_button=func(_id: int,_button: int) -> bool: return false
 session.device_info=func(_id: int) -> Dictionary: return {name="restore test gamepad",known=true}
 root.add_child(session)
 check("session setup and hover reset",session.setup() and session.reset())
 if external:
  check("external stick-rate gamepad selected",session.apply_controller_selection(PAD,{name="restore test gamepad",known=true},Profile.defaults("gamepad","mode2")))
 else:
  session._on_joy_connection_changed(PAD,true)
 check("stick-rate gamepad connected",session.radio.connected and session.radio.is_rate_throttle() and session.radio.throttle_position()==session.commands.throttle)
 for axis: int in 4: session.radio.on_motion(PAD,axis,0.0)
 return session

# Paused polls collect neutral-dwell evidence without integrating the collective.
func settle(session: Node) -> void:
 for i: int in 60: session._physics_process(session.sim.dt())

func fly(session: Node,ticks: int) -> bool:
 for i: int in ticks:
  session._physics_process(session.sim.dt())
  session.sim.step()
  if not session.is_flyable(): print("FAULT ",session.pause_reason); return false
 return true

func exercise(external: bool) -> void:
 var tag: String="external" if external else "built-in"
 stick.fill(0.0)
 var session: Node=make_session(external)
 settle(session)
 check(tag+": neutral gamepad can resume",session.radio.armed and session.can_resume())
 session.resume()
 check(tag+": live gamepad hover advances",not session.sim.paused and fly(session,24))
 var saved: Dictionary=session.checkpoint()
 check(tag+": checkpoint emitted",not saved.is_empty())
 if saved.is_empty(): session.free(); return
 var hover: float=saved.commands.throttle
 check(tag+": reference tail advances",fly(session,120))
 var endpoint: PackedFloat64Array=session.sim.state.duplicate()
 var rotor_endpoint: PackedFloat64Array=session.sim.continuous.duplicate()
 stick[THROTTLE_AXIS]=-1.0
 check(tag+": collective raised through the stick-rate integrator",fly(session,48))
 stick[THROTTLE_AXIS]=0.0
 check(tag+": centred stick holds the raised collective",fly(session,1))
 var moved: float=session.radio.throttle_position()
 check(tag+": integrated collective moved away from the checkpoint",absf(moved-hover)>.05,"%.17f vs %.17f"%[moved,hover])
 var bad: Dictionary=saved.duplicate(true)
 bad.aircraft_sha256="foreign"
 var armed_before: bool=session.radio.armed
 var paused_before: bool=session.sim.paused
 var reason_before: String=session.pause_reason
 check(tag+": refused restore leaves radio and session unchanged",not session.restore_checkpoint(bad).ok and session.radio.throttle_position()==moved and session.radio.armed==armed_before and session.sim.paused==paused_before and session.pause_reason==reason_before)
 check(tag+": checkpoint restores paused",session.restore_checkpoint(saved).ok and session.sim.paused)
 check(tag+": restore resynchronizes the stick-rate collective",session.radio.throttle_position()==hover,"%.17f vs %.17f"%[session.radio.throttle_position(),hover])
 if external:
  check(tag+": restore requires fresh neutral evidence",not session.radio.armed and not session.can_resume())
  check(tag+": restore explains the neutral requirement",session.pause_reason.begins_with("Checkpoint restored."),session.pause_reason)
  settle(session)
  check(tag+": neutral evidence keeps the restored collective",session.radio.armed and session.radio.throttle_position()==hover)
 else:
  check(tag+": built-in restore keeps radio readiness",session.radio.armed and session.pause_reason.is_empty())
 check(tag+": restored flight can resume",session.can_resume())
 session.resume()
 session._physics_process(session.sim.dt())
 check(tag+": first unpaused tick commands the restored collective",session.commands.throttle==hover and session.sim.inputs[3]==hover,"%.17f vs %.17f"%[session.commands.throttle,hover])
 session.sim.step()
 check(tag+": restored tail advances",session.is_flyable() and fly(session,119))
 check(tag+": restored live-gamepad tail replays byte-identically",endpoint.to_byte_array()==session.sim.state.to_byte_array() and rotor_endpoint.to_byte_array()==session.sim.continuous.to_byte_array())
 session.free()

func _run() -> void:
 exercise(false)
 exercise(true)
 print("HELI restore radio: %d checks, %d failed"%[checks,failures])
 quit(1 if failures>0 else 0)
