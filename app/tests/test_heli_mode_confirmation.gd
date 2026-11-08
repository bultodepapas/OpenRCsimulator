extends SceneTree
const Session=preload("res://sim/helicopter_flight_session.gd")
const Activity=preload("res://helicopter_main.gd")
const Electronics=preload("res://physics/rotorcraft/electronics.gd")
const Field=preload("res://data/field_loader.gd")
const RcInput=preload("res://input/rc_input.gd")
const PROMPT="Mode changes pitch %.1f to %.1f deg. Press mode again to apply."
var checks:=0
var failures:=0

func _initialize() -> void:
 Engine.physics_ticks_per_second=240
 _run.call_deferred()

func check(label: String,ok: bool,detail: String="") -> void:
 checks+=1
 if not ok:
  failures+=1
  printerr("FAIL ",label," ",detail)

func session_fixture() -> Node:
 var s=Session.new()
 s.physics_enabled=false
 s.input_enabled=false
 root.add_child(s)
 check("ground session prepared",s.setup() and s.set_field(Field.load_from().field) and s.set_start_choice("ground") and s.reset(),s.start_error)
 return s

func set_inputs(s: Node, throttle: float,roll: float=0.0,pitch: float=0.0,yaw: float=0.0) -> void:
 s.commands={roll=roll,pitch=pitch,yaw=yaw,throttle=throttle}
 s.sim.inputs=PackedFloat64Array([roll,pitch,yaw,throttle])

func predict(s: Node,mode: String,controls: Dictionary={}) -> Dictionary:
 var c: Dictionary=controls if not controls.is_empty() else s.commands
 var state: PackedFloat64Array=s.sim.state.duplicate()
 state.append_array(s.sim.continuous.slice(0,6))
 return Electronics.fast_evaluate(s.aircraft.context.electronics_model,state,PackedFloat64Array([-c.pitch,c.roll,c.yaw,2.0*c.throttle-1.0]),mode,s.trainer_enabled,s._trim)

func message(s: Node,next: String,controls: Dictionary={}) -> String:
 var a: Dictionary=predict(s,s.flight_mode,controls)
 var b: Dictionary=predict(s,next,controls)
 var result: String=tr(PROMPT)%[rad_to_deg(a.collective_75_rad),rad_to_deg(b.collective_75_rad)]
 if a.servo_travel_limited or b.servo_travel_limited:
  result+="\n"+tr("Cyclic forward/right %.1f / %.1f to %.1f / %.1f deg.")%[rad_to_deg(a.cyclic_forward_rad),rad_to_deg(a.cyclic_right_rad),rad_to_deg(b.cyclic_forward_rad),rad_to_deg(b.cyclic_right_rad)]
 return result

func reset_fixture(s: Node) -> void:
 check("reset fixture",s.reset(),s.start_error)

func _stale_and_reverse(s: Node,flight: Node) -> void:
 set_inputs(s,.94166666666666)
 var initial_prompt: String=message(s,"idle_up")
 check("mode action recognized",flight.controller_action("helicopter_mode"))
 check("initial preview displays actual postmix endpoints",s.flight_mode=="normal" and s.pending_mode=="idle_up" and s.pause_reason==initial_prompt)
 set_inputs(s,0.0)
 var refreshed: String=message(s,"idle_up")
 flight.controller_action("helicopter_mode")
 check("changed collective refreshes rather than applies",s.flight_mode=="normal" and s.pending_mode=="idle_up" and s.pause_reason==refreshed and refreshed!=initial_prompt)
 flight.controller_action("helicopter_mode")
 check("unchanged refreshed proposal confirms",s.flight_mode=="idle_up" and s.pending_mode.is_empty() and s.commands.throttle==0.0)
 var reverse: String=message(s,"normal")
 flight.controller_action("helicopter_mode")
 check("reverse transition previews postmix",s.flight_mode=="idle_up" and s.pending_mode=="normal" and s.pause_reason==reverse)
 set_inputs(s,1.0)
 var below_threshold: String=message(s,"normal")
 flight.controller_action("helicopter_mode")
 check("moving below threshold refreshes existing proposal",s.flight_mode=="idle_up" and s.pending_mode=="normal" and s.pause_reason==below_threshold and below_threshold!=reverse)
 flight.controller_action("helicopter_mode")
 check("refreshed zero-jump proposal still needs a separate press",s.flight_mode=="normal" and s.pending_mode.is_empty())
 set_inputs(s,1.0)
 check("no pending and zero pitch jump applies immediately",s.request_flight_mode() and s.flight_mode=="idle_up")

func _display_identity(s: Node) -> void:
 reset_fixture(s)
 s.trainer_enabled=false
 var seen: Dictionary={}
 var pair: Array=[]
 for i: int in 1001:
  var throttle: float=float(i)/1000.0
  set_inputs(s,throttle)
  var before: Dictionary=predict(s,"normal")
  var after: Dictionary=predict(s,"idle_up")
  var delta: float=rad_to_deg(after.collective_75_rad-before.collective_75_rad)
  if absf(delta)<=.5: continue
  var key: String="%.1f"%delta
  var endpoints: String=("%.1f|%.1f"%[rad_to_deg(before.collective_75_rad),rad_to_deg(after.collective_75_rad)])
  if seen.has(key) and seen[key].endpoints!=endpoints:
   pair=[seen[key].throttle,throttle]
   break
  seen[key]={throttle=throttle,endpoints=endpoints}
 check("same displayed delta with different endpoints fixture exists",pair.size()==2)
 if pair.size()==2:
  set_inputs(s,pair[0])
  s.request_flight_mode()
  var old_message: String=s.pause_reason
  set_inputs(s,pair[1])
  var updated: String=message(s,"idle_up")
  check("equal rounded delta cannot hide changed endpoints",not s.request_flight_mode() and s.flight_mode=="normal" and s.pause_reason==updated and old_message!=updated)
  check("updated endpoints confirm",s.request_flight_mode() and s.flight_mode=="idle_up")
 reset_fixture(s)
 set_inputs(s,.5)
 s.request_flight_mode()
 var visible: String=s.pause_reason
 set_inputs(s,.500000001)
 check("changed sample with unchanged displayed effect is not locked out",message(s,"idle_up")==visible and s.request_flight_mode() and s.flight_mode=="idle_up")

func _visibility_and_context(s: Node) -> void:
 reset_fixture(s)
 set_inputs(s,.5)
 check("large pitch delta starts pending",not s.request_flight_mode() and s.pending_mode=="idle_up")
 var prompt: String=s.pause_reason
 s.pause_reason="another status"
 check("hidden prompt cannot authorize transition",not s.request_flight_mode() and s.flight_mode=="normal" and s.pause_reason==prompt)
 check("freshly visible same prompt confirms",s.request_flight_mode() and s.flight_mode=="idle_up")
 reset_fixture(s)
 set_inputs(s,.5)
 s.request_flight_mode()
 s.trainer_enabled=not s.trainer_enabled
 check("trainer change requires new preview",not s.request_flight_mode() and s.flight_mode=="normal" and s.pending_mode=="idle_up")
 check("unchanged trainer preview confirms",s.request_flight_mode() and s.flight_mode=="idle_up")
 reset_fixture(s)
 set_inputs(s,.5)
 s.request_flight_mode()
 s.flight_mode="idle_up"
 check("changed source mode cannot consume old consent",not s.request_flight_mode() and s.flight_mode=="idle_up" and s.pending_mode=="normal")
 check("fresh reverse proposal confirms",s.request_flight_mode() and s.flight_mode=="normal")

func _saturation(s: Node) -> void:
 reset_fixture(s)
 s.trainer_enabled=false
 set_inputs(s,.5,1.0,0.0)
 var right_before: Dictionary=predict(s,"normal")
 var right_after: Dictionary=predict(s,"idle_up")
 s.request_flight_mode()
 var right_message: String=s.pause_reason
 set_inputs(s,.5,-1.0,0.0)
 var left_before: Dictionary=predict(s,"normal")
 var left_after: Dictionary=predict(s,"idle_up")
 var left_message: String=message(s,"idle_up")
 check("opposite roll keeps the same displayed pitch endpoints",("%.1f|%.1f"%[rad_to_deg(right_before.collective_75_rad),rad_to_deg(right_after.collective_75_rad)])==("%.1f|%.1f"%[rad_to_deg(left_before.collective_75_rad),rad_to_deg(left_after.collective_75_rad)]))
 check("opposite roll reverses the cyclic switch effect",signf(right_after.cyclic_right_rad-right_before.cyclic_right_rad)==-signf(left_after.cyclic_right_rad-left_before.cyclic_right_rad) and right_after.cyclic_right_rad!=right_before.cyclic_right_rad)
 check("opposite cyclic clipping refreshes visible effect",not s.request_flight_mode() and s.flight_mode=="normal" and s.pending_mode=="idle_up" and s.pause_reason==left_message and left_message!=right_message and left_message.contains("Cyclic forward/right"))
 check("updated opposite-cyclic effect confirms",s.request_flight_mode() and s.flight_mode=="idle_up")
 reset_fixture(s)
 s.trainer_enabled=false
 set_inputs(s,.5,1.0,1.0)
 var a: Dictionary=predict(s,"normal")
 var b: Dictionary=predict(s,"idle_up")
 var preview: String=message(s,"idle_up")
 check("saturation fixture exercises servo clipping",a.servo_travel_limited or b.servo_travel_limited)
 check("postmix differs from unsaturated collective accessor",absf(a.collective_75_rad-s.collective_pitch())>1e-6)
 check("saturated mode proposal shows actual mixed pitch",not s.request_flight_mode() and s.pending_mode=="idle_up" and s.pause_reason==preview)
 set_inputs(s,.5,0.0,0.0)
 var changed: String=message(s,"idle_up")
 check("cyclic clipping change is detected before apply",not s.request_flight_mode() and s.flight_mode=="normal" and s.pending_mode=="idle_up" and s.pause_reason==changed and changed!=preview)
 check("updated unsaturated effect can be confirmed",s.request_flight_mode() and s.flight_mode=="idle_up")
 reset_fixture(s)
 s.trainer_enabled=true
 set_inputs(s,.5)
 s.request_flight_mode()
 var trainer_preview: String=s.pause_reason
 var found:=false
 for rate: float in [-5.0,-3.0,-1.0,1.0,3.0,5.0]:
  s.sim.state[10]=rate
  if message(s,"idle_up")!=trainer_preview:
   found=true
   break
 check("trainer body-rate fixture changes postmix pitch",found)
 if found:
  var updated: String=message(s,"idle_up")
  check("new trainer state refreshes postmix effect",not s.request_flight_mode() and s.flight_mode=="normal" and s.pause_reason==updated)
  check("unchanged trainer state can confirm",s.request_flight_mode() and s.flight_mode=="idle_up")

func _arm_with_pending(s: Node) -> void:
 reset_fixture(s)
 set_inputs(s,s.startup_collective)
 check("zero-pitch stopped mode change needs confirmation",not s.request_flight_mode() and s.pending_mode=="idle_up")
 check("arming cancels the pending preview",s.toggle_motor_arm() and s.power.armed and s.pending_mode.is_empty() and s._mode_confirmation.is_empty() and s.pause_reason=="Armed in hold. Release hold to start the rotor.")
 check("arm status cannot authorize the hidden preview",not s.request_flight_mode() and s.flight_mode=="normal" and s.pending_mode=="idle_up" and s.pause_reason.contains("Press mode again"))
 check("newly visible post-arm preview confirms",s.request_flight_mode() and s.flight_mode=="idle_up")
 check("reverse mode is pending before hold release",not s.request_flight_mode() and s.pending_mode=="normal")
 check("hold release cancels the pending preview",s.set_drive_hold(false) and s.pending_mode.is_empty() and s._mode_confirmation.is_empty())
 check("after hold release a fresh action only previews",not s.request_flight_mode() and s.pending_mode=="normal")
 check("new hold-release preview confirms",s.request_flight_mode() and s.flight_mode=="normal")

func _pause_cancel_restore(s: Node) -> void:
 reset_fixture(s)
 set_inputs(s,.5)
 s.request_flight_mode()
 s.sim.set_paused(true)
 check("direct pause clears consent and displayed prompt",s.pending_mode.is_empty() and s._mode_confirmation.is_empty())
 check("paused request refuses",not s.request_flight_mode() and s.flight_mode=="normal")
 s.resume()
 check("after pause new action only previews",not s.request_flight_mode() and s.pending_mode=="idle_up")
 s.hold("modal")
 check("modal hold clears consent",s.pending_mode.is_empty() and s._mode_confirmation.is_empty())
 s.release("modal")
 s.resume()
 s.request_flight_mode()
 s.cancel_calibration()
 check("cancellation clears consent",s.pending_mode.is_empty() and s._mode_confirmation.is_empty())
 s.request_flight_mode()
 var saved: Dictionary=s.checkpoint()
 check("pending-mode checkpoint fixture exists",not saved.is_empty())
 var bad: Dictionary=saved.duplicate(true)
 bad.aircraft_sha256="invalid"
 var before: String=s.pause_reason
 check("rejected restore preserves the visible proposal",not s.restore_checkpoint(bad).ok and s.pending_mode=="idle_up" and s.pause_reason==before)
 check("accepted restore clears consent and pauses",s.restore_checkpoint(saved).ok and s.sim.paused and s.pending_mode.is_empty() and s._mode_confirmation.is_empty())
 s.resume()
 check("after restore a fresh action previews",not s.request_flight_mode() and s.pending_mode=="idle_up")
 s.controller_focus_lost()
 check("focus loss clears consent",s.pending_mode.is_empty() and s._mode_confirmation.is_empty())

func _invalid(s: Node) -> void:
 reset_fixture(s)
 set_inputs(s,.5)
 s.request_flight_mode()
 s.commands.throttle=NAN
 check("nonfinite preview refuses and clears pending",not s.request_flight_mode() and s.flight_mode=="normal" and s.pending_mode.is_empty() and s._mode_confirmation.is_empty())
 check("invalid-preview explanation is exposed",s.pause_reason==tr("Mode change unavailable. Check controls and try again."))
 reset_fixture(s)
 set_inputs(s,.5)
 s.request_flight_mode()
 var body: PackedFloat64Array=s.sim.state.duplicate()
 for i: int in range(6,10): s.sim.state[i]=0.0
 check("degenerate attitude refuses preview and clears consent",not s.request_flight_mode() and s.flight_mode=="normal" and s.pending_mode.is_empty())
 s.sim.state=body

func _controller_reselection(s: Node) -> void:
 reset_fixture(s)
 set_inputs(s,.5)
 s.request_flight_mode()
 check("controller deselection succeeds",s.apply_controller_selection(-1,{},{}))
 check("controller deselection clears consent and pauses",s.pending_mode.is_empty() and s._mode_confirmation.is_empty() and s.sim.paused)
 s.resume()
 check("controller deselection requires a fresh proposal",not s.request_flight_mode() and s.pending_mode=="idle_up")

func _radio(s: Node,flight: Node) -> void:
 reset_fixture(s)
 var axes: Array=[0.0,0.0,-1.0,0.0]
 var info: Dictionary={guid="radio-test",name="EdgeTX RadioMaster TX16S",vendor_id=0x1209,product_id=0x4f54}
 s.radio.connect_device(3,info,RcInput.DEFAULT_PROFILE)
 for axis: int in 4: s.radio.on_motion(3,axis,axes[axis])
 s.read_axis=func(_device: int,axis: int) -> float: return float(axes[axis]) if axis<axes.size() else 0.0
 s.read_button=func(_device: int,_button: int) -> bool: return false
 s.radio.poll(s.read_axis,s.sim.dt(),s.read_button)
 check("radio arms using low physical throttle",s.radio.armed and s.radio.profile==s.radio._profile_snapshot)
 axes[2]=.88333333333332
 s.radio.on_motion(3,2,axes[2])
 s.input_enabled=true
 s._physics_process(s.sim.dt())
 s.input_enabled=false
 var at_first: Dictionary=s.radio.sticks()
 var first_message: String=message(s,"idle_up",at_first)
 flight.controller_action("helicopter_mode")
 check("radio mode action previews live conditioned output",s.pending_mode=="idle_up" and s.pause_reason==first_message)
 var last_command: float=s.commands.throttle
 axes[2]=-1.0
 s.radio.on_motion(3,2,axes[2])
 var newest: Dictionary=s.radio.sticks()
 var expected: String=message(s,"idle_up",newest)
 flight.controller_action("helicopter_mode")
 check("fresh axis event before physics sample refreshes preview",s.flight_mode=="normal" and s.pending_mode=="idle_up" and s.pause_reason==expected and expected!=first_message)
 check("preview does not move physical or sampled collective",s.commands.throttle==last_command and newest.throttle==0.0 and s.radio.axes[2]==-1.0)
 check("unchanged fresh radio sample confirms",s.request_flight_mode() and s.flight_mode=="idle_up")
 reset_fixture(s)
 s.input_enabled=true
 s._physics_process(s.sim.dt())
 s.input_enabled=false
 s.request_flight_mode()
 var valid_profile: Dictionary=s.radio.profile.duplicate(true)
 s.radio.profile.roll.invert=not s.radio.profile.roll.invert
 check("unvalidated profile change cancels consent",not s.request_flight_mode() and s.flight_mode=="normal" and s.pending_mode.is_empty())
 check("original radio profile can be reactivated",s.radio.use_profile(valid_profile,"test recovery"))
 s.radio.on_motion(3,2,-1.0)
 s.radio.poll(s.read_axis,s.sim.dt(),s.read_button)
 check("radio rearms after profile recovery",s.radio.armed)
 s.request_flight_mode()
 s.radio.on_motion(3,0,NAN)
 check("invalid radio cannot authorize via fallback zeros",not s.request_flight_mode() and s.flight_mode=="normal" and s.pending_mode.is_empty() and not s.radio.input_error.is_empty())
 s.radio.disconnect_device()
 s.controller_disconnected()
 check("controller loss cannot leave consent",s.pending_mode.is_empty() and s._mode_confirmation.is_empty() and s.sim.paused)

func _run() -> void:
 var s: Node=session_fixture()
 var flight=Activity.new()
 flight.session=s
 _stale_and_reverse(s,flight)
 _display_identity(s)
 _visibility_and_context(s)
 _saturation(s)
 _arm_with_pending(s)
 _pause_cancel_restore(s)
 _invalid(s)
 _controller_reselection(s)
 _radio(s,flight)
 flight.free()
 s.free()
 print("HELI H04 mode confirmation: %d checks, %d failures"%[checks,failures])
 quit(1 if failures else 0)
