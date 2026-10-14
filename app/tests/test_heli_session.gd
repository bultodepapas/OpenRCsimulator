# HELI-16: actual generated preset, common Simulation owner and player controls.
extends SceneTree
const Session=preload("res://sim/helicopter_flight_session.gd")
const Data=preload("res://physics/rotorcraft_data.gd")
const M=preload("res://physics/math3d.gd")
const Recorder=preload("res://sim/rotorcraft_recorder.gd")
const RcInput=preload("res://input/rc_input.gd")
var checks: int=0
var failures: int=0
var session: Node
func check(label: String,ok: bool) -> void:
 checks+=1
 if not ok: failures+=1; print("FAIL ",label)
func advance(ticks: int) -> bool:
 for i: int in ticks:
  session.sim.step()
  if not session.is_flyable(): print("FAULT ",session.pause_reason); return false
 return true
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
 var path: String="res://data/aircraft/xcell_60_research.json"
 var raw: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
 check("actual generated v2 preset prepares",Data.validate(raw).ok)
 var pad: RefCounted=RcInput.new()
 pad.connect_device(999,{"name":"test gamepad","known":true})
 check("gamepad can preserve explicit airborne collective",pad.set_rate_throttle_for_start(.54))
 pad.poll(func(_id: int,_axis: int) -> float: return 0.0,1.0/240.0)
 check("centred gamepad preserves hover collective",absf(pad.sticks().throttle-.54)<1e-15)
 check("invalid gamepad start position refused",not pad.set_rate_throttle_for_start(NAN) and not pad.set_rate_throttle_for_start(1.1))
 pad.disconnect_device()
 pad.connect_device(998,{"name":"test radio","known":false})
 check("airborne gamepad initialization cannot bypass radio arming",not pad.set_rate_throttle_for_start(.54) and not pad.armed)
 var bad: Dictionary=raw.duplicate(true)
 bad.main_rotor.rotor_radius_m.unit="cm"
 check("dimension mismatch cannot fly",not Data.validate(bad).ok)
 bad=raw.duplicate(true)
 bad.body.mass_kg.erase("source")
 check("missing quantity evidence cannot fly",not Data.validate(bad).ok)
 bad=raw.duplicate(true)
 bad.skids.spring_n_m.value=1e9
 check("unstable contact stiffness cannot fly",not Data.validate(bad).ok)
 bad=raw.duplicate(true)
 bad.shaft_elements[1].spin_axis_body_frd.value=[0,-1,0]
 check("gyro axis and aerodynamic shaft torque must agree",not Data.validate(bad).ok)
 bad=raw.duplicate(true)
 bad.shaft_elements[1].speed_ratio.value=4.2
 check("aerodynamic and inertial gearing must agree",not Data.validate(bad).ok)
 session=Session.new()
 session.input_enabled=false
 session.physics_enabled=false
 root.add_child(session)
 check("preset loads and full hover trims",session.setup() and session.reset())
 if not session.is_flyable(): print(session.start_error); quit(1); return
 var start: PackedFloat64Array=session.sim.state.duplicate()
 check("30 second actual-session hover remains finite",advance(7200))
 check("hover altitude drift below 2 cm",absf(session.sim.state[2]-start[2])<.02)
 check("hover horizontal drift below 2 cm",absf(session.sim.state[0]-start[0])+absf(session.sim.state[1]-start[1])<.02)
 for axis: int in 3:
  session.reset()
  session.sim.inputs[axis]=.3
  check("positive pilot axis %d stays finite"%axis,advance(120))
  check("positive pilot axis %d produces positive body rate"%axis,session.sim.state[10+axis]>0.01)
 session.reset()
 var hover_throttle: float=session.commands.throttle
 session.commands.throttle=hover_throttle+.04
 session.sim.inputs[3]=session.commands.throttle
 check("collective increase stays finite",advance(480))
 check("collective increase climbs",session.sim.state[2]<start[2]-.1)
 session.reset()
 var landing_ok: bool=true
 var descent_integral: float=0.0
 # Test pilot reduces collective as GE builds; the runtime has no altitude/landing assist.
 for tick: int in 7200:
  var down_target: float=clampf((-session.sim.state[2]-.10)*.3,0.0,.3)
  var error: float=down_target-session.sim.state[5]
  descent_integral=clampf(descent_integral+.03*error*session.sim.dt(),-.1,.1)
  session.commands.throttle=clampf(hover_throttle-.07*error-descent_integral,.25,.75)
  session.sim.inputs[3]=session.commands.throttle
  if not advance(1): landing_ok=false; break
 check("gentle descent with pilot GE compensation and skid landing stays finite",landing_ok)
 check("patins support CG above soil",-session.sim.state[2]>.08 and -session.sim.state[2]<.15)
 check("landing vertical speed settles",absf(session.sim.state[5])<.08)
 session.reset()
 session.sim.state[2]=-.15
 var tilted: PackedFloat64Array=M.q_from_euler(0,0,.6)
 for i: int in 4: session.sim.state[6+i]=tilted[i]
 session.sim.step()
 check("actual tilted rotor ground strike pauses flight",not session.crash.is_empty() and session.sim.paused)
 check("restart recovers a rotor strike",session.reset() and session.is_flyable())
 session.reset()
 var saved: Dictionary=session.checkpoint()
 check("full checkpoint emitted",not saved.is_empty() and not saved.simulation.is_empty())
 check("advance before replay",advance(240))
 var endpoint: PackedFloat64Array=session.sim.state.duplicate()
 var extra: PackedFloat64Array=session.sim.continuous.duplicate()
 check("compatible checkpoint restores",session.restore_checkpoint(saved).ok)
 check("advance after replay",advance(240))
 check("restored body and continuous replay is byte-identical",endpoint.to_byte_array()==session.sim.state.to_byte_array() and extra.to_byte_array()==session.sim.continuous.to_byte_array())
 var before: Dictionary=session.checkpoint()
 bad=saved.duplicate(true)
 bad.aircraft_sha256="incorrect"
 check("foreign checkpoint refused atomically",not session.restore_checkpoint(bad).ok and var_to_bytes(before)==var_to_bytes(session.checkpoint()))
 session.reset()
 session.sim.inputs[0]=NAN
 session.sim.step()
 check("bad input freezes last valid state",not session.sim.fault_reason.is_empty() and session.sim.paused)
 check("explicit reset recovers numerical fault",session.reset() and session.is_flyable())
 session.radio.connect_device(997,{"name":"test gamepad","known":true})
 check("radio calibration pauses the helicopter",session.start_calibration() and session.sim.paused)
 check("restart exits calibration before resuming hover",session.reset() and session.calibration==null and not session.sim.paused)
 session.radio.disconnect_device()
 var recorder: RefCounted=Recorder.new(session.sim)
 recorder.start(session.trace_meta())
 check("rotorcraft recorder follows fixed ticks",advance(3) and recorder.trace.row_count()==4)
 var trace_path: String="user://heli-session-test.csv"
 check("complete rotorcraft CSV saves",recorder.stop(trace_path)==OK)
 var lines: PackedStringArray=FileAccess.get_file_as_string(trace_path).split("\n",false)
 var row: PackedStringArray=lines[-1].split(",")
 check("CSV contains all body, rotor, load and input columns",row.size()==Recorder.FlightRows.COLUMNS.size())
 check("CSV numeric fields round-trip float64",float(row[3])==session.sim.state[0] and float(row[16])==session.sim.continuous[0])
 check("CSV identifies load sampling time separately",absf(float(row[2])-(session.sim.tick-1)*session.sim.dt())<1e-15)
 recorder.detach()
 DirAccess.remove_absolute(ProjectSettings.globalize_path(trace_path))
 print("HELI-16 generated preset/session: %d checks, %d failed"%[checks,failures])
 quit(1 if failures else 0)
