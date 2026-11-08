extends SceneTree
const Session := preload("res://sim/helicopter_flight_session.gd")
const StepAdapter := preload("res://physics/rotorcraft/simulation_step_adapter.gd")
const Skids := preload("res://physics/rotorcraft/skid_contact.gd")
const Detector := preload("res://physics/rotorcraft/impact_detector.gd")
const Field := preload("res://data/field_loader.gd")
const Data := preload("res://physics/rotorcraft_data.gd")
const M := preload("res://physics/math3d.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
 Engine.physics_ticks_per_second=240
 _run.call_deferred()

func check(label: String, ok: bool, detail: String="") -> void:
 checks+=1
 if not ok:
  failures+=1
  printerr("FAIL ",label," ",detail)

func _session(start: String) -> Node:
 var session=Session.new()
 session.physics_enabled=false
 session.input_enabled=false
 root.add_child(session)
 check("session setup "+start,session.setup() and session.set_field(Field.load_from().field) and session.set_start_choice(start) and session.reset(), session.start_error)
 return session

func _frame(session: Node) -> PackedFloat64Array:
 var frame: PackedFloat64Array=session.sim.state.duplicate()
 frame.append_array(session.sim.continuous)
 return frame

func _loaded(session: Node, state: PackedFloat64Array) -> bool:
 var contact: Dictionary=Skids.evaluate(state.slice(0,13),session.aircraft.skids,session.ground_surfaces,true,state.slice(19) if state.size()==27 else PackedFloat64Array())
 if not contact.ok: return false
 for force: float in contact.normal_forces_n:
  if force>0.0: return true
 return false

func _comparison(session: Node, start: PackedFloat64Array, slope: PackedFloat64Array, tracks: bool, label: String) -> void:
 var f := func(_state: PackedFloat64Array,_time: float) -> PackedFloat64Array: return slope.duplicate()
 var before: PackedByteArray=var_to_bytes([session.sim.state,session.sim.continuous,session.sim.tick])
 var plain: Variant=StepAdapter.step(start,0.0,1.0,f,slope)
 var actual: Variant=session._step_with_heading_tracking(start,0.0,1.0,f,slope)
 if not plain is Dictionary or not actual is Dictionary:
  check(label+" integrates",false)
  return
 var expected: PackedFloat64Array=plain.state.duplicate()
 var loaded: bool=_loaded(session,expected)
 if tracks:
  expected[17]=M.q_to_euler(M.q_normalized(expected.slice(6,10)))[0]
  expected[18]=0.0
 check(label+" respects loaded skid criterion", loaded==tracks if start[13]==0.0 and session.aircraft.context.electronics_model.law==Session.Electronics.TRAINER_LAW else loaded)
 check(label+" preserves every other integrated value and events", actual.state.to_byte_array()==expected.to_byte_array() and actual.events==plain.events)
 check(label+" does not publish trial state", before==var_to_bytes([session.sim.state,session.sim.continuous,session.sim.tick]))

func _located_stop(session: Node) -> void:
 var initial: PackedFloat64Array=_frame(session)
 initial[13]=0.00005
 initial[17]=4.0
 initial[18]=.2
 var f := func(state: PackedFloat64Array,_time: float) -> PackedFloat64Array:
  var slope:=PackedFloat64Array()
  slope.resize(state.size())
  slope[13]=-0.1 if state[13]>0.0 else 0.0
  slope[17]=1.0
  return slope
 var first: PackedFloat64Array=f.call(initial,0.0)
 var raw: Variant=StepAdapter.step(initial,0.0,.004166666666666667,f,first)
 var stopped: Variant=session._step_with_heading_tracking(initial,0.0,.004166666666666667,f,first)
 check("rotating-to-stopped tick locates its rotor stop without projection",raw is Dictionary and stopped is Dictionary and stopped.state[13]==0.0 and stopped.events.size()==1 and stopped.events[0].type=="rotor_stop" and stopped.state.to_byte_array()==raw.state.to_byte_array())
 if stopped is Dictionary:
  var next_first: PackedFloat64Array=f.call(stopped.state,.004166666666666667)
  var following: Variant=session._step_with_heading_tracking(stopped.state,.004166666666666667,.004166666666666667,f,next_first)
  var heading: float=M.q_to_euler(M.q_normalized(stopped.state.slice(6,10)))[0]
  check("following loaded zero-speed tick reconciles controller memory",following is Dictionary and following.state[17]==heading and following.state[18]==0.0)

func _contact_refusal(session: Node) -> void:
 var invalid: PackedFloat64Array=_frame(session)
 invalid[2]=1e308
 var slope:=PackedFloat64Array()
 slope.resize(invalid.size())
 var f := func(_state: PackedFloat64Array,_time: float) -> PackedFloat64Array: return slope.duplicate()
 var raw: Variant=StepAdapter.step(invalid,0.0,.004166666666666667,f,slope)
 var rejected: Variant=session._step_with_heading_tracking(invalid,0.0,.004166666666666667,f,slope)
 check("invalid endpoint contact rejects the tick",raw is Dictionary and rejected is PackedFloat64Array and rejected.is_empty())

func _body_rate_law(session: Node) -> void:
 var body_rate: Dictionary=Data.load_file("res://data/aircraft/hx700_electric_3d_experimental.json")
 check("body-rate research fixture loads",body_rate.ok)
 if not body_rate.ok: return
 var original: Dictionary=session.aircraft
 var original_geometry: Dictionary=session._impact_geometry
 session.aircraft=original.duplicate()
 session.aircraft.context=body_rate.context
 session._impact_geometry=Detector.prepare(body_rate.context,session.aircraft.skids)
 var ground: PackedFloat64Array=_frame(session)
 ground[17]=4.0
 ground[18]=.2
 var slope:=PackedFloat64Array()
 slope.resize(ground.size())
 _comparison(session,ground,slope,false,"separate body-rate law")
 session.aircraft=original
 session._impact_geometry=original_geometry

func _synthetic_boundaries(session: Node) -> void:
 var base: PackedFloat64Array=_frame(session)
 check("ground fixture has normal force",_loaded(session,base))
 for sign_value: float in [-1.0,1.0]:
  var state: PackedFloat64Array=base.duplicate()
  var from: PackedFloat64Array=M.q_from_euler(sign_value*3.10,0.0,0.0)
  var to: PackedFloat64Array=M.q_from_euler(-sign_value*3.10,0.0,0.0)
  var slope:=PackedFloat64Array()
  slope.resize(state.size())
  for axis: int in 4:
   state[6+axis]=from[axis]
   slope[6+axis]=-to[axis]-from[axis] # nearest quaternion crosses the heading wrap
  state[17]=sign_value*10.0
  state[18]=sign_value*.3
  _comparison(session,state,slope,true,"accepted turn across wrap "+str(sign_value))
  slope[13]=1.0
  _comparison(session,state,slope,true,"first zero-to-spooling interval "+str(sign_value))
  state[13]=1.0
  slope[13]=0.0
  _comparison(session,state,slope,false,"rotating rotor on ground "+str(sign_value))
 var air: PackedFloat64Array=base.slice(0,19)
 air[2]=-3.0
 air[17]=2.0
 air[18]=.2
 var zero:=PackedFloat64Array()
 zero.resize(air.size())
 _comparison(session,air,zero,false,"zero-rotor airborne")
 var contact_delta: PackedFloat64Array=zero.duplicate()
 contact_delta[2]=base[2]-air[2]
 _comparison(session,air,contact_delta,true,"airborne-layout recontact")
 var ground_without_bristles: PackedFloat64Array=base.slice(0,19)
 var takeoff:=PackedFloat64Array()
 takeoff.resize(19)
 takeoff[2]=-3.0
 _comparison(session,ground_without_bristles,takeoff,false,"first unloaded liftoff")
 var unweighted: PackedFloat64Array=base.duplicate()
 unweighted[5]=-100.0
 var unloading:=PackedFloat64Array()
 unloading.resize(unweighted.size())
 var contact: Dictionary=Skids.evaluate(unweighted.slice(0,13),session.aircraft.skids,session.ground_surfaces,true,unweighted.slice(19))
 check("penetration without reaction is not treated as support",contact.contact_count>0 and not _loaded(session,unweighted))
 _comparison(session,unweighted,unloading,false,"penetrating unloaded skid")

func _set_yaw(session: Node,value: float) -> void:
 session.commands.yaw=value
 session.sim.inputs[2]=value

func _real_case(sign_value: float) -> void:
 var session: Node=_session("ground")
 var observed: Array=[]
 var notifications: Array=[0]
 session.sim.stepped.connect(func(_tick: int,_time: float,body: PackedFloat64Array,_loads: PackedFloat64Array,_inputs: PackedFloat64Array,_aux: PackedFloat64Array) -> void:
  notifications[0]+=1
  if observed.size()<2:
   observed.append([M.q_to_euler(M.q_normalized(body.slice(6,10)))[0],session.sim.continuous[4],session.sim.continuous[5],session.telemetry().controls.heading_error_rad]))
 session.sim.continuous[5]=sign_value*.2
 _set_yaw(session,sign_value)
 var complete:=true
 for i: int in 1200:
  session.sim.step()
  if not session.is_flyable(): complete=false; break
 check("long held yaw advances on stopped skids "+str(sign_value),complete and session.sim.tick==1200)
 check("accepted signal sees projected heading and integral "+str(sign_value),observed.size()==2 and observed[0][0]==observed[0][1] and observed[0][2]==0.0 and observed[0][3]==0.0)
 check("accepted cache contains projected controller memory "+str(sign_value),session.sim._last_valid_continuous.to_byte_array()==session.sim.continuous.to_byte_array())
 check("metadata identifies law "+str(sign_value),session.trace_meta().get("heading_memory_law")==Session.HEADING_MEMORY_LAW and session.sim.model.identity.get("heading_memory_law")==Session.HEADING_MEMORY_LAW)
 _set_yaw(session,0.0)
 session.sim.step()
 var controls: Dictionary=session.telemetry().controls
 check("centering cancels stale yaw command "+str(sign_value),absf(controls.heading_error_rad)<1e-10 and absf(controls.target_yaw_rate_rad_s)<1e-10 and session.sim.continuous[5]==0.0)
 var saved: Dictionary=session.checkpoint()
 check("candidate checkpoint identifies the law "+str(sign_value),saved.get("heading_memory_law")==Session.HEADING_MEMORY_LAW)
 _set_yaw(session,sign_value)
 for i: int in 24: session.sim.step()
 var endpoint: PackedByteArray=var_to_bytes([session.sim.state,session.sim.continuous,session.shaft_phase])
 var restored: bool=session.restore_checkpoint(saved).get("ok",false)
 _set_yaw(session,sign_value)
 for i: int in 24: session.sim.step()
 check("candidate checkpoint replays exactly "+str(sign_value),restored and endpoint==var_to_bytes([session.sim.state,session.sim.continuous,session.shaft_phase]))
 _set_yaw(session,0.0)
 session.sim.step()
 saved=session.checkpoint()
 var before: PackedByteArray=var_to_bytes([session.sim.tick,session.sim.state,session.sim.continuous,session.shaft_phase])
 var callbacks_before: int=notifications[0]
 var prior: Callable=session.sim.model.block_aux
 session.sim.model.block_aux=func(_c: PackedFloat64Array,_a: PackedFloat64Array) -> PackedFloat64Array: return PackedFloat64Array()
 session.sim.step()
 session.sim.model.block_aux=prior
 check("rejected tick rolls back candidate and emits no step "+str(sign_value),not session.sim.fault_reason.is_empty() and before==var_to_bytes([session.sim.tick,session.sim.state,session.sim.continuous,session.shaft_phase]) and notifications[0]==callbacks_before)
 check("last valid checkpoint restores after rejected tick "+str(sign_value),session.restore_checkpoint(saved).get("ok",false))
 session.resume()
 check("arm and release hold "+str(sign_value),session.toggle_motor_arm() and session.set_drive_hold(false),session.pause_reason)
 var transition_seen:=false
 for i: int in 3200:
  var old_omega: float=session.sim.continuous[0]
  session.sim.step()
  if old_omega==0.0 and session.sim.continuous[0]>0.0:
   transition_seen=true
   var heading: float=M.q_to_euler(M.q_normalized(session.sim.state.slice(6,10)))[0]
   check("first spooling tick tracks accepted heading "+str(sign_value),session.sim.continuous[4]==heading and session.sim.continuous[5]==0.0)
  if not session.is_flyable(): break
 check("spool completes with positive rotor speed "+str(sign_value),transition_seen and session.is_flyable() and session.sim.continuous[0]>1.0)
 var heading_before: float=M.q_to_euler(session.sim.state.slice(6,10))[0]
 session.commands.throttle=.32
 session.sim.inputs[3]=.32
 _set_yaw(session,sign_value)
 for i: int in 960:
  session.sim.step()
  if not session.is_flyable(): break
 var heading_after: float=M.q_to_euler(session.sim.state.slice(6,10))[0]
 var turn: float=wrapf(heading_after-heading_before,-PI,PI)
 check("powered ground turn stays available "+str(sign_value),session.is_flyable() and _loaded(session,_frame(session)) and signf(turn)==sign_value and absf(turn)>.1,"turn="+str(turn))
 _set_yaw(session,0.0)
 session.commands.throttle=.55
 session.sim.inputs[3]=.55
 var before_liftoff: float=session.sim.continuous[4]
 var lifted:=false
 for i: int in 120:
  session.sim.step()
  if not session.is_flyable(): break
  if not _loaded(session,_frame(session)):
   lifted=true
   break
 check("first real liftoff retains rotating-rotor heading memory "+str(sign_value),lifted and session.sim.continuous[0]>0.0 and session.sim.continuous[4]==before_liftoff)
 session.free()

func _airborne_coast() -> void:
 var session: Node=_session("airborne")
 check("airborne coast can be requested",session.set_drive_hold(true))
 var heading: float=session.sim.continuous[4]
 _set_yaw(session,.5)
 for i: int in 120: session.sim.step()
 check("coasting flight preserves manual yaw memory",session.is_flyable() and session.sim.continuous[0]>0.0 and session.sim.continuous[4]>heading+.1 and not _loaded(session,_frame(session)))
 session.free()

func _run() -> void:
 var ground: Node=_session("ground")
 _synthetic_boundaries(ground)
 _body_rate_law(ground)
 _located_stop(ground)
 _contact_refusal(ground)
 ground.free()
 _real_case(1.0)
 _real_case(-1.0)
 _airborne_coast()
 print("HELI H01 stopped-rotor heading: %d checks, %d failures"%[checks,failures])
 quit(1 if failures else 0)
