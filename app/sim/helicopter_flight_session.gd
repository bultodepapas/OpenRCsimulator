# HELI-16: rotorcraft lifecycle on the common fixed-step Simulation owner.
extends Node
const Sim = preload("res://sim/simulation.gd")
const Data = preload("res://physics/rotorcraft_data.gd")
const Flight = preload("res://physics/rotorcraft/flight_dynamics.gd")
const Hover = preload("res://physics/rotorcraft/trim.gd")
const Skids = preload("res://physics/rotorcraft/skid_contact.gd")
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
var device_info: Callable = func(id: int) -> Dictionary:
  var info: Dictionary = Input.get_joy_info(id)
  info.merge({name=Input.get_joy_name(id),guid=Input.get_joy_guid(id),known=Input.is_joy_known(id)})
  return info
var radio: RefCounted = RcInput.new()
var calibration: RefCounted
var profiles_path: String = "user://rc_calibration.cfg"
var external_controller_selection: bool = false
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
var _weather: RefCounted = WeatherField.new()
var _start: PackedFloat64Array = PackedFloat64Array([12,4,-3])
var _hover: Dictionary = {}
var _trim: Dictionary = {}
var _ready_to_fly: bool = false
var _stage_failure: String = ""

func _init() -> void:
 sim.name="Simulation"
 sim.process_physics_priority=10
 add_child(sim)
 sim.continuous_evaluate=_stage
 sim.continuous_aux=func(c: PackedFloat64Array,_a: PackedFloat64Array) -> PackedFloat64Array: return PackedFloat64Array([c[0]*60.0/(2.0*PI)])
 sim.faulted.connect(func(reason: String) -> void: pause_reason=reason+(" · "+_stage_failure if not _stage_failure.is_empty() else ""))
 sim.stepped.connect(_on_stepped)

func setup(path: String=aircraft_path,_id: String="") -> bool:
 var loaded: Dictionary=Data.load_file(path,air_density())
 if not loaded.ok:
  start_error="; ".join(loaded.errors)
  pause_reason=start_error
  return false
 aircraft_path=path
 aircraft=loaded
 sim.mass=aircraft.context.mass_kg
 sim.gravity=aircraft.context.gravity_m_s2
 sim.inertia=aircraft.context.inertia_body_kg_m2
 return true

func set_field(field: Dictionary) -> bool:
 var table: Dictionary=GroundSurfaces.load_table()
 var built: Dictionary=GroundSurfaces.build(table.table,field) if table.ok else table
 if not built.ok:
  surface_error="; ".join(built.errors)
  return false
 ground_surfaces=built.rects
 _start[0]=float(field.pilot.north)+12.0
 _start[1]=float(field.pilot.east)+4.0
 return true

func setup_weather(settings: Variant) -> bool:
 var result: Dictionary=WeatherField.build(settings)
 if not result.ok or result.field.has_turbulence():
  weather_error="; ".join(result.errors) if not result.ok else "Rotorcraft turbulence integration is not qualified; choose calm, steady wind or gusts."
  return false
 if sim.tick>0:
  weather_error="Weather changes require a new helicopter flight."
  return false
 _weather=result.field
 return setup(aircraft_path)

func set_start_altitude(altitude: float) -> void:
 if is_finite(altitude) and altitude>.3: _start[2]=-altitude

func reset() -> bool:
 cancel_calibration()
 resetting.emit()
 _ready_to_fly=false
 _stage_failure=""
 if not aircraft.ok: return false
 var ground: float=Terrain.sample_validated(_start[0],_start[1],ground_surfaces)[0]
 var solved: Dictionary={ok=false}
 # Match trim to the same terrain sample used by each live RK stage, including hub offset.
 for iteration: int in 5:
  solved=Hover.solve_hover(aircraft.context,0.0,_start,wind_at(0.0),{"ground_height_up_m":ground})
  if not solved.ok: break
  var actual_ground: float=_ground_under_hub(solved.state)
  if absf(actual_ground-ground)<1e-10: break
  ground=actual_ground
 if not solved.ok:
  start_error="Helicopter hover trim refused: "+str(solved.get("fault",solved.get("message","no equilibrium")))
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
 zero_drive_hold=false
 crash={}
 sim.inputs=PackedFloat64Array([0,0,0,commands.throttle])
 sim.continuous=solved.state.slice(13)
 sim.aux=PackedFloat64Array([solved.state[13]*60.0/(2.0*PI)])
 _ready_to_fly=sim.reset(solved.state.slice(0,13))
 start_error="" if _ready_to_fly else sim.fault_reason
 pause_reason=start_error
 sim.process_mode=Node.PROCESS_MODE_INHERIT if physics_enabled else Node.PROCESS_MODE_DISABLED
 sim.set_paused(not holds.is_empty() or not _ready_to_fly)
 return _ready_to_fly

func _stage(body: PackedFloat64Array,continuous: PackedFloat64Array,t: float) -> Dictionary:
 var state: PackedFloat64Array=body.duplicate()
 state.append_array(continuous)
 var contact: Dictionary=Skids.evaluate(body,aircraft.skids,ground_surfaces)
 if not contact.ok: return {}
 var sticks: PackedFloat64Array=PackedFloat64Array([-sim.inputs[1],sim.inputs[0],sim.inputs[2],2.0*sim.inputs[3]-1.0])
 var result: Dictionary=Flight.evaluate(state,aircraft.context,sticks,flight_mode,trainer_enabled,zero_drive_hold,wind_at(t),false,contact.loads,_trim,_height_over_radius(state))
 if not result.ok:
  _stage_failure=str(result.get("message","flight equation refused state"))
  return {}
 return {loads=result.loads,body_derivative=result.body_derivative,derivative=result.derivative,rotor_momentum=result.rotor_momentum}

func _hub_offset(state: PackedFloat64Array) -> PackedFloat64Array:
 var main: Dictionary=aircraft.context.main_model
 return M.q_rotate(M.q_normalized(state.slice(6,10)),M.v3(main.hub_x_m,main.hub_y_m,main.hub_z_m))

func _ground_under_hub(state: PackedFloat64Array) -> float:
 var offset: PackedFloat64Array=_hub_offset(state)
 return Terrain.sample_validated(state[0]+offset[0],state[1]+offset[1],ground_surfaces)[0]

func _height_over_radius(state: PackedFloat64Array) -> float:
 return (-state[2]-_hub_offset(state)[2]-_ground_under_hub(state))/aircraft.context.main_model.rotor_radius_m

func _ready() -> void:
 if external_controller_selection: return
 Input.joy_connection_changed.connect(_on_joy_connection_changed)
 for id: int in Input.get_connected_joypads():
  if not radio.connected: _on_joy_connection_changed(id,true)

func _input(event: InputEvent) -> void:
 if event is InputEventJoypadMotion: radio.on_motion(event.device,event.axis,event.axis_value)
 elif event is InputEventJoypadButton: radio.on_button(event.device,event.button_index,event.pressed)

func _physics_process(_dt: float) -> void:
 if not input_enabled: return
 if not holds.is_empty():
  if external_controller_selection and radio.connected: radio.poll(read_axis,sim.dt(),Callable(),false)
  return
 if calibration!=null:
  radio.poll(read_axis,sim.dt())
  calibration.sample(radio.axes)
  return
 if sim.paused:
  if radio.connected: radio.poll(read_axis,sim.dt(),Callable(),false)
  return
 if radio.connected:
  radio.poll(read_axis,sim.dt())
  commands=radio.sticks()
  raw=commands.duplicate()
 else:
  raw=read_raw.call()
  commands=Commands.step_commands(commands,raw,sim.dt())
 sim.inputs=PackedFloat64Array([commands.roll,commands.pitch,commands.yaw,commands.throttle])

func _on_stepped(_tick: int,_t: float,body: PackedFloat64Array,_loads: PackedFloat64Array,_inputs: PackedFloat64Array,_aux: PackedFloat64Array) -> void:
 if not _ready_to_fly or body.is_empty(): return
 var state: PackedFloat64Array=body.duplicate()
 state.append_array(sim.continuous)
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
 if not radio.connected or radio.profile.get("kind","radio")=="gamepad": return false
 calibration=RcCalibration.new(radio.profile)
 sim.set_paused(true)
 pause_reason="calibrating radio"
 return true
func advance_calibration() -> void:
 if calibration!=null and calibration.advance(radio.axes):
  radio.use_profile(calibration.profile,"calibrated")
  RcCalibration.save_profile(profiles_path,radio.device_key,calibration.profile)
  calibration=null
  pause_reason="radio calibrated"

func apply_controller_selection(id: int,info: Dictionary,profile: Dictionary,_initial_start: bool=false) -> bool:
 calibration=null
 radio.disconnect_device()
 _controller_lost=false
 sim.set_paused(true)
 pause_reason="Controller selected. Check collective and continue explicitly."
 if id<0: return true
 if profile.is_empty() or profile.get("throttle_mode","")=="trigger_absolute":
  _controller_lost=true
  pause_reason="Choose a stick-rate or calibrated radio profile for helicopter collective."
  return false
 radio.connect_device(id,info,profile)
 if radio.is_rate_throttle(): radio.set_rate_throttle_for_start(commands.throttle)
 return true

func controller_disconnected() -> void:
 radio.disconnect_device()
 calibration=null
 _controller_lost=true
 sim.set_paused(true)
 pause_reason="Controller lost. Select controls and review collective before continuing."

func controller_focus_lost() -> void:
 if external_controller_selection and radio.connected:
  radio.require_neutral(true)
  sim.set_paused(true)
  pause_reason="Focus lost. Release controls and review collective before continuing."

func air_density() -> float: return _weather.air_density()
func wind_at(t: float) -> PackedFloat64Array: return _weather.sample(t)
func weather_configuration() -> Dictionary: return _weather.configuration()
func telemetry() -> Dictionary:
 if sim.continuous.size()!=6: return {}
 var state: PackedFloat64Array=sim.state.duplicate()
 state.append_array(sim.continuous)
 var sticks: PackedFloat64Array=PackedFloat64Array([-sim.inputs[1],sim.inputs[0],sim.inputs[2],2.0*sim.inputs[3]-1.0])
 var out: Dictionary=Flight.evaluate(state,aircraft.context,sticks,flight_mode,trainer_enabled,zero_drive_hold,wind_at(sim.time()),false,PackedFloat64Array(),_trim,_height_over_radius(state))
 return out
func trace_meta() -> Dictionary:
 return {aircraft_id=aircraft.id,aircraft_sha256=aircraft.input_identity.sha256,vehicle="rotorcraft",law="experimental-xcell-hx700-v1",continuous_layout="Omega,a1,b1,vi,heading_reference,yaw_integrator",qualification=aircraft.qualification,weather=weather_configuration()}
func checkpoint() -> Dictionary:
 return {format="openrc-helicopter-checkpoint v1",aircraft_sha256=aircraft.input_identity.sha256,weather=weather_configuration(),simulation=sim.checkpoint(),commands=commands.duplicate(),trim=_trim.duplicate(),flight_mode=flight_mode,trainer_enabled=trainer_enabled,zero_drive_hold=zero_drive_hold}

func restore_checkpoint(candidate: Variant) -> Dictionary:
 if not candidate is Dictionary or candidate.size()!=9 or not candidate.has_all(["format","aircraft_sha256","weather","simulation","commands","trim","flight_mode","trainer_enabled","zero_drive_hold"]):
  return {ok=false,errors=["malformed helicopter checkpoint"]}
 if candidate.format!="openrc-helicopter-checkpoint v1" or candidate.aircraft_sha256!=aircraft.input_identity.sha256 or candidate.weather!=weather_configuration() or candidate.trim!=_trim:
  return {ok=false,errors=["helicopter checkpoint configuration mismatch"]}
 if candidate.flight_mode not in ["normal","idle_up"] or not candidate.trainer_enabled is bool or not candidate.zero_drive_hold is bool or not candidate.commands is Dictionary or candidate.commands.size()!=4:
  return {ok=false,errors=["invalid helicopter control configuration"]}
 for key: String in ["roll","pitch","yaw","throttle"]:
  var value: Variant=candidate.commands.get(key)
  if typeof(value) not in [TYPE_FLOAT,TYPE_INT] or not is_finite(float(value)) or value>1.0 or value<(-1.0 if key!="throttle" else 0.0):
   return {ok=false,errors=["invalid saved pilot commands"]}
 if not candidate.simulation is Dictionary or not sim.can_restore_checkpoint(candidate.simulation,1,0):
  return {ok=false,errors=["invalid saved simulation"]}
 var saved: Dictionary=candidate.simulation
 var expected: PackedFloat64Array=PackedFloat64Array([candidate.commands.roll,candidate.commands.pitch,candidate.commands.yaw,candidate.commands.throttle])
 if saved.inputs.to_byte_array()!=expected.to_byte_array(): return {ok=false,errors=["saved commands disagree with sampled inputs"]}
 var state: PackedFloat64Array=saved.state.duplicate()
 state.append_array(saved.continuous)
 var sticks: PackedFloat64Array=PackedFloat64Array([-expected[1],expected[0],expected[2],2.0*expected[3]-1.0])
 var evaluated: Dictionary=Flight.evaluate(state,aircraft.context,sticks,candidate.flight_mode,candidate.trainer_enabled,candidate.zero_drive_hold,wind_at(saved.tick*saved.dt),false,PackedFloat64Array(),_trim,_height_over_radius(state))
 if not evaluated.ok: return {ok=false,errors=["saved flight state is outside the rotorcraft domain"]}
 # Every check finishes before recorder/state mutation.
 resetting.emit()
 if not sim.restore_checkpoint(candidate.simulation): return {ok=false,errors=["simulation restore refused"]}
 commands=candidate.commands.duplicate()
 flight_mode=candidate.flight_mode
 trainer_enabled=candidate.trainer_enabled
 zero_drive_hold=candidate.zero_drive_hold
 crash={}
 _ready_to_fly=true
 pause_reason=""
 sim.set_paused(true)
 return {ok=true,errors=[]}
