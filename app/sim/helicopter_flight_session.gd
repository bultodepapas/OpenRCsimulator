# HELI-16: rotorcraft lifecycle on the common fixed-step Simulation owner.
extends Node
const Sim = preload("res://sim/simulation.gd")
const VehicleModel = preload("res://sim/vehicle_model.gd")
const Data = preload("res://physics/rotorcraft_data.gd")
const ControllerProfile = preload("res://input/controller_profile.gd")
const Flight = preload("res://physics/rotorcraft/flight_dynamics.gd")
const MainRotor = preload("res://physics/rotorcraft/main_rotor.gd")
const Electronics = preload("res://physics/rotorcraft/electronics.gd")
const Hover = preload("res://physics/rotorcraft/trim.gd")
const Skids = preload("res://physics/rotorcraft/skid_contact.gd")
const ImpactDetector = preload("res://physics/rotorcraft/impact_detector.gd")
const CollisionWorld = preload("res://scenery/collision_world.gd")
const GroundStart = preload("res://physics/rotorcraft/ground_start.gd")
const Lifecycle = preload("res://physics/rotorcraft/lifecycle.gd")
const StepAdapter = preload("res://physics/rotorcraft/simulation_step_adapter.gd")
const Swash = preload("res://physics/rotorcraft/swash.gd")
const M = preload("res://physics/math3d.gd")
const RB = preload("res://physics/rigid_body.gd")
const Commands = preload("res://input/commands.gd")
const Keyboard = preload("res://input/keyboard.gd")
const RcInput = preload("res://input/rc_input.gd")
const RcCalibration = preload("res://input/rc_calibration.gd")
const ControllerStore = preload("res://input/controller_profile_store.gd")
const WeatherField = preload("res://physics/wind_field.gd")
const SimEnvironment = preload("res://sim/environment.gd")
const NativeStage = preload("res://sim/native_stage.gd")
const NativeWeather = preload("res://sim/native/native_weather.gd")
const GroundSurfaces = preload("res://physics/ground_surfaces.gd")
const Terrain = preload("res://physics/ground_terrain.gd")
const LakeSurface = preload("res://physics/lake_surface.gd")
const LakeLoader = preload("res://data/lake_loader.gd")
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
var connected_device_ids: Callable = Input.get_connected_joypads
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
## SF-07: the environment contract (physical weather and the field's surfaces); the fields below are views of it.
var environment: SimEnvironment = SimEnvironment.new()
var ground_surfaces: PackedFloat64Array:
 get:
  return environment.surfaces
 set(value):
  environment.surfaces = value
var flight_mode: String = "normal"
var trainer_enabled: bool = true
var zero_drive_hold: bool = false
var _controller_cut_held: bool = false
var start_choice: String = "airborne"
var power: Dictionary = Lifecycle.initial(true)
var startup_collective: float = 0.0
var pending_mode: String = ""
var _mode_confirmation: Dictionary = {}
var shaft_phase := PackedFloat64Array([0.0,0.0])
var _phase_omega := PackedFloat64Array([0.0,0.0])
var _field: Dictionary = {}
var _collision_world: Dictionary = {}
var _impact_geometry: Dictionary = {}
var _pending_impact: Dictionary = {}
var _ground_start: Dictionary = {}
var _weather: WeatherField:
 get:
  return environment.weather
 set(value):
  environment.weather = value
var _start: PackedFloat64Array = PackedFloat64Array([12,4,-3])
var _hover: Dictionary = {}
var _trim: Dictionary = {}
var _ready_to_fly: bool = false
var _stage_failure: String = ""
var _stage_domain_diagnostics: Dictionary = {}
var _fault_domain_diagnostics: Dictionary = {}
## The stopped-rotor tracking policy changes accepted controller state; older
## checkpoints cannot claim exact continuation under this law.
const HEADING_MEMORY_LAW: String = "stopped-rotor-loaded-skid-tracking-v1"
const CONTACT_LAW: String = "composed-lake-unsupported-water-disc-v1"
const CHECKPOINT_FORMAT: String = "openrc-helicopter-checkpoint v8"
const NATIVE_CHECKPOINT_FORMAT: String = "openrc-helicopter-checkpoint v9"
var _stage_backend_requested: String = NativeStage.BACKEND_REFERENCE
var _backend_selection_locked: bool = false
var _native_stage: RefCounted = null
var _native_previous_pre_tick := Callable()
var stage_backend_error: String = ""
var _transition_active: bool = false
var _reset_committed: bool = false


## Technical sessions retain the reference by default. The application may
## select the native stage before committing its aircraft configuration.
func setup_stage_backend(mode: String) -> bool:
 if _transition_reentry(): return false
 if _backend_selection_locked or mode not in [NativeStage.BACKEND_REFERENCE,NativeStage.BACKEND_NATIVE]:
  stage_backend_error="stage backend must be native or gdscript_reference and selected before setup"
  return false
 _stage_backend_requested=mode
 stage_backend_error=""
 return true


func stage_backend_identity() -> Dictionary:
 return _native_stage.backend_identity() if _native_stage!=null and _native_stage.owns_stage(self) else NativeStage.reference_identity()


func stage_backend_status() -> Dictionary:
 return {requested=_stage_backend_requested,identity=stage_backend_identity(),reason=stage_backend_error}


func _detach_stage_backend() -> void:
 if _native_stage!=null:
  _native_stage.restore_reference_callback(self)
  if sim.model.pre_tick==Callable(self,"_kernel_pre_step"):
   sim.model.pre_tick=_native_previous_pre_tick
 _native_stage=null
 _native_previous_pre_tick=Callable()


func _stage_backend_pending() -> void:
 if _stage_backend_requested==NativeStage.BACKEND_NATIVE:
  _detach_stage_backend()
  stage_backend_error="configuration changed; reset required"


func _transition_reentry() -> bool:
 if not _transition_active: return false
 sim.note_reset_publication_reentry()
 return true


## Kernel publication guards the vehicle and physical frame. The session also
## owns drive, controls and source configuration, which observers may inspect
## but cannot change while a committed reset or restore is being published.
const _PUBLICATION_FIELDS := ["aircraft","aircraft_path","_hover","_trim","commands","raw",
 "flight_mode","trainer_enabled","zero_drive_hold","power","pending_mode","_mode_confirmation","start_choice","_start","_field",
 "environment","ground_surfaces","_weather","_collision_world","_impact_geometry","_pending_impact","_ground_start",
 "startup_collective","shaft_phase","_phase_omega","crash","_ready_to_fly","calibration",
 "_stage_domain_diagnostics","_fault_domain_diagnostics",
 "_controller_cut_held","_controller_lost","_native_stage","_native_previous_pre_tick",
 "_stage_backend_requested","_backend_selection_locked"]


func _publish_transition() -> void:
 var saved: Dictionary={}
 for field: String in _PUBLICATION_FIELDS: saved[field]=Sim._guard_copy(get(field))
 var provider: RefCounted=_weather
 var weather_fields: Array=NativeWeather.FIELD_VALUES+["_spatial"]
 var weather_values: Dictionary={}
 for field: String in weather_fields: weather_values[field]=Sim._guard_copy(provider.get(field))
 var environment_values: Dictionary={}
 for field: String in ["turbulence","lake","road","gravity"]:
  environment_values[field]=Sim._guard_copy(environment.get(field))
 resetting.emit()
 var changed: bool=false
 for field: String in _PUBLICATION_FIELDS:
  if not Sim._guard_values_equal(get(field),saved[field]):
   set(field,Sim._guard_copy(saved[field]))
   changed=true
 for field: String in weather_fields:
  if not Sim._guard_values_equal(provider.get(field),weather_values[field]):
   provider.set(field,Sim._guard_copy(weather_values[field]))
   changed=true
 for field: String in environment_values:
  if not Sim._guard_values_equal(environment.get(field),environment_values[field]):
   environment.set(field,Sim._guard_copy(environment_values[field]))
   changed=true
 if changed: sim.note_reset_publication_reentry()


func _publish_native_restore() -> void:
 if radio.connected and radio.is_rate_throttle(): radio.set_rate_throttle_for_start(commands.throttle)
 if external_controller_selection and radio.connected:
  radio.require_neutral(true)
  pause_reason="Checkpoint restored. Release controls and review collective before continuing."
 _publish_transition()


func _publish_reset_transition() -> void:
 if radio.connected and radio.is_rate_throttle(): radio.set_rate_throttle_for_start(commands.throttle)
 _publish_transition()


func _restore_native_guard_after_refusal() -> void:
 if _native_stage==null or not _ready_to_fly: return
 if not _native_stage.owns_stage(self):
  stage_backend_error="native evaluator ownership changed; reset required"
 elif not _native_stage.configuration_matches(self) and not _native_stage.restore_configuration_guard(self):
  stage_backend_error="native prepared configuration changed; reset required"


## Called only after the reference reset has committed its complete context.
func _prepare_stage_backend(time_now: float) -> void:
 _detach_stage_backend()
 stage_backend_error=""
 if _stage_backend_requested!=NativeStage.BACKEND_NATIVE or not _ready_to_fly: return
 if not environment.lake.is_empty():
  stage_backend_error="native helicopter terrain does not support lakes; using gdscript_reference"
  return
 var previous: Callable=sim.model.pre_tick
 _native_previous_pre_tick=previous
 sim.model.pre_tick=Callable(self,"_kernel_pre_step")
 var candidate := NativeStage.new()
 var prepared: Dictionary=candidate.prepare(self)
 if not prepared.get("ok",false):
  stage_backend_error=str(prepared.get("reason",prepared.get("error","native stage refused")))
  sim.model.pre_tick=previous
  _native_previous_pre_tick=Callable()
  return
 _native_stage=candidate
 if not candidate.install(self).is_valid():
  stage_backend_error=candidate.reason
  _detach_stage_backend()
  return
 if not candidate.tick_context(self,sim.aux,sim.inputs,time_now):
  stage_backend_error="native helicopter tick context refused"
  _detach_stage_backend()


## Tick controls and lifecycle are sampled once; native RK stages query only
## their prepared weather and the immutable state handed over at this boundary.
func _kernel_pre_step(aux: PackedFloat64Array,inputs: PackedFloat64Array,dt: float) -> PackedFloat64Array:
 if _native_stage==null or not environment.lake.is_empty() or not _native_stage.configuration_matches(self):
  stage_backend_error="native prepared configuration changed; reset required"
  return PackedFloat64Array()
 var next: Variant=_native_previous_pre_tick.call(aux,inputs,dt) if _native_previous_pre_tick.is_valid() else aux
 if not next is PackedFloat64Array or next.size()!=aux.size(): return PackedFloat64Array()
 if not _native_stage.tick_context(self,next,inputs,sim.time()):
  stage_backend_error="native helicopter tick context refused"
  return PackedFloat64Array()
 return next

func _init() -> void:
 sim.name="Simulation"
 sim.process_physics_priority=10
 add_child(sim)
 # SF-02: the rotorcraft installs its VehicleModel with a declared layout (one sampled rpm, six coupled states).
 var vehicle: VehicleModel=VehicleModel.new()
 vehicle.input_size=4
 vehicle.aux_size=1
 vehicle.continuous_size=Flight.STATE_SIZE-13 # hover layout; reset() redeclares a ground start
 vehicle.identity={"vehicle":"rotorcraft","state_layout":Flight.STATE_LAYOUT,"heading_memory_law":HEADING_MEMORY_LAW,"contact_law":CONTACT_LAW}
 vehicle.stage=_stage
 vehicle.step_policy=_step_with_heading_tracking
 vehicle.block_aux=func(c: PackedFloat64Array,_a: PackedFloat64Array) -> PackedFloat64Array: return PackedFloat64Array([c[0]*60.0/(2.0*PI)])
 if not sim.set_model(vehicle): push_error("Cannot install the rotorcraft vehicle model")
 # A direct reset preparation can evaluate a rejected trial without a fault.
 # Discard that tentative reason once per tick, before any stage can fail.
 sim.before_step.connect(func(_tick: int) -> void:
  _stage_failure=""
  _stage_domain_diagnostics={})
 sim.faulted.connect(func(reason: String) -> void:
  _pending_impact={}
  if _native_stage!=null:
   var native_failure: String=_native_stage.last_failure()
   if not native_failure.is_empty(): _stage_failure=native_failure
  var stage_refused: bool=reason in ["step rejected: joint stage evaluation is nonfinite or malformed", "step rejected: RK joint stage evaluation is nonfinite or malformed"]
  var rotor_refused: bool=_stage_failure=="main-rotor advance ratio exceeds the kernel domain at this speed"
  _fault_domain_diagnostics=_stage_domain_diagnostics.duplicate(true) if stage_refused and rotor_refused and _native_stage==null else {}
  var failure: String="" if rotor_refused and not stage_refused else _stage_failure
  var detail: String=_rotor_domain_report(_fault_domain_diagnostics)
  pause_reason=reason+(" · "+failure if not failure.is_empty() else "")+(" · "+detail if not detail.is_empty() else ""))
 sim.paused_changed.connect(func(value: bool) -> void:
  if value: _clear_mode_confirmation())
 sim.stepped.connect(_on_stepped)


## The stopped tail law supplies exactly zero rotor thrust at the beginning of
## this interval. Reconcile only a successfully integrated, loaded-skid endpoint;
## rotating/coasting rotors retain their original heading and yaw control law.
## The first zero-to-spooling interval is included. This detached candidate is
## validated and committed by Simulation, so failed ticks cannot change memory.
func _step_with_heading_tracking(state: PackedFloat64Array,t: float,dt: float,f: Callable,first: PackedFloat64Array) -> Variant:
 _pending_impact={}
 var result: Variant=StepAdapter.step(state,t,dt,f,first)
 # The kernel has already latched a refused reference RK stage. Its zero
 # derivative fallback can still yield a finite speculative endpoint, which
 # must not replace that earlier refusal with a later contact diagnostic.
 if not _stage_failure.is_empty(): return result
 if result is Dictionary and result.get("state") is PackedFloat64Array \
 and _water_contact_possible(state,result.state):
  _stage_failure="Helicopter water contact is unsupported; the candidate tick was refused."
  return PackedFloat64Array()
 if not result is Dictionary or state.size() not in [19,27]: return result
 var endpoint: Variant=result.get("state")
 if not endpoint is PackedFloat64Array or endpoint.size()!=state.size(): return result
 var body: PackedFloat64Array=endpoint.slice(0,RB.SIZE)
 if not Sim.state_is_valid(body): return result
 if state[13]==0.0 and aircraft.context.electronics_model.law==Electronics.TRAINER_LAW:
  var bristles: PackedFloat64Array=endpoint.slice(19) if endpoint.size()==27 else PackedFloat64Array()
  var contact: Dictionary=Skids.evaluate(body,aircraft.skids,ground_surfaces,true,bristles,environment.lake)
  if not contact.get("ok",false): return PackedFloat64Array()
  var loaded: bool=false
  for normal_force: float in contact.normal_forces_n:
   if normal_force>0.0:
    loaded=true
    break
  if loaded:
   var attitude: PackedFloat64Array=M.q_normalized(body.slice(RB.ATT,RB.ATT+4))
   endpoint[17]=M.q_to_euler(attitude)[0]
   endpoint[18]=0.0
   result.state=endpoint
 var continuous: PackedFloat64Array=endpoint.slice(RB.SIZE)
 var omega:=PackedFloat64Array([continuous[0]*aircraft.context.main_model.rotation_sense,continuous[0]*aircraft.context.tail_model.tail_to_main_speed_ratio*aircraft.context.tail_model.rotation_sense])
 var phase: PackedFloat64Array=shaft_phase.duplicate()
 for index: int in 2: phase[index]+=.5*(_phase_omega[index]+omega[index])*dt
 var detected: Dictionary=ImpactDetector.evaluate(state.slice(0,RB.SIZE),body,continuous,aircraft.context,aircraft.skids,ground_surfaces,phase,_collision_world,_impact_geometry,environment.lake)
 if not detected.get("ok",false):
  _stage_failure="Contact detection refused: "+str(detected.get("error","invalid input"))
  return PackedFloat64Array()
 _pending_impact={tick=sim.tick+1,body=body.duplicate(),continuous=continuous.duplicate(),phase=phase.duplicate(),impact=detected.impact.duplicate(true)}
 return result

func setup(path: String=aircraft_path,selected_id: String="") -> bool:
 if _transition_reentry(): return false
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
 var impact_geometry: Dictionary=ImpactDetector.prepare(loaded.context,loaded.skids)
 if not impact_geometry.get("ok",false):
  start_error="Helicopter contact geometry could not be prepared."
  pause_reason=start_error
  return false
 _stage_backend_pending()
 _backend_selection_locked=true
 aircraft_path=path
 aircraft=loaded
 _impact_geometry=impact_geometry
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
 if _transition_reentry(): return false
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
 if changed: _stage_backend_pending()
 ground_surfaces=built.rects
 _field=field.duplicate(true)
 _start=candidate_start
 surface_error=""
 if changed and _ready_to_fly:
  _ready_to_fly=false
  sim.set_paused(true)
  pause_reason="Field changed; reset helicopter before continuing."
 return true

## Adopt only the scene's published, normalized lake; never retain caller-owned geometry.
func set_lake_context(normalized_lake: Dictionary) -> bool:
 if _transition_reentry(): return false
 var next: Dictionary={}
 if not normalized_lake.is_empty():
  if not LakeSurface.is_valid_definition(normalized_lake): return false
  var identity: String=LakeLoader.identity(normalized_lake)
  if identity.is_empty() or identity!=str(normalized_lake.get("identity","")): return false
  next=normalized_lake.duplicate(true)
 var changed: bool=str(next.get("identity",""))!=str(environment.lake.get("identity",""))
 if sim.tick>0 and changed: return false
 if changed: _stage_backend_pending()
 environment.lake=next
 if changed and _ready_to_fly:
  _ready_to_fly=false
  sim.set_paused(true)
  pause_reason="Lake configuration changed; reset helicopter before continuing."
 return true

func lake_context() -> Dictionary:
 return environment.lake.duplicate(true)

## Contact with water is unsupported. Bound each hull part and rotor by a swept
## sphere and compare with the actual shoreline, including the maximum wave.
## Bounding spheres may refuse nearby dry points; they never produce flotation.
func _water_contact_possible(previous: PackedFloat64Array,current: PackedFloat64Array) -> bool:
 if environment.lake.is_empty(): return false
 if previous.size()<13 or current.size()<13 or not _impact_geometry.get("ok",false) \
 or not LakeSurface.is_valid_definition(environment.lake): return true
 var lake: Dictionary=environment.lake
 var overall_reach: float=float(_impact_geometry.max_reach_m)+0.5*maxf(0.0, \
  maxf(float(aircraft.context.main_model.get("blade_chord_m",0.0)),float(aircraft.context.tail_model.get("blade_chord_m",0.0))))
 overall_reach+=1.0e-6 # include polygon edge tolerance and rounding in this clear-only gate
 if maxf(previous[2],current[2])+overall_reach<float(lake.water_level_down_m)-float(lake.wave_bounds.max_amplitude_m): return false
 var polygon: PackedFloat64Array=lake.shoreline_ne_m
 var bounds:=PackedFloat64Array([INF,-INF,INF,-INF])
 for index: int in range(0,polygon.size(),2):
  bounds[0]=minf(bounds[0],polygon[index]); bounds[1]=maxf(bounds[1],polygon[index])
  bounds[2]=minf(bounds[2],polygon[index+1]); bounds[3]=maxf(bounds[3],polygon[index+1])
 if maxf(previous[0],current[0])+overall_reach<bounds[0] or minf(previous[0],current[0])-overall_reach>bounds[1] \
 or maxf(previous[1],current[1])+overall_reach<bounds[2] or minf(previous[1],current[1])-overall_reach>bounds[3]: return false
 var q0: PackedFloat64Array=M.q_normalized(previous.slice(6,10))
 var q1: PackedFloat64Array=M.q_normalized(current.slice(6,10))
 var dot: float=absf(q0[0]*q1[0]+q0[1]*q1[1]+q0[2]*q1[2]+q0[3]*q1[3])
 var angle: float=2.0*M.acos_(clampf(dot,-1.0,1.0))
 var groups: Dictionary={}
 for probe: Dictionary in _impact_geometry.probes:
  var part: String=str(probe.part)
  if not groups.has(part): groups[part]=[]
  groups[part].append(probe.point)
 for points: Array in groups.values():
  var low:=PackedFloat64Array([INF,INF,INF])
  var high:=PackedFloat64Array([-INF,-INF,-INF])
  for point: PackedFloat64Array in points:
   for axis: int in 3:
    low[axis]=minf(low[axis],point[axis]); high[axis]=maxf(high[axis],point[axis])
  var center: PackedFloat64Array=M.scale(M.add(low,high),0.5)
  var radius: float=M.norm(M.sub(high,low))*0.5
  if _water_group_possible(previous,current,q0,q1,center,radius,angle,lake): return true
 var main: Dictionary=aircraft.context.main_model
 var tail: Dictionary=aircraft.context.tail_model
 var main_center: PackedFloat64Array=M.v3(main.hub_x_m,main.hub_y_m,main.hub_z_m)
 var tail_center: PackedFloat64Array=M.v3(-tail.hub_distance_aft_m,0.0,-tail.hub_height_above_cg_m)
 var main_radius: float=float(main.rotor_radius_m)+0.5*maxf(0.0,float(main.get("blade_chord_m",0.0)))
 var tail_radius: float=float(tail.tail_rotor_radius_m)+0.5*maxf(0.0,float(tail.get("blade_chord_m",0.0)))
 return _water_group_possible(previous,current,q0,q1,main_center,main_radius,angle,lake) \
 or _water_group_possible(previous,current,q0,q1,tail_center,tail_radius,angle,lake)

func _water_group_possible(previous: PackedFloat64Array,current: PackedFloat64Array,q0: PackedFloat64Array,
 q1: PackedFloat64Array,arm: PackedFloat64Array,radius: float,angle: float,lake: Dictionary) -> bool:
 var a: PackedFloat64Array=M.add(previous.slice(0,3),M.q_rotate(q0,arm))
 var b: PackedFloat64Array=M.add(current.slice(0,3),M.q_rotate(q1,arm))
 # The entire rotated center path stays within this margin of its endpoint chord.
 var margin: float=radius+2.0*M.norm(arm)*M.sin_(angle*0.5)+1.0e-6
 if maxf(a[2],b[2])+margin<float(lake.water_level_down_m)-float(lake.wave_bounds.max_amplitude_m): return false
 return _water_near_segment(lake.shoreline_ne_m,a,b,margin)

func _water_near_segment(polygon: PackedFloat64Array,a: PackedFloat64Array,b: PackedFloat64Array,margin: float) -> bool:
 if LakeSurface.shore_distance_validated(environment.lake,a[0],a[1])>=0.0 \
 or LakeSurface.shore_distance_validated(environment.lake,b[0],b[1])>=0.0: return true
 var limit: float=margin*margin
 for index: int in range(0,polygon.size(),2):
  var next: int=(index+2)%polygon.size()
  var cn: float=polygon[index]
  var ce: float=polygon[index+1]
  var dn: float=polygon[next]
  var de: float=polygon[next+1]
  if _segments_intersect_ne(a[0],a[1],b[0],b[1],cn,ce,dn,de): return true
  var distance: float=minf(minf(_point_segment_distance_sq(a[0],a[1],cn,ce,dn,de),_point_segment_distance_sq(b[0],b[1],cn,ce,dn,de)), \
   minf(_point_segment_distance_sq(cn,ce,a[0],a[1],b[0],b[1]),_point_segment_distance_sq(dn,de,a[0],a[1],b[0],b[1])))
  if not is_finite(distance) or distance<=limit: return true
 return false

static func _point_segment_distance_sq(n: float,e: float,an: float,ae: float,bn: float,be: float) -> float:
 var dn: float=bn-an
 var de: float=be-ae
 var length: float=dn*dn+de*de
 if not is_finite(length): return NAN
 var t: float=clampf(((n-an)*dn+(e-ae)*de)/length,0.0,1.0) if length>0.0 else 0.0
 return (n-an-t*dn)*(n-an-t*dn)+(e-ae-t*de)*(e-ae-t*de)

static func _segments_intersect_ne(an: float,ae: float,bn: float,be: float,cn: float,ce: float,dn: float,de: float) -> bool:
 var ab_c: float=(bn-an)*(ce-ae)-(be-ae)*(cn-an)
 var ab_d: float=(bn-an)*(de-ae)-(be-ae)*(dn-an)
 var cd_a: float=(dn-cn)*(ae-ce)-(de-ce)*(an-cn)
 var cd_b: float=(dn-cn)*(be-ce)-(de-ce)*(bn-cn)
 if not is_finite(ab_c) or not is_finite(ab_d) or not is_finite(cd_a) or not is_finite(cd_b): return true
 return ((ab_c<=0.0 and ab_d>=0.0) or (ab_c>=0.0 and ab_d<=0.0)) \
 and ((cd_a<=0.0 and cd_b>=0.0) or (cd_a>=0.0 and cd_b<=0.0)) \
 and maxf(minf(an,bn),minf(cn,dn))<=minf(maxf(an,bn),maxf(cn,dn)) \
 and maxf(minf(ae,be),minf(ce,de))<=minf(maxf(ae,be),maxf(ce,de))

## GroundStart solves only the dry horizontal pad. Refuse a changed support
## before reset publishes anything; ordinary pads outside the bank stay exact.
func _lake_pad_supported() -> bool:
 if environment.lake.is_empty(): return true
 if not _lake_identity_valid(): return false
 if not aircraft.get("ok",false): return true
 if start_choice!="ground":
  var reach: float=float(_impact_geometry.max_reach_m)+0.5*maxf(0.0, \
   maxf(float(aircraft.context.main_model.get("blade_chord_m",0.0)),float(aircraft.context.tail_model.get("blade_chord_m",0.0))))
  if _start[2]+reach>=float(environment.lake.water_level_down_m)-float(environment.lake.wave_bounds.max_amplitude_m) \
  and _water_near_segment(environment.lake.shoreline_ne_m,_start,_start,reach): return false
  return true
 var candidate: Dictionary=GroundStart.resolve(_field,aircraft)
 if not candidate.get("ok",false): return true # let the ordinary start error report this
 var state: PackedFloat64Array=candidate.state
 if _water_contact_possible(state,state): return false
 var q: PackedFloat64Array=state.slice(6,10)
 var points: PackedFloat64Array=aircraft.skids.points_body_frd_m
 for index: int in range(0,12,3):
  var offset: PackedFloat64Array=M.q_rotate(q,points.slice(index,index+3))
  var n: float=state[0]+offset[0]
  var e: float=state[1]+offset[1]
  if Terrain.sample_validated(n,e,ground_surfaces).to_byte_array()!=environment.ground(n,e).to_byte_array(): return false
 return true

## Read-only admission shared by the session and helicopter launch preflight.
## The returned field is detached; callers do not mutate session weather here.
static func validate_weather_selection(settings: Variant) -> Dictionary:
 var result: Dictionary=WeatherField.build(settings)
 if not result.ok:
  return {ok=false,code="invalid",error="; ".join(result.errors),field=null}
 if result.field.is_spatial():
  return {ok=false,code="spatial",error="Spatial weather is not qualified for rotorcraft. Choose a uniform weather preset.",field=null}
 if result.field.has_vertical_atmosphere():
  return {ok=false,code="vertical",error="Rotorcraft vertical atmosphere integration is not qualified; choose reference or uniform field conditions.",field=null}
 if result.field.has_turbulence():
  return {ok=false,code="turbulence",error="Rotorcraft turbulence integration is not qualified; choose calm, steady wind or gusts.",field=null}
 return {ok=true,code="ok",error="",field=result.field}

func setup_weather(settings: Variant) -> bool:
 if _transition_reentry(): return false
 var result: Dictionary=validate_weather_selection(settings)
 if not result.ok:
  weather_error=result.error
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
 if _transition_reentry(): return
 if sim.tick>0 or not is_finite(altitude) or altitude<=.3: return
 var next_start: PackedFloat64Array=_start.duplicate()
 next_start[2]=-altitude
 if next_start.to_byte_array()==_start.to_byte_array(): return
 _stage_backend_pending()
 _start=next_start
 if _ready_to_fly:
  _ready_to_fly=false
  sim.set_paused(true)
  pause_reason="Start altitude changed; reset helicopter before continuing."

func set_start_choice(choice: String) -> bool:
 if _transition_reentry(): return false
 if sim.tick>0:
  start_error="Start selection changes require a new helicopter flight."
  return false
 if choice not in ["airborne","ground","runway"]:
  start_error="Unknown helicopter start; choose ground or airborne."
  return false
 var selected: String="ground" if choice in ["ground","runway"] else "airborne"
 if selected!=start_choice: _stage_backend_pending()
 if selected!=start_choice and _ready_to_fly:
  _ready_to_fly=false
  sim.set_paused(true)
  pause_reason="Start selection changed; reset helicopter before continuing."
 start_choice=selected
 return true

const _RESET_FIELDS := ["_ready_to_fly","_stage_failure","_stage_domain_diagnostics","_fault_domain_diagnostics","_hover","_trim","commands","raw",
 "flight_mode","trainer_enabled","zero_drive_hold","power","pending_mode","_mode_confirmation","shaft_phase","_phase_omega",
 "crash","_ground_start","_pending_impact","startup_collective","calibration","_native_stage","_native_previous_pre_tick",
 "stage_backend_error","pause_reason"]


func reset() -> bool:
 if _transition_reentry(): return false
 if not _lake_pad_supported():
  start_error="Helicopter start refused: unsupported water or lake geometry overlaps the qualified dry rotorpad."
  return false
 var kernel: Dictionary=sim._capture_endpoint_guard()
 var owner: Dictionary={}
 for field: String in _RESET_FIELDS: owner[field]=Sim._guard_copy(get(field))
 # The installed native guard binds the original trim dictionary by identity.
 # Reset replaces it with a new solve; a refused reset must restore that owner.
 var prior_trim: Dictionary=_trim
 var prior_model: RefCounted=sim.model
 var prior_identity: Dictionary=prior_model.identity
 var prior_events: Array[Dictionary]=prior_model.events
 _transition_active=true
 _reset_committed=false
 var accepted: bool=_reset_impl()
 if not accepted and not _reset_committed:
  var refusal: String=start_error
  sim._endpoint_guard_unchanged(kernel)
  # Kernel rollback restores detached values. Reattach the original untouched
  # containers so the prepared native guard still owns the same model roots.
  if sim.model==prior_model:
   if Sim._guard_values_equal(prior_identity,sim.model.identity): sim.model.identity=prior_identity
   if Sim._guard_values_equal(prior_events,sim.model.events): sim.model.events=prior_events
  for field: String in _RESET_FIELDS:
   set(field,prior_trim if field=="_trim" else Sim._guard_copy(owner[field]))
  start_error=refusal
  _restore_native_guard_after_refusal()
 _transition_active=false
 _reset_committed=false
 return accepted


func _reset_impl() -> bool:
 _cancel_calibration_internal()
 _ready_to_fly=false
 _stage_failure=""
 _stage_domain_diagnostics={}
 _fault_domain_diagnostics={}
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
   # A calm reference at the selected density is controller calibration, not a
   # wind-cancelling start. Actual weather still enters every live dynamics stage.
   var reference: Dictionary=Hover.solve_hover(aircraft.context,_ground_start.pad.heading,reference_position,PackedFloat64Array([0,0,0]),{"ground_height_up_m":_ground_under_hub(_ground_start.state)})
   if not reference.ok:
    start_error="Ground trainer control reference refused: "+str(reference.get("message","no hover reference"))
    return false
   var state: PackedFloat64Array=_ground_start.state.duplicate()
   state.append_array(PackedFloat64Array([0,0,0,0,_ground_start.pad.heading,0]))
   # Four N/E elastic friction pairs are integrated and checkpointed with the rotor.
   state.append_array(PackedFloat64Array([0,0,0,0,0,0,0,0]))
   solved={ok=true,state=state,trim={"ground_yaw_precomp_tail_bias_rad":reference.trim.tail_collective_bias_rad,"ground_yaw_precomp_collective_rad":reference.collective_75_rad},sticks=PackedFloat64Array([0,0,0,pickup.stick])}
   startup_collective=pickup.collective
  else:
   solved={ok=false,message=_ground_start.get("reason","") if not _ground_start.ok else pickup.reason}
 else:
  var ground: float=environment.ground(_start[0],_start[1])[0]
  # Match trim to the same terrain sample used by each live RK stage, including hub offset.
  for iteration: int in 5:
   solved=Hover.solve_hover(aircraft.context,0.0,_start,environment.wind_world(_start,0.0),{"ground_height_up_m":ground})
   if not solved.ok: break
   var actual_ground: float=_ground_under_hub(solved.state)
   if absf(actual_ground-ground)<1e-10: break
   ground=actual_ground
 if not solved.ok:
  start_error="Helicopter start refused: "+str(solved.get("fault",solved.get("message","no equilibrium")))
  return false
 _hover=solved
 _trim=solved.trim
 commands={roll=0.0,pitch=0.0,yaw=0.0,throttle=(solved.sticks[3]+1.0)*.5}
 raw=Commands.neutral_raw()
 flight_mode="normal"
 trainer_enabled=true
 zero_drive_hold=start_choice=="ground"
 power=Lifecycle.initial(start_choice!="ground")
 _clear_mode_confirmation()
 shaft_phase=PackedFloat64Array([0.0,0.0])
 _phase_omega=PackedFloat64Array([0.0,0.0])
 _pending_impact={}
 crash={}
 sim.inputs=PackedFloat64Array([0,0,0,commands.throttle])
 # SF-02: six rotor states in hover; a ground start adds four N/E elastic skid-friction pairs. Declared per start, fixed for the run.
 sim.model.continuous_size=Flight.STATE_SIZE-13+(8 if start_choice=="ground" else 0)
 sim.continuous=solved.state.slice(13)
 sim.aux=PackedFloat64Array([solved.state[13]*60.0/(2.0*PI)])
 # Both backends prepare the reference stage before publishing the accepted
 # reset. A native helper may then be installed for the new layout.
 _detach_stage_backend()
 var prepared: Dictionary=sim.prepare_reset(solved.state.slice(0,13))
 if not prepared.get("ok",false):
  var detail: String=_rotor_domain_report(_stage_domain_diagnostics)
  start_error=str(prepared.get("message","helicopter reset preparation failed"))+(" · "+_stage_failure if not _stage_failure.is_empty() else "")+(" · "+detail if not detail.is_empty() else "")
  return false
 # The physical frame is committed before this hook, but keep checkpoints
 # unavailable until the requested backend is installed after publication.
 if not sim.commit_prepared_reset(prepared,Callable(self,"_publish_reset_transition")):
  start_error="prepared helicopter reset was refused"
  return false
 _reset_committed=true
 _ready_to_fly=true
 var reset_failure: String=""
 if not sim.reset_observer_fault.is_empty():
  _ready_to_fly=false
  reset_failure=sim.reset_observer_fault
 if _ready_to_fly: _prepare_stage_backend(0.0)
 start_error="" if _ready_to_fly else (reset_failure if not reset_failure.is_empty() else sim.fault_reason)+( " · "+_stage_failure if not _stage_failure.is_empty() else "")
 pause_reason=start_error
 sim.process_mode=Node.PROCESS_MODE_INHERIT if physics_enabled else Node.PROCESS_MODE_DISABLED
 sim.set_paused(not holds.is_empty() or not _ready_to_fly)
 if _ready_to_fly and external_controller_selection and radio.connected:
  radio.require_neutral(true)
  sim.set_paused(true)
  pause_reason="Restart ready. Release controls and review collective before continuing."
 return _ready_to_fly

func _stage(body: PackedFloat64Array,continuous: PackedFloat64Array,t: float) -> Dictionary:
 var state: PackedFloat64Array=body.duplicate()
 state.append_array(continuous.slice(0,6))
 if _water_contact_possible(body,body):
  _stage_failure="Helicopter water contact is unsupported; the candidate stage was refused."
  return {}
 var contact: Dictionary=Skids.evaluate(body,aircraft.skids,ground_surfaces,false,continuous.slice(6) if continuous.size()==14 else PackedFloat64Array(),environment.lake)
 if not contact.ok: return {}
 var sticks: PackedFloat64Array=PackedFloat64Array([-sim.inputs[1],sim.inputs[0],sim.inputs[2],2.0*sim.inputs[3]-1.0])
 var wind: PackedFloat64Array=wind_at(t,state.slice(0,RB.SIZE))
 var result: Dictionary=Flight.evaluate(state,aircraft.context,sticks,flight_mode,trainer_enabled,zero_drive_hold or not power.armed,wind,false,contact.loads,_trim,_height_over_radius(state),Lifecycle.scale(power,zero_drive_hold,t))
 if not result.ok:
  _stage_failure=str(result.get("message","flight equation refused state"))
  if result.get("fault","")=="main_rotor_advance_ratio_out_of_domain":
   _stage_domain_diagnostics=_rotor_domain_at_stage(state,wind)
  return {}
 # Do not accumulate heading-hold I error against constrained skids during startup.
 # Existing airborne/contact trajectories retain their original control law.
 if start_choice=="ground" and contact.max_depth_m>0.0:
  result.derivative[5]=0.0
 if continuous.size()==14: result.derivative.append_array(contact.bristle_derivative)
 return {loads=result.loads,body_derivative=result.body_derivative,derivative=result.derivative,rotor_momentum=result.rotor_momentum}


## The reference evaluator normalizes attitude before converting CG velocity
## and wind to body FRD. Use the same failed trial and its body-rate hub offset;
## a rolled-back endpoint or world wind cannot reconstruct an RK-stage refusal.
func _rotor_domain_at_stage(state: PackedFloat64Array,wind: PackedFloat64Array) -> Dictionary:
 var attitude: PackedFloat64Array=state.slice(RB.ATT,RB.ATT+4)
 var norm: float=sqrt(M.dot(attitude.slice(1,4),attitude.slice(1,4))+attitude[0]*attitude[0])
 for index: int in 4: attitude[index]/=norm
 var body_velocity: PackedFloat64Array=state.slice(RB.VEL,RB.VEL+3)
 var velocity_ned: PackedFloat64Array=M.q_rotate(attitude,body_velocity)
 var air_cg: PackedFloat64Array=M.q_rotate(M.q_conj(attitude),M.sub(velocity_ned,wind))
 var rates: PackedFloat64Array=state.slice(RB.RATE,RB.RATE+3)
 var model: Dictionary=aircraft.context.main_model
 var arm: PackedFloat64Array=M.v3(model.hub_x_m,model.hub_y_m,model.hub_z_m)
 return MainRotor.domain_diagnostics(model,state[Flight.OMEGA],M.add(air_cg,M.cross(rates,arm)))


## Only a terminal reference-stage fault is published here. A direct reset
## preparation can fail without publishing its candidate to the session.
## Native stages do not expose their failed trial state to this owner.
func stage_domain_diagnostics() -> Dictionary:
 return {} if _native_stage!=null or sim.fault_reason.is_empty() else _fault_domain_diagnostics.duplicate(true)


func _rotor_domain_report(d: Dictionary) -> String:
 if d.is_empty(): return ""
 if not d.get("ok",false): return "Main-rotor hub domain diagnostic unavailable."
 var hub: PackedFloat64Array=d.hub_air_velocity_body_frd_m_s
 var source_indicator: String=_diagnostic_value(d.mu_below_source_indicator) if d.mu_squared!=null else "unavailable"
 return "Hub air-relative FRD (longitudinal, lateral, axial) %s m/s; crossflow %s m/s; head %s rad/s; transition %s–%s rad/s (%s); mu_x %s, mu_y %s, mu² %s; standard member required %s, algebraic mu² < %s valid %s, pole factor %s; source mu < %s indicator %s (not a validated aircraft limit)." % [
  str(hub),str(d.hub_crossflow_m_s),str(d.head_speed_rad_s),str(d.transition_lower_rad_s),
  str(d.transition_upper_rad_s),str(d.regime),_diagnostic_ratio(hub[0],d.tip_speed_m_s),
  _diagnostic_ratio(hub[1],d.tip_speed_m_s),_diagnostic_value(d.mu_squared),str(d.standard_member_required),
  str(d.standard_algebraic_mu_squared_limit),_diagnostic_value(d.standard_algebraic_mu_valid),
  _diagnostic_value(d.pole_factor),str(d.source_identified_mu_indicator_limit),source_indicator]


func _diagnostic_value(value: Variant) -> String:
 return "unavailable" if value==null else str(value)


func _diagnostic_ratio(component: float,tip: Variant) -> String:
 if typeof(tip) not in [TYPE_FLOAT,TYPE_INT] or not is_finite(float(tip)) or float(tip)<=0.0: return "unavailable"
 var ratio: float=component/float(tip)
 return str(ratio) if is_finite(ratio) else "unavailable"

func _hub_offset(state: PackedFloat64Array) -> PackedFloat64Array:
 var main: Dictionary=aircraft.context.main_model
 return M.q_rotate(M.q_normalized(state.slice(6,10)),M.v3(main.hub_x_m,main.hub_y_m,main.hub_z_m))

func _ground_under_hub(state: PackedFloat64Array) -> float:
 var offset: PackedFloat64Array=_hub_offset(state)
 return environment.ground(state[0]+offset[0],state[1]+offset[1])[0]

func _height_over_radius(state: PackedFloat64Array) -> float:
 var offset: PackedFloat64Array=_hub_offset(state)
 var ground: float=environment.ground(state[0]+offset[0],state[1]+offset[1])[0]
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
 if not _ready_to_fly or body.is_empty() or not crash.is_empty() or _tick==0 or _tick!=sim.tick: return
 if _pending_impact.get("tick",-1)!=_tick or not _pending_impact.get("body") is PackedFloat64Array \
 or not _pending_impact.get("continuous") is PackedFloat64Array or not _pending_impact.get("phase") is PackedFloat64Array \
 or _pending_impact.body.to_byte_array()!=body.to_byte_array() \
 or _pending_impact.continuous.to_byte_array()!=sim.continuous.to_byte_array() \
 or _pending_impact.phase.to_byte_array()!=shaft_phase.to_byte_array():
  _ready_to_fly=false
  pause_reason="Contact detection refused: accepted state differs from its preflight."
  sim.set_paused(true)
  return
 var detected: Dictionary=_pending_impact.impact
 _pending_impact={}
 if not detected.is_empty():
  crash=detected.duplicate(true)
  crash.tick=sim.tick
  crash.time_s=sim.time()
  crash.shaft_phase=shaft_phase.duplicate()
  var point: PackedFloat64Array=crash.point_world_ned
  var terrain: PackedFloat64Array=environment.ground(point[0],point[1])
  crash.ground_point_world_ned=PackedFloat64Array([point[0],point[1],-terrain[0]])
  var up: PackedFloat64Array=PackedFloat64Array([-terrain[1],-terrain[2],-1.0])
  crash.ground_normal_world_ned=M.scale(up,1.0/M.norm(up))
  pause_reason=str(crash.reason) # UI-31: Pause offers Restart; the HUD keeps its own key hint
  # Preserve accepted body/shaft state for evidence; cut drive at the terminal boundary.
  power.armed=false
  zero_drive_hold=true
  _clear_mode_confirmation()
  radio.set_auxiliary_enabled(false)
  sim.set_paused(true)

func set_collision_world(world: Dictionary) -> bool:
 if _transition_reentry(): return false
 if sim.tick>0: return false
 if not world.is_empty():
  if not CollisionWorld._world_header_is_valid(world): return false
  for proxy: Dictionary in world.proxies:
   if not CollisionWorld._proxy_is_valid(proxy): return false
 if world!=_collision_world or _ready_to_fly: _stage_backend_pending()
 _collision_world=world.duplicate(true)
 if _ready_to_fly:
  _ready_to_fly=false
  sim.set_paused(true)
  pause_reason="Obstacle configuration changed. Restart the helicopter."
 return true

func collision_world() -> Dictionary:
 return _collision_world.duplicate(true)

func _on_joy_connection_changed(id: int,connected: bool) -> void:
 if external_controller_selection:
  if not connected and radio.connected and id==radio.device_id: controller_disconnected()
  return
 if connected and not radio.connected:
  _clear_mode_confirmation()
  var info: Dictionary=device_info.call(id)
  var unique_legacy: bool=ControllerStore.legacy_identity_is_unique_for_ids(id,info,connected_device_ids.call(),device_info)
  var saved: Dictionary=RcCalibration.load_profile(profiles_path,RcInput.key_for(id,info)) if unique_legacy else {}
  radio.connect_device(id,info,saved)
  if radio.is_rate_throttle(): radio.set_rate_throttle_for_start(commands.throttle)
  sim.set_paused(true)
  pause_reason="Gamepad connected: P resumes the hover collective." if radio.is_rate_throttle() else "Radio: lower collective to arm, return it to %.0f%% for hover, then P."%(commands.throttle*100.0)
 elif not connected and radio.connected and id==radio.device_id:
  _clear_mode_confirmation()
  radio.disconnect_device()
  cancel_calibration()
  sim.set_paused(true)
  pause_reason="radio disconnected"

func hold(reason: String) -> void:
 _clear_mode_confirmation()
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
 if _transition_reentry(): return
 _cancel_calibration_internal()
func _cancel_calibration_internal() -> void:
 _clear_mode_confirmation()
 if calibration!=null: calibration=null; pause_reason="calibration cancelled"
func start_calibration() -> bool:
 if _transition_reentry(): return false
 if not radio.connected or radio.profile.get("kind","")!="radio": return false
 _clear_mode_confirmation()
 calibration=RcCalibration.new(radio.profile)
 radio.set_auxiliary_enabled(false)
 sim.set_paused(true)
 pause_reason="calibrating radio"
 return true
func advance_calibration() -> void:
 if _transition_reentry(): return
 if calibration!=null and calibration.advance(radio.axes):
  if external_controller_selection and persist_controller_profile.is_valid():
   var result: Dictionary=persist_controller_profile.call(calibration.profile)
   calibration=null
   pause_reason="Radio calibrated. Lower collective again before continuing." if result.get("ok",false) else "Calibration not saved: "+str(result.get("error","storage error"))
   return
  var completed: Dictionary=calibration.profile.duplicate(true)
  if not radio.profile.get("configured",false): completed["actions"]=ControllerProfile.ControllerActions.clean_radio_bindings()
  radio.use_profile(completed,"calibrated")
  var info: Dictionary=device_info.call(radio.device_id)
  var unique_legacy: bool=RcInput.key_for(radio.device_id,info)==radio.device_key and ControllerStore.legacy_identity_is_unique_for_ids(radio.device_id,info,connected_device_ids.call(),device_info)
  var err: Error=RcCalibration.save_profile(profiles_path,radio.device_key,completed) if unique_legacy else ERR_ALREADY_IN_USE
  calibration=null
  pause_reason="radio calibrated" if err==OK else "radio calibrated, NOT saved (error %d)"%err

func controller_profile_rejection(profile: Dictionary) -> String:
 return "Choose a stick-rate or calibrated radio profile for helicopter collective." if profile.get("throttle_mode","")=="trigger_absolute" else ""

func apply_controller_selection(id: int,info: Dictionary,profile: Dictionary,_initial_start: bool=false) -> bool:
 if _transition_reentry(): return false
 _clear_mode_confirmation()
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
 if _transition_reentry(): return
 _clear_mode_confirmation()
 radio.disconnect_device()
 calibration=null
 _controller_lost=true
 sim.set_paused(true)
 pause_reason="Controller lost. Select controls and review collective before continuing."

func controller_focus_lost() -> void:
 if _transition_reentry(): return
 _clear_mode_confirmation()
 if external_controller_selection and radio.connected:
  radio.set_auxiliary_enabled(false)
  radio.require_neutral(true,true)
  sim.set_paused(true)
  pause_reason="Focus lost. Release controls and review collective before continuing."

func air_density() -> float: return environment.air_density()
func wind_at(t: float,s: PackedFloat64Array=PackedFloat64Array()) -> PackedFloat64Array:
 var body: PackedFloat64Array=s
 if body.is_empty():
  body=sim.state if sim.state.size()==RB.SIZE else PackedFloat64Array()
 elif body.size()==Flight.STATE_SIZE:
  body=body.slice(0,RB.SIZE)
 if body.size()!=RB.SIZE:
  if not s.is_empty(): return PackedFloat64Array([NAN,NAN,NAN])
  return environment.wind_world(PackedFloat64Array([0.0,0.0,0.0]),t)
 return environment.wind_world(body.slice(RB.POS,RB.POS+3),t)
func weather_configuration() -> Dictionary: return _weather.configuration()
func collective_pitch(mode: String="") -> float:
 var model: Dictionary=aircraft.context.electronics_model
 var curve: Dictionary=Swash.sample_mode_curve(model.curves_by_mode,flight_mode if mode.is_empty() else mode,"pitch",2.0*commands.throttle-1.0)
 return float(curve.value)*model.linkage.collective_rad_per_unit if curve.ok else NAN

func toggle_motor_arm() -> bool:
 if _transition_reentry(): return false
 if power.armed:
  power.armed=false
  zero_drive_hold=true
  _clear_mode_confirmation()
  return true
 if not is_flyable() or not holds.is_empty() or sim.paused or calibration!=null or _controller_lost \
 or (radio.connected and not radio.armed):
  pause_reason="Resume with controls released before arming."
  return false
 if not zero_drive_hold or absf(collective_pitch())>Lifecycle.PICKUP_TOLERANCE_RAD \
 or absf(commands.roll)>.05 or absf(commands.pitch)>.05 or absf(commands.yaw)>.05:
  pause_reason="Arm: hold ON, cyclic/yaw centered, collective within 1 degree of zero pitch."
  return false
 _clear_mode_confirmation()
 power.armed=true
 power.spool_start_s=sim.time()
 pause_reason="Armed in hold. Release hold to start the rotor."
 return true

func set_drive_hold(enabled: bool) -> bool:
 if _transition_reentry(): return false
 if enabled:
  zero_drive_hold=true
  _clear_mode_confirmation()
  return true
 if _controller_cut_held:
  pause_reason="Release throttle cut before releasing rotor hold."
  return false
 if not power.armed:
  pause_reason="Motor is disarmed. Arm at zero collective pitch first."
  return false
 if sim.paused or not holds.is_empty() or _controller_lost or (radio.connected and not radio.armed):
  pause_reason="Resume explicitly before releasing rotor hold."
  return false
 if zero_drive_hold:
  power.spool_start_s=sim.time()
 _clear_mode_confirmation()
 zero_drive_hold=false
 pause_reason="Soft start: wait for governed RPM, then raise collective."
 return true

# The standard cut control always enters a latched hold; releasing it never starts a motor.
func set_controller_cut(enabled: bool) -> void:
 if _transition_reentry(): return
 _controller_cut_held=enabled
 if enabled: set_drive_hold(true)

func _clear_mode_confirmation() -> void:
 if not _mode_confirmation.is_empty() and pause_reason==_mode_confirmation.get("message",null):
  pause_reason=""
 pending_mode=""
 _mode_confirmation={}


## Sample the same postmix output the flight equations consume. The radio's
## latest conditioned axes can be newer than the last physics sample; reading
## them does not move the physical or virtual collective.
func _mode_change_preview(next: String) -> Dictionary:
 if not Sim.state_is_valid(sim.state) or sim.continuous.size() not in [6,14]: return {}
 var controls: Dictionary=radio.sticks() if radio.connected else commands.duplicate(true)
 for key: String in ["roll","pitch","yaw","throttle"]:
  var value: Variant=controls.get(key)
  if typeof(value) not in [TYPE_FLOAT,TYPE_INT] or not is_finite(float(value)): return {}
 var state: PackedFloat64Array=sim.state.duplicate()
 state.append_array(sim.continuous.slice(0,6))
 var sticks:=PackedFloat64Array([-controls.pitch,controls.roll,controls.yaw,2.0*controls.throttle-1.0])
 var model: Dictionary=aircraft.context.electronics_model
 var old_output: Dictionary=Electronics.fast_evaluate(model,state,sticks,flight_mode,trainer_enabled,_trim)
 var new_output: Dictionary=Electronics.fast_evaluate(model,state,sticks,next,trainer_enabled,_trim)
 if not old_output.get("ok",false) or not new_output.get("ok",false): return {}
 var old_pitch: float=float(old_output.get("collective_75_rad",NAN))
 var new_pitch: float=float(new_output.get("collective_75_rad",NAN))
 if not is_finite(old_pitch) or not is_finite(new_pitch): return {}
 var old_degrees: float=rad_to_deg(old_pitch)
 var new_degrees: float=rad_to_deg(new_pitch)
 var source: Dictionary={kind="radio",device=radio.device_id,profile=radio.profile.duplicate(true)} if radio.connected else {kind="keyboard"}
 var identity: Dictionary={source_mode=flight_mode,target_mode=next,input_source=source,trainer=trainer_enabled,
  old_pitch="%.1f"%old_degrees,new_pitch="%.1f"%new_degrees,
  old_saturated=old_output.servo_travel_limited,new_saturated=new_output.servo_travel_limited}
 var message: String=tr("Mode changes pitch %.1f to %.1f deg. Press mode again to apply.")%[old_degrees,new_degrees]
 if old_output.servo_travel_limited or new_output.servo_travel_limited:
  var old_forward: float=rad_to_deg(float(old_output.cyclic_forward_rad))
  var old_right: float=rad_to_deg(float(old_output.cyclic_right_rad))
  var new_forward: float=rad_to_deg(float(new_output.cyclic_forward_rad))
  var new_right: float=rad_to_deg(float(new_output.cyclic_right_rad))
  if not is_finite(old_forward) or not is_finite(old_right) or not is_finite(new_forward) or not is_finite(new_right): return {}
  identity["cyclic"]=["%.1f"%old_forward,"%.1f"%old_right,"%.1f"%new_forward,"%.1f"%new_right]
  message+="\n"+tr("Cyclic forward/right %.1f / %.1f to %.1f / %.1f deg.")%[old_forward,old_right,new_forward,new_right]
 return {identity=identity,input_sample=controls.duplicate(true),old_pitch=old_pitch,new_pitch=new_pitch,
  message=message}


func request_flight_mode() -> bool:
 if _transition_reentry(): return false
 if not is_flyable() or sim.paused or not holds.is_empty() or calibration!=null or _controller_lost:
  _clear_mode_confirmation()
  return false
 if radio.connected and (not radio.armed or not radio.input_error.is_empty() or not radio.profile_error.is_empty() or radio.profile!=radio._profile_snapshot):
  _clear_mode_confirmation()
  pause_reason=tr("Mode change unavailable. Check controls and try again.")
  return false
 var next: String="idle_up" if flight_mode=="normal" else "normal"
 var preview: Dictionary=_mode_change_preview(next)
 if preview.is_empty():
  _clear_mode_confirmation()
  pause_reason=tr("Mode change unavailable. Check controls and try again.")
  return false
 var has_pending: bool=not pending_mode.is_empty() and not _mode_confirmation.is_empty()
 var confirmed: bool=has_pending and pending_mode==next and _mode_confirmation.identity==preview.identity \
  and _mode_confirmation.message==preview.message and pause_reason==_mode_confirmation.message
 if (has_pending and not confirmed) or (not has_pending and absf(preview.new_pitch-preview.old_pitch)>.5*PI/180.0):
  pending_mode=next
  _mode_confirmation=preview
  pause_reason=preview.message
  return false
 flight_mode=next
 _clear_mode_confirmation()
 pause_reason=""
 return true

func power_phase() -> String:
 if sim.continuous.size() not in [6,14]: return "DISARMED"
 return Lifecycle.phase(power,zero_drive_hold,sim.time(),sim.continuous[0],aircraft.context.drive_model.governor_target_main_rad_s)

func trace_controls() -> PackedFloat64Array:
 return PackedFloat64Array([1.0 if power.armed else 0.0,1.0 if zero_drive_hold else 0.0,0.0 if flight_mode=="normal" else 1.0,Lifecycle.scale(power,zero_drive_hold,sim.time()),shaft_phase[0],shaft_phase[1]])

func telemetry() -> Dictionary:
 if sim.continuous.size() not in [6,14] or sim.state.size()!=13: return {}
 var state: PackedFloat64Array=sim.state.duplicate()
 state.append_array(sim.continuous.slice(0,6))
 var sticks: PackedFloat64Array=PackedFloat64Array([-sim.inputs[1],sim.inputs[0],sim.inputs[2],2.0*sim.inputs[3]-1.0])
 var out: Dictionary=Flight.evaluate(state,aircraft.context,sticks,flight_mode,trainer_enabled,zero_drive_hold or not power.armed,wind_at(sim.time(),state.slice(0,RB.SIZE)),false,PackedFloat64Array(),_trim,_height_over_radius(state),Lifecycle.scale(power,zero_drive_hold,sim.time()))
 return out
func trace_meta() -> Dictionary:
 var metadata: Dictionary={aircraft_id=aircraft.id,aircraft_sha256=aircraft.input_identity.sha256,vehicle="rotorcraft",law="experimental-rotorcraft-v2",heading_memory_law=HEADING_MEMORY_LAW,lifecycle_law=Lifecycle.LAW,power_at_record_start=power.duplicate(),control_reference=_trim.duplicate(),start_choice=start_choice,pad=_field.get("rotorcraft_pad",{}),continuous_layout="Omega,a1,b1,vi,heading_reference,yaw_integrator"+(",skid0_z_n,skid0_z_e,skid1_z_n,skid1_z_e,skid2_z_n,skid2_z_e,skid3_z_n,skid3_z_e" if start_choice=="ground" else ""),qualification=aircraft.qualification,weather=weather_configuration()}
 metadata.contact_law=CONTACT_LAW
 metadata.lake_identity=str(environment.lake.get("identity",""))
 var backend: Dictionary=stage_backend_identity()
 if backend.backend==NativeStage.BACKEND_NATIVE: metadata.stage_backend=backend
 return metadata
func checkpoint() -> Dictionary:
 if _native_stage!=null and not _native_stage.configuration_matches(self): return {}
 if not _ready_to_fly or not aircraft.get("ok",false) or not crash.is_empty() \
 or not Terrain.is_valid_surface_table(ground_surfaces) or not _lake_identity_valid() or _start.size()!=3:
  return {}
 for value: float in _start:
  if not is_finite(value): return {}
 var saved_simulation: Dictionary=sim.checkpoint()
 if saved_simulation.is_empty() or not Lifecycle.valid(power,sim.time()) or (not power.armed and not zero_drive_hold) or not _simulation_configuration_matches(saved_simulation) \
 or not _checkpoint_flight_state_is_valid(saved_simulation,commands,flight_mode,trainer_enabled,zero_drive_hold,power): return {}
 var result: Dictionary={format=CHECKPOINT_FORMAT,contact_law=CONTACT_LAW,lake_identity=str(environment.lake.get("identity","")),heading_memory_law=HEADING_MEMORY_LAW,aircraft_sha256=aircraft.input_identity.sha256,weather=weather_configuration(),simulation=saved_simulation,commands=commands.duplicate(),trim=_trim.duplicate(),ground_surfaces=ground_surfaces.duplicate(),start_position=_start.duplicate(),flight_mode=flight_mode,trainer_enabled=trainer_enabled,zero_drive_hold=zero_drive_hold,power=power.duplicate(),start_choice=start_choice,pad=_field.get("rotorcraft_pad",{}).duplicate(true),shaft_phase=shaft_phase.duplicate(),collision_world_identity=str(_collision_world.get("identity",""))}
 var backend: Dictionary=stage_backend_identity()
 if backend.backend==NativeStage.BACKEND_NATIVE:
  result.format=NATIVE_CHECKPOINT_FORMAT
  result.stage_backend=backend
 return result

func _lake_identity_valid() -> bool:
 return environment.lake.is_empty() or (LakeSurface.is_valid_definition(environment.lake) \
  and LakeLoader.identity(environment.lake)==str(environment.lake.get("identity","")))

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
 var evaluated: Dictionary=Flight.evaluate(state,aircraft.context,sticks,saved_mode,saved_trainer,saved_zero_drive or not saved_power.armed,wind_at(saved.tick*saved.dt,state.slice(0,RB.SIZE)),false,PackedFloat64Array(),_trim,_height_over_radius(state),Lifecycle.scale(saved_power,saved_zero_drive,saved.tick*saved.dt))
 return evaluated.ok

func restore_checkpoint(candidate: Variant) -> Dictionary:
 if _transition_reentry(): return {ok=false,errors=["helicopter checkpoint transition is already active"]}
 if _stage_backend_requested==NativeStage.BACKEND_NATIVE:
  _transition_active=true
  var result: Dictionary=_restore_checkpoint_impl(candidate,true)
  _transition_active=false
  if not result.get("ok",false): _restore_native_guard_after_refusal()
  return result
 return _restore_checkpoint_impl(candidate,false)


func _restore_checkpoint_impl(candidate: Variant,transactional: bool) -> Dictionary:
 if not _ready_to_fly:
  return {ok=false,errors=["Reset the selected start before restoring a helicopter checkpoint."]}
 if not candidate is Dictionary:
  return {ok=false,errors=["malformed helicopter checkpoint"]}
 if candidate.get("format") in ["openrc-helicopter-checkpoint v1","openrc-helicopter-checkpoint v2","openrc-helicopter-checkpoint v3","openrc-helicopter-checkpoint v4","openrc-helicopter-checkpoint v5","openrc-helicopter-checkpoint v6","openrc-helicopter-checkpoint v7"]:
  return {ok=false,errors=["Helicopter checkpoint %s uses an earlier contact or heading-memory law; regenerate with v8/v9" % candidate.format]}
 if _native_stage!=null and not _native_stage.configuration_matches(self):
  return {ok=false,errors=["native helicopter configuration changed; reset required"]}
 var recorded_backend: Dictionary=NativeStage.reference_identity()
 if candidate.get("format")==NATIVE_CHECKPOINT_FORMAT:
  if candidate.size()!=20 or not candidate.get("stage_backend") is Dictionary or candidate.stage_backend.get("backend")!=NativeStage.BACKEND_NATIVE:
   return {ok=false,errors=["malformed native helicopter checkpoint"]}
  recorded_backend=candidate.stage_backend.duplicate(true)
  candidate=candidate.duplicate(true)
  candidate.erase("stage_backend")
  candidate.format=CHECKPOINT_FORMAT
 elif candidate.has("stage_backend"):
  return {ok=false,errors=["unexpected helicopter checkpoint backend"]}
 if recorded_backend!=stage_backend_identity():
  return {ok=false,errors=["helicopter checkpoint stage backend differs from this session"]}
 if candidate.get("format")!=CHECKPOINT_FORMAT or candidate.size()!=19 or not candidate.has_all(["format","contact_law","lake_identity","heading_memory_law","aircraft_sha256","weather","simulation","commands","trim","ground_surfaces","start_position","flight_mode","trainer_enabled","zero_drive_hold","power","start_choice","pad","shaft_phase","collision_world_identity"]):
  return {ok=false,errors=["malformed or unsupported helicopter checkpoint"]}
 if candidate.contact_law!=CONTACT_LAW or typeof(candidate.lake_identity)!=TYPE_STRING \
 or not _lake_identity_valid() or candidate.lake_identity!=str(environment.lake.get("identity","")):
  return {ok=false,errors=["helicopter checkpoint terrain or contact law mismatch"]}
 if candidate.heading_memory_law!=HEADING_MEMORY_LAW:
  return {ok=false,errors=["helicopter checkpoint heading-memory law differs from this session"]}
 if typeof(candidate.collision_world_identity)!=TYPE_STRING or candidate.collision_world_identity!=str(_collision_world.get("identity","")):
  return {ok=false,errors=["helicopter checkpoint obstacle inventory mismatch"]}
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
 if _water_contact_possible(saved.state,saved.state):
  return {ok=false,errors=["helicopter checkpoint is in unsupported water contact"]}
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
 if _native_stage!=null:
  # Preflight the restored tick before publishing any owner/kernel changes.
  # On refusal, reestablish the old native context and leave the session intact.
  var previous: Dictionary={mode=flight_mode,trainer=trainer_enabled,hold=zero_drive_hold,power=power}
  flight_mode=candidate.flight_mode
  trainer_enabled=candidate.trainer_enabled
  zero_drive_hold=candidate.zero_drive_hold
  power=candidate.power
  var context_ok: bool=_native_stage.tick_context(self,saved.aux,saved.inputs,float(saved.tick)*float(saved.dt))
  flight_mode=previous.mode
  trainer_enabled=previous.trainer
  zero_drive_hold=previous.hold
  power=previous.power
  if not context_ok:
   _native_stage.tick_context(self,sim.aux,sim.inputs,sim.time())
   return {ok=false,errors=["native helicopter checkpoint tick context refused"]}
 if transactional:
  # The kernel may reject its revalidation; stage the owner so its accepted
  # notification sees the restored controls, and roll back on refusal.
  var owner: Dictionary={}
  for field: String in _RESET_FIELDS: owner[field]=Sim._guard_copy(get(field))
  var prior_trim: Dictionary=_trim
  var old_start_error: String=start_error
  commands=candidate.commands.duplicate()
  flight_mode=candidate.flight_mode
  trainer_enabled=candidate.trainer_enabled
  zero_drive_hold=candidate.zero_drive_hold
  power=candidate.power.duplicate()
  _clear_mode_confirmation()
  shaft_phase=candidate.shaft_phase.duplicate()
  _phase_omega=PackedFloat64Array([saved.continuous[0]*aircraft.context.main_model.rotation_sense,saved.continuous[0]*aircraft.context.tail_model.tail_to_main_speed_ratio*aircraft.context.tail_model.rotation_sense])
  _pending_impact={}
  crash={}
  _ready_to_fly=true
  start_error=""
  _stage_failure=""
  _stage_domain_diagnostics={}
  _fault_domain_diagnostics={}
  pause_reason=""
  if not sim.restore_checkpoint(saved,Callable(self,"_publish_native_restore")):
   for field: String in _RESET_FIELDS:
    set(field,prior_trim if field=="_trim" else Sim._guard_copy(owner[field]))
   start_error=old_start_error
   if _native_stage!=null: _native_stage.tick_context(self,sim.aux,sim.inputs,sim.time())
   return {ok=false,errors=["simulation restore refused"]}
  if not sim.reset_observer_fault.is_empty():
   _ready_to_fly=false
   start_error=sim.reset_observer_fault
   pause_reason=start_error
   return {ok=false,errors=[start_error]}
  return {ok=true,errors=[]}
 # Simulation restoration revalidates its candidate; emit only after the state commit succeeds.
 if not sim.restore_checkpoint(candidate.simulation):
  if _native_stage!=null: _native_stage.tick_context(self,sim.aux,sim.inputs,sim.time())
  return {ok=false,errors=["simulation restore refused"]}
 commands=candidate.commands.duplicate()
 # As in reset(): the stick-rate integrator must hold the restored collective, or the first live tick reverts it.
 if radio.connected and radio.is_rate_throttle(): radio.set_rate_throttle_for_start(commands.throttle)
 flight_mode=candidate.flight_mode
 trainer_enabled=candidate.trainer_enabled
 zero_drive_hold=candidate.zero_drive_hold
 power=candidate.power.duplicate()
 _clear_mode_confirmation()
 shaft_phase=candidate.shaft_phase.duplicate()
 _phase_omega=PackedFloat64Array([sim.continuous[0]*aircraft.context.main_model.rotation_sense,sim.continuous[0]*aircraft.context.tail_model.tail_to_main_speed_ratio*aircraft.context.tail_model.rotation_sense])
 _pending_impact={}
 crash={}
 _ready_to_fly=true
 start_error=""
 _stage_failure=""
 _stage_domain_diagnostics={}
 _fault_domain_diagnostics={}
 pause_reason=""
 sim.set_paused(true)
 if external_controller_selection and radio.connected:
  radio.require_neutral(true)
  pause_reason="Checkpoint restored. Release controls and review collective before continuing."
 resetting.emit()
 return {ok=true,errors=[]}
