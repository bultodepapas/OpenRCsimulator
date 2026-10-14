# HELI-16: rotorcraft lifecycle on the common fixed-step Simulation owner.
extends Node
const Sim = preload("res://sim/simulation.gd")
const Data = preload("res://physics/rotorcraft_data.gd")
const ControllerProfile = preload("res://input/controller_profile.gd")
const Flight = preload("res://physics/rotorcraft/flight_dynamics.gd")
const Hover = preload("res://physics/rotorcraft/trim.gd")
const Skids = preload("res://physics/rotorcraft/skid_contact.gd")
const GroundStart = preload("res://physics/rotorcraft/ground_start.gd")
const Lifecycle = preload("res://physics/rotorcraft/lifecycle.gd")
const StepAdapter = preload("res://physics/rotorcraft/simulation_step_adapter.gd")
const Swash = preload("res://physics/rotorcraft/swash.gd")
const M = preload("res://physics/math3d.gd")
const Commands = preload("res://input/commands.gd")
const Keyboard = preload("res://input/keyboard.gd")
const RcInput = preload("res://input/rc_input.gd")
const RcCalibration = preload("res://input/rc_calibration.gd")
const WeatherField = preload("res://physics/wind_field.gd")
const GroundSurfaces = preload("res://physics/ground_surfaces.gd")
const Terrain = preload("res://physics/ground_terrain.gd")
signal resetting
var sim: Node = Sim.new()
var aircraft: Dictionary = {ok=false}
var aircraft_path: String = "res://data/aircraft/xcell_60_research.json"
var physics_enabled: bool = true
var input_enabled: bool = true
var commands: Dictionary = {roll=0.0,pitch=0.0,yaw=0.0,throttle=.5}
var raw: Dictionary = Commands.neutral_raw()
var read_raw: Callable = Keyboard.read_raw
var read_axis: Callable = Input.get_joy_axis
var read_button: Callable = Input.is_joy_button_pressed
var device_info: Callable = func(id: int) -> Dictionary:
  var info: Dictionary = Input.get_joy_info(id)
  info.merge({name=Input.get_joy_name(id),guid=Input.get_joy_guid(id),known=Input.is_joy_known(id)})
  return info
var radio: RefCounted = RcInput.new()
var calibration: RefCounted
var profiles_path: String = "user://rc_calibration.cfg"
var external_controller_selection: bool = false
var persist_controller_profile := Callable()
var persist_full_controller_profile := Callable()
var _controller_lost: bool = false
var holds: Dictionary = {}
var pause_reason: String = ""
var start_error: String = ""
var surface_error: String = ""
var weather_error: String = ""
var crash: Dictionary = {}
var crash_auto_restart: bool = false
var ground_surfaces: PackedFloat64Array = PackedFloat64Array()
var flight_mode: String = "normal"
var trainer_enabled: bool = true
var zero_drive_hold: bool = false
var start_choice: String = "airborne"
var power: Dictionary = Lifecycle.initial(true)
var startup_collective: float = 0.0
var pending_mode: String = ""
var shaft_phase := PackedFloat64Array([0.0,0.0])
var _phase_omega := PackedFloat64Array([0.0,0.0])
var _field: Dictionary = {}
var _ground_start: Dictionary = {}
var _weather: RefCounted = WeatherField.new()
var _start: PackedFloat64Array = PackedFloat64Array([12,4,-3])
var _hover: Dictionary = {}
var _trim: Dictionary = {}
var _ready_to_fly: bool = false
var _stage_failure: String = ""
const CHECKPOINT_FORMAT: String = "openrc-helicopter-checkpoint v3"

func _init() -> void:
 sim.name="Simulation"
 sim.process_physics_priority=10
 add_child(sim)
 sim.continuous_evaluate=_stage
 sim.continuous_step=StepAdapter.step
 sim.continuous_aux=func(c: PackedFloat64Array,_a: PackedFloat64Array) -> PackedFloat64Array: return PackedFloat64Array([c[0]*60.0/(2.0*PI)])
 sim.faulted.connect(func(reason: String) -> void: pause_reason=reason+(" · "+_stage_failure if not _stage_failure.is_empty() else ""))
 sim.stepped.connect(_on_stepped)

func setup(path: String=aircraft_path,selected_id: String="") -> bool:
 if sim.tick>0:
  start_error="Aircraft configuration changes require a new helicopter flight."
  pause_reason=start_error
  return false
 var loaded: Dictionary=Data.load_file(path,air_density())
 if not loaded.ok or (not selected_id.is_empty() and loaded.get("id","")!=selected_id):
  start_error="; ".join(loaded.errors) if not loaded.ok else "Selected aircraft and rotorcraft data identity disagree."
  pause_reason=start_error
  return false
 if loaded.get("release_gate",{}).get("state","")=="laboratory_only":
  start_error="This rotorcraft profile is laboratory-only: "+", ".join(loaded.release_gate.missing_capabilities)
  pause_reason=start_error
  return false
 aircraft_path=path
 aircraft=loaded
 sim.mass=aircraft.context.mass_kg
 sim.gravity=aircraft.context.gravity_m_s2
 sim.inertia=aircraft.context.inertia_body_kg_m2
 start_error=""
 if _ready_to_fly:
  _ready_to_fly=false
  sim.set_paused(true)
  pause_reason="Aircraft configuration changed; reset helicopter before continuing."
 return true

func set_field(field: Dictionary) -> bool:
 if sim.tick>0:
  surface_error="Field changes require a new helicopter flight."
  return false
 var pilot: Variant=field.get("pilot")
 if not pilot is Dictionary:
  surface_error="Field pilot position is missing."
  return false
 var north_value: Variant=pilot.get("north")
 var east_value: Variant=pilot.get("east")
 if typeof(north_value) not in [TYPE_FLOAT,TYPE_INT] or typeof(east_value) not in [TYPE_FLOAT,TYPE_INT] \
 or not is_finite(float(north_value)) or not is_finite(float(east_value)):
  surface_error="Field pilot position must contain finite north and east coordinates."
  return false
 var field_surfaces: Variant=field.get("surfaces")
 if not field_surfaces is Array:
  surface_error="Field surfaces must be an array."
  return false
 for surface: Variant in field_surfaces:
  if not surface is Dictionary or typeof(surface.get("type"))!=TYPE_STRING:
   surface_error="Field surface entries are malformed."
   return false
  for key: String in ["width_north_south","length_east_west","center_north","center_east"]:
   var value: Variant=surface.get(key)
   if typeof(value) not in [TYPE_FLOAT,TYPE_INT] or not is_finite(float(value)):
    surface_error="Field surface dimensions and position must be finite numbers."
    return false
  if float(surface.width_north_south)<=0.0 or float(surface.length_east_west)<=0.0:
   surface_error="Field surface dimensions must be positive."
   return false
 var candidate_start: PackedFloat64Array=_start.duplicate()
 candidate_start[0]=float(north_value)+12.0
 candidate_start[1]=float(east_value)+4.0
 if not is_finite(candidate_start[0]) or not is_finite(candidate_start[1]):
  surface_error="Field pilot position is outside the supported range."
  return false
 var table: Dictionary=GroundSurfaces.load_table()
 var built: Dictionary=GroundSurfaces.build(table.table,field) if table.ok else table
 if not built.ok:
  surface_error="; ".join(built.errors)
  return false
 if not Terrain.is_valid_surface_table(built.rects):
  surface_error="Field surface table is invalid."
  return false
 var changed: bool=ground_surfaces.to_byte_array()!=built.rects.to_byte_array() or _start.to_byte_array()!=candidate_start.to_byte_array() or _field.get("rotorcraft_pad",{})!=field.get("rotorcraft_pad",{})
 ground_surfaces=built.rects
 _field=field.duplicate(true)
 _start=candidate_start
 surface_error=""
 if changed and _ready_to_fly:
  _ready_to_fly=false
  sim.set_paused(true)
  pause_reason="Field changed; reset helicopter before continuing."
 return true

func setup_weather(settings: Variant) -> bool:
 var result: Dictionary=WeatherField.build(settings)
 if not result.ok or result.field.has_turbulence():
  weather_error="; ".join(result.errors) if not result.ok else "Rotorcraft turbulence integration is not qualified; choose calm, steady wind or gusts."
  return false
 if sim.tick>0:
  weather_error="Weather changes require a new helicopter flight."
  return false
 var previous_weather: RefCounted=_weather
 _weather=result.field
 if not setup(aircraft_path):
  _weather=previous_weather
  weather_error=start_error
  return false
 weather_error=""
 return true

func set_start_altitude(altitude: float) -> void:
 if sim.tick>0 or not is_finite(altitude) or altitude<=.3: return
 var next_start: PackedFloat64Array=_start.duplicate()
 next_start[2]=-altitude
 if next_start.to_byte_array()==_start.to_byte_array(): return
 _start=next_start
 if _ready_to_fly:
  _ready_to_fly=false
  sim.set_paused(true)
  pause_reason="Start altitude changed; reset helicopter before continuing."

func set_start_choice(choice: String) -> bool:
 if sim.tick>0:
  start_error="Start selection changes require a new helicopter flight."
  return false
 if choice not in ["airborne","ground","runway"]:
  start_error="Unknown helicopter start; choose ground or airborne."
  return false
 var selected: String="ground" if choice in ["ground","runway"] else "airborne"
 if selected!=start_choice and _ready_to_fly:
  _ready_to_fly=false
  sim.set_paused(true)
  pause_reason="Start selection changed; reset helicopter before continuing."
 start_choice=selected
 return true

func reset() -> bool:
 cancel_calibration()
 resetting.emit()
 _ready_to_fly=false
 _stage_failure=""
 if not aircraft.ok: return false
 var solved: Dictionary={ok=false}
 if start_choice=="ground":
  _ground_start=GroundStart.resolve(_field,aircraft)
  var pickup: Dictionary=Lifecycle.collective_for_pitch(aircraft.context.electronics_model,"normal",0.0)
  if _ground_start.ok and pickup.ok:
   # Derive the trainer's collective-to-tail precomp reference from this model.
   # This does not seed the ground pose, RPM, wake, or cyclic with an airborne state.
   var reference_position: PackedFloat64Array=_ground_start.state.slice(0,3)
   reference_position[2]=-3.0
   var reference: Dictionary=Hover.solve_hover(aircraft.context,_ground_start.pad.heading,reference_position,wind_at(0.0),{"ground_height_up_m":_ground_under_hub(_ground_start.state)})
   if not reference.ok:
    start_error="Ground trainer control reference refused: "+str(reference.get("message","no hover reference"))
    pause_reason=start_error
    sim.set_paused(true)
    return false
   var state: PackedFloat64Array=_ground_start.state.duplicate()
   state.append_array(PackedFloat64Array([0,0,0,0,_ground_start.pad.heading,0]))
   # Four N/E elastic friction pairs are integrated and checkpointed with the rotor.
   state.append_array(PackedFloat64Array([0,0,0,0,0,0,0,0]))
   solved={ok=true,state=state,trim={ground_yaw_precomp_tail_bias_rad=reference.trim.tail_collective_bias_rad,ground_yaw_precomp_collective_rad=reference.collective_75_rad},sticks=PackedFloat64Array([0,0,0,pickup.stick])}
   startup_collective=pickup.collective
  else:
   solved={ok=false,message=_ground_start.get("reason","") if not _ground_start.ok else pickup.reason}
 else:
  var ground: float=Terrain.sample_validated(_start[0],_start[1],ground_surfaces)[0]
  # Match trim to the same terrain sample used by each live RK stage, including hub offset.
  for iteration: int in 5:
   solved=Hover.solve_hover(aircraft.context,0.0,_start,wind_at(0.0),{"ground_height_up_m":ground})
   if not solved.ok: break
   var actual_ground: float=_ground_under_hub(solved.state)
   if absf(actual_ground-ground)<1e-10: break
   ground=actual_ground
 if not solved.ok:
  start_error="Helicopter start refused: "+str(solved.get("fault",solved.get("message","no equilibrium")))
  pause_reason=start_error
  sim.set_paused(true)
  return false
 _hover=solved
 _trim=solved.trim
 commands={roll=0.0,pitch=0.0,yaw=0.0,throttle=(solved.sticks[3]+1.0)*.5}
 if radio.connected and radio.is_rate_throttle(): radio.set_rate_throttle_for_start(commands.throttle)
 raw=Commands.neutral_raw()
 flight_mode="normal"
 trainer_enabled=true
 zero_drive_hold=start_choice=="ground"
 power=Lifecycle.initial(start_choice!="ground")
 pending_mode=""
 shaft_phase=PackedFloat64Array([0.0,0.0])
 _phase_omega=PackedFloat64Array([0.0,0.0])
 crash={}
 sim.inputs=PackedFloat64Array([0,0,0,commands.throttle])
 sim.continuous=solved.state.slice(13)
 sim.aux=PackedFloat64Array([solved.state[13]*60.0/(2.0*PI)])
 _ready_to_fly=sim.reset(solved.state.slice(0,13))
 start_error="" if _ready_to_fly else sim.fault_reason
 pause_reason=start_error
 sim.process_mode=Node.PROCESS_MODE_INHERIT if physics_enabled else Node.PROCESS_MODE_DISABLED
 sim.set_paused(not holds.is_empty() or not _ready_to_fly)
 if external_controller_selection and radio.connected:
  radio.require_neutral(true)
  sim.set_paused(true)
  pause_reason="Restart ready. Release controls and review collective before continuing."
 return _ready_to_fly

func _stage(body: PackedFloat64Array,continuous: PackedFloat64Array,t: float) -> Dictionary:
 var state: PackedFloat64Array=body.duplicate()
 state.append_array(continuous.slice(0,6))
 var contact: Dictionary=Skids.evaluate(body,aircraft.skids,ground_surfaces,false,continuous.slice(6) if continuous.size()==14 else PackedFloat64Array())
 if not contact.ok: return {}
 var sticks: PackedFloat64Array=PackedFloat64Array([-sim.inputs[1],sim.inputs[0],sim.inputs[2],2.0*sim.inputs[3]-1.0])
 var result: Dictionary=Flight.evaluate(state,aircraft.context,sticks,flight_mode,trainer_enabled,zero_drive_hold or not power.armed,wind_at(t),false,contact.loads,_trim,_height_over_radius(state),Lifecycle.scale(power,zero_drive_hold,t))
 if not result.ok:
  _stage_failure=str(result.get("message","flight equation refused state"))
  return {}
 # Do not accumulate heading-hold I error against constrained skids during startup.
 # Existing airborne/contact trajectories retain their original control law.
 if start_choice=="ground" and contact.max_depth_m>0.0:
  result.derivative[5]=0.0
 if continuous.size()==14: result.derivative.append_array(contact.bristle_derivative)
 return {loads=result.loads,body_derivative=result.body_derivative,derivative=result.derivative,rotor_momentum=result.rotor_momentum}

func _hub_offset(state: PackedFloat64Array) -> PackedFloat64Array:
 var main: Dictionary=aircraft.context.main_model
 return M.q_rotate(M.q_normalized(state.slice(6,10)),M.v3(main.hub_x_m,main.hub_y_m,main.hub_z_m))

func _ground_under_hub(state: PackedFloat64Array) -> float:
 var offset: PackedFloat64Array=_hub_offset(state)
 return Terrain.sample_validated(state[0]+offset[0],state[1]+offset[1],ground_surfaces)[0]

func _height_over_radius(state: PackedFloat64Array) -> float:
 var offset: PackedFloat64Array=_hub_offset(state)
 var ground: float=Terrain.sample_validated(state[0]+offset[0],state[1]+offset[1],ground_surfaces)[0]
 return (-state[2]-offset[2]-ground)/aircraft.context.main_model.rotor_radius_m

func _ready() -> void:
 if external_controller_selection: return
 Input.joy_connection_changed.connect(_on_joy_connection_changed)
 for id: int in Input.get_connected_joypads():
  if not radio.connected: _on_joy_connection_changed(id,true)

func _input(event: InputEvent) -> void:
 radio.set_auxiliary_enabled(not sim.paused and calibration==null and holds.is_empty())
 if event is InputEventJoypadMotion: radio.on_motion(event.device,event.axis,event.axis_value)
 elif event is InputEventJoypadButton: radio.on_button(event.device,event.button_index,event.pressed)

func _poll_controller(integrate: bool=true) -> bool:
 radio.poll(read_axis,sim.dt(),read_button,integrate and not sim.paused and calibration==null and holds.is_empty())
 if external_controller_selection and (not radio.input_error.is_empty() or not radio.profile_error.is_empty()):
  controller_disconnected()
  pause_reason="Invalid controller input. Select controls again before continuing."
  return false
 return true

func _physics_process(_dt: float) -> void:
 if not input_enabled: return
 if not holds.is_empty():
  if external_controller_selection and radio.connected: _poll_controller(false)
  return
 if calibration!=null:
  if not _poll_controller(): return
  calibration.sample(radio.axes)
  return
 if sim.paused:
  if radio.connected: _poll_controller(false)
  return
 if radio.connected:
  if not _poll_controller(): return
  commands=radio.sticks()
  raw=commands.duplicate()
 else:
  raw=read_raw.call()
  commands=Commands.step_commands(commands,raw,sim.dt())
 sim.inputs=PackedFloat64Array([commands.roll,commands.pitch,commands.yaw,commands.throttle])

func _on_stepped(_tick: int,_t: float,body: PackedFloat64Array,_loads: PackedFloat64Array,_inputs: PackedFloat64Array,_aux: PackedFloat64Array) -> void:
 if _tick==0: shaft_phase=PackedFloat64Array([0.0,0.0])
 if sim.continuous.size() in [6,14] and aircraft.get("ok",false):
  var omega := PackedFloat64Array([sim.continuous[0]*aircraft.context.main_model.rotation_sense,sim.continuous[0]*aircraft.context.tail_model.tail_to_main_speed_ratio*aircraft.context.tail_model.rotation_sense])
  if _tick>0:
   for i: int in 2: shaft_phase[i]+=.5*(_phase_omega[i]+omega[i])*sim.dt()
  _phase_omega=omega
 if not _ready_to_fly or body.is_empty(): return
 var state: PackedFloat64Array=body.duplicate()
 state.append_array(sim.continuous.slice(0,6))
 var reason: String=Skids.strike(state,aircraft.context.main_model,aircraft.context.tail_model,ground_surfaces)
 var contact: Dictionary=Skids.evaluate(body,aircraft.skids,ground_surfaces)
 if reason.is_empty() and contact.ok and contact.max_depth_m>.04: reason="hard landing: skid travel exceeded"
 if not reason.is_empty():
  crash={reason=reason,tick=sim.tick}
  pause_reason=reason+" · R: restart"
  sim.set_paused(true)

func _on_joy_connection_changed(id: int,connected: bool) -> void:
 if external_controller_selection:
  if not connected and radio.connected and id==radio.device_id: controller_disconnected()
  return
 if connected and not radio.connected:
  var info: Dictionary=device_info.call(id)
  radio.connect_device(id,info,RcCalibration.load_profile(profiles_path,RcInput.key_for(id,info)))
  if radio.is_rate_throttle(): radio.set_rate_throttle_for_start(commands.throttle)
  sim.set_paused(true)
  pause_reason="Gamepad connected: P resumes the hover collective." if radio.is_rate_throttle() else "Radio: lower collective to arm, return it to %.0f%% for hover, then P."%(commands.throttle*100.0)
 elif not connected and radio.connected and id==radio.device_id:
  radio.disconnect_device()
  cancel_calibration()
  sim.set_paused(true)
  pause_reason="radio disconnected"

func hold(reason: String) -> void:
 pending_mode=""
 radio.set_auxiliary_enabled(false)
 if external_controller_selection and not holds.has(reason) and radio.connected: radio.require_neutral(true)
 holds[reason]=true
 sim.set_paused(true)
func release(reason: String) -> void: holds.erase(reason)
func is_flyable() -> bool: return _ready_to_fly and sim.fault_reason.is_empty() and crash.is_empty()
func can_resume() -> bool: return is_flyable() and holds.is_empty() and calibration==null and not _controller_lost and (not radio.connected or radio.armed)
func resume() -> void:
 if can_resume():
  pause_reason=""
  sim.set_paused(false)
func cancel_calibration() -> void:
 if calibration!=null: calibration=null; pause_reason="calibration cancelled"
func start_calibration() -> bool:
 if not radio.connected or radio.profile.get("kind","")!="radio": return false
 calibration=RcCalibration.new(radio.profile)
 radio.set_auxiliary_enabled(false)
 sim.set_paused(true)
 pause_reason="calibrating radio"
 return true
func advance_calibration() -> void:
 if calibration!=null and calibration.advance(radio.axes):
  if external_controller_selection and persist_controller_profile.is_valid():
   var result: Dictionary=persist_controller_profile.call(calibration.profile)
   calibration=null
   pause_reason="Radio calibrated. Lower collective again before continuing." if result.get("ok",false) else "Calibration not saved: "+str(result.get("error","storage error"))
   return
  radio.use_profile(calibration.profile,"calibrated")
  RcCalibration.save_profile(profiles_path,radio.device_key,calibration.profile)
  calibration=null
  pause_reason="radio calibrated"

func controller_profile_rejection(profile: Dictionary) -> String:
 return "Choose a stick-rate or calibrated radio profile for helicopter collective." if profile.get("throttle_mode","")=="trigger_absolute" else ""

func apply_controller_selection(id: int,info: Dictionary,profile: Dictionary,_initial_start: bool=false) -> bool:
 if id<0:
  calibration=null
  radio.disconnect_device()
  _controller_lost=false
  sim.set_paused(true)
  pause_reason="Controller selected. Check collective and continue explicitly."
  return true
 var normalized: Dictionary=ControllerProfile.upgrade_legacy(profile)
 if normalized.is_empty() or not controller_profile_rejection(normalized).is_empty():
  _controller_lost=true
  sim.set_paused(true)
  pause_reason="Choose a stick-rate or calibrated radio profile for helicopter collective."
  return false
 calibration=null
 radio.disconnect_device()
 _controller_lost=false
 sim.set_paused(true)
 pause_reason="Controller selected. Check collective and continue explicitly."
 radio.connect_device(id,info,normalized)
 if not radio.input_error.is_empty() or not radio.profile_error.is_empty():
  radio.disconnect_device()
  _controller_lost=true
  pause_reason="Controller profile is invalid. Select controls again before continuing."
  return false
 if radio.is_rate_throttle(): radio.set_rate_throttle_for_start(commands.throttle)
 return true

func controller_disconnected() -> void:
 pending_mode=""
 radio.disconnect_device()
 calibration=null
 _controller_lost=true
 sim.set_paused(true)
 pause_reason="Controller lost. Select controls and review collective before continuing."

func controller_focus_lost() -> void:
 pending_mode=""
 if external_controller_selection and radio.connected:
  radio.set_auxiliary_enabled(false)
  radio.require_neutral(true,true)
  sim.set_paused(true)
  pause_reason="Focus lost. Release controls and review collective before continuing."

func air_density() -> float: return _weather.air_density()
func wind_at(t: float) -> PackedFloat64Array: return _weather.sample(t)
func weather_configuration() -> Dictionary: return _weather.configuration()
func collective_pitch(mode: String="") -> float:
 var model: Dictionary=aircraft.context.electronics_model
 var curve: Dictionary=Swash.sample_mode_curve(model.curves_by_mode,flight_mode if mode.is_empty() else mode,"pitch",2.0*commands.throttle-1.0)
 return float(curve.value)*model.linkage.collective_rad_per_unit if curve.ok else NAN

func toggle_motor_arm() -> bool:
 if power.armed:
  power.armed=false
  zero_drive_hold=true
  pending_mode=""
  return true
 if not is_flyable() or not holds.is_empty() or sim.paused or calibration!=null or _controller_lost \
 or (radio.connected and not radio.armed):
  pause_reason="Resume with controls released before arming."
  return false
 if not zero_drive_hold or absf(collective_pitch())>Lifecycle.PICKUP_TOLERANCE_RAD \
 or absf(commands.roll)>.05 or absf(commands.pitch)>.05 or absf(commands.yaw)>.05:
  pause_reason="Arm: hold ON, cyclic/yaw centered, collective within 1 degree of zero pitch."
  return false
 power.armed=true
 power.spool_start_s=sim.time()
 pause_reason="Armed in hold. Release hold to start the rotor."
 return true

func set_drive_hold(enabled: bool) -> bool:
 if enabled:
  zero_drive_hold=true
  pending_mode=""
  return true
 if not power.armed:
  pause_reason="Motor is disarmed. Arm at zero collective pitch first."
  return false
 if sim.paused or not holds.is_empty() or _controller_lost or (radio.connected and not radio.armed):
  pause_reason="Resume explicitly before releasing rotor hold."
  return false
 if zero_drive_hold:
  power.spool_start_s=sim.time()
 zero_drive_hold=false
 pause_reason="Soft start: wait for governed RPM, then raise collective."
 return true

# The standard cut control always enters a latched hold; releasing it never starts a motor.
func set_controller_cut(enabled: bool) -> void:
 if enabled: set_drive_hold(true)

func request_flight_mode() -> bool:
 var next: String="idle_up" if flight_mode=="normal" else "normal"
 var old_pitch: float=collective_pitch()
 var new_pitch: float=collective_pitch(next)
 if pending_mode!=next and absf(new_pitch-old_pitch)>.5*PI/180.0:
  pending_mode=next
  pause_reason=tr("Mode changes pitch %.1f to %.1f deg. Press mode again to apply.")%[old_pitch*180.0/PI,new_pitch*180.0/PI]
  return false
 flight_mode=next
 pending_mode=""
 pause_reason=""
 return true

func power_phase() -> String:
 if sim.continuous.size() not in [6,14]: return "DISARMED"
 return Lifecycle.phase(power,zero_drive_hold,sim.time(),sim.continuous[0],aircraft.context.drive_model.governor_target_main_rad_s)

func trace_controls() -> PackedFloat64Array:
 return PackedFloat64Array([1.0 if power.armed else 0.0,1.0 if zero_drive_hold else 0.0,0.0 if flight_mode=="normal" else 1.0,Lifecycle.scale(power,zero_drive_hold,sim.time()),shaft_phase[0],shaft_phase[1]])

func telemetry() -> Dictionary:
 if sim.continuous.size() not in [6,14]: return {}
 var state: PackedFloat64Array=sim.state.duplicate()
 state.append_array(sim.continuous.slice(0,6))
 var sticks: PackedFloat64Array=PackedFloat64Array([-sim.inputs[1],sim.inputs[0],sim.inputs[2],2.0*sim.inputs[3]-1.0])
 var out: Dictionary=Flight.evaluate(state,aircraft.context,sticks,flight_mode,trainer_enabled,zero_drive_hold or not power.armed,wind_at(sim.time()),false,PackedFloat64Array(),_trim,_height_over_radius(state),Lifecycle.scale(power,zero_drive_hold,sim.time()))
 return out
func trace_meta() -> Dictionary:
 return {aircraft_id=aircraft.id,aircraft_sha256=aircraft.input_identity.sha256,vehicle="rotorcraft",law="experimental-rotorcraft-v2",lifecycle_law=Lifecycle.LAW,power_at_record_start=power.duplicate(),start_choice=start_choice,pad=_field.get("rotorcraft_pad",{}),continuous_layout="Omega,a1,b1,vi,heading_reference,yaw_integrator"+(",skid0_z_n,skid0_z_e,skid1_z_n,skid1_z_e,skid2_z_n,skid2_z_e,skid3_z_n,skid3_z_e" if start_choice=="ground" else ""),qualification=aircraft.qualification,weather=weather_configuration()}
func checkpoint() -> Dictionary:
 if not _ready_to_fly or not aircraft.get("ok",false) or not crash.is_empty() \
 or not Terrain.is_valid_surface_table(ground_surfaces) or _start.size()!=3:
  return {}
 for value: float in _start:
  if not is_finite(value): return {}
 var saved_simulation: Dictionary=sim.checkpoint()
 if saved_simulation.is_empty() or not Lifecycle.valid(power,sim.time()) or (not power.armed and not zero_drive_hold) or not _simulation_configuration_matches(saved_simulation) \
 or not _checkpoint_flight_state_is_valid(saved_simulation,commands,flight_mode,trainer_enabled,zero_drive_hold,power): return {}
 return {format=CHECKPOINT_FORMAT,aircraft_sha256=aircraft.input_identity.sha256,weather=weather_configuration(),simulation=saved_simulation,commands=commands.duplicate(),trim=_trim.duplicate(),ground_surfaces=ground_surfaces.duplicate(),start_position=_start.duplicate(),flight_mode=flight_mode,trainer_enabled=trainer_enabled,zero_drive_hold=zero_drive_hold,power=power.duplicate(),start_choice=start_choice,pad=_field.get("rotorcraft_pad",{}).duplicate(true),shaft_phase=shaft_phase.duplicate()}

func _simulation_configuration_matches(saved: Dictionary) -> bool:
 if not aircraft.get("ok",false) or not saved.has_all(["mass","gravity","inertia","aux","continuous"]): return false
 if not saved.aux is PackedFloat64Array or saved.aux.size()!=1 \
 or not saved.continuous is PackedFloat64Array or saved.continuous.size()!=(14 if start_choice=="ground" else 6): return false
 var projected_rpm: PackedFloat64Array=PackedFloat64Array([saved.continuous[0]*60.0/(2.0*PI)])
 if projected_rpm.to_byte_array()!=saved.aux.to_byte_array(): return false
 var context: Dictionary=aircraft.context
 var expected_inertia: PackedFloat64Array=context.inertia_body_kg_m2
 return typeof(saved.mass) in [TYPE_FLOAT,TYPE_INT] and float(saved.mass)==float(context.mass_kg) \
 and typeof(saved.gravity) in [TYPE_FLOAT,TYPE_INT] and float(saved.gravity)==float(context.gravity_m_s2) \
 and saved.inertia is PackedFloat64Array and saved.inertia.to_byte_array()==expected_inertia.to_byte_array()

func _checkpoint_flight_state_is_valid(saved: Dictionary,saved_commands: Dictionary,saved_mode: String,saved_trainer: bool,saved_zero_drive: bool,saved_power: Dictionary) -> bool:
 if saved_commands.size()!=4 or saved_mode not in ["normal","idle_up"]: return false
 var expected: PackedFloat64Array=PackedFloat64Array()
 for key: String in ["roll","pitch","yaw","throttle"]:
  var value: Variant=saved_commands.get(key)
  if typeof(value) not in [TYPE_FLOAT,TYPE_INT] or not is_finite(float(value)) \
  or value>1.0 or value<(-1.0 if key!="throttle" else 0.0):
   return false
  expected.append(float(value))
 if saved.inputs.to_byte_array()!=expected.to_byte_array(): return false
 var state: PackedFloat64Array=saved.state.duplicate()
 state.append_array(saved.continuous.slice(0,6))
 var sticks: PackedFloat64Array=PackedFloat64Array([-expected[1],expected[0],expected[2],2.0*expected[3]-1.0])
 var evaluated: Dictionary=Flight.evaluate(state,aircraft.context,sticks,saved_mode,saved_trainer,saved_zero_drive or not saved_power.armed,wind_at(saved.tick*saved.dt),false,PackedFloat64Array(),_trim,_height_over_radius(state),Lifecycle.scale(saved_power,saved_zero_drive,saved.tick*saved.dt))
 return evaluated.ok

func restore_checkpoint(candidate: Variant) -> Dictionary:
 if not _ready_to_fly:
  return {ok=false,errors=["Reset the selected start before restoring a helicopter checkpoint."]}
 if not candidate is Dictionary:
  return {ok=false,errors=["malformed helicopter checkpoint"]}
 if candidate.get("format") in ["openrc-helicopter-checkpoint v1","openrc-helicopter-checkpoint v2"]:
  return {ok=false,errors=["helicopter checkpoint v1/v2 lacks power lifecycle and rotor phase; regenerate with v3"]}
 if candidate.get("format")!=CHECKPOINT_FORMAT or candidate.size()!=15 or not candidate.has_all(["format","aircraft_sha256","weather","simulation","commands","trim","ground_surfaces","start_position","flight_mode","trainer_enabled","zero_drive_hold","power","start_choice","pad","shaft_phase"]):
  return {ok=false,errors=["malformed or unsupported helicopter checkpoint"]}
 if not aircraft.get("ok",false) or candidate.aircraft_sha256!=aircraft.input_identity.sha256 or candidate.weather!=weather_configuration() or candidate.trim!=_trim:
  return {ok=false,errors=["helicopter checkpoint configuration mismatch"]}
 if not candidate.ground_surfaces is PackedFloat64Array or not Terrain.is_valid_surface_table(candidate.ground_surfaces) \
 or candidate.ground_surfaces.to_byte_array()!=ground_surfaces.to_byte_array() \
 or not candidate.start_position is PackedFloat64Array or candidate.start_position.size()!=3:
  return {ok=false,errors=["helicopter checkpoint field or start position mismatch"]}
 for value: float in candidate.start_position:
  if not is_finite(value): return {ok=false,errors=["invalid saved start position"]}
 if candidate.start_position.to_byte_array()!=_start.to_byte_array():
  return {ok=false,errors=["helicopter checkpoint field or start position mismatch"]}
 if typeof(candidate.flight_mode)!=TYPE_STRING or candidate.flight_mode not in ["normal","idle_up"] or not candidate.trainer_enabled is bool or not candidate.zero_drive_hold is bool or not candidate.commands is Dictionary or candidate.commands.size()!=4:
  return {ok=false,errors=["invalid helicopter control configuration"]}
 for key: String in ["roll","pitch","yaw","throttle"]:
  var value: Variant=candidate.commands.get(key)
  if typeof(value) not in [TYPE_FLOAT,TYPE_INT] or not is_finite(float(value)) or value>1.0 or value<(-1.0 if key!="throttle" else 0.0):
   return {ok=false,errors=["invalid saved pilot commands"]}
 if not candidate.simulation is Dictionary or not sim.can_restore_checkpoint(candidate.simulation,1,0) or not _simulation_configuration_matches(candidate.simulation):
  return {ok=false,errors=["invalid saved simulation"]}
 var saved: Dictionary=candidate.simulation
 if not Lifecycle.valid(candidate.power,saved.tick*saved.dt) or candidate.start_choice!=start_choice or candidate.pad!=_field.get("rotorcraft_pad",{}):
  return {ok=false,errors=["helicopter start or power lifecycle mismatch"]}
 if not candidate.shaft_phase is PackedFloat64Array or candidate.shaft_phase.size()!=2:
  return {ok=false,errors=["invalid rotor phase"]}
 for value: float in candidate.shaft_phase:
  if not is_finite(value) or absf(value)>1e12: return {ok=false,errors=["invalid rotor phase"]}
 if not candidate.power.armed and not candidate.zero_drive_hold:
  return {ok=false,errors=["disarmed checkpoint must retain hold"]}
 if not _checkpoint_flight_state_is_valid(saved,candidate.commands,candidate.flight_mode,candidate.trainer_enabled,candidate.zero_drive_hold,candidate.power):
  return {ok=false,errors=["saved commands or flight state are outside the rotorcraft domain"]}
 # Simulation restoration revalidates its candidate; emit only after the state commit succeeds.
 if not sim.restore_checkpoint(candidate.simulation): return {ok=false,errors=["simulation restore refused"]}
 commands=candidate.commands.duplicate()
 flight_mode=candidate.flight_mode
 trainer_enabled=candidate.trainer_enabled
 zero_drive_hold=candidate.zero_drive_hold
 power=candidate.power.duplicate()
 pending_mode=""
 shaft_phase=candidate.shaft_phase.duplicate()
 _phase_omega=PackedFloat64Array([sim.continuous[0]*aircraft.context.main_model.rotation_sense,sim.continuous[0]*aircraft.context.tail_model.tail_to_main_speed_ratio*aircraft.context.tail_model.rotation_sense])
 crash={}
 _ready_to_fly=true
 start_error=""
 _stage_failure=""
 pause_reason=""
 sim.set_paused(true)
 resetting.emit()
 return {ok=true,errors=[]}
