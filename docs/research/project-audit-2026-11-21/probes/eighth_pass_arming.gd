extends SceneTree
const Session = preload("res://sim/helicopter_flight_session.gd")
const Electronics = preload("res://physics/rotorcraft/electronics.gd")
const Lifecycle = preload("res://physics/rotorcraft/lifecycle.gd")
const M = preload("res://physics/math3d.gd")
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
 Engine.physics_ticks_per_second = 240
 _run.call_deferred()

func check(label: String, ok: bool) -> void:
 checks += 1
 if not ok:
  failures += 1
  print("FAIL ",label)

func frame(s: Node) -> PackedFloat64Array:
 var result: PackedFloat64Array=s.sim.state.duplicate()
 result.append_array(s.sim.continuous.slice(0,6))
 return result

func input(s: Node, throttle: float, roll: float=0.0, pitch: float=0.0) -> void:
 s.commands={roll=roll,pitch=pitch,yaw=0.0,throttle=throttle}
 s.sim.inputs=PackedFloat64Array([roll,pitch,0.0,throttle])

func controls(s: Node, trainer: bool) -> Dictionary:
 var c: Dictionary=s.commands
 return Electronics.fast_evaluate(s.aircraft.context.electronics_model,frame(s),PackedFloat64Array([-c.pitch,c.roll,c.yaw,2.0*c.throttle-1.0]),s.flight_mode,trainer,s._trim)

func _step_one(s: Node) -> bool:
 var previous: int=s.sim.tick
 s.sim.step()
 return s.is_flyable() and s.sim.tick==previous+1 and s.sim.fault_reason.is_empty() and s.crash.is_empty()

func _tape(s: Node, label: String, positive: Dictionary, negative: Dictionary, roll: float, pitch: float, ticks: int, take_positive: bool) -> void:
 check(label+" reset",s.reset() and s.is_flyable())
 var initial: Array=Array(frame(s))
 var hover: float=float(s.commands.throttle)
 # This is the session state changed by helicopter_main's trainer action.
 s.trainer_enabled=false
 input(s,hover,roll,pitch)
 var completed: bool=true
 for i: int in ticks:
  if not _step_one(s):
   completed=false
   break
 check(label+" direct-cyclic input tape accepted",completed and s.sim.tick==ticks)
 if not completed: return
 var target: Dictionary=positive if take_positive else negative
 input(s,float(target.collective))
 s.trainer_enabled=true
 var assisted: Dictionary=controls(s,true)
 var direct: Dictionary=controls(s,false)
 var stage: Dictionary=s.telemetry()
 var body_before: PackedFloat64Array=s.sim.state.duplicate()
 var combined_before: Array=Array(frame(s))
 var premix: float=rad_to_deg(s.collective_pitch())
 var postmix: float=rad_to_deg(assisted.collective_75_rad) if assisted.ok else NAN
 check(label+" source guard and actual flight stage disagree",assisted.ok and stage.ok and direct.ok \
  and absf(premix)<1.0 and absf(postmix)>1.0 and absf(rad_to_deg(stage.controls.collective_75_rad)-postmix)<1e-9)
 check(label+" direct control has no collective discrepancy",direct.ok and absf(rad_to_deg(direct.collective_75_rad)-premix)<1e-9)
 var disarm: bool=s.toggle_motor_arm()
 var rearm: bool=s.toggle_motor_arm()
 var armed_in_hold: bool=s.power.armed and s.zero_drive_hold
 var released: bool=s.set_drive_hold(false)
 var tick_before: int=s.sim.tick
 var accepted: bool=_step_one(s)
 check(label+" guard accepts and flight continues",disarm and rearm and armed_in_hold and released and accepted)
 print("TAPE ",JSON.stringify({"case":label,"aircraft":s.aircraft.id,"aircraft_sha256":s.aircraft.input_identity.sha256,
  "backend":s.stage_backend_identity(),"dt_s":s.sim.dt(),"start_altitude_m":100.0,
  "initial_state19":initial,"input_tape":{"trainer":false,"roll":roll,"pitch":pitch,"yaw":0.0,"throttle":hover,"ticks":ticks},
  "next_command":{"trainer":true,"roll":0.0,"pitch":0.0,"yaw":0.0,"throttle":float(target.collective)},
  "pre_action_state19":combined_before,"euler_yaw_pitch_roll":Array(M.q_to_euler(body_before.slice(6,10))),
  "guard_limit_deg":rad_to_deg(Lifecycle.PICKUP_TOLERANCE_RAD),"premix_deg":premix,"postmix_deg":postmix,
  "postmix_from_stage_deg":rad_to_deg(stage.controls.collective_75_rad),"direct_control_deg":rad_to_deg(direct.collective_75_rad),
  "servo_positions":Array(assisted.swash_servo_targets),"servo_commands":Array(assisted.swash_servo_commands),
  "servo_limited":assisted.servo_travel_limited,"disarm_return":disarm,"rearm_return":rearm,"armed_in_hold":armed_in_hold,"hold_release_return":released,
  "tick_before":tick_before,"tick_after":s.sim.tick,"accepted":accepted,"state_after19":Array(frame(s)),"fault":s.sim.fault_reason,"crash":s.crash,"pause_reason":s.pause_reason}))

func _spaced_tape(s: Node, positive: Dictionary) -> void:
 check("spaced reset",s.reset() and s.is_flyable())
 var initial: Array=Array(frame(s))
 var hover: float=float(s.commands.throttle)
 s.trainer_enabled=false
 input(s,hover,1.0,-1.0)
 var accepted: bool=true
 for i: int in 181:
  if not _step_one(s): accepted=false; break
 check("spaced direct-cyclic tape accepted",accepted and s.sim.tick==181)
 input(s,float(positive.collective))
 s.trainer_enabled=true
 var disarm: bool=s.toggle_motor_arm()
 for i: int in 6:
  if not _step_one(s): accepted=false; break
 check("spaced disarm and delay accepted",disarm and accepted and s.sim.tick==187)
 var before: Array=Array(frame(s))
 var stage: Dictionary=s.telemetry()
 var direct: Dictionary=controls(s,false)
 var premix: float=rad_to_deg(s.collective_pitch())
 var postmix: float=rad_to_deg(stage.controls.collective_75_rad) if stage.ok else NAN
 check("spaced rearm still crosses postmix threshold",stage.ok and direct.ok and absf(premix)<1.0 \
  and absf(postmix)>1.0 and absf(rad_to_deg(direct.collective_75_rad)-premix)<1e-9)
 var arm: bool=s.toggle_motor_arm()
 var armed_in_hold: bool=s.power.armed and s.zero_drive_hold
 for i: int in 6:
  if not _step_one(s): accepted=false; break
 check("spaced rearm and delay accepted",arm and armed_in_hold and accepted and s.sim.tick==193)
 var release: bool=s.set_drive_hold(false)
 for i: int in 6:
  if not _step_one(s): accepted=false; break
 check("spaced release and delay accepted",release and accepted and s.sim.tick==199)
 print("SPACED_TAPE ",JSON.stringify({"case":"six_tick_gaps_181", "aircraft":s.aircraft.id,
  "aircraft_sha256":s.aircraft.input_identity.sha256,"backend":s.stage_backend_identity(),"dt_s":s.sim.dt(),
  "start_altitude_m":100.0,"initial_state19":initial,"input_tape":{"trainer":false,"roll":1.0,"pitch":-1.0,"yaw":0.0,"throttle":hover,"ticks":181},
  "next_command":{"trainer":true,"roll":0.0,"pitch":0.0,"yaw":0.0,"throttle":float(positive.collective)},
  "pre_rearm_state19":before,"pre_rearm_tick":187,"delay_ticks":6,"guard_limit_deg":rad_to_deg(Lifecycle.PICKUP_TOLERANCE_RAD),
  "premix_deg":premix,"postmix_from_stage_deg":postmix,"direct_control_deg":rad_to_deg(direct.collective_75_rad),
  "servo_positions":Array(stage.controls.swash_servo_targets),"servo_commands":Array(stage.controls.swash_servo_commands),
  "disarm_return":disarm,"rearm_return":arm,"armed_in_hold":armed_in_hold,"hold_release_return":release,
  "tick_after":s.sim.tick,"accepted":accepted,"state_after19":Array(frame(s)),"fault":s.sim.fault_reason,"crash":s.crash}))

func _run() -> void:
 var s: Node=Session.new()
 s.physics_enabled=false
 s.input_enabled=false
 root.add_child(s)
 check("setup stock X-Cell",s.setup())
 s.set_start_altitude(100.0)
 check("prepare airborne reference start",s.reset() and s.is_flyable())
 if failures>0:
  print("SETUP ERROR ",s.start_error)
  s.free()
  quit(1)
  return
 var model: Dictionary=s.aircraft.context.electronics_model
 var positive: Dictionary=Lifecycle.collective_for_pitch(model,"normal",deg_to_rad(0.9))
 var negative: Dictionary=Lifecycle.collective_for_pitch(model,"normal",deg_to_rad(-0.9))
 check("both pitch requests invert on authored normal curve",positive.ok and negative.ok)
 var disarm: bool=s.toggle_motor_arm()
 input(s,float(positive.collective))
 var stationary: Dictionary=controls(s,true)
 var stationary_pre: float=rad_to_deg(stationary.collective_75_rad)
 var candidate_body: PackedFloat64Array=s.sim.state.duplicate()
 var continuous_before: PackedFloat64Array=s.sim.continuous.duplicate()
 candidate_body[10]=-3.0
 candidate_body[11]=3.0
 var accepted_reset: bool=s.sim.reset(candidate_body)
 check("constructed body accepted by detached simulation reset",accepted_reset and s.sim.continuous.to_byte_array()==continuous_before.to_byte_array() and s.zero_drive_hold and not s.power.armed)
 var assisted: Dictionary=controls(s,true)
 var direct: Dictionary=controls(s,false)
 var stage: Dictionary=s.telemetry()
 var combined_before: Array=Array(frame(s))
 var premix: float=rad_to_deg(s.collective_pitch())
 var postmix: float=rad_to_deg(assisted.collective_75_rad)
 var rearm: bool=s.toggle_motor_arm()
 var armed_in_hold: bool=s.power.armed and s.zero_drive_hold
 var released: bool=s.set_drive_hold(false)
 var before_tick: int=s.sim.tick
 var accepted: bool=_step_one(s)
 check("constructed guard witness",disarm and rearm and armed_in_hold and released and accepted and stage.ok \
  and absf(premix)<1.0 and postmix>1.0 and absf(rad_to_deg(stage.controls.collective_75_rad)-postmix)<1e-9)
 check("matched stationary trainer and high-rate direct controls",stationary.ok and direct.ok \
  and absf(stationary_pre-0.9)<1e-9 and absf(rad_to_deg(direct.collective_75_rad)-0.9)<1e-9)
 print("CONSTRUCTED ",JSON.stringify({"case":"constructed_body_rates","reset_accepted":accepted_reset,"aircraft":s.aircraft.id,"aircraft_sha256":s.aircraft.input_identity.sha256,"backend":s.stage_backend_identity(),
  "dt_s":s.sim.dt(),"pre_action_state19":combined_before,"roll_pitch_yaw_input":[0,0,0],"trainer":true,
  "guard_limit_deg":rad_to_deg(Lifecycle.PICKUP_TOLERANCE_RAD),"premix_deg":premix,"postmix_deg":postmix,"postmix_from_stage_deg":rad_to_deg(stage.controls.collective_75_rad),
  "zero_feedback_deg":stationary_pre,"direct_control_deg":rad_to_deg(direct.collective_75_rad),
  "servo_positions":Array(assisted.swash_servo_targets),"servo_commands":Array(assisted.swash_servo_commands),"servo_limited":assisted.servo_travel_limited,
  "disarm_return":disarm,"rearm_return":rearm,"armed_in_hold":armed_in_hold,"hold_release_return":released,
  "tick_before":before_tick,"tick_after":s.sim.tick,"accepted":accepted,"state_after19":Array(frame(s)),"fault":s.sim.fault_reason,"crash":s.crash}))
 _tape(s,"moderate_bank_67",positive,negative,1.0,-1.0,67,true)
 _tape(s,"large_bank_355",positive,negative,-1.0,1.0,355,false)
 _spaced_tape(s,positive)
 s.free()
 print("R8 final arming observations: %d checks, %d failures"%[checks,failures])
 quit(1 if failures else 0)
