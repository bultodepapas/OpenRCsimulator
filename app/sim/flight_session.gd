# One flight of one aircraft: its data, the trimmed start, the pilot's commands, the fixed-step simulation, reset.
# 64-bit floats only (guarded). Pilot commands are sampled once per PHYSICS TICK, before the simulation steps
# (process_physics_priority), so a flight depends only on the per-tick input samples, never on the frame rate.
# Input device: the radio/joystick while one is connected (positions, unshaped, armed throttle), else the keyboard
# (virtual stick: rate-limited, self-centering). Unplugging the radio triggers the failsafe: idle, sticks centred,
# visible pause; resuming is an explicit action (resume()).
extends Node

const FailureConfig := preload("res://failures/config.gd")
const FailureRuntime := preload("res://failures/runtime.gd")
const FailureCatalog := preload("res://failures/catalog.gd")
const FAILURE_CHECKPOINT_FORMAT := "openrc-flight-checkpoint v10"
signal failure_changed
var _failures: RefCounted = null
var failure_error: String = ""


## One resolved episode per new flight. Restart reuses it; ordinary technical flights remain unchanged.
func setup_failures(config: Dictionary, seed_value: int) -> bool:
	var checked: Dictionary = FailureConfig.validate(config)
	if not checked.ok or sim == null or sim.tick != 0 or not physics_enabled or not _flight_ready():
		failure_error = "Failure settings require a valid physics flight at tick zero."
		return false
	var candidate: RefCounted = FailureRuntime.new()
	if not candidate.begin(checked.config, seed_value, sim.dt(), FailureCatalog.profile_for_model(aircraft.model)):
		failure_error = "Failure seed or timestep is invalid."
		return false
	_failures = candidate if checked.config.probability_percent > 0 else null
	failure_error = ""
	return true


func failure_status() -> Dictionary:
	return _failures.status() if _failures != null else {active = false, selected = false, enabled = false}


## Demand downstream of the failed receiver/actuator; pilot inputs stay intact for traces and replay.
func propulsion_throttle() -> float:
	return sim.inputs[3] if _failures == null else _failures.effective_throttle(sim.inputs[3])


## Source inhibition is staged before RK; engine mode belongs to Simulation's tick transaction.
func failure_power_cut_active() -> bool:
	return _failures != null and _failures.propulsion_cut_active()


func propulsion_power_enabled() -> bool:
	return engine_running and not failure_power_cut_active()


## Training delay counts only accepted ticks at least five metres above local terrain and clear of the wheels.
func _failure_airborne() -> bool:
	var ground_up: float = environment.terrain(sim.state[RB.POS], sim.state[RB.POS + 1])[0]
	if -sim.state[RB.POS + 2] - ground_up < 5.0:
		return false
	for compression: float in gear_compressions(sim.state):
		if compression > 0.0:
			return false
	return true

const EventStep: Script = preload("res://physics/event_step.gd")
const GlowFlight: Script = preload("res://physics/glow/flight.gd")
## Fixed original wet-CG datum; live contact mobility and linear fuel sampling at swept crossing fractions.
const MASS_CONTACT_LAW := "fixed-datum-live-mass-contact-linear-fuel-v1"
const BatteryStep: Script = preload("res://physics/electric_battery_step.gd")
const BATTERY_LAW: String = "electric-ocv-resistance-coupled-events-v1"
const BATTERY_LAYOUT: String = "axial wash increment m/s, slipstream.pieces order, then propeller shaft rpm, remaining charge C, terminal energy J, pack heat J; RK4 coupled"
const ELECTRIC_LAW: String = "electric-fixed-bus-coupled-stop-v1"
## Conservative source-only explicit-step envelope, qualified by EL1d scalar refinement.
## Propeller/aerodynamic stiffness still needs per-configuration flight evidence.
const ELECTRIC_MAX_STEP_RATIO: float = 0.25

const WeatherField = preload("res://physics/wind_field.gd")
const SimEnvironment := preload("res://sim/environment.gd")
const Turbulence = preload("res://physics/wind_turbulence.gd")
const WeatherConfig = preload("res://physics/wind_config.gd")
## SF-07: the environment contract this session consumes (physical weather, turbulence, field surfaces, lake).
## The private fields below are views of it, so every existing consumer reads the same providers.
var environment: SimEnvironment = SimEnvironment.new()
var _weather: WeatherField:
	get:
		return environment.weather
	set(value):
		environment.weather = value
var weather_error: String = ""
var _trim_density: float = 1.225
var _trim_charge: float = 1.0
var _weather_pending_reset: bool = false
var _turbulence_aux_index: int = -1 # derived layout cache; reset/restore only, excluded from snapshots
var _shaft_integrator: String = "split"
var _shaft_explicit: bool = false
var _shaft_pending_reset: bool = false
var shaft_error: String = ""


## G2a/G2b: experimental shaft coupling is a launch-time choice, independent of aircraft coefficients.
func setup_shaft_integrator(mode: Variant) -> bool:
	if typeof(mode) != TYPE_STRING or mode not in ["split", "coupled-rk4"]:
		shaft_error = "shaft integrator must be split or coupled-rk4"
		return false
	if sim != null and sim.tick > 0:
		shaft_error = "shaft integration changes require a new flight"
		return false
	if mode == "coupled-rk4" and aircraft.get("ok", false) and not _supports_coupled_shaft(aircraft.model):
		shaft_error = "coupled-rk4 requires a propeller shaft model with positive rotor inertia"
		return false
	if mode == "split" and aircraft.get("ok", false) and (Propulsion.is_electric(aircraft.model.propulsion) or glow_is_active()):
		shaft_error = "electric propulsion requires coupled-rk4"
		return false
	_shaft_explicit = true
	if mode == _shaft_integrator:
		shaft_error = ""
		return true
	resetting.emit()
	_shaft_integrator = mode
	_shaft_pending_reset = sim != null
	if sim != null:
		_configure_continuous_callbacks()
		sim.set_paused(true)
	shaft_error = ""
	return true


func shaft_integrator() -> String:
	return _shaft_integrator


func shaft_is_coupled() -> bool:
	return _shaft_integrator == "coupled-rk4"


func glow_is_active() -> bool:
	return aircraft.get("ok", false) and Propulsion.is_glow(aircraft.model.propulsion)


func glow_state() -> Dictionary:
	return GlowFlight.telemetry(self) if glow_is_active() and _flight_ready() else {ok=false}


## Separate cut and starter commands: moving the throttle never changes the ignition latch.
func glow_cut() -> bool:
	if not glow_is_active() or not _flight_ready(): return false
	var cut: Dictionary=GlowFlight.Life.cut(GlowFlight.unpack(sim.continuous,aircraft.model.propulsion.glow))
	if not cut.ok: return false
	sim.continuous=GlowFlight.put_state(sim.continuous,cut.state)
	engine_running=false
	return true


func glow_set_mixture(value: float) -> bool:
	if not glow_is_active() or not _flight_ready() or not is_finite(value) or value<0.0 or value>2.8: return false
	sim.continuous[12]=value
	return true


## Simplified external starter action; crank impulse conserves aircraft/rotor momentum.
## A metered priming dose leaves the finite tank. Hot engines refuse restart.
func glow_start() -> bool:
	if not glow_is_active() or not _flight_ready() or failure_power_cut_active(): return false
	var install: Dictionary=aircraft.model.propulsion.glow
	var current: Dictionary=GlowFlight.unpack(sim.continuous,install)
	if current.is_empty() or current.running or current.fuel_kg<=install.settings.starter_prime_kg: return false
	var rpm: float=maxf(sim.continuous[0],install.settings.minimum_start_rpm)
	var started: Dictionary=GlowFlight.Life.request_start(install.profile,install.settings,current,rpm,true)
	if not started.get("started",false): return false
	var next: Dictionary=started.state
	next.fuel_kg-=install.settings.starter_prime_kg
	var source: Dictionary=GlowFlight.Source.evaluate(install.profile,rpm,next.air_fraction,sim.continuous[12],1.225*engine_charge_ratio(),true)
	if not source.ok: return false
	next.fuel_transport_kg_s=source.delivered_fuel_kg_s
	var mass: Dictionary=GlowFlight.properties(self,next.fuel_kg)
	if not mass.ok: return false
	var prop: Dictionary=aircraft.model.propulsion
	var impulse: float=prop.rotor_inertia*(rpm-sim.continuous[0])*TAU/60.0
	var correction: PackedFloat64Array=RB.inertia_mul(mass.inverse,M.scale(prop.axis,-impulse))
	var velocity_correction: PackedFloat64Array=M.cross(correction,mass.cg_body_m)
	for i in 3:
		sim.state[RB.RATE+i]+=correction[i]
		sim.state[RB.VEL+i]-=velocity_correction[i]
	sim.continuous=GlowFlight.put_state(sim.continuous,next)
	sim.continuous[0]=rpm
	sim.aux[AUX_RPM]=rpm
	engine_running=true
	return true


## AV-20: data selects stage-coupled turbine RPM independently of the propeller shaft route.
func turbine_is_continuous() -> bool:
	return aircraft.get("ok", false) and Turbine.is_continuous(aircraft.model.propulsion)


func _supports_coupled_shaft(model: Dictionary) -> bool:
	var prop: Dictionary = model.get("propulsion", {})
	if Turbine.is_turbine(prop) or not Propulsion.has_rotor_dynamics(prop) or not _model_is_valid(model) \
			or not is_finite(float(prop.get("rotor_inertia", NAN))) or float(prop.get("rotor_inertia", 0.0)) <= 0.0:
		return false
	var axis: PackedFloat64Array = Propulsion.axis(prop)
	var inverse: PackedFloat64Array = RB.inertia_inverse(model.inertia)
	return 1.0 - float(prop.rotor_inertia) * M.dot(axis, RB.inertia_mul(inverse, axis)) > 0.0


func _electric_step_supported(model: Dictionary) -> bool:
	var prop: Dictionary = model.propulsion
	var carrier: float = 1.0 - float(prop.rotor_inertia) * M.dot(Propulsion.axis(prop),
		RB.inertia_mul(RB.inertia_inverse(model.inertia), Propulsion.axis(prop)))
	var kt: float = 60.0 / (TAU * float(prop.motor.kv_rpm_per_volt))
	var denominator: float = float(prop.motor.resistance_ohm) * float(prop.rotor_inertia) * carrier
	if not is_finite(denominator) or denominator <= 0.0:
		return false
	var ratio: float = sim.dt() * kt * kt / denominator
	if Propulsion.has_dynamic_battery(prop):
		var capacity_c: float = 3600.0 * float(prop.battery.capacity_ah)
		var points: PackedFloat64Array = prop.battery.ocv_points
		var slope: float = 0.0
		for at: int in range(0, points.size() - 2, 2):
			slope = maxf(slope, (points[at + 3] - points[at + 1]) / (points[at + 2] - points[at]))
		var battery_denominator: float = float(prop.motor.resistance_ohm) * capacity_c
		if not is_finite(slope) or not is_finite(battery_denominator) or battery_denominator <= 0.0:
			return false
		# Bound the active branch's mechanical + charge feedback eigenvalue using Rm.
		ratio += sim.dt() * slope / battery_denominator
	return is_finite(ratio) and ratio >= 0.0 and ratio <= ELECTRIC_MAX_STEP_RATIO


## Configure only at a launch boundary, then reset() to build the selected start in this air mass.
## Rejected settings never alter the existing flight, field or recorder.
func setup_weather(settings: Variant) -> bool:
	var built: Dictionary = WeatherField.build(settings)
	if not built.ok:
		weather_error = "; ".join(built.errors)
		return false
	if sim != null and sim.tick > 0:
		weather_error = "weather changes require a new flight or reset boundary"
		return false
	resetting.emit() # a recording cannot span an environment-identity change
	_weather = built.field
	_weather_pending_reset = sim != null
	if sim != null:
		sim.set_paused(true)
	weather_error = ""
	return true


func weather_configuration() -> Dictionary:
	return _weather.configuration()


func weather_is_calm() -> bool:
	return _weather.is_calm()


## Pure sample at the fixed body datum. No terrain clearance or density altitude enters this coordinate.
## Empty state selects the accepted endpoint for HUD/observers; stage callers pass their own body state.
func _atmosphere_down(s: PackedFloat64Array = PackedFloat64Array()) -> float:
	if not s.is_empty():
		return s[RB.POS + 2] if s.size() == RB.SIZE else NAN
	return sim.state[RB.POS + 2] if sim != null and sim.state.size() == RB.SIZE else 0.0


func environment_at(s: PackedFloat64Array) -> Dictionary:
	return environment.air(_atmosphere_down(s))


func atmosphere_configuration(s: PackedFloat64Array = PackedFloat64Array()) -> Dictionary:
	return environment.air(_atmosphere_down(s))


func atmosphere_is_reference() -> bool:
	return not _weather.has_atmosphere()


func air_density(s: PackedFloat64Array = PackedFloat64Array()) -> float:
	return environment.air_density(_atmosphere_down(s))


func engine_charge_ratio(s: PackedFloat64Array = PackedFloat64Array()) -> float:
	return environment.engine_charge_ratio(_atmosphere_down(s))


func wind_at(time_s: float) -> PackedFloat64Array:
	if _weather_pending_reset:
		return M.v3(NAN, NAN, NAN)
	return environment.wind(time_s)


## The owner's turbulence sample for the environment contract: empty without turbulence (nothing is added), a NAN
## vector when the sampled state is malformed, otherwise the committed tick's interpolated noise.
func _turbulence_noise(time_s: float) -> PackedFloat64Array:
	if not _weather.has_turbulence() or sim == null:
		return PackedFloat64Array()
	var index: int = _turbulence_aux_index
	if index < AUX_ANCHORS or sim.aux.size() != index + 7:
		return M.v3(NAN, NAN, NAN)
	return turbulence_at(sim.aux, index, time_s, sim.dt())


## Read-only interpolation of the committed tick's wind interval. No draws during RK/render/trace queries.
static func turbulence_at(aux: PackedFloat64Array, index: int, time_s: float, dt: float) -> PackedFloat64Array:
	if index < 0 or aux.size() < index + 7 or not is_finite(time_s) or not is_finite(dt) or dt <= 0.0:
		return PackedFloat64Array([NAN, NAN, NAN])
	var fraction: float = clampf((time_s - aux[index + 6]) / dt, 0.0, 1.0)
	var result := PackedFloat64Array([0.0, 0.0, 0.0])
	for axis: int in 3:
		result[axis] = aux[index + axis] + fraction * (aux[index + 3 + axis] - aux[index + axis])
	return result


func turbulence_index() -> int:
	return AUX_ANCHORS + anchor_count() * Ground.ANCHOR_STRIDE + (1 if downwash_index() >= 0 else 0) + (GEAR_AUX_SIZE if gear_is_retractable() else 0) + (1 if flaps_available() else 0)


## Stationary restart sample. This is a value, never mutable RNG state outside the simulation snapshot.
func _initial_turbulence() -> Dictionary:
	if not _weather.has_turbulence():
		return {ok = true, values = PackedFloat64Array([0.0, 0.0, 0.0]), rng_state = 0}
	return Turbulence.initial(_weather.turbulence_rms(), _weather.turbulence_seed())


func _restart_weather_aux() -> PackedFloat64Array:
	_weather_pending_reset = false
	var initial: Dictionary = _initial_turbulence()
	_turbulence_aux_index = turbulence_index() if _weather.has_turbulence() else -1
	if not _weather.has_turbulence():
		sim.modes = PackedInt64Array([sim.modes[0]])
		return PackedFloat64Array()
	sim.modes = PackedInt64Array([sim.modes[0], initial.rng_state])
	var window: PackedFloat64Array = initial.values.duplicate()
	window.append_array(initial.values)
	window.append(0.0)
	return window


## Reset-time wind independent of the old tick/window (also used by transactional runway preflight).
func _initial_wind() -> PackedFloat64Array:
	var wind: PackedFloat64Array = _weather.sample(0.0)
	var initial: Dictionary = _initial_turbulence()
	for axis: int in 3:
		wind[axis] += initial.values[axis]
	return wind


func air_data(s: PackedFloat64Array, time_s: float = NAN) -> Dictionary:
	return Air.compute(s, wind_at(sim.time() if is_nan(time_s) else time_s), air_density(s))

const Commands := preload("res://input/commands.gd")
const ControlActuators := preload("res://physics/control_actuators.gd")
const Keyboard := preload("res://input/keyboard.gd")
const RcInput := preload("res://input/rc_input.gd")
const RcCalibration := preload("res://input/rc_calibration.gd")
const Sim := preload("res://sim/simulation.gd")
const VehicleModel := preload("res://sim/vehicle_model.gd")
const Scenarios := preload("res://sim/scenarios.gd")
const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")
const AircraftData := preload("res://physics/aircraft_data.gd")
const Air := preload("res://physics/air_data.gd")
const Aero := preload("res://physics/aero.gd")
const Propulsion := preload("res://physics/propulsion.gd")
const PropulsionRuntime := preload("res://sim/aircraft_propulsion_runtime.gd")
const RotorCoupling = preload("res://physics/rotor_coupling.gd")
const GroundStart := preload("res://physics/ground_start.gd")
const Turbine := preload("res://physics/turbine.gd")
const WashTransport := preload("res://physics/wash_transport.gd")
const Dynamics := preload("res://physics/dynamics.gd")
const Ground := preload("res://physics/ground_contact.gd")
const Flaps := preload("res://physics/flaps.gd")
const RetractableGear := preload("res://physics/retractable_gear.gd")
const GroundTerrain := preload("res://physics/ground_terrain.gd")
const GroundEffect := preload("res://physics/ground_effect.gd")
const ImpactSnapshot := preload("res://physics/impact_snapshot.gd")
const HullContact := preload("res://physics/hull_contact.gd")
const ContactContract := preload("res://physics/aircraft_contact_contract.gd")
const ContactEvents := preload("res://sim/aircraft_contact_events.gd")
const GroundSurfaces := preload("res://physics/ground_surfaces.gd")
const CollisionWorld := preload("res://scenery/collision_world.gd")
const SceneryCollision := preload("res://sim/scenery_collision.gd")
const SceneryDamage := preload("res://sim/scenery_damage.gd")
const LakeLoader := preload("res://data/lake_loader.gd")
const LakeSurface := preload("res://physics/lake_surface.gd")
const LakeCollision := preload("res://sim/lake_collision.gd")

const START_AIRBORNE := "airborne"
const START_RUNWAY := "runway"
const START_HALF_POWER := "airborne_half_power"
const PowerTrim := preload("res://physics/cruise_trim.gd")
## Catalog aircraft with supported static runway starts; physical ground handling remains aircraft-specific.
const RUNWAY_AIRCRAFT_IDS := ["jensen-das-ugly-stik-60", "turbo-lumber-evolution", "stik-glow-55ax-2t", "stik-glow-fs64v-4t", "stik-glow-61fx-2t", "sebart-avanti-s-a200-p100rx", "p51d-mustang-120", "gp-extra-300s-60"]
const RUNWAY_FIELD_ID := "default"


static func runway_aircraft_supported(aircraft_id: String) -> bool:
	return RUNWAY_AIRCRAFT_IDS.has(aircraft_id)


## D6e-R1: explicitly selected operating point, not an aircraft cruise-speed claim.
static func half_power_start_supported(aircraft_id: String) -> bool:
	return aircraft_id == "jensen-das-ugly-stik-60"


func _selected_airborne_trim(model: Dictionary, down_m: float = -30.0) -> Dictionary:
	var speed: float = model.get("start_speed", 15.0)
	var density: float = _weather.air_density(down_m)
	var charge: float = _weather.engine_charge_ratio(down_m)
	if not is_finite(density) or not is_finite(charge):
		return {ok = false, message = "starting altitude is outside the atmosphere's supported domain"}
	if start_choice != START_HALF_POWER:
		return Scenarios.trimmed_level_across_view(model, sim.gravity, model.controls.throw_rad, speed, density, charge)
	if not half_power_start_supported(str(model.get("id", ""))):
		return {ok = false, message = "half-power airborne start is not qualified for this aircraft"}
	# Search bounds limit this opt-in policy; they do not prescribe a flight speed.
	var t: Dictionary = PowerTrim.solve_level_at_throttle(speed, 0.5, 2.0 * speed, model, sim.gravity, model.controls.throw_rad, density, charge)
	if t.ok:
		t.state = Scenarios.Trim.state_for(t.V, t.alpha, t.gamma, PI / 2.0, M.v3(60.0, -40.0, -30.0), t.beta)
	return t

## Emitted at the start of reset(), before the simulation restarts (recorders close their file here).
signal resetting
## Emitted when the detached scenery damage state changes or a session reset/restore succeeds.
signal scenery_damage_changed
## Accepted contact observations changed, including decisions made between integration steps.
## Consumers read the detached contact_events() snapshot; no signal is emitted for rejected candidates.
signal contact_events_changed

## Auxiliary simulation state (advanced once per tick in _pre_step): engine rpm, then the servos' actual positions
## (roll, pitch, yaw in command units, −1…1 of each surface's throw, trims included).
const AUX_RPM := 0
const AUX_SERVO := 1
const AUX_LAYOUT := ["engine_rpm", "srv_roll", "srv_pitch", "srv_yaw"]
## E3b1: with stiction data the per-wheel anchors follow AUX_LAYOUT ([north, east, stuck] per contact, gear order).
## AUX_LAYOUT stays the trace's four auxiliary columns.
const AUX_ANCHORS := 4
const GEAR_AUX_SIZE := 2 # extension, accepted down target; before optional turbulence
var _flap_requested := 0.0
var _gear_requested_down := false
var _wheel_brake_demand := 0.0
var _gear_request_inhibited := false
var _gear_cache_fraction := -1.0
var _gear_cache: Dictionary = {}
## E0a2b: with a tail downwash lag the lagged wing CL follows the anchors (downwash_index()).

## The fixed-step simulation: a child node, stepped after this node on every tick.
var sim: Node
## The aircraft data file ([F5] reloads it).
var aircraft_path := Scenarios.AIRCRAFT
## AS-03: selected visual/catalog identity. Empty only for explicit research/donor sessions.
var expected_aircraft_id: String = ""
var aircraft := {} # AircraftData result: { ok, errors, warnings, model }
var start := {} # trimmed starting condition (Trim result); empty without valid data
## Persistent product start selection. Set before setup(), or before reset(); explicit runway failures stay stopped.
var start_choice: String = START_AIRBORNE
## Empty after a successful reset; otherwise the explicit reason the requested start was refused.
var start_error: String = ""
var _runway_field: Dictionary = {}
var _launch_metadata: Dictionary = {}
var _has_committed_aircraft: bool = false
## Trims in pilot units (−1…1), like radio trim tabs: solved at the start, added to the sticks.
var trims := { roll = 0.0, pitch = 0.0, yaw = 0.0 }
## D6e: the sticks' rate profile. "full": the data's maximum throws, no expo (scripted maneuvers, tests, radios).
## "normal": the aircraft's controls.rates.normal (the manual's normal-flight dual rates and expo) shapes the keyboard
## sticks, and the travel alone the gamepad's (it has its own expo); a radio always passes through with its own rates.
## Aircraft without controls.rates fly their maximum throws under either name. The flight scene sets it (--rates=full).
var rate_profile := "full"
## Stick commands after shaping (−1…1, throttle 0…1), and the raw input sample they came from.
var commands := Commands.neutral_commands()
var raw := Commands.neutral_raw()
## read_raw() -> { roll, pitch, yaw, throttle }: the keyboard, sampled once per physics tick.
var read_raw: Callable = func() -> Dictionary: return Keyboard.read_raw()
## The radio (or joystick): flies instead of the keyboard while connected.
var radio := RcInput.new()
## read_axis(device, axis) -> float and device_info(device) -> { guid, name, vendor_id, product_id }. Replaceable in
## tests: Input.get_joy_guid on a device that does not exist prints an engine error.
var read_axis: Callable = func(device: int, axis: int) -> float: return Input.get_joy_axis(device, axis as JoyAxis)
var read_button: Callable = Input.is_joy_button_pressed
var device_info: Callable = func(device: int) -> Dictionary:
	var info := Input.get_joy_info(device)
	return { guid = Input.get_joy_guid(device), name = Input.get_joy_name(device),
		vendor_id = info.get("vendor_id", 0), product_id = info.get("product_id", 0), known = Input.is_joy_known(device) }
## Saved radio calibrations, one per device key.
var profiles_path := "user://rc_calibration.cfg"
## Interactive shell owns selection; technical sessions retain their explicit legacy test seams.
var external_controller_selection := false
var persist_controller_profile := Callable()
var persist_full_controller_profile := Callable()
var _controller_lost := false
var _pending_controller_start := -1.0
var controller_cut_held := false
## The calibration wizard while it runs, else null.
var calibration: RefCounted = null
## Source enable, stored with accepted simulation modes. Glow/electric shafts can coast or windmill
## while disabled; their continuous dynamics own RPM and passive propeller loads.
var engine_running: bool:
	get:
		return true if sim == null else sim.modes[0] == 1
	set(value):
		if sim != null:
			sim.modes[0] = 1 if value else 0
## After a crash the scene freezes this long (s, counted in physics ticks), showing the impact, then restarts.
const CRASH_HOLD_S := 1.5
## Presentation may retain the aftermath until explicit reset; technical sessions keep the legacy timer.
var crash_auto_restart := true
## E3d1: crash-hull points become soft ground contacts (HullContact): light touches continue the flight and only a
## C2-grade impact or a deep crush ends it. Off by default so trace, scripted and golden routes keep D9d's "any hull
## contact is a crash"; Main turns it on for interactive flights.
var soft_hull_contacts := false
var _hull_contact := {}
## E3d1 presentation feed: the hull points touching after the latest tick (HullContact.contacts); read-only.
var soft_contacts: Array = []
## E3d2: the propeller strike of this flight (empty until one): {tick, rpm, point_ned, velocity_ned}. The engine is
## stopped through engine_running (a simulation mode); presentation hides the broken blades.
var prop_strike: Dictionary = {}
var _prop_disc := {}
## AS-13: detached events at the last accepted tick; no force evaluation reads this history.
var _contact_bindings: Dictionary = {}
var _contact_tick: int = -1
var _contact_events: Array[Dictionary] = []
var _active_hull_ids := PackedStringArray()
var _resolving_contact: bool = false
var _committing_contacts: bool = false
var _pending_contact_tick: int = -1
var _pending_crash: ImpactSnapshot.Snapshot = null
var _pending_crash_state := PackedFloat64Array()
var _pending_scenery_event: SceneryCollision.Event = null
var _pending_lake_event: LakeCollision.WaterEvent = null
## The last crash while shown: CG speed/sink (m/s), ticks_left, why and a typed tick-boundary impact; empty while flying.
var crash := {}
## Latest launch outcome; diagnostic only, never consulted by a force evaluation.
var runway_start_outcome: Dictionary = {}
## Why the session paused the simulation ("" = it did not), for the panel.
var pause_reason := ""
## false: commands hold still (captures, headless traces).
var input_enabled := true
## Holds by name (UI-02: "menu"). While any is set the session is frozen: no input sampling, no crash countdown,
## the simulation paused. Releasing the last hold does not resume: continuing stays the pilot's explicit resume().
var holds := {}
## E3a: the field's surfaces as a flat table for the tyre forces (set_field); empty = dry pavement everywhere.
var ground_surfaces: PackedFloat64Array:
	get:
		return environment.surfaces
	set(value):
		environment.surfaces = value
## H2: last deflections built by _deflections() and the servo positions they belong to (cleared with each aircraft).
var _deflection_key := PackedFloat64Array()
var _deflection_cache := {}
## The field id the surfaces came from ("" = none: pavement), and why they could not be built ("" = fine).
var ground_field_id := ""
## M5-GE-1: CG height above the ground beyond which no wing strip is in ground effect; 0 = no aero.ground_effect module.
var _ground_effect_reach: float = 0.0
var surface_error := ""
## Detached scalar proxy inventory; empty keeps the legacy no-world path byte-for-byte unchanged.
var _collision_world: Dictionary = {}
var _last_scenery_event: SceneryCollision.Event = null
## Accepted, normalized lake geometry for this session only; empty disables lake terrain and collision queries.
var _lake: Dictionary:
	get:
		return environment.lake
	set(value):
		environment.lake = value
var _lake_bank_bounds: PackedFloat64Array = PackedFloat64Array()
var _last_lake_event: LakeCollision.WaterEvent = null
var _scenery_damage: Dictionary = {}
var _pending_scenery_damage: Dictionary = {}
var _pending_scenery_tick: int = -1
## false: no aircraft physics (the Stage 0/1 scripted circle). The simulation is disabled; input still shapes commands.
var physics_enabled := true


func _init() -> void:
	environment.turbulence = _turbulence_noise
	process_physics_priority = -1 # lower runs first: shape this tick's commands before the simulation steps


## Loads the aircraft, solves the trimmed start and creates the simulation. Call once, before adding to the tree.
## Workshop trials resolve once. Reload/reset must retain that exact immutable candidate.
var _frozen_aircraft: Dictionary = {}
var workshop_identity: Dictionary = {}


func setup(path := Scenarios.AIRCRAFT, expected_id: String = "", frozen_data: Dictionary = {}) -> void:
	aircraft_path = path
	expected_aircraft_id = expected_id
	_frozen_aircraft = frozen_data.duplicate(true)
	sim = Sim.new()
	sim.modes = PackedInt64Array([1])
	sim.faulted.connect(_on_sim_faulted)
	sim.stepped.connect(_on_sim_stepped)
	var prepared := _prepare_aircraft(_load_selected_aircraft())
	if prepared.ok:
		_commit_aircraft(prepared)
	else:
		_set_initial_failure(prepared)
	if not physics_enabled:
		sim.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(sim)
	reset()


func _load_selected_aircraft() -> Dictionary:
	return _frozen_aircraft.duplicate(true) if not _frozen_aircraft.is_empty() else AircraftData.load_file(aircraft_path)


func _ready() -> void:
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	if external_controller_selection:
		return
	radio.confirmed_gamepad_connection = _confirmed_direct_gamepad
	var pads := Input.get_connected_joypads()
	if not pads.is_empty():
		_on_joy_connection_changed(pads[0], true)


## Technical/direct flights have no ControllerService to certify live polling.
func _confirmed_direct_gamepad(id: int) -> bool:
	if external_controller_selection or not is_inside_tree() or not get_window().has_focus():
		return false
	if id != radio.device_id or not Input.get_connected_joypads().has(id) or not Input.is_joy_known(id):
		return false
	var info: Dictionary = device_info.call(id)
	return RcInput.key_for(id, info) == radio.device_key


func _input(event: InputEvent) -> void:
	radio.set_auxiliary_enabled(not sim.paused and calibration == null and holds.is_empty())
	if event is InputEventJoypadMotion:
		radio.on_motion(event.device, event.axis, event.axis_value)
	elif event is InputEventJoypadButton:
		radio.on_button(event.device, event.button_index, event.pressed)


func _on_joy_connection_changed(device: int, is_connected: bool) -> void:
	if external_controller_selection:
		if not is_connected and radio.connected and device == radio.device_id:
			controller_disconnected()
		return
	if is_connected and not radio.connected:
		var info: Dictionary = device_info.call(device)
		radio.connect_device(device, info, RcCalibration.load_profile(profiles_path, RcInput.key_for(device, info)))
		if radio.profile.get("kind", "") == "gamepad":
			var smoke_binding: Dictionary = RcCalibration.load_smoke_binding(profiles_path, radio.device_key)
			if not smoke_binding.is_empty():
				var gamepad_profile: Dictionary = radio.profile.duplicate(true)
				gamepad_profile.aux = {smoke = smoke_binding}
				radio.use_profile(gamepad_profile, "gamepad")
		print("radio connected: %s (%s profile)" % [radio.device_key, radio.profile_source])
	elif not is_connected and radio.connected and device == radio.device_id:
		calibration = null
		radio.disconnect_device()
		_failsafe("radio disconnected")


## [K]: start the radio calibration wizard. The simulation pauses and the engine idles until it is done.
func start_calibration() -> bool:
	if not radio.connected or radio.profile.get("kind", "") != "radio":
		return false
	calibration = RcCalibration.new(radio.profile)
	radio.set_auxiliary_enabled(false)
	_failsafe("calibrating radio")
	return true


## [Enter]: next calibration step. When the wizard finishes, the profile is used and saved for this device.
func advance_calibration() -> void:
	if calibration == null:
		return
	if calibration.advance(radio.axes):
		if external_controller_selection and persist_controller_profile.is_valid():
			var result: Dictionary = persist_controller_profile.call(calibration.profile)
			calibration = null
			pause_reason = "Radio calibrated. Lower throttle again before continuing." if result.get("ok", false) else "Calibration not saved: " + str(result.get("error", "storage error"))
			return
		radio.use_profile(calibration.profile, "calibrated")
		var err := RcCalibration.save_profile(profiles_path, radio.device_key, calibration.profile)
		calibration = null
		pause_reason = "radio calibrated%s" % ("" if err == OK else ", NOT saved (error %d)" % err)
		print(pause_reason, ": ", radio.device_key)


## [Esc]: abandon the wizard; the previous profile stays.
func cancel_calibration() -> void:
	if calibration != null:
		calibration = null
		pause_reason = "calibration cancelled"


## Engine to idle, sticks centred (trims stay, like a hands-off airplane), simulation paused until resume().
func _failsafe(reason: String) -> void:
	commands = Commands.neutral_commands()
	commands.throttle = 0.0
	raw = Commands.neutral_raw()
	sim.inputs = _inputs()
	sim.set_paused(true)
	pause_reason = reason
	print("failsafe: ", reason)


## Freezes the session for `reason` (a menu): inputs, crash countdown and simulation all stop where they are.
func hold(reason: String) -> void:
	radio.set_auxiliary_enabled(false)
	if external_controller_selection and not holds.has(reason) and radio.connected and radio.is_gamepad():
		radio.require_neutral(true)
	holds[reason] = true
	sim.set_paused(true)


## Lifts one hold. The flight stays paused until resume() (or the crash hold ends and restarts it).
func release(reason: String) -> void:
	holds.erase(reason)


## Compatibility preflight before a profile is persisted or activated.
func controller_profile_rejection(_profile: Dictionary) -> String:
	return ""


## Called only at a paused, explicit shell selection boundary; never by device enumeration.
func apply_controller_selection(device: int, info: Dictionary, profile: Dictionary, initial_start := false) -> bool:
	controller_cut_held = false
	var staged_throttle: float = float(commands.throttle) if initial_start else 0.0
	calibration = null
	radio.disconnect_device()
	_controller_lost = false
	_pending_controller_start = -1.0
	_failsafe("Controller selected; check controls and continue.")
	if device < 0:
		return true
	if profile.is_empty():
		_controller_lost = true
		pause_reason = "Configure the selected controller before flying."
		return false
	radio.connect_device(device, info, profile)
	if radio.is_rate_throttle():
		_pending_controller_start = staged_throttle
		pause_reason = "Continue at %d%% throttle." % roundi(staged_throttle * 100.0)
	return true


func controller_disconnected() -> void:
	controller_cut_held = false
	calibration = null
	radio.disconnect_device()
	_controller_lost = true
	_pending_controller_start = -1.0
	_failsafe("Controller lost. Select a controller or keyboard in Controls.")


func controller_focus_lost() -> void:
	if external_controller_selection and radio.connected:
		radio.set_auxiliary_enabled(false)
		radio.require_neutral(true, true)
		sim.set_paused(true)
		pause_reason = "Focus lost. Select Continue to resume."


func controller_throttle_cut() -> void:
	if radio.connected and radio.is_rate_throttle():
		radio.set_rate_throttle_for_start(0.0)
		_pending_controller_start = -1.0
		commands.throttle = 0.0
		sim.inputs = _inputs()


func set_controller_cut(held: bool) -> void:
	controller_cut_held = held
	if held: controller_throttle_cut()


## E3a: the wheels roll on this field's surfaces (a validated FieldLoader field). Invalid surface data refuses the
## flight (like invalid aircraft data). Returns false on failure; call reset() afterwards to restart on them.
func set_field(field: Dictionary, table_path := GroundSurfaces.DEFAULT_PATH) -> bool:
	var table := GroundSurfaces.load_table(table_path)
	var built := GroundSurfaces.build(table.table, field) if table.ok else table
	if not built.ok:
		surface_error = "ground surfaces invalid: " + str(built.errors[0] if not built.errors.is_empty() else "unknown")
		ground_surfaces = PackedFloat64Array()
		ground_field_id = ""
		_runway_field = {}
		pause_reason = surface_error
		sim.set_paused(true)
		printerr(surface_error)
		return false
	surface_error = ""
	ground_surfaces = built.rects
	ground_field_id = str(field.get("id", "?"))
	_runway_field = field.duplicate(true)
	return true


## Installs one normalized lake at a launch/reset boundary. Invalid or stale identities leave the current lake intact.
func set_lake_context(normalized_lake: Dictionary) -> bool:
	var next_lake: Dictionary = {}
	if not normalized_lake.is_empty():
		if not LakeSurface.is_valid_definition(normalized_lake):
			return false
		var expected_identity: String = LakeLoader.identity(normalized_lake)
		if expected_identity.is_empty() or expected_identity != str(normalized_lake.identity):
			return false
		next_lake = normalized_lake.duplicate(true)
	var old_identity: String = str(_lake.get("identity", ""))
	var next_identity: String = str(next_lake.get("identity", ""))
	if sim != null and sim.tick > 0 and next_identity != old_identity:
		return false
	_lake = next_lake
	_lake_bank_bounds = _polygon_bounds_ne(_lake.get("bank_ne_m", PackedFloat64Array()))
	_last_lake_event = null
	if sim != null and aircraft.get("ok", false):
		_hull_contact = _prepare_hull_contact()
	_sync_post_step()
	return true


## A detached normalized lake snapshot; callers cannot mutate the active session geometry.
func lake_context() -> Dictionary:
	return _lake.duplicate(true)


func _lake_identity() -> String:
	return str(_lake.get("identity", ""))


func _has_collision_query() -> bool:
	return not _lake.is_empty() or (not _collision_world.is_empty() and not _collision_world.proxies.is_empty())


func _polygon_bounds_ne(polygon: PackedFloat64Array) -> PackedFloat64Array:
	if polygon.size() < 2 or polygon.size() % 2 != 0:
		return PackedFloat64Array()
	var min_n: float = polygon[0]
	var max_n: float = polygon[0]
	var min_e: float = polygon[1]
	var max_e: float = polygon[1]
	for at in range(2, polygon.size(), 2):
		min_n = minf(min_n, polygon[at])
		max_n = maxf(max_n, polygon[at])
		min_e = minf(min_e, polygon[at + 1])
		max_e = maxf(max_e, polygon[at + 1])
	return PackedFloat64Array([min_n, max_n, min_e, max_e])


func _inside_lake_bank_bounds(north: float, east: float) -> bool:
	return _lake_bank_bounds.size() == 4 and north >= _lake_bank_bounds[0] and north <= _lake_bank_bounds[1] \
		and east >= _lake_bank_bounds[2] and east <= _lake_bank_bounds[3]


func _sync_post_step() -> void:
	if sim == null:
		return
	var dynamic_mass: bool = glow_is_active()
	sim.model.post_tick = Callable(self, "_resolve_collision_step") if _has_collision_query() and not dynamic_mass else Callable()
	sim.model.post_tick_joint = Callable(self, "_resolve_mass_contact_step") if dynamic_mass else Callable()


func _prepare_hull_contact() -> Dictionary:
	if glow_is_active():
		return HullContact.prepare_geometry(aircraft.model.crash_hull, _lake)
	return HullContact.prepare(aircraft.model.crash_hull, sim.mass, sim.inertia, _lake)


## Installs one normalized, detached world at a flight boundary. Proxy data contains scalar NED geometry only.
func set_collision_world(world: Dictionary) -> bool:
	if world.is_empty():
		if sim != null and sim.tick > 0 and not _collision_world.is_empty():
			return false
		var had_world := not _collision_world.is_empty()
		_collision_world = {}
		_last_scenery_event = null
		_clear_pending_scenery_damage()
		if had_world:
			_clear_scenery_damage()
		_sync_post_step()
		return true
	if typeof(world.get("format")) != TYPE_STRING or str(world.get("format")) != CollisionWorld.FORMAT \
			or typeof(world.get("identity")) != TYPE_STRING or str(world.get("identity")).is_empty() \
			or typeof(world.get("proxies")) != TYPE_ARRAY or typeof(world.get("bins")) != TYPE_DICTIONARY \
			or typeof(world.get("cell_size_m")) not in [TYPE_FLOAT, TYPE_INT] or float(world.cell_size_m) != CollisionWorld.CELL_SIZE_M:
		return false
	var identity := str(world.identity)
	var old_identity := str(_collision_world.get("identity", ""))
	if sim != null and sim.tick > 0 and identity != old_identity:
		return false
	if world.proxies.is_empty():
		if sim != null and sim.tick > 0 and not old_identity.is_empty():
			return false
		_collision_world = {}
		_last_scenery_event = null
		_clear_pending_scenery_damage()
		if identity != old_identity:
			_clear_scenery_damage()
		_sync_post_step()
		return true
	_collision_world = world.duplicate(true)
	_last_scenery_event = null
	if identity != old_identity:
		_clear_pending_scenery_damage()
		_clear_scenery_damage()
	_sync_post_step()
	return true


## Detached read view for crash wreck contacts and deterministic debugging.
func collision_world(active_only: bool = false) -> Dictionary:
	var view: Dictionary = _collision_world.duplicate(true)
	if not active_only or view.is_empty() or _scenery_damage.is_empty():
		return view
	var active_proxies: Array[Dictionary] = []
	for proxy: Dictionary in view.proxies:
		if not SceneryDamage.id_is_broken(_scenery_damage, str(proxy.get("damage_id", ""))):
			active_proxies.append(proxy)
	if active_proxies.size() == view.proxies.size():
		return view
	view.proxies = active_proxies
	view.bins = _collision_bins_for(active_proxies, float(view.cell_size_m))
	return view


func _collision_bins_for(proxies: Array[Dictionary], cell_size: float) -> Dictionary:
	var bins: Dictionary = {}
	for index: int in proxies.size():
		var proxy: Dictionary = proxies[index]
		var min_n: int = floori(float(proxy.bounds_north_min) / cell_size)
		var max_n: int = floori(float(proxy.bounds_north_max) / cell_size)
		var min_e: int = floori(float(proxy.bounds_east_min) / cell_size)
		var max_e: int = floori(float(proxy.bounds_east_max) / cell_size)
		var min_d: int = floori(float(proxy.bounds_down_min) / cell_size)
		var max_d: int = floori(float(proxy.bounds_down_max) / cell_size)
		for north_cell: int in range(min_n, max_n + 1):
			for east_cell: int in range(min_e, max_e + 1):
				for down_cell: int in range(min_d, max_d + 1):
					var key := "%d,%d,%d" % [north_cell, east_cell, down_cell]
					if not bins.has(key):
						bins[key] = PackedInt64Array()
					bins[key].append(index)
	return bins


## Detached damage snapshot for renderer state and checkpoint inspection.
func scenery_damage() -> Dictionary:
	return _scenery_damage.duplicate(true)


func last_scenery_event() -> SceneryCollision.Event:
	return _last_scenery_event


func last_lake_event() -> LakeCollision.WaterEvent:
	return _last_lake_event


## Whether this flight can fly at all: valid aircraft and start, no simulation fault (menus disable Continue).
func is_flyable() -> bool:
	return _flight_ready()


## Whether resume() would fly now: flyable, not held, not showing a crash.
func can_resume() -> bool:
	return holds.is_empty() and crash.is_empty() and _flight_ready() and not _controller_lost \
		and (not external_controller_selection or not radio.connected or radio.armed)


## The pilot's explicit "continue" (never automatic). Refused while a menu holds the session or a crash is shown
## (the crash restarts by itself; flying on would pass through the ground).
func resume() -> void:
	if not holds.is_empty() or not crash.is_empty():
		return
	if _controller_lost or (external_controller_selection and radio.connected and not radio.armed):
		return
	if not _has_valid_start():
		sim.set_paused(true)
		if pause_reason.is_empty():
			pause_reason = _start_failure_reason()
		return
	if not sim.fault_reason.is_empty():
		sim.set_paused(true)
		pause_reason = "simulation fault: " + sim.fault_reason
		return
	if external_controller_selection and radio.connected:
		if _pending_controller_start >= 0.0:
			radio.set_rate_throttle_for_start(_pending_controller_start)
			_pending_controller_start = -1.0
		commands = radio.sticks()
		raw = commands.duplicate()
		sim.inputs = _inputs()
	pause_reason = ""
	sim.set_paused(false)


## Prepares the complete aircraft/trim candidate without changing the active flight.
func _prepare_aircraft(data: Dictionary) -> Dictionary:
	var neutral_trims := { roll = 0.0, pitch = 0.0, yaw = 0.0 }
	if not data.get("ok", false):
		var error_text := "aircraft data invalid"
		if not data.get("errors", []).is_empty():
			error_text += ": " + str(data.errors[0])
		return { ok = false, data = data, start = { ok = false, message = error_text }, trims = neutral_trims, message = error_text }
	var model: Dictionary = data.get("model", {})
	if not expected_aircraft_id.is_empty() and data.get("input_identity", {}).get("format", "") != AircraftData.FORMAT:
		var contract_error := "selected aircraft requires " + AircraftData.FORMAT
		return {ok = false, data = data, start = {ok = false, message = contract_error}, trims = neutral_trims, message = contract_error}
	if not expected_aircraft_id.is_empty() and model.get("id", "") != expected_aircraft_id:
		var identity_error := "aircraft identity mismatch: selected '%s', loaded '%s'" % [expected_aircraft_id, model.get("id", "")]
		return {ok = false, data = data, start = {ok = false, message = identity_error}, trims = neutral_trims, message = identity_error}
	var electric: bool = Propulsion.is_electric(model.get("propulsion", {}))
	var glow: bool = Propulsion.is_glow(model.get("propulsion", {}))
	if glow and _shaft_explicit and not shaft_is_coupled():
		return {ok=false,data=data,start={ok=false},trims=neutral_trims,message="glow installation requires coupled-rk4"}
	if electric and _shaft_explicit and not shaft_is_coupled():
		return {ok = false, data = data, start = {ok = false}, trims = neutral_trims, message = "electric propulsion requires coupled-rk4"}
	if (electric or glow or (shaft_is_coupled() and _shaft_explicit)) and not _supports_coupled_shaft(model):
		return {ok = false, data = data, start = {ok = false}, trims = neutral_trims,
			message = "coupled-rk4 requires a propeller shaft model with positive carrier inertia"}
	if not _model_is_valid(model):
		var invalid_model := "aircraft model has invalid mass properties or control throws"
		return { ok = false, data = data, start = { ok = false, message = invalid_model }, trims = neutral_trims, message = invalid_model }
	var contact_binding: Dictionary = ContactContract.describe(model, soft_hull_contacts)
	if not contact_binding.ok:
		var contact_error: String = "aircraft contact contract: " + "; ".join(contact_binding.errors)
		return {ok = false, data = data, start = {ok = false}, trims = neutral_trims, message = contact_error}
	if electric and not _electric_step_supported(model):
		return {ok = false, data = data, start = {ok = false}, trims = neutral_trims,
			message = "electric source is too stiff for the selected timestep (source step ratio > 0.25); qualify a slower source or a finer solver"}
	if Turbine.is_continuous(model.propulsion) and not Turbine.step_supported(model.propulsion, sim.dt()):
		return {ok = false, data = data, start = {ok = false}, trims = neutral_trims,
			message = "turbine governor/schedule is too stiff for the selected timestep (step ratio > 0.25)"}
	# AV-09 qualifies the existing joint turbine RPM + wheel-speed layout.
	# Each aircraft declares its own start speed (the Stik's 15 m/s is the loader's default).
	var candidate_start := _selected_airborne_trim(model)
	if not candidate_start.get("ok", false):
		var trim_error := "trim: " + str(candidate_start.get("message", "trim failed"))
		return { ok = false, data = data, start = candidate_start, trims = neutral_trims, message = trim_error }
	if not Sim.state_is_valid(candidate_start.state):
		var invalid_state := "trim produced a nonfinite or malformed starting state"
		return { ok = false, data = data, start = { ok = false, message = invalid_state }, trims = neutral_trims, message = invalid_state }
	var candidate_trims := {
		roll = float(candidate_start.roll_command),
		pitch = float(candidate_start.pitch_command),
		yaw = float(candidate_start.get("yaw_command", 0.0)),
	}
	for value in [candidate_start.get("throttle", NAN), candidate_start.get("rpm", NAN), candidate_trims.roll, candidate_trims.pitch, candidate_trims.yaw]:
		if not is_finite(value):
			var nonfinite_trim := "trim produced a nonfinite throttle, rpm, or control trim"
			return { ok = false, data = data, start = { ok = false, message = nonfinite_trim }, trims = neutral_trims, message = nonfinite_trim }
	if not _candidate_loads_are_valid(model, candidate_start, candidate_trims):
		var bad_loads := "trimmed aircraft produces nonfinite or malformed initial loads"
		return { ok = false, data = data, start = { ok = false, message = bad_loads }, trims = neutral_trims, message = bad_loads }
	return { ok = true, data = data, start = candidate_start, trims = candidate_trims, message = "prepared" }


## Compatibility helper for in-memory callers. Invalid candidates leave the active flight untouched.
func _apply(data: Dictionary) -> bool:
	var prepared := _prepare_aircraft(data)
	if not prepared.ok:
		return false
	_commit_aircraft(prepared)
	return true


func _commit_aircraft(prepared: Dictionary) -> void:
	aircraft = prepared.data
	# SF-01: the session installs one VehicleModel. Propulsion and contact callbacks are configured on it below
	# through the kernel's compatibility properties; the laws themselves still live in this session.
	var vehicle: VehicleModel = VehicleModel.new()
	vehicle.input_size = _input_count()
	vehicle.identity = { vehicle = "fixed-wing", loads_law = Aero.LOADS_LAW }
	vehicle.loads = _loads
	vehicle.pre_tick = _pre_step
	vehicle.rotor_momentum = rotor_momentum
	vehicle.substeps = _substeps
	if not sim.set_model(vehicle):
		push_error("Cannot install the fixed-wing vehicle model")
	_gear_cache.clear()
	_gear_cache_fraction = -1.0
	_contact_bindings = ContactContract.describe(aircraft.model, soft_hull_contacts)
	if not _shaft_explicit:
		_shaft_integrator = "coupled-rk4" if Propulsion.is_electric(aircraft.model.propulsion) or glow_is_active() else "split"
	start = prepared.start
	trims = prepared.trims.duplicate(true)
	_has_committed_aircraft = true
	_trim_density = air_density(start.state)
	_trim_charge = engine_charge_ratio(start.state)
	sim.mass = aircraft.model.mass_kg
	sim.inertia = aircraft.model.inertia.duplicate()
	_hull_contact = _prepare_hull_contact()
	_prop_disc = HullContact.prop_disc(aircraft.model.propulsion)
	_deflection_key = PackedFloat64Array()
	_ground_effect_reach = GroundEffect.reach(aircraft.model)
	_configure_continuous_callbacks()
	_sync_post_step()
	for warning in aircraft.warnings:
		print("aircraft data warning: ", warning)


func _configure_continuous_callbacks() -> void:
	var prepared: Dictionary = PropulsionRuntime.prepare_callbacks(self)
	if not prepared.ok:
		push_error("Cannot prepare aircraft propulsion: " + str(prepared.get("errors", [])))
		return
	for field: String in PropulsionRuntime.CALLBACK_FIELDS:
		sim.model.set(field, prepared[field])
	var declared: Array[Dictionary] = []
	for event: Variant in prepared.get("events", []):
		declared.append(event)
	sim.model.events = declared


## Family-independent accepted-endpoint observation; never called from a force evaluation.
func propulsion_observation() -> Dictionary:
	return PropulsionRuntime.observe(self)


func _set_initial_failure(prepared: Dictionary) -> void:
	aircraft = prepared.get("data", {})
	start = prepared.get("start", { ok = false, message = prepared.get("message", "aircraft unavailable") })
	trims = prepared.get("trims", { roll = 0.0, pitch = 0.0, yaw = 0.0 }).duplicate(true)
	engine_running = false
	pause_reason = str(prepared.get("message", "aircraft unavailable"))
	printerr(pause_reason)


func _model_is_valid(model: Dictionary) -> bool:
	if not model.has("mass_kg") or not is_finite(float(model.mass_kg)) or model.mass_kg <= 0.0:
		return false
	var inertia: PackedFloat64Array = model.get("inertia", PackedFloat64Array())
	if inertia.size() != 6:
		return false
	for value in inertia:
		if not is_finite(value):
			return false
	var minor2 := inertia[0] * inertia[1] - inertia[3] * inertia[3]
	var determinant := inertia[0] * (inertia[1] * inertia[2] - inertia[5] * inertia[5]) \
		- inertia[3] * (inertia[3] * inertia[2] - inertia[4] * inertia[5]) \
		+ inertia[4] * (inertia[3] * inertia[5] - inertia[4] * inertia[1])
	if inertia[0] <= 0.0 or minor2 <= 0.0 or determinant <= 0.0 \
			or not is_finite(minor2) or not is_finite(determinant):
		return false
	var controls: Dictionary = model.get("controls", {})
	var throws: Dictionary = controls.get("throw_rad", {})
	for axis in ["aileron", "elevator", "rudder"]:
		if not throws.has(axis) or not is_finite(float(throws[axis])) or throws[axis] <= 0.0:
			return false
	return true


func _candidate_loads_are_valid(model: Dictionary, candidate_start: Dictionary, candidate_trims: Dictionary) -> bool:
	var f := Commands.neutral_commands()
	f.roll = candidate_trims.roll
	f.pitch = candidate_trims.pitch
	f.yaw = candidate_trims.yaw
	f.throttle = candidate_start.throttle
	var surfaces := Commands.surface_deflections_deg(f, model.controls.throw_deg)
	var deflections := Aero.deflections_from_surfaces(surfaces)
	var wind := PackedFloat64Array([0.0, 0.0, 0.0])
	var result: PackedFloat64Array = Dynamics.loads(candidate_start.state, model, deflections,
		candidate_start.rpm, air_density(candidate_start.state), wind)
	if result.size() != 6:
		return false
	for value in result:
		if not is_finite(value):
			return false
	var rotor := Dynamics.rotor_momentum(model, candidate_start.rpm)
	for value in rotor:
		if not is_finite(value):
			return false
	return true


func _start_failure_reason() -> String:
	if not surface_error.is_empty():
		return surface_error
	if not aircraft.get("ok", false):
		return "aircraft data is invalid"
	return "trimmed starting condition is invalid: " + str(start.get("message", "no valid trim"))


func _on_sim_faulted(reason: String) -> void:
	if _failures != null:
		_failures.rollback()
	_clear_pending_scenery_damage()
	_clear_pending_contacts()
	pause_reason = "simulation fault: " + reason


func _on_sim_stepped(tick: int, _time_s: float, _state: PackedFloat64Array,
		_loads: PackedFloat64Array, _inputs: PackedFloat64Array, _aux: PackedFloat64Array) -> void:
	# This connection precedes external observers: a rejected RK/contact candidate never announces an incident.
	var failure_activated: bool = _failures != null and tick > 0 and _failures.commit(tick)
	_committing_contacts = true
	_observe_contact_tick(tick)
	if _pending_contact_tick == tick:
		_last_scenery_event = _pending_scenery_event
		_last_lake_event = _pending_lake_event
		if _pending_crash != null:
			_crash(_pending_crash, _pending_crash_state)
		elif _pending_scenery_event != null:
			_append_contact_event(ContactEvents.impact_event(
				_pending_scenery_event, _contact_bindings, _impact_policy(_pending_scenery_event)))
	_clear_pending_contacts()
	var damage_changed: bool = _pending_scenery_tick == tick and not _pending_scenery_damage.is_empty()
	if damage_changed:
		for damage_id: String in _pending_scenery_damage:
			_scenery_damage[damage_id] = _pending_scenery_damage[damage_id].duplicate(true)
	_clear_pending_scenery_damage()
	if damage_changed:
		scenery_damage_changed.emit()
	_committing_contacts = false
	contact_events_changed.emit()
	if failure_activated:
		failure_changed.emit() # owner contact/scenery state is now checkpointable at the same accepted tick


func contact_events() -> Dictionary:
	return {format = "openrc-aircraft-contact-state v1", tick = _contact_tick,
		active_hull_ids = _active_hull_ids.duplicate(), events = _contact_events.duplicate(true),
		prop_strike = prop_strike.duplicate(true)}


func _observe_contact_tick(tick: int) -> void:
	_contact_tick = tick
	_contact_events.clear()
	if tick == 0:
		_active_hull_ids.clear()
		prop_strike = {}
	if not soft_hull_contacts or not aircraft.get("ok", false):
		_active_hull_ids.clear()
		return
	soft_contacts = HullContact.contacts(sim.previous, sim.state, _hull_contact)
	if soft_contacts.is_empty() and _active_hull_ids.is_empty():
		return
	var observed: Dictionary = ContactEvents.hull_events(soft_contacts, _contact_bindings, _active_hull_ids, tick)
	if not observed.ok:
		push_error("Aircraft contact events: " + str(observed.get("errors", [])))
		return
	_active_hull_ids = observed.active_ids
	if tick > 0:
		_contact_events.assign(observed.events)


func _append_contact_event(event: Dictionary) -> void:
	if event.is_empty():
		return
	# A terminal decision upgrades the same hull observation instead of duplicating the touch.
	for index in _contact_events.size():
		var existing: Dictionary = _contact_events[index]
		if existing.source == event.source and existing.contact_id == event.contact_id:
			_contact_events[index] = event.duplicate(true)
			if not _committing_contacts:
				contact_events_changed.emit()
			return
	_contact_events.append(event.duplicate(true))
	if not _committing_contacts:
		contact_events_changed.emit()


func _impact_policy(impact: ImpactSnapshot.Snapshot) -> String:
	if impact is LakeCollision.WaterEvent:
		return "lake-contact-v1:" + _lake_identity()
	if impact is SceneryCollision.Event:
		return "scenery-response-v1:" + SceneryDamage.POLICY_VERSION
	if impact.trigger == "gear_limit":
		return "gear-overtravel-terminal-v1"
	return HullContact.law() if soft_hull_contacts else "legacy-terminal-hull-v1"


func _clear_pending_contacts() -> void:
	_pending_contact_tick = -1
	_pending_crash = null
	_pending_crash_state = PackedFloat64Array()
	_pending_scenery_event = null
	_pending_lake_event = null


func _reset_contact_history() -> void:
	_contact_tick = -1
	_contact_events.clear()
	_active_hull_ids.clear()
	_clear_pending_contacts()


func _restore_contact_history(record: Dictionary) -> void:
	_contact_tick = int(record.tick)
	_active_hull_ids = record.active_hull_ids.duplicate()
	_contact_events.assign(record.events.duplicate(true))
	prop_strike = record.prop_strike.duplicate(true)
	_clear_pending_contacts()


func _contact_history_is_valid(value: Variant, snapshot: Dictionary) -> bool:
	if typeof(value) != TYPE_DICTIONARY:
		return false
	var record: Dictionary = value
	if record.size() != 5 or record.get("format") != "openrc-aircraft-contact-state v1" \
			or typeof(record.get("tick")) != TYPE_INT or record.tick != snapshot.tick \
			or typeof(record.get("active_hull_ids")) != TYPE_PACKED_STRING_ARRAY \
			or typeof(record.get("prop_strike")) != TYPE_DICTIONARY:
		return false
	if not ContactEvents.validate_events(record.get("events"), snapshot.tick, _contact_bindings):
		return false
	for event: Dictionary in record.events:
		if not _contact_event_context_is_valid(event):
			return false
		if event.event_type == "hull_contact" and (record.active_hull_ids.has(event.contact_id) == (event.lifecycle == "ended")):
			return false
	var expected_ids := _active_contacts_at(snapshot.state)
	if record.active_hull_ids != expected_ids:
		return false
	var strike: Dictionary = record.prop_strike
	if strike.is_empty():
		return true
	if not soft_hull_contacts or _prop_disc.is_empty() or strike.size() != 4 \
			or typeof(strike.get("tick")) != TYPE_INT or strike.tick < 0 or strike.tick > snapshot.tick \
			or typeof(strike.get("rpm")) not in [TYPE_FLOAT, TYPE_INT] \
			or not is_finite(float(strike.rpm)) or float(strike.rpm) < HullContact.STRIKE_MIN_RPM:
		return false
	for key: String in ["point_ned", "velocity_ned"]:
		if typeof(strike.get(key)) != TYPE_PACKED_FLOAT64_ARRAY or strike[key].size() != 3:
			return false
		for component: float in strike[key]:
			if not is_finite(component):
				return false
	return true


## Environment membership and selected policy are checked only at save/restore boundaries.
func _contact_event_context_is_valid(event: Dictionary) -> bool:
	match event.source:
		"hull":
			if event.event_type == "hull_contact" and not soft_hull_contacts:
				return false
			return event.policy == (HullContact.law() if soft_hull_contacts else "legacy-terminal-hull-v1")
		"gear":
			return event.policy == "gear-overtravel-terminal-v1"
		"propeller":
			return soft_hull_contacts and event.policy == HullContact.law()
		"lake":
			return not _lake.is_empty() and event.lake_id == str(_lake.id) \
				and event.policy == "lake-contact-v1:" + _lake_identity()
		"scenery":
			if event.policy != "scenery-response-v1:" + SceneryDamage.POLICY_VERSION:
				return false
			for proxy: Dictionary in _collision_world.get("proxies", []):
				if event.contact_id == str(proxy.get("id", "")):
					return event.get("obstacle_kind") == str(proxy.get("kind", "")) \
						and event.get("obstacle_part") == str(proxy.get("part", "")) \
						and event.get("response_class") == str(proxy.get("response_class", ""))
	return false


func _active_contacts_at(state: PackedFloat64Array) -> PackedStringArray:
	var ids := PackedStringArray()
	if soft_hull_contacts:
		for contact: Dictionary in HullContact.contacts(state, state, _hull_contact):
			ids.append(str(_contact_bindings.hull_probes[int(contact.index)].id))
	return ids


func _legacy_contact_history(snapshot: Dictionary) -> Dictionary:
	# Historical checkpoints lack presentation history. Seed ongoing contacts without inventing impacts.
	return {format = "openrc-aircraft-contact-state v1", tick = snapshot.tick,
		active_hull_ids = _active_contacts_at(snapshot.state), events = [], prop_strike = {}}


func _stage_scenery_damage(event: SceneryCollision.Event) -> void:
	if event == null or not SceneryDamage.profile_is_valid(event.damage_profile) \
			or event.damage_profile == "none" or event.damage_id.is_empty() \
			or not is_finite(event.impact_energy_j) or event.impact_energy_j < SceneryDamage.threshold_j(event.damage_profile):
		return
	var impact_state: String = SceneryDamage.impact_state(event.damage_profile, event.impact_energy_j)
	if impact_state.is_empty() or SceneryDamage.id_is_broken(_scenery_damage, event.damage_id):
		return
	if _pending_scenery_tick != event.tick:
		_clear_pending_scenery_damage()
		_pending_scenery_tick = event.tick
	_pending_scenery_damage[event.damage_id] = {
		profile = event.damage_profile,
		state = impact_state,
		tick = event.tick,
		energy_j = event.impact_energy_j,
		point_ned = event.point_ned.duplicate(),
		normal_ned = event.normal_ned.duplicate(),
		velocity_ned = event.velocity_ned.duplicate(),
		obstacle_id = event.obstacle_id,
	}


func _clear_pending_scenery_damage() -> void:
	_pending_scenery_damage.clear()
	_pending_scenery_tick = -1


func _clear_scenery_damage(emit_if_empty: bool = false) -> void:
	var changed := not _scenery_damage.is_empty()
	_scenery_damage.clear()
	_clear_pending_scenery_damage()
	if changed or emit_if_empty:
		scenery_damage_changed.emit()


## Re-trims at another condition ("level" at `speed`, or "glide" power-off) and makes it the start. For scripted
## maneuvers (tests, golden flights). Returns the Trim result.
func trim_at(speed: float, mode := "level") -> Dictionary:
	var m: Dictionary = aircraft.model
	var down_m: float = start.state[RB.POS + 2] if _has_valid_start() else -30.0
	var density: float = _weather.air_density(down_m)
	var charge: float = _weather.engine_charge_ratio(down_m)
	if not is_finite(density) or not is_finite(charge):
		return {ok = false, message = "starting altitude is outside the atmosphere's supported domain"}
	var t := Scenarios.trimmed_level_across_view(m, sim.gravity, m.controls.throw_rad, speed, density, charge) if mode == "level" \
		else Scenarios.trimmed_glide_across_view(m, sim.gravity, m.controls.throw_rad, speed, density, charge)
	if t.ok:
		t.state[RB.POS + 2] = down_m
		start = t
		_trim_density = density
		_trim_charge = charge
		trims = { roll = t.roll_command, pitch = t.pitch_command, yaw = t.get("yaw_command", 0.0) }
	return t


## Moves the start above the NED datum. reset() re-trims if the selected atmosphere changes with altitude.
func set_start_altitude(altitude: float) -> void:
	if start.get("ok", false) and is_finite(altitude) and Sim.state_is_valid(start.state):
		var s: PackedFloat64Array = start.state
		s[RB.POS + 2] = -altitude
		start.state = s


## [F5] Reloads the aircraft data file, re-trims and restarts: tune a coefficient without restarting the app.
## Invalid data keeps the current aircraft flying. Returns a message for the panel.
func reload() -> String:
	var prepared := _prepare_aircraft(_load_selected_aircraft())
	if not prepared.ok:
		return "reload failed; previous aircraft and flight retained: %s" % prepared.message
	if _failures != null and not _failures.accepts_profile(FailureCatalog.profile_for_model(prepared.data.model)):
		return "reload failed; the propulsion failure profile changed; start a new flight"
	if start_choice == START_RUNWAY:
		var runway_candidate: Dictionary = _validate_runway_candidate(prepared)
		if not runway_candidate.ok:
			return "reload failed; previous aircraft and flight retained: %s" % runway_candidate.message
	var old_flight: Dictionary = { data = aircraft, start = start, trims = trims.duplicate(true) }
	var old_snapshot: Dictionary = sim.checkpoint()
	var old_failures: Dictionary = _failures.snapshot() if _failures != null else {}
	var old_commands := commands.duplicate(true)
	var old_gear_controls := [_gear_requested_down, _wheel_brake_demand, _gear_request_inhibited]
	var old_flap_requested := _flap_requested
	var old_raw := raw.duplicate(true)
	var old_crash := crash.duplicate(true)
	var old_reason := pause_reason
	var old_start_error: String = start_error
	var old_launch_metadata: Dictionary = _launch_metadata.duplicate(true)
	var old_paused: bool = sim.paused
	var old_damage: Dictionary = _scenery_damage.duplicate(true)
	var old_contacts: Dictionary = contact_events()
	var old_soft_contacts: Array = soft_contacts.duplicate(true)
	var old_scenery_event: SceneryCollision.Event = _last_scenery_event
	var old_lake_event: LakeCollision.WaterEvent = _last_lake_event
	_commit_aircraft(prepared)
	reset()
	if not sim.fault_reason.is_empty():
		var reason: String = sim.fault_reason
		if old_snapshot.is_empty():
			return "aircraft reload failed during reset; simulation paused: %s" % reason
		_commit_aircraft(old_flight)
		if _restore_reload_checkpoint(old_snapshot):
			if _failures != null and not old_failures.is_empty():
				_failures.restore(old_failures, sim.tick)
			_restore_contact_history(old_contacts)
			soft_contacts = old_soft_contacts
			_last_scenery_event = old_scenery_event
			_last_lake_event = old_lake_event
			_scenery_damage = old_damage
			if not old_damage.is_empty():
				scenery_damage_changed.emit()
			commands = old_commands
			_gear_requested_down = old_gear_controls[0]
			_wheel_brake_demand = old_gear_controls[1]
			_gear_request_inhibited = old_gear_controls[2]
			_flap_requested = old_flap_requested
			raw = old_raw
			crash = old_crash
			pause_reason = old_reason
			start_error = old_start_error
			_launch_metadata = old_launch_metadata
			sim.set_paused(old_paused)
			contact_events_changed.emit()
			return "reload failed; previous aircraft and flight retained: " + reason
		return "aircraft reload failed during reset; simulation paused: %s" % reason
	if str(_launch_metadata.get("launch_choice", "")) == "runway":
		return "aircraft reloaded: runway start on field '%s'" % str(_launch_metadata.get("launch_field_id", ""))
	return "aircraft reloaded: trimmed at %.0f m/s, throttle %d %%" % [start.V, roundi(start.throttle * 100.0)]


func _restore_reload_checkpoint(snapshot: Dictionary) -> bool:
	if snapshot.is_empty() or not snapshot.has("state") or not snapshot.has("aux"):
		return false
	if sim.restore_checkpoint(snapshot):
		return true
	# Establish the previous aircraft's state-array widths and loads before validating the exact old tick boundary.
	sim.continuous = snapshot.get("continuous", PackedFloat64Array()).duplicate()
	sim.aux = snapshot.aux.duplicate()
	sim.inputs = snapshot.inputs.duplicate()
	sim.modes = snapshot.modes.duplicate()
	if not sim.reset(snapshot.state):
		return false
	return sim.restore_checkpoint(snapshot)


## Preflights the selected runway route before reload emits `resetting` or replaces active data.
func _validate_runway_candidate(prepared: Dictionary) -> Dictionary:
	if not surface_error.is_empty():
		return { ok = false, message = surface_error }
	if _runway_field.is_empty():
		return { ok = false, message = "runway start needs a loaded field" }
	var field_id: String = str(_runway_field.get("id", ""))
	if field_id != RUNWAY_FIELD_ID or ground_field_id != field_id:
		return { ok = false, message = "runway start is supported only on field '%s' (got '%s')" % [RUNWAY_FIELD_ID, field_id] }
	var data: Dictionary = prepared.get("data", {})
	if not data.get("ok", false):
		return { ok = false, message = "aircraft data is invalid" }
	var model: Dictionary = data.get("model", {})
	var model_id: String = str(model.get("id", ""))
	if not runway_aircraft_supported(model_id):
		return { ok = false, message = "runway start is supported only for qualified aircraft %s (got '%s')" % [str(RUNWAY_AIRCRAFT_IDS), model_id] }
	var gear: Dictionary = model.get("landing_gear", {})
	if gear.is_empty() or not gear.has("breakaway_factor") or gear.get("contacts", []).is_empty():
		return { ok = false, message = "runway start needs landing gear with stiction data" }
	var spot: Dictionary = GroundStart.threshold(_runway_field)
	if not spot.ok:
		return { ok = false, message = "runway start: " + str(spot.message) }
	var pilot_commands: Dictionary = Commands.neutral_commands()
	var candidate_trims: Dictionary = prepared.get("trims", {})
	pilot_commands.roll = clampf(float(candidate_trims.get("roll", 0.0)), -1.0, 1.0)
	pilot_commands.pitch = clampf(float(candidate_trims.get("pitch", 0.0)), -1.0, 1.0)
	pilot_commands.yaw = clampf(float(candidate_trims.get("yaw", 0.0)), -1.0, 1.0)
	pilot_commands.throttle = 0.0
	var input_values := PackedFloat64Array([pilot_commands.roll, pilot_commands.pitch, pilot_commands.yaw, 0.0])
	var surface_angles: Dictionary = Commands.surface_deflections_deg(pilot_commands, model.controls.throw_deg)
	var deflections: Dictionary = Aero.deflections_from_surfaces(surface_angles)
	var density: float = _weather.air_density(0.0)
	var charge: float = _weather.engine_charge_ratio(0.0)
	var rpm: float = 0.0 if Propulsion.is_glow(model.propulsion) else Propulsion.steady_rpm(0.0, 0.0, model.propulsion, density, charge)
	var solved: Dictionary = GroundStart.solve(model, ground_surfaces, float(spot.north), float(spot.east), float(spot.heading),
		deflections, input_values[2], rpm, density, sim.gravity, _initial_wind(), _model_wheel_count(model) > 0,
		environment_at if _weather.has_vertical_atmosphere() else Callable())
	return { ok = true, message = "" } if solved.ok else { ok = false, message = "runway start: " + str(solved.message) }


func _poll_controller(integrate := true) -> bool:
	radio.poll(read_axis, sim.dt(), read_button, integrate and not sim.paused and calibration == null and holds.is_empty())
	if external_controller_selection and (not radio.input_error.is_empty() or not radio.profile_error.is_empty()):
		controller_disconnected()
		pause_reason = "Invalid controller input. Review the device and select it again in Controls."
		return false
	return true


func _physics_process(_delta: float) -> void:
	if not holds.is_empty():
		if external_controller_selection and input_enabled and radio.connected:
			_poll_controller(false)
		return # frozen by a menu: no sampling (navigation keys never reach the flight), no crash countdown
	if external_controller_selection and sim.paused and calibration == null:
		if input_enabled and radio.connected:
			_poll_controller(false)
		return
	if input_enabled:
		if radio.connected and calibration != null:
			if not _poll_controller(): return
			calibration.sample(radio.axes)
		elif radio.connected:
			if not _poll_controller(): return
			var previous_yaw: float = commands.yaw
			commands = radio.sticks()
			# An unbound AUX defaults to zero: it must not override keyboard/controller toggles.
			if gear_is_retractable() and not sim.paused and not radio.profile.get("aux", {}).get("gear", {}).is_empty():
				_gear_requested_down = radio.auxiliary_amount("gear") < 0.5
			if flaps_available() and not sim.paused and not radio.profile.get("aux", {}).get("flaps", {}).is_empty():
				_flap_requested = radio.auxiliary_amount("flaps")
			if controller_cut_held:
				controller_throttle_cut()
				commands.throttle = 0.0
			raw = commands.duplicate()
			raw.throttle = radio.throttle_position() # the stick, even while the throttle is held at idle
			if radio.armed and radio.is_gamepad() and rates_active():
				var response: float = aircraft.model.controls.get("gamepad", {}).get("yaw_response_time", 0.0)
				if response > 0.0:
					commands.yaw = Commands.gamepad_yaw_response(previous_yaw, commands.yaw, sim.dt(), response)
		else:
			raw = read_raw.call()
			var keyboard: Dictionary = aircraft.model.controls.get("keyboard", {}) if rates_active() else {}
			commands = Commands.step_commands(commands, raw, sim.dt(), keyboard)
		sim.inputs = _inputs()
	# D9d: any crash-hull point at or below the ground is a crash. E1: the wheels are spring-damper contacts instead
	# (aircraft with a landing_gear section); a leg pushed past its travel is a crash too.
	if not crash.is_empty():
		if not crash_auto_restart:
			return
		crash.ticks_left -= 1
		if crash.ticks_left <= 0:
			reset()
		return
	if physics_enabled and not sim.paused and _flight_ready() and Sim.state_is_valid(sim.state):
		if soft_hull_contacts:
			soft_contacts = HullContact.contacts(sim.previous, sim.state, _hull_contact)
			# Glow terminal hull decisions already ran with the previous fuel snapshot inside the accepted tick.
			var hit: Dictionary = {index = -1} if glow_is_active() else HullContact.terminal(sim.previous, sim.state, _hull_contact)
			if int(hit.index) >= 0:
				_crash(ImpactSnapshot.hull_point(sim.state, sim.tick, aircraft.model.crash_hull, int(hit.index),
					sim.previous, str(hit.rule)))
			elif gear_collapsed(sim.state):
				_crash(_gear_limit_impact(sim.state))
			else:
				# Only a flight that goes on can lose its propeller: a crash freezes the checkpoint untouched.
				_check_prop_strike()
		elif touches_ground(sim.state):
			_crash(ImpactSnapshot.hull_contact(sim.state, sim.tick, aircraft.model.crash_hull, sim.previous))
		elif gear_collapsed(sim.state):
			_crash(_gear_limit_impact(sim.state))


## E3d2: a turning propeller whose disc reaches the field breaks: the engine stops (dead stick) and the flight goes on.
## Once per flight; scripted and trace routes never call it (soft_hull_contacts off).
func _check_prop_strike() -> void:
	if not prop_strike.is_empty() or not engine_running or _prop_disc.is_empty() or sim.aux[AUX_RPM] < HullContact.STRIKE_MIN_RPM:
		return
	var disc: Dictionary = HullContact.prop_disc_depth(sim.state, _prop_disc, _lake, float(sim.tick) * sim.dt())
	if float(disc.depth) <= 0.0:
		return
	var q := RB._att(sim.state)
	prop_strike = {tick = sim.tick, rpm = sim.aux[AUX_RPM], point_ned = disc.point_ned,
		velocity_ned = M.q_rotate(q, RB._slice3(sim.state, RB.VEL))}
	engine_running = false
	_append_contact_event(ContactEvents.strike_event(prop_strike, sim.tick, HullContact.law(), _contact_bindings))
	print("PROP STRIKE at %.0f rpm, %.1f m/s: engine stopped" % [prop_strike.rpm, M.norm(prop_strike.velocity_ned)])


## True when any landing-gear contact at state `s` is compressed past its travel (E1). Always false without gear.
func gear_collapsed(s: PackedFloat64Array) -> bool:
	if not Sim.state_is_valid(s) or not aircraft.get("ok", false):
		return false
	return Ground.collapsed(s, current_landing_gear(),
		ground_surfaces if wheel_count() > 0 else PackedFloat64Array(), _lake)


## Compression of each landing-gear contact at state `s` (m, ≤ 0 in the air), in data order; empty without gear.
func gear_compressions(s: PackedFloat64Array) -> PackedFloat64Array:
	if not Sim.state_is_valid(s) or not aircraft.get("ok", false):
		return PackedFloat64Array()
	return Ground.compressions(s, current_landing_gear(),
		ground_surfaces if wheel_count() > 0 else PackedFloat64Array(), _lake)


func _gear_limit_impact(s: PackedFloat64Array) -> ImpactSnapshot.Snapshot:
	var surfaces: PackedFloat64Array = ground_surfaces if wheel_count() > 0 else PackedFloat64Array()
	var gear: Dictionary = current_landing_gear()
	if _lake.is_empty():
		return ImpactSnapshot.gear_limit(s, sim.tick, gear, surfaces)
	var out: ImpactSnapshot.Snapshot = ImpactSnapshot.Snapshot.new()
	out.trigger = "gear_limit"
	out.tick = sim.tick
	out.detected_state = s.duplicate()
	var compressions: PackedFloat64Array = Ground.compressions(s, gear, surfaces, _lake)
	for index in compressions.size():
		var contact: Dictionary = gear.contacts[index]
		if compressions[index] <= float(contact.max_compression):
			continue
		out.point_index = index
		out.component_name = str(contact.get("name", ""))
		out.body_point = contact.position.duplicate()
		if is_finite(compressions[index]) and is_finite(float(contact.max_compression)):
			out.has_compression = true
			out.compression_m = compressions[index]
			out.travel_limit_m = float(contact.max_compression)
		break
	return out


## True when any crash-hull point of the airplane at state `s` is at or below the ground (NED down ≥ 0).
## Wheels are not hull points on aircraft with landing gear (E1): a wheel on the ground is a landing.
func touches_ground(s: PackedFloat64Array) -> bool:
	if not Sim.state_is_valid(s) or not aircraft.get("ok", false):
		return false
	var hull: PackedFloat64Array = aircraft.model.crash_hull
	var q := PackedFloat64Array([s[RB.ATT], s[RB.ATT + 1], s[RB.ATT + 2], s[RB.ATT + 3]])
	for i in range(0, hull.size(), 3):
		# down component of R(q)·p: third row of the body→NED rotation matrix
		var down := 2.0 * (q[1] * q[3] - q[0] * q[2]) * hull[i] + 2.0 * (q[2] * q[3] + q[0] * q[1]) * hull[i + 1] \
			+ (1.0 - 2.0 * (q[1] * q[1] + q[2] * q[2])) * hull[i + 2]
		var ground_down: float = 0.0
		if not _lake.is_empty():
			var world_point: PackedFloat64Array = M.add(RB._slice3(s, RB.POS), M.q_rotate(q, hull.slice(i, i + 3)))
			var point_north: float = world_point[0]
			var point_east: float = world_point[1]
			if _inside_lake_bank_bounds(point_north, point_east):
				var terrain: Dictionary = LakeSurface.sample_terrain_validated(_lake, point_north, point_east)
				if bool(terrain.get("covered", false)):
					ground_down = float(terrain.ground_down_m)
		if s[RB.POS + 2] + down >= ground_down:
			return true
	return false


## Swept contact interpolates position, velocity and rates plus normalized attitude.
## Fuel is linearly sampled at the same fraction; this is not event-substep integration.
## Existing response truncates body motion at impact while continuous state completes the tick.
## The sampler is pure; rejected candidates publish no contact, damage or continuous-state change.
func _resolve_mass_contact_step(previous: PackedFloat64Array, candidate: PackedFloat64Array,
		next_tick: int, previous_values: PackedFloat64Array, candidate_values: PackedFloat64Array) -> PackedFloat64Array:
	var sampler: Callable = _contact_mass_sampler(previous_values, candidate_values)
	if not sampler.is_valid():
		return PackedFloat64Array()
	return _resolve_collision_step(previous, candidate, next_tick, sampler)


func _contact_mass_sampler(previous_values: PackedFloat64Array, candidate_values: PackedFloat64Array) -> Callable:
	if not glow_is_active() or previous_values.size() != GlowFlight.SIZE + wheel_count() \
			or candidate_values.size() != previous_values.size():
		return Callable()
	var initial_fuel: float = aircraft.model.propulsion.glow.initial_fuel_kg
	var before: float = previous_values[1]
	var after: float = candidate_values[1]
	if not is_finite(before) or not is_finite(after) or before < 0.0 or after < 0.0 \
			or before > initial_fuel or after > initial_fuel:
		return Callable()
	return func(fraction: float) -> Dictionary:
		if not is_finite(fraction) or fraction < 0.0 or fraction > 1.0:
			return {ok = false, reason = "contact mass fraction is outside the tick"}
		return GlowFlight.properties(self, lerpf(before, after, fraction))


func _resolve_collision_step(previous: PackedFloat64Array, candidate: PackedFloat64Array,
		next_tick: int, mass_at_fraction: Callable = Callable()) -> PackedFloat64Array:
	_clear_pending_contacts()
	_pending_contact_tick = next_tick
	var accepted_scenery: SceneryCollision.Event = _last_scenery_event
	var accepted_lake: LakeCollision.WaterEvent = _last_lake_event
	_resolving_contact = true
	var filtered: PackedFloat64Array = _resolve_collision_candidate(previous, candidate, next_tick, mass_at_fraction)
	if mass_at_fraction.is_valid() and soft_hull_contacts and _pending_crash == null and Sim.state_is_valid(filtered) \
			and not _hull_contact.is_empty() and -filtered[RB.POS + 2] <= float(_hull_contact.reach):
		var properties_previous: Dictionary = mass_at_fraction.call(0.0)
		var terminal_result: Dictionary = HullContact.terminal_at_properties(previous, filtered, _hull_contact, properties_previous)
		var hit: Dictionary = terminal_result.get("event", {})
		if not terminal_result.get("ok", false):
			filtered = PackedFloat64Array()
		elif int(hit.index) >= 0:
			_crash(ImpactSnapshot.hull_point(filtered, next_tick, aircraft.model.crash_hull, int(hit.index),
				previous, str(hit.rule)), filtered)
	_resolving_contact = false
	_pending_scenery_event = _last_scenery_event
	_pending_lake_event = _last_lake_event
	_last_scenery_event = accepted_scenery
	_last_lake_event = accepted_lake
	return filtered


func _resolve_collision_candidate(previous: PackedFloat64Array, candidate: PackedFloat64Array,
		next_tick: int, mass_at_fraction: Callable = Callable()) -> PackedFloat64Array:
	_clear_pending_scenery_damage()
	if not _lake.is_empty():
		return _resolve_collision_step_with_lake(previous, candidate, next_tick, mass_at_fraction)
	if _collision_world.is_empty() or _collision_world.proxies.is_empty() or not aircraft.get("ok", false):
		_last_scenery_event = null
		return candidate
	var sampled: Dictionary = _scenery_hit(previous, candidate, next_tick, mass_at_fraction)
	if not sampled.ok:
		return PackedFloat64Array()
	var scenery_hit: SceneryCollision.Event = sampled.event
	var ground_hit: ImpactSnapshot.Snapshot = null
	var ground_fraction := INF
	# E3d1: with soft hull contacts the ground pushes back through the loads; the tick check decides crashes.
	if not soft_hull_contacts and touches_ground(candidate):
		ground_hit = ImpactSnapshot.hull_contact(candidate, next_tick, aircraft.model.crash_hull, previous)
		if ground_hit.point_index >= 0:
			ground_fraction = ground_hit.crossing.fraction if ground_hit.crossing != null and ground_hit.crossing.available else 0.0
	# Flat-ground contact wins a same-tick tie to preserve the existing ground-first policy.
	if ground_hit != null and ground_hit.point_index >= 0 and (scenery_hit == null \
			or ground_fraction <= scenery_hit.time_fraction + SceneryCollision.FRACTION_TIE):
		_last_scenery_event = null
		var contact_state := candidate
		if ground_hit.crossing != null and ground_hit.crossing.available:
			contact_state = SceneryCollision.state_at_fraction(previous, candidate, ground_fraction)
			ground_hit.detected_state = contact_state.duplicate()
		_crash(ground_hit, contact_state)
		return contact_state
	if scenery_hit == null:
		_last_scenery_event = null
		return candidate
	_last_scenery_event = scenery_hit
	_stage_scenery_damage(scenery_hit)
	var contact_state: PackedFloat64Array = scenery_hit.contact_state()
	if scenery_hit.terminal:
		scenery_hit.response_status = "terminal"
		_crash(scenery_hit, contact_state)
		return contact_state
	var response: Dictionary = _scenery_response(contact_state, scenery_hit)
	if not response.get("ok", false):
		scenery_hit.terminal = true
		scenery_hit.response_status = "response_failed_terminal"
		_crash(scenery_hit, contact_state)
		return contact_state
	scenery_hit.response_status = "dissipative_impulse"
	scenery_hit.restitution = float(response.restitution)
	scenery_hit.dissipated_energy_j = float(response.dissipated_energy_j)
	return response.state


func _resolve_collision_step_with_lake(previous: PackedFloat64Array, candidate: PackedFloat64Array,
		next_tick: int, mass_at_fraction: Callable = Callable()) -> PackedFloat64Array:
	if not aircraft.get("ok", false):
		_last_scenery_event = null
		_last_lake_event = null
		return candidate
	var scenery_hit: SceneryCollision.Event = null
	if not _collision_world.is_empty() and not _collision_world.proxies.is_empty():
		var sampled: Dictionary = _scenery_hit(previous, candidate, next_tick, mass_at_fraction)
		if not sampled.ok:
			return PackedFloat64Array()
		scenery_hit = sampled.event
	var lake_hit: LakeCollision.WaterEvent
	if mass_at_fraction.is_valid():
		var sampled_lake: Dictionary = LakeCollision.first_hit_sampled(_lake, previous, candidate,
			aircraft.model.crash_hull, current_landing_gear(), next_tick, sim.dt(), mass_at_fraction,
			soft_hull_contacts, _prop_disc)
		if not sampled_lake.ok:
			return PackedFloat64Array()
		lake_hit = sampled_lake.event
	else:
		lake_hit = LakeCollision.first_hit(_lake, previous, candidate,
			aircraft.model.crash_hull, current_landing_gear(), next_tick, sim.dt(), sim.mass,
			sim.inertia, soft_hull_contacts, _prop_disc)
	var ground_hit: ImpactSnapshot.Snapshot = null
	var ground_fraction: float = INF
	if not soft_hull_contacts:
		var dry_hit: Dictionary = _flat_ground_hit_outside_lake(previous, candidate, next_tick)
		ground_hit = dry_hit.get("impact")
		ground_fraction = float(dry_hit.get("fraction", INF))
	var winner: String = ""
	var winner_fraction: float = INF
	if scenery_hit != null:
		winner = "scenery"
		winner_fraction = scenery_hit.time_fraction
	# Scenery keeps a deterministic tie when both swept obstacle sets meet at the same fraction.
	if lake_hit != null and (winner.is_empty() \
			or lake_hit.time_fraction < winner_fraction - SceneryCollision.FRACTION_TIE):
		winner = "lake"
		winner_fraction = lake_hit.time_fraction
	# The legacy dry-ground-first tie is retained for ground outside the bounded bank.
	if ground_hit != null and ground_hit.point_index >= 0 \
			and ground_fraction <= winner_fraction + SceneryCollision.FRACTION_TIE:
		winner = "ground"
		winner_fraction = ground_fraction
	if winner.is_empty():
		_last_scenery_event = null
		_last_lake_event = null
		return candidate
	if winner == "ground":
		_last_scenery_event = null
		_last_lake_event = null
		var contact_state: PackedFloat64Array = candidate
		if ground_hit.crossing != null and ground_hit.crossing.available:
			contact_state = SceneryCollision.state_at_fraction(previous, candidate, winner_fraction)
			ground_hit.detected_state = contact_state.duplicate()
		_crash(ground_hit, contact_state)
		return contact_state
	if winner == "lake":
		_last_scenery_event = null
		_last_lake_event = lake_hit
		lake_hit.response_status = "terminal"
		_crash(lake_hit, lake_hit.contact_state())
		return lake_hit.contact_state()
	_last_lake_event = null
	_last_scenery_event = scenery_hit
	_stage_scenery_damage(scenery_hit)
	var scenery_state: PackedFloat64Array = scenery_hit.contact_state()
	if scenery_hit.terminal:
		scenery_hit.response_status = "terminal"
		_crash(scenery_hit, scenery_state)
		return scenery_state
	var response: Dictionary = _scenery_response(scenery_state, scenery_hit)
	if not response.get("ok", false):
		scenery_hit.terminal = true
		scenery_hit.response_status = "response_failed_terminal"
		_crash(scenery_hit, scenery_state)
		return scenery_state
	scenery_hit.response_status = "dissipative_impulse"
	scenery_hit.restitution = float(response.restitution)
	scenery_hit.dissipated_energy_j = float(response.dissipated_energy_j)
	return response.state


func _scenery_hit(previous: PackedFloat64Array, candidate: PackedFloat64Array,
		next_tick: int, mass_at_fraction: Callable) -> Dictionary:
	if mass_at_fraction.is_valid():
		return SceneryCollision.first_hit_sampled(previous, candidate, aircraft.model.crash_hull,
			_collision_world, next_tick, mass_at_fraction, _scenery_damage)
	return {ok = true, event = SceneryCollision.first_hit(previous, candidate, aircraft.model.crash_hull,
		_collision_world, next_tick, sim.mass, sim.inertia, _scenery_damage)}


func _scenery_response(body: PackedFloat64Array, hit: SceneryCollision.Event) -> Dictionary:
	if glow_is_active():
		var properties: Dictionary = hit.contact_mass_properties
		if not properties.get("ok", false):
			return {ok = false}
		return SceneryCollision.apply_response_properties(body, hit)
	return SceneryCollision.apply_response(body, hit, sim.mass, sim.inertia)


func _flat_ground_hit_outside_lake(previous: PackedFloat64Array, candidate: PackedFloat64Array,
		next_tick: int) -> Dictionary:
	var hull: PackedFloat64Array = aircraft.model.crash_hull
	var q: PackedFloat64Array = RB._att(candidate)
	var best: ImpactSnapshot.Snapshot = null
	var best_fraction: float = INF
	for index: int in range(0, hull.size(), 3):
		var body_point: PackedFloat64Array = hull.slice(index, index + 3)
		var point: PackedFloat64Array = M.add(RB._slice3(candidate, RB.POS), M.q_rotate(q, body_point))
		if point[2] < 0.0:
			continue
		var hit: ImpactSnapshot.Snapshot = ImpactSnapshot.hull_point(candidate, next_tick, hull, index / 3, previous)
		if hit.point_index < 0:
			continue
		var fraction: float = hit.crossing.fraction if hit.crossing != null and hit.crossing.available else 0.0
		var crossing_state: PackedFloat64Array = SceneryCollision.state_at_fraction(previous, candidate, fraction) \
			if hit.crossing != null and hit.crossing.available else candidate
		var crossing_point: PackedFloat64Array = M.add(RB._slice3(crossing_state, RB.POS),
			M.q_rotate(RB._att(crossing_state), body_point))
		if _inside_lake_bank_bounds(crossing_point[0], crossing_point[1]):
			var terrain: Dictionary = LakeSurface.sample_terrain_validated(_lake, crossing_point[0], crossing_point[1])
			if bool(terrain.get("covered", false)):
				continue # Lake terrain owns contacts inside its bank; flat ground must not mask its bed or shoreline.
		if best == null or fraction < best_fraction:
			best = hit
			best_fraction = fraction
	return {impact = best, fraction = best_fraction}


func _crash(impact: ImpactSnapshot.Snapshot, impact_state: PackedFloat64Array = PackedFloat64Array()) -> void:
	if _resolving_contact:
		# Engine modes already belong to Simulation's transaction and roll back on failure.
		if impact.trigger == "water":
			engine_running = false
		_pending_crash = impact
		_pending_crash_state = impact_state.duplicate()
		return
	var why: String = impact.description()
	if impact.trigger == "water":
		engine_running = false
	var s: PackedFloat64Array = impact_state if not impact_state.is_empty() else sim.state
	var speed := M.sqrt_(s[RB.VEL] ** 2 + s[RB.VEL + 1] ** 2 + s[RB.VEL + 2] ** 2)
	var prev: PackedFloat64Array = sim.previous
	var sink: float = (s[RB.POS + 2] - prev[RB.POS + 2]) / sim.dt()
	if not impact_state.is_empty():
		sink = M.q_rotate(RB._att(s), RB._slice3(s, RB.VEL))[2]
	crash = { speed = speed, sink = sink, ticks_left = roundi(CRASH_HOLD_S / sim.dt()), why = why, impact = impact }
	sim.set_paused(true)
	pause_reason = "CRASH at %.1f m/s (sink %.1f m/s%s) - %s" % [speed, sink, "" if why.is_empty() else ", " + why, "restarting" if crash_auto_restart else "[R] restart"]
	print(pause_reason)
	_append_contact_event(ContactEvents.impact_event(impact, _contact_bindings, _impact_policy(impact)))


func reset() -> void:
	if start_choice == START_RUNWAY:
		var result := _reset_selected_runway_start()
		runway_start_outcome = result.duplicate(true)
		if not result.ok:
			start_error = str(result.message)
			if not Sim.state_is_valid(sim.state):
				_fail_selected_start(start_error)
		elif external_controller_selection and radio.connected:
			_pending_controller_start = float(commands.throttle) if radio.is_rate_throttle() else -1.0
			radio.require_neutral(false)
			sim.set_paused(true)
			pause_reason = "Restart ready. Release controls and continue explicitly."
		return
	_shaft_pending_reset = false
	resetting.emit()
	_clear_scenery_damage(true)
	_reset_contact_history()
	soft_contacts = []
	prop_strike = {}
	crash = {}
	_last_scenery_event = null
	_last_lake_event = null
	if pause_reason.begins_with("CRASH"):
		pause_reason = ""
	start_error = ""
	var half_power_refit: bool = start_choice == START_HALF_POWER and start.get("requested_throttle", -1.0) != 0.5
	var start_density: float = air_density(start.get("state", PackedFloat64Array()))
	var start_charge: float = engine_charge_ratio(start.get("state", PackedFloat64Array()))
	if aircraft.get("ok", false) and (_trim_density != start_density or _trim_charge != start_charge or half_power_refit):
		var old_start: Dictionary = start
		var speed: float = float(old_start.get("V", aircraft.model.get("start_speed", 15.0)))
		if not is_finite(speed) or speed <= 0.0:
			speed = float(aircraft.model.get("start_speed", 15.0))
		var refit: Dictionary = _selected_airborne_trim(aircraft.model, _atmosphere_down(old_start.get("state", PackedFloat64Array()))) if start_choice == START_HALF_POWER else trim_at(speed, str(old_start.get("mode", "level")))
		if not refit.ok:
			start = refit
			_trim_density = NAN
			_trim_charge = NAN
			_fail_selected_start("atmosphere trim refused: " + str(refit.message))
			return
		if start_choice == START_HALF_POWER:
			start = refit
			_trim_density = start_density
			_trim_charge = start_charge
		if Sim.state_is_valid(old_start.get("state", PackedFloat64Array())):
			for axis: int in 3:
				start.state[RB.POS + axis] = old_start.state[RB.POS + axis]
	# D6e-R1: a restart must restore the solved equilibrium, including pilot-adjusted trim.
	if _has_valid_start():
		trims = {roll = start.roll_command, pitch = start.pitch_command, yaw = start.get("yaw_command", 0.0)}
	if start_choice == START_AIRBORNE or start_choice == START_HALF_POWER:
		_reset_airborne_start()
	elif start_choice == START_RUNWAY:
		var result: Dictionary = _reset_selected_runway_start()
		if not result.ok:
			_fail_selected_start(str(result.message))
	else:
		_fail_selected_start("unsupported start choice '%s'" % start_choice)
	if external_controller_selection and radio.connected:
		_pending_controller_start = float(commands.throttle) if radio.is_rate_throttle() else -1.0
		radio.require_neutral(false)
		sim.set_paused(true)
		pause_reason = "Restart ready. Release controls and continue explicitly."


## Rebuilds the ordinary trimmed flight without emitting a second reset signal.
func _reset_airborne_start() -> bool:
	_flap_requested = 0.0
	var gear_aux := _initial_gear_aux(false)
	if _failures != null:
		_failures.restart()
	var weather_aux: PackedFloat64Array = _restart_weather_aux()
	var initial: PackedFloat64Array = start.state.duplicate() if _has_valid_start() else PackedFloat64Array()
	if _has_valid_start() and not weather_is_calm():
		var attitude: PackedFloat64Array = M.quat(initial[RB.ATT], initial[RB.ATT + 1], initial[RB.ATT + 2], initial[RB.ATT + 3])
		var wind_body: PackedFloat64Array = M.q_rotate(M.q_conj(attitude), _initial_wind())
		for axis: int in 3:
			initial[RB.VEL + axis] += wind_body[axis]
	commands = Commands.neutral_commands()
	if _has_valid_start():
		commands.throttle = start.throttle
		engine_running = start.get("mode", "level") != "glide"
	else:
		engine_running = false
	# Inputs first: synchronous paths (capture, --trace) never tick this node, so they must start trimmed too.
	sim.inputs = _inputs()
	# Engine at its trimmed rpm and servos already at the trimmed surface positions.
	var aux := PackedFloat64Array([start.get("rpm", 0.0) if _has_valid_start() else 0.0, sim.inputs[0], sim.inputs[1], sim.inputs[2]])
	aux.resize(AUX_ANCHORS + anchor_count() * Ground.ANCHOR_STRIDE) # E3b1: every wheel starts sliding
	if downwash_index() >= 0 and _has_valid_start():
		aux.append(0.0)
	aux.append_array(gear_aux)
	if flaps_available(): aux.append(0.0)
	aux.append_array(weather_aux)
	sim.aux = aux
	if downwash_index() >= 0 and _has_valid_start():
		aux[downwash_index()] = _wing_cl(initial, aux, 0.0) # E0a2b: start settled, no downwash transient
	sim.aux = aux
	if _has_valid_start():
		sim.continuous = _settled_continuous(initial, aux)
		if not sim.reset(initial):
			sim.set_paused(true)
			var reason: String = "simulation reset failed: " + sim.fault_reason
			_fail_selected_start(reason)
			return false
		pause_reason = ""
		sim.set_paused(not holds.is_empty())
		_capture_launch("airborne", "trimmed_airborne", "", "")
		return true
	else:
		# An invalid initial candidate is parked in a valid, inert state. It never enters the throw/flying fallback.
		if not Sim.state_is_valid(sim.state):
			sim.reset(PackedFloat64Array([0.0, 0.0, -1000.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]))
		if pause_reason.is_empty():
			pause_reason = _start_failure_reason()
		sim.set_paused(true)
		# Trace/capture helpers may call step() directly, so the invalid initial condition must also block raw stepping.
		sim.fault_reason = pause_reason
		start_error = pause_reason
		_capture_launch("failed", "failed", "", start_error)
		return false


func _reset_selected_runway_start() -> Dictionary:
	if not surface_error.is_empty():
		return { ok = false, message = surface_error }
	if not aircraft.get("ok", false) or not start.get("ok", false):
		return { ok = false, message = _start_failure_reason() }
	var model_id: String = str(aircraft.model.get("id", ""))
	if not runway_aircraft_supported(model_id):
		return { ok = false, message = "runway start is supported only for qualified aircraft %s (got '%s')" % [str(RUNWAY_AIRCRAFT_IDS), model_id] }
	if _runway_field.is_empty():
		return { ok = false, message = "runway start needs a loaded field" }
	var field_id: String = str(_runway_field.get("id", ""))
	if field_id != RUNWAY_FIELD_ID or ground_field_id != field_id:
		return { ok = false, message = "runway start is supported only on field '%s' (got '%s')" % [RUNWAY_FIELD_ID, field_id] }
	if anchor_count() == 0:
		return { ok = false, message = "runway start needs landing gear with stiction data" }
	var spot: Dictionary = GroundStart.threshold(_runway_field)
	if not spot.ok:
		return { ok = false, message = "runway start: " + str(spot.message) }
	var result: Dictionary = _apply_runway_start(float(spot.north), float(spot.east), float(spot.heading))
	if not result.ok:
		return result
	_capture_launch("runway", "runway_threshold", field_id, "")
	return result


## Solves and installs a runway pose. It never selects or falls back to another start.
func _apply_runway_start(north: float, east: float, heading: float) -> Dictionary:
	if not _has_valid_start() or anchor_count() == 0:
		return {ok = false, status = "invalid_input", message = "runway start needs valid aircraft data, trim, and stiction gear"}
	var prop: Dictionary = aircraft.model.propulsion
	var density: float = _weather.air_density(0.0)
	var charge: float = _weather.engine_charge_ratio(0.0)
	var rpm: float = 0.0 if Propulsion.is_electric(prop) or Propulsion.is_glow(prop) else Propulsion.steady_rpm(0.0, 0.0, prop, density, charge)
	var inputs := PackedFloat64Array([clampf(trims.roll, -1.0, 1.0), clampf(trims.pitch, -1.0, 1.0), clampf(trims.yaw, -1.0, 1.0), 0.0])
	if gear_is_retractable():
		inputs.append_array(PackedFloat64Array([1.0, 0.0]))
	if flaps_available(): inputs.append(0.0)
	var aux := PackedFloat64Array([rpm, inputs[0], inputs[1], inputs[2]])
	# Solve first, without changing commands, modes, weather, crash state, or observers.
	var solved: Dictionary = GroundStart.solve(aircraft.model, ground_surfaces, north, east, heading, _deflections(aux), aux[AUX_SERVO+2],
		rpm, density, sim.gravity, _initial_wind(), wheel_count() > 0,
		environment_at if _weather.has_vertical_atmosphere() else Callable())
	if not solved.ok:
		solved.message = "runway start: " + str(solved.message)
		return solved
	aux.append_array(solved.anchors)
	if downwash_index() >= 0:
		aux.append(0.0)
	# Some existing force callbacks read the owner's sampled context. Stage only that
	# context synchronously, with no observer publication, and restore it on rejection.
	var saved := {}
	for key in ["commands", "_flap_requested", "_gear_requested_down", "_wheel_brake_demand", "_gear_request_inhibited", "_gear_cache_fraction", "_gear_cache",
		"_weather_pending_reset", "_turbulence_aux_index", "_deflection_key", "_deflection_cache"]:
		saved[key] = get(key)
	var old_aux: PackedFloat64Array = sim.aux
	var old_inputs: PackedFloat64Array = sim.inputs
	var old_continuous: PackedFloat64Array = sim.continuous
	var old_modes: PackedInt64Array = sim.modes.duplicate()
	var old_failures: RefCounted = _failures
	if old_failures != null:
		var fresh := FailureRuntime.new()
		if not fresh.restore(old_failures.snapshot(), sim.tick):
			return {ok = false, status = "invalid_input", message = "runway start: failure state cannot be prepared"}
		fresh.restart()
		_failures = fresh
	commands = Commands.neutral_commands()
	commands.throttle = 0.0 # match the solved runway inputs; neutral_commands defaults to airborne half power
	engine_running = not glow_is_active()
	sim.inputs = inputs
	aux.append_array(_initial_gear_aux(true))
	_flap_requested = 0.0
	if flaps_available(): aux.append(0.0)
	aux.append_array(_restart_weather_aux())
	sim.aux = aux
	if downwash_index() >= 0:
		aux[downwash_index()] = _wing_cl(solved.state, aux, 0.0)
	sim.aux = aux
	sim.continuous = _settled_continuous(solved.state, aux)
	var candidate: Dictionary = sim.prepare_reset(solved.state)
	if not candidate.ok:
		for key in saved:
			set(key, saved[key])
		sim.aux = old_aux
		sim.inputs = old_inputs
		sim.continuous = old_continuous
		sim.modes = old_modes
		_failures = old_failures
		return {ok = false, status = "numerical_unresolved", message = "runway start: " + str(candidate.message), diagnostics = solved.get("diagnostics", {})}
	# All validation has passed. This is the sole visible launch transaction.
	resetting.emit()
	_clear_scenery_damage(true)
	_reset_contact_history()
	soft_contacts = []
	prop_strike = {}
	crash = {}
	_last_scenery_event = null
	_last_lake_event = null
	_shaft_pending_reset = false
	pause_reason = ""
	start_error = ""
	sim.commit_prepared_reset(candidate)
	sim.set_paused(not holds.is_empty())
	solved.status = "converged"
	return solved


## Explicit launch transaction. A rejected attempt leaves the current flight intact.
## Rejection is diagnostic; the caller may separately choose an airborne fallback.
func try_runway_start(north: float, east: float, heading: float) -> Dictionary:
	var result := _apply_runway_start(north, east, heading)
	runway_start_outcome = result.duplicate(true)
	if result.ok:
		_capture_launch("runway", "runway_threshold", ground_field_id, "")
	else:
		start_error = str(result.message)
	return result


func _fail_selected_start(reason: String) -> void:
	_flap_requested = 0.0
	var gear_aux := _initial_gear_aux(false)
	start_error = reason if not reason.is_empty() else "requested start could not be prepared"
	pause_reason = start_error
	crash = {}
	commands = Commands.neutral_commands()
	commands.throttle = 0.0
	raw = Commands.neutral_raw()
	engine_running = false
	if sim != null:
		sim.inputs = _inputs()
		var parked := PackedFloat64Array([0.0, 0.0, -1000.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
		if _has_committed_aircraft:
			var aux := PackedFloat64Array([0.0, sim.inputs[0], sim.inputs[1], sim.inputs[2]])
			aux.resize(AUX_ANCHORS + anchor_count() * Ground.ANCHOR_STRIDE)
			if downwash_index() >= 0:
				aux.append(0.0)
			aux.append_array(gear_aux)
			if flaps_available(): aux.append(0.0)
			aux.append_array(_restart_weather_aux())
			sim.aux = aux
			if downwash_index() >= 0:
				aux[downwash_index()] = _wing_cl(parked, aux, 0.0)
			sim.continuous = _settled_continuous(parked, aux)
		else:
			sim.aux = PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
			sim.continuous = PackedFloat64Array()
		if not Sim.state_is_valid(sim.state) or _has_committed_aircraft:
			sim.reset(parked)
		sim.fault_reason = start_error
		sim.set_paused(true)
	_capture_launch("failed", "failed", str(_runway_field.get("id", "")), start_error)


func _capture_launch(actual_choice: String, launch_kind: String, field_id: String, error_text: String) -> void:
	var state_snapshot: PackedFloat64Array = sim.state.duplicate() if sim != null and Sim.state_is_valid(sim.state) else PackedFloat64Array()
	var aux_snapshot: PackedFloat64Array = sim.aux.slice(0, AUX_LAYOUT.size()) if sim != null else PackedFloat64Array()
	var continuous_snapshot: PackedFloat64Array = sim.continuous.duplicate() if sim != null else PackedFloat64Array()
	var anchor_snapshot: PackedFloat64Array = PackedFloat64Array()
	if sim != null and actual_choice == "runway":
		anchor_snapshot = sim.aux.slice(AUX_ANCHORS, AUX_ANCHORS + anchor_count() * Ground.ANCHOR_STRIDE)
	_launch_metadata = {
		"selected_start_choice": start_choice,
		"launch_choice": actual_choice,
		"launch_kind": launch_kind,
		"launch_field_id": field_id,
		"launch_state": JSON.stringify(Array(state_snapshot), "", true, true),
		"launch_aux": JSON.stringify(Array(aux_snapshot), "", true, true),
		"launch_continuous": JSON.stringify(Array(continuous_snapshot), "", true, true),
		"launch_ground_anchors": JSON.stringify(Array(anchor_snapshot), "", true, true),
		"launch_engine_running": JSON.stringify(engine_running),
		"launch_error": error_text,
	}


func _has_valid_start() -> bool:
	return aircraft.get("ok", false) and start.get("ok", false) and sim != null and surface_error.is_empty()


func _flight_ready() -> bool:
	return _has_valid_start() and not _weather_pending_reset and not _shaft_pending_reset and sim.fault_reason.is_empty()


## D6e: true while the aircraft's normal rate profile shapes the sticks (see rate_profile).
func rates_active() -> bool:
	return rate_profile == "normal" and aircraft.get("ok", false) and aircraft.model.controls.has("rates") \
		and not (radio.connected and not radio.is_gamepad())


## Manual elevator trim, degrees trailing edge up (+ = nose up). Only changes the command offset;
## the normal tick sampler and servo apply it. No force, attitude, throttle or speed is changed here.
func adjust_elevator_trim(delta_deg: float) -> bool:
	if not is_finite(delta_deg) or not physics_enabled or not input_enabled or not _flight_ready() \
			or sim.paused or not holds.is_empty() or not crash.is_empty() or calibration != null:
		return false
	var throw_deg: float = aircraft.model.controls.throw_deg.elevator
	trims.pitch = clampf(float(trims.pitch) + delta_deg / throw_deg, -1.0, 1.0)
	return true


## Keyboard trim in normalized maximum-throw units; the fault remains downstream of this command.
func adjust_aileron_trim(delta_units: float) -> bool:
	if not is_finite(delta_units) or not physics_enabled or not input_enabled or not _flight_ready() \
			or sim.paused or not holds.is_empty() or not crash.is_empty() or calibration != null:
		return false
	trims.roll = clampf(float(trims.roll) + delta_units, -1.0, 1.0)
	return true


## Stick commands plus trims in maximum-throw units. Reduced rates never attenuate the trim correction.
func flown_commands() -> Dictionary:
	var c := commands.duplicate()
	if rates_active():
		c = Commands.shape_sticks(c, aircraft.model.controls.rates.normal, not radio.connected)
		# Short gamepad sticks may have aircraft-specific normal pitch/yaw travel.
		# This is a fixed device setting; trim and physical radio travel remain independent.
		if radio.connected and radio.is_gamepad():
			c.pitch *= float(aircraft.model.controls.get("gamepad", {}).get("pitch_scale", 1.0))
			c.yaw *= float(aircraft.model.controls.get("gamepad", {}).get("yaw_scale", 1.0))
	c.roll = clampf(c.roll + trims.roll, -1.0, 1.0)
	c.pitch = clampf(c.pitch + trims.pitch, -1.0, 1.0)
	c.yaw = clampf(c.yaw + trims.yaw, -1.0, 1.0)
	return c


## The surfaces' actual positions (servo outputs) as commands { roll, pitch, yaw, throttle }: what the airplane flies
## with and what the renderer should draw. Without physics (scripted mode): the flown commands.
func surfaces() -> Dictionary:
	if not physics_enabled or not aircraft.get("ok", false):
		return flown_commands()
	var a: PackedFloat64Array = sim.aux
	return { roll = a[AUX_SERVO], pitch = a[AUX_SERVO + 1], yaw = a[AUX_SERVO + 2], throttle = propulsion_throttle() }


## Detached accepted trailing-edge angles in degrees. Renderers consume actual
## surface positions without reconstructing them from pilot commands or topology.
func surface_angles_deg() -> Dictionary:
	if not physics_enabled or not aircraft.get("ok", false):
		return Commands.surface_deflections_deg(flown_commands(), throws_deg())
	return _surface_angles_from_aux(sim.aux)


func _surface_angles_from_aux(a: PackedFloat64Array) -> Dictionary:
	return Commands.surface_deflections_deg({roll = a[AUX_SERVO], pitch = a[AUX_SERVO + 1],
		yaw = a[AUX_SERVO + 2]}, throws_deg())


## Maximum surface throws in degrees from the loaded aircraft ({} without valid data: Commands' default).
func throws_deg() -> Dictionary:
	return aircraft.model.controls.throw_deg if aircraft.get("ok", false) else {}


func _inputs() -> PackedFloat64Array:
	var f := flown_commands()
	var values := PackedFloat64Array([f.roll, f.pitch, f.yaw, f.throttle])
	if gear_is_retractable():
		values.append(1.0 if _gear_requested_down else 0.0)
		values.append(_wheel_brake_demand)
	if flaps_available(): values.append(_flap_requested)
	return values


func flaps_available() -> bool:
	return aircraft.get("ok", false) and Flaps.enabled(aircraft.model)


func _input_count() -> int:
	return 4 + (2 if gear_is_retractable() else 0) + (1 if flaps_available() else 0)


func flap_input_index() -> int:
	return (6 if gear_is_retractable() else 4) if flaps_available() else -1


func flap_aux_index() -> int:
	return (AUX_ANCHORS + anchor_count() * Ground.ANCHOR_STRIDE + (1 if downwash_index() >= 0 else 0)
		+ (GEAR_AUX_SIZE if gear_is_retractable() else 0)) if flaps_available() else -1


func _flap_aux_valid(values: PackedFloat64Array) -> bool:
	var index := flap_aux_index()
	return index >= 0 and values.size() > index and RetractableGear.valid_fraction(values[index])


func set_flaps(amount: float) -> bool:
	if not RetractableGear.valid_fraction(amount) or not flaps_available() or not physics_enabled \
			or not input_enabled or not _flight_ready() or sim.paused or not holds.is_empty() or not crash.is_empty():
		return false
	_flap_requested = amount
	return true


## Read-only status. The limit is advisory, not an automatic retraction or an invented damage law.
func flap_state() -> Dictionary:
	if not flaps_available() or sim == null or not _flap_aux_valid(sim.aux):
		return {available = false}
	var spec: Dictionary = aircraft.model.flaps
	var actual: float = sim.aux[flap_aux_index()]
	var requested: float = _flap_requested if input_enabled else sim.inputs[flap_input_index()]
	var speed: float = air_data(sim.state).V * M.sqrt_(air_density(sim.state) / 1.225)
	return {available = true, actual = actual, requested = requested,
		angle_deg = actual * spec.max_angle_deg, target_deg = requested * spec.max_angle_deg,
		moving = absf(actual - requested) > 1e-10, limit_mps = spec.max_speed_mps,
		overspeed = actual > 0.001 and speed > spec.max_speed_mps}


func gear_is_retractable() -> bool:
	return aircraft.get("ok", false) and RetractableGear.enabled(aircraft.model.get("landing_gear", {}))


func gear_aux_index() -> int:
	return AUX_ANCHORS + anchor_count() * Ground.ANCHOR_STRIDE + (1 if downwash_index() >= 0 else 0) if gear_is_retractable() else -1


func _gear_aux_valid(values: PackedFloat64Array) -> bool:
	var index := gear_aux_index()
	return index >= 0 and values.size() >= index + GEAR_AUX_SIZE \
		and RetractableGear.valid_fraction(values[index]) and values[index + 1] in [0.0, 1.0]


## Detached presentation/status of accepted actuator state. Commands are sampled at the next tick.
func gear_state() -> Dictionary:
	if not gear_is_retractable() or sim == null or not _gear_aux_valid(sim.aux):
		return {available = false, extension = 0.0, target_down = false, status = "unavailable", brake = 0.0, inhibited = false}
	var index := gear_aux_index()
	var extension: float = sim.aux[index]
	var target_down: bool = sim.aux[index + 1] == 1.0
	var status := "down" if extension == 1.0 else "up" if extension == 0.0 else "extending" if target_down else "retracting"
	return {available = true, extension = extension, target_down = target_down, status = status,
		brake = float(sim.inputs[5]) if sim.inputs.size() == _input_count() else 0.0,
		inhibited = _gear_request_inhibited or (sim.inputs.size() == _input_count() and sim.inputs[4] == 0.0 and target_down)}


func set_gear_down(down: bool) -> bool:
	if not gear_is_retractable() or not physics_enabled or not input_enabled or not _flight_ready() \
			or sim.paused or not holds.is_empty() or not crash.is_empty():
		return false
	if not down and _gear_weight_on_wheels(sim.aux):
		_gear_request_inhibited = true
		return false # simulator operator interlock, not a claimed pneumatic hardware feature
	_gear_requested_down = down
	_gear_request_inhibited = false
	return true


func toggle_gear() -> bool:
	return set_gear_down(not _gear_requested_down)


func set_wheel_brake(amount: float) -> bool:
	if not RetractableGear.valid_fraction(amount):
		return false
	if amount == 0.0:
		_wheel_brake_demand = 0.0 # releases clear even while a menu/focus hold is active
		return true
	if not gear_is_retractable() or not physics_enabled or not input_enabled or not _flight_ready() \
			or sim.paused or not holds.is_empty() or not crash.is_empty():
		return false
	_wheel_brake_demand = amount
	return true


func _gear_weight_on_wheels(values: PackedFloat64Array) -> bool:
	if not _gear_aux_valid(values) or values[gear_aux_index()] != 1.0 or not Sim.state_is_valid(sim.state):
		return false
	for compression: float in Ground.compressions(sim.state, aircraft.model.landing_gear, ground_surfaces, _lake):
		if compression > 1.0e-5:
			return true
	return false


## Same admitted contact geometry for loads, crash limits and presentation.
func current_landing_gear(values := PackedFloat64Array()) -> Dictionary:
	if not aircraft.get("ok", false):
		return {}
	var original: Dictionary = aircraft.model.get("landing_gear", {})
	if not gear_is_retractable():
		return original
	var sampled: PackedFloat64Array = sim.aux if values.is_empty() else values
	if not _gear_aux_valid(sampled):
		return {}
	var extension: float = sampled[gear_aux_index()]
	if extension != _gear_cache_fraction:
		_gear_cache = RetractableGear.pose(original, extension)
		_gear_cache_fraction = extension
	return _gear_cache


func _initial_gear_aux(down: bool) -> PackedFloat64Array:
	_gear_requested_down = down
	_wheel_brake_demand = 0.0
	_gear_request_inhibited = false
	_gear_cache_fraction = -1.0
	return PackedFloat64Array([1.0 if down else 0.0, 1.0 if down else 0.0]) if gear_is_retractable() else PackedFloat64Array()


## Simulation loads: aerodynamics (D3) + propulsion (D5) from the servos' actual positions, in calm air, plus the
## landing gear's ground contacts (E1) while a wheel pushes on the ground (nothing is added in the air), with tyre
## friction and the nose wheel steered by the rudder servo's actual position (E2), scaled by the surface under each
## wheel (E3a).
func _loads(s: PackedFloat64Array, t: float) -> PackedFloat64Array:
	if turbine_is_continuous():
		var result: Dictionary = _turbine_evaluate(s, sim.continuous, t)
		return result.get("loads", PackedFloat64Array([NAN, NAN, NAN, NAN, NAN, NAN]))
	return _wash_loads(s, sim.continuous, t)


## Fixed layout: one turbine RPM, then optional wheel rim speeds. No independent aux rotor state.
func _turbine_rpm(values: PackedFloat64Array) -> float:
	if values.size() != 1 + wheel_count():
		return NAN
	var rpm: float = values[0]
	return rpm if is_finite(rpm) and rpm >= 0.0 and rpm <= float(aircraft.model.propulsion.max_rpm) else NAN


func _turbine_aux(values: PackedFloat64Array, sampled: PackedFloat64Array) -> PackedFloat64Array:
	var rpm: float = _turbine_rpm(values)
	if not is_finite(rpm) or sampled.size() < AUX_ANCHORS:
		return PackedFloat64Array([NAN])
	var out: PackedFloat64Array = sampled.duplicate()
	out[AUX_RPM] = rpm
	return out


## Pure RK stage response, using this stage's RPM, air velocity, body state and time.
## Mounting reaction is unchanged: gyro only; gas angular-momentum flux is still unmeasured (AV-26).
func _turbine_evaluate(s: PackedFloat64Array, values: PackedFloat64Array, stage_time: float) -> Dictionary:
	var rpm: float = _turbine_rpm(values)
	if sim.modes.size() != (2 if _weather.has_turbulence() else 1) or sim.modes[0] not in [0, 1]:
		return {}
	if not is_finite(rpm) or (not engine_running and rpm != 0.0):
		return {} # A hot cutoff needs AV-05b; do not invent a cold/hot rundown law here.
	var prop: Dictionary = aircraft.model.propulsion
	var a: PackedFloat64Array = sim.aux
	var air: Dictionary = air_data(s, stage_time)
	var density: float = air_density(s)
	var inlet_air: PackedFloat64Array = Turbine.local_intake_velocity(air.v_air,
		s.slice(RB.RATE, RB.RATE + 3), prop)
	var turbine_loads: PackedFloat64Array = Turbine.loads(inlet_air, rpm, prop, density)
	var lag: int = downwash_index()
	var out: PackedFloat64Array = Dynamics.loads_from_air(s, aircraft.model, _deflections(a), rpm,
		density, air, a[lag] if lag >= 0 and lag < a.size() else NAN, PackedFloat64Array(), _ground_up(s), turbine_loads)
	if out.size() != 6:
		return {}
	var ground: Dictionary = _ground_evaluation(s, a, values, air if gear_is_retractable() else {})
	if not ground.get("ok", false):
		return {}
	var ground_loads: PackedFloat64Array = ground.loads
	for at: int in ground_loads.size():
		out[at] += ground_loads[at]
	var rate: float = Turbine.spool_rate(rpm, Turbine.demand_rpm(propulsion_throttle(), prop), prop) if engine_running else 0.0
	var derivative := PackedFloat64Array([rate])
	derivative.append_array(ground.derivative)
	return {loads = out, derivative = derivative, rotor_momentum = Turbine.rotor_momentum(rpm, prop)}


## Accepted-endpoint engine observations. Flow is the current map estimate; prescribed fuel never depletes mass.
func turbine_state() -> Dictionary:
	if not aircraft.get("ok", false) or not Turbine.is_turbine(aircraft.model.propulsion) or not _flight_ready():
		return {ok = false}
	if sim.modes.size() != (2 if _weather.has_turbulence() else 1) or sim.modes[0] not in [0, 1]:
		return {ok = false}
	var prop: Dictionary = aircraft.model.propulsion
	var rpm: float = _turbine_rpm(sim.continuous) if turbine_is_continuous() else sim.aux[AUX_RPM]
	if not is_finite(rpm) or (turbine_is_continuous() and not engine_running and rpm != 0.0):
		return {ok = false}
	var air: Dictionary = air_data(sim.state, sim.time())
	var inlet_air: PackedFloat64Array = Turbine.local_intake_velocity(air.v_air,
		sim.state.slice(RB.RATE, RB.RATE + 3), prop)
	var density: float = air_density()
	var axial_speed: float = M.dot(inlet_air, prop.axis)
	return {ok = true, tick = sim.tick, time_s = sim.time(), rpm = rpm,
		demand_rpm = Turbine.demand_rpm(propulsion_throttle(), prop) if engine_running else 0.0,
		engine_running = engine_running, axial_airspeed_m_s = axial_speed,
		intake_air_velocity_body_m_s = inlet_air,
		mass_flow_kg_s = Turbine.mass_flow(rpm, prop, density, axial_speed),
		gross_thrust_n = Turbine.gross_thrust(rpm, prop, density, axial_speed),
		net_thrust_n = Turbine.thrust(rpm, axial_speed, prop, density),
		fuel_flow_kg_s = Turbine.fuel_flow(rpm, prop), fuel_mass_policy = "prescribed_fuel"}


func _wash_loads(s: PackedFloat64Array, transported_dv: PackedFloat64Array, stage_time: float) -> PackedFloat64Array:
	var prop: Dictionary = aircraft.model.propulsion
	var expected: int = prop.slipstream.pieces.size() if WashTransport.enabled(prop) else 0
	if transported_dv.size() != expected + wheel_count():
		return PackedFloat64Array([NAN, NAN, NAN, NAN, NAN, NAN]) # Simulation rejects before any piece indexing.
	var a: PackedFloat64Array = sim.aux
	var lag := downwash_index()
	var wash_state: PackedFloat64Array = transported_dv if wheel_count() == 0 else transported_dv.slice(0, expected)
	var out := Dynamics.loads(s, aircraft.model, _deflections(a), a[AUX_RPM],
		air_density(s), wind_at(stage_time), a[lag] if lag >= 0 and lag < a.size() else NAN, wash_state, _ground_up(s))
	var ground: Dictionary = _ground_evaluation(s, a, transported_dv, air_data(s, stage_time) if gear_is_retractable() else {})
	if not ground.get("ok", false):
		return PackedFloat64Array([NAN, NAN, NAN, NAN, NAN, NAN])
	var ground_loads: PackedFloat64Array = ground.loads
	for i in ground_loads.size():
		out[i] += ground_loads[i]
	return out


## Continuous wash uses stage airspeed and state, with the existing sampled RPM/servo policy.
func _wash_derivative(s: PackedFloat64Array, lagged: PackedFloat64Array, stage_time: float) -> PackedFloat64Array:
	if wheel_count() == 0:
		var legacy_air: Dictionary = air_data(s, stage_time)
		return WashTransport.derivative(legacy_air.v_air, sim.aux[AUX_RPM], aircraft.model.propulsion, air_density(s), lagged)
	var expected: int = _rotor_index()
	if lagged.size() != expected + wheel_count():
		return PackedFloat64Array([NAN])
	var air: Dictionary = air_data(s, stage_time)
	var out: PackedFloat64Array = WashTransport.derivative(air.v_air, sim.aux[AUX_RPM], aircraft.model.propulsion,
		air_density(s), lagged.slice(0, expected)) if expected > 0 else PackedFloat64Array()
	var ground: Dictionary = _ground_evaluation(s, sim.aux, lagged, air_data(s, stage_time) if gear_is_retractable() else {})
	if not ground.get("ok", false):
		return PackedFloat64Array([NAN])
	out.append_array(ground.derivative)
	return out


## The wheel-enabled split path shares one terrain evaluation for loads and rim-speed derivatives at each RK stage.
func _wheel_evaluate(s: PackedFloat64Array, values: PackedFloat64Array, stage_time: float) -> Dictionary:
	var expected: int = _rotor_index()
	if wheel_count() == 0 or values.size() != expected + wheel_count():
		return {}
	var a: PackedFloat64Array = sim.aux
	var lag: int = downwash_index()
	var out: PackedFloat64Array = Dynamics.loads(s, aircraft.model, _deflections(a), a[AUX_RPM],
		air_density(s), wind_at(stage_time), a[lag] if lag >= 0 and lag < a.size() else NAN, values.slice(0, expected),
		_ground_up(s))
	var ground: Dictionary = _ground_evaluation(s, a, values, air_data(s, stage_time) if gear_is_retractable() else {})
	if not ground.get("ok", false):
		return {}
	var ground_loads: PackedFloat64Array = ground.loads
	for i in ground_loads.size():
		out[i] += ground_loads[i]
	var air: Dictionary = air_data(s, stage_time)
	var derivative: PackedFloat64Array = WashTransport.derivative(air.v_air, a[AUX_RPM],
		aircraft.model.propulsion, air_density(s), values.slice(0, expected)) if expected > 0 else PackedFloat64Array()
	derivative.append_array(ground.derivative)
	if derivative.size() != values.size():
		return {}
	return {loads = out, derivative = derivative, rotor_momentum = rotor_momentum(a)}


## Legacy gear keeps its original contact law; a file-backed wheel profile opts into terrain and wheel-spin state.
func _ground_evaluation(s: PackedFloat64Array, aux: PackedFloat64Array, values: PackedFloat64Array, stage_air: Dictionary = {}) -> Dictionary:
	if gear_is_retractable() and (not _gear_aux_valid(aux) or sim.inputs.size() != _input_count() or stage_air.is_empty()):
		return {ok = false, loads = PackedFloat64Array([NAN]), derivative = PackedFloat64Array([NAN])}
	var gear: Dictionary = current_landing_gear(aux)
	var steer: float = aux[AUX_SERVO + 2]
	var brake: float = sim.inputs[5] if gear_is_retractable() else 0.0
	var anchors: PackedFloat64Array = aux.slice(AUX_ANCHORS, AUX_ANCHORS + anchor_count() * Ground.ANCHOR_STRIDE)
	var hull: PackedFloat64Array = PackedFloat64Array()
	if soft_hull_contacts:
		if glow_is_active():
			if _hull_contact.is_empty() or values.size() < GlowFlight.SIZE:
				return {ok = false, loads = PackedFloat64Array([NAN]), derivative = PackedFloat64Array([NAN])}
			# Geometry reach is independent of fuel; avoid any new mass/contact work in free flight.
			if -s[RB.POS + 2] <= float(_hull_contact.reach):
				var sampled: Dictionary = HullContact.loads_at_properties(s, _hull_contact, GlowFlight.properties(self, values[1]))
				if not sampled.get("ok", false):
					return {ok = false, loads = PackedFloat64Array([NAN]), derivative = PackedFloat64Array([NAN])}
				hull = sampled.loads
				if hull.size() not in [0, 6]:
					return {ok = false, loads = PackedFloat64Array([NAN]), derivative = PackedFloat64Array([NAN])}
		else:
			hull = HullContact.loads(s, _hull_contact)
		for value: float in hull:
			if not is_finite(value):
				return {ok = false, loads = PackedFloat64Array([NAN]), derivative = PackedFloat64Array([NAN])}
	if gear_is_retractable():
		hull = _add_loads(hull, RetractableGear.drag_loads(s, stage_air.v_air, aircraft.model.landing_gear, aux[gear_aux_index()], air_density(s)))
	if wheel_count() == 0:
		return {ok = true, loads = _add_loads(Ground.loads(s, gear, steer, ground_surfaces, anchors,
			PackedFloat64Array(), brake, _lake), hull), derivative = PackedFloat64Array()}
	if values.size() != wheel_index() + wheel_count():
		return {ok = false, loads = PackedFloat64Array([NAN]), derivative = PackedFloat64Array([NAN])}
	var speeds: PackedFloat64Array = values.slice(wheel_index(), wheel_index() + wheel_count())
	for speed in speeds:
		if not is_finite(speed):
			return {ok = false, loads = PackedFloat64Array([NAN]), derivative = PackedFloat64Array([NAN])}
	var evaluation: Dictionary = Ground.evaluate(s, gear, steer, ground_surfaces, anchors, speeds, brake, false, _lake)
	var loads: PackedFloat64Array = evaluation.get("loads", PackedFloat64Array())
	var rates: PackedFloat64Array = evaluation.get("derivative", PackedFloat64Array())
	if (not loads.is_empty() and loads.size() != 6) or rates.size() != wheel_count():
		return {ok = false, loads = PackedFloat64Array([NAN]), derivative = PackedFloat64Array([NAN])}
	for value in loads:
		if not is_finite(value):
			return {ok = false, loads = PackedFloat64Array([NAN]), derivative = PackedFloat64Array([NAN])}
	for value in rates:
		if not is_finite(value):
			return {ok = false, loads = PackedFloat64Array([NAN]), derivative = PackedFloat64Array([NAN])}
	evaluation.ok = true
	evaluation.loads = _add_loads(loads, hull)
	return evaluation


## Sums two optional 6-entry body load arrays; an empty array adds nothing (a free flight stays bit-identical).
static func _add_loads(a: PackedFloat64Array, b: PackedFloat64Array) -> PackedFloat64Array:
	if b.is_empty():
		return a
	if a.is_empty():
		return b
	var out := a.duplicate()
	for i in 6:
		out[i] += b[i]
	return out


func _settled_wash(s: PackedFloat64Array, aux: PackedFloat64Array) -> PackedFloat64Array:
	if not WashTransport.enabled(aircraft.model.propulsion):
		return PackedFloat64Array()
	var air: Dictionary = air_data(s, 0.0)
	return WashTransport.settled(air.v_air, aux[AUX_RPM], aircraft.model.propulsion, air_density(s))


func _settled_continuous(s: PackedFloat64Array, aux: PackedFloat64Array) -> PackedFloat64Array:
	if glow_is_active():
		var glow_values: PackedFloat64Array=GlowFlight.initial(self,aux,s)
		for _i in wheel_count(): glow_values.append(0.0)
		return glow_values
	var out: PackedFloat64Array = _settled_wash(s, aux)
	if turbine_is_continuous():
		out.append(aux[AUX_RPM])
	if shaft_is_coupled():
		out.append(aux[AUX_RPM])
		if battery_is_dynamic():
			out.append_array(PackedFloat64Array([_battery_initial_charge(), 0.0, 0.0]))
	# Wheels begin at zero relative rim speed on both airborne and runway starts.
	for _i in wheel_count():
		out.append(0.0)
	return out


func battery_is_dynamic() -> bool:
	return aircraft.get("ok", false) and Propulsion.has_dynamic_battery(aircraft.model.propulsion)


func electric_law() -> String:
	return BATTERY_LAW if battery_is_dynamic() else ELECTRIC_LAW


func _rotor_index() -> int:
	var prop: Dictionary = aircraft.model.propulsion
	return prop.slipstream.pieces.size() if WashTransport.enabled(prop) else 0


func _battery_initial_charge() -> float:
	var battery: Dictionary = aircraft.model.propulsion.battery
	return 3600.0 * float(battery.capacity_ah) * float(battery.initial_soc)


## Charge is the sole depletion state; SOC and consumed coulombs are derived.
func _battery_values_valid(values: PackedFloat64Array, trial: bool = false) -> bool:
	var at: int = _rotor_index() + 1
	if values.size() != at + 3 + wheel_count():
		return false
	for i: int in range(at, at + 3):
		if not is_finite(values[i]):
			return false
	return (trial or values[at] >= 0.0) and values[at] <= _battery_initial_charge() \
		and values[at + 1] >= 0.0 and values[at + 2] >= 0.0


func _battery_point(rpm: float, values: PackedFloat64Array, dynamics_only: bool = false) -> Dictionary:
	if not _battery_values_valid(values, true):
		return {ok = false}
	var charge: float = values[_rotor_index() + 1]
	var prop: Dictionary = aircraft.model.propulsion
	var soc: float = maxf(0.0, charge / (3600.0 * float(prop.battery.capacity_ah)))
	return Propulsion.electric_source_state(rpm, propulsion_throttle(), prop, propulsion_power_enabled(), soc, charge < 0.0, dynamics_only)


func _coupled_rpm(values: PackedFloat64Array, trial: bool = false) -> float:
	if glow_is_active():
		return values[0] if values.size()==GlowFlight.SIZE+wheel_count() and is_finite(values[0]) and (trial or values[0]>=0.0) else NAN
	var prop: Dictionary = aircraft.model.propulsion
	var count: int = prop.slipstream.pieces.size() if WashTransport.enabled(prop) else 0
	if values.size() != count + (4 if battery_is_dynamic() else 1) + wheel_count() \
			or not is_finite(values[count]) or (values[count] < 0.0 and not trial):
		return NAN
	return values[count]


## The optional RPM boundary mirror is telemetry, never a second evolving shaft state.
func _coupled_aux(values: PackedFloat64Array, sampled: PackedFloat64Array) -> PackedFloat64Array:
	if glow_is_active() and not GlowFlight.valid(values,aircraft.model.propulsion.glow):
		return PackedFloat64Array([NAN])
	var out: PackedFloat64Array = sampled.duplicate()
	if out.is_empty() or (battery_is_dynamic() and not _battery_values_valid(values)):
		return PackedFloat64Array([NAN])
	out[AUX_RPM] = _coupled_rpm(values)
	return out


func _coupled_rotor(_s: PackedFloat64Array, values: PackedFloat64Array, _t: float) -> PackedFloat64Array:
	return Dynamics.rotor_momentum(aircraft.model, maxf(0.0, _coupled_rpm(values, true)) if Propulsion.is_electric(aircraft.model.propulsion) else _coupled_rpm(values))


## External loads include -Q_prop exactly once. The rotor response adds only relative-spin reaction.
func _coupled_response(s: PackedFloat64Array, values: PackedFloat64Array, time_s: float) -> Dictionary:
	var prop: Dictionary = aircraft.model.propulsion
	var electric: bool = Propulsion.is_electric(prop)
	var trial_rpm: float = _coupled_rpm(values, electric)
	if not is_finite(trial_rpm):
		return {ok = false}
	var rpm: float = maxf(0.0, trial_rpm) if electric else trial_rpm
	var air: Dictionary = air_data(s, time_s)
	var battery_point: Dictionary = {}
	var rate: float
	if battery_is_dynamic():
		battery_point = _battery_point(rpm, values, true)
		if not battery_point.get("ok", false):
			return {ok = false}
		var load_torque: float = Propulsion.prop_torque(rpm, M.dot(air.v_air, Propulsion.axis(prop)), prop, air_density(s))
		rate = (float(battery_point.shaft_torque_nm) - load_torque) / float(prop.rotor_inertia) * 60.0 / TAU
	else:
		rate = Propulsion.shaft_rate(rpm, propulsion_throttle(), M.dot(air.v_air, Propulsion.axis(prop)),
			prop, air_density(s), engine_charge_ratio(s), propulsion_power_enabled())
	if not is_finite(rate):
		return {ok = false}
	var a: PackedFloat64Array = sim.aux
	var lag: int = downwash_index()
	var external: PackedFloat64Array = Dynamics.loads_from_air(s, aircraft.model, _deflections(a), rpm,
		air_density(s), air, a[lag] if lag >= 0 and lag < a.size() else NAN, values.slice(0, _rotor_index()), _ground_up(s))
	var ground: Dictionary = _ground_evaluation(s, a, values, air if gear_is_retractable() else {})
	if not ground.get("ok", false):
		return {ok = false}
	var ground_loads: PackedFloat64Array = ground.loads
	for i: int in ground_loads.size():
		external[i] += ground_loads[i]
	var locked: bool = false
	if electric and trial_rpm <= 0.0:
		var point: Dictionary = battery_point if not battery_point.is_empty() else Propulsion.electric_source_state(rpm, propulsion_throttle(), prop, propulsion_power_enabled())
		if not point.get("ok", false):
			return {ok = false}
		var kt: float = 60.0 / (TAU * float(prop.motor.kv_rpm_per_volt))
		var friction: float = kt * float(prop.motor.no_load_current_a)
		if trial_rpm < 0.0:
			# Left-limit continuation for event localization only. Never commit this RPM.
			rate = (kt * float(point.motor_current_a) - friction) / float(prop.rotor_inertia) * 60.0 / TAU
		elif rpm == 0.0:
			# Static bearing friction may hold the relative rotor against body acceleration.
			var w: PackedFloat64Array = s.slice(RB.RATE, RB.RATE + 3)
			var free_body: PackedFloat64Array = RB.inertia_mul(RB.inertia_inverse(sim.inertia),
				M.sub(external.slice(3, 6), M.cross(w, RB.inertia_mul(sim.inertia, w))))
			var required: float = float(prop.rotor_inertia) * M.dot(Propulsion.axis(prop), free_body)
			var drive: float = kt * float(point.motor_current_a)
			if absf(drive - required) <= friction:
				locked = true
				rate = required / float(prop.rotor_inertia) * 60.0 / TAU
			elif drive - required < -friction:
				return {ok = false} # unsupported reverse breakaway, not an invented stop torque
			else:
				# Body acceleration can initiate forward relative spin even with the source off.
				# Use moving-side bearing loss; the isolated motor's rest clamp is not valid here.
				rate = (drive - friction) / float(prop.rotor_inertia) * 60.0 / TAU
	var response: Dictionary = RotorCoupling.response(M.v3(s[RB.RATE], s[RB.RATE + 1], s[RB.RATE + 2]),
		M.v3(external[3], external[4], external[5]), sim.inertia, RB.inertia_inverse(sim.inertia),
		Propulsion.axis(prop), prop.rotor_inertia, rpm * TAU / 60.0, rate * prop.rotor_inertia * TAU / 60.0)
	if not response.ok:
		return response
	if locked:
		response.spin_acceleration = 0.0
		response.reaction = PackedFloat64Array([0.0, 0.0, 0.0])
	for i: int in 3:
		external[3 + i] += response.reaction[i]
	response.loads = external
	response.air = air
	response.rpm_rate = response.spin_acceleration * 60.0 / TAU
	response.wheel_derivative = ground.derivative
	if not battery_point.is_empty():
		response.battery = battery_point
	return response


func _coupled_loads(s: PackedFloat64Array, values: PackedFloat64Array, time_s: float) -> PackedFloat64Array:
	var result: Dictionary = _coupled_response(s, values, time_s)
	return result.loads if result.ok else PackedFloat64Array([NAN, NAN, NAN, NAN, NAN, NAN])


func _coupled_derivative(s: PackedFloat64Array, values: PackedFloat64Array, time_s: float) -> PackedFloat64Array:
	var result: Dictionary = _coupled_response(s, values, time_s)
	if not result.ok:
		return PackedFloat64Array([NAN])
	var air: Dictionary = air_data(s, time_s)
	var wash: PackedFloat64Array = WashTransport.derivative(air.v_air, _coupled_rpm(values),
		aircraft.model.propulsion, air_density(s), values.slice(0, _rotor_index())) if _rotor_index() > 0 else PackedFloat64Array()
	wash.append(result.rpm_rate)
	_append_battery_rates(wash, result)
	wash.append_array(result.get("wheel_derivative", PackedFloat64Array()))
	return wash


## One response per RK stage; both the old separate callbacks and this joint path keep the same arithmetic.
func _coupled_evaluate(s: PackedFloat64Array, values: PackedFloat64Array, time_s: float) -> Dictionary:
	var result: Dictionary = _coupled_response(s, values, time_s)
	if not result.ok:
		return {}
	var extra: PackedFloat64Array = PackedFloat64Array()
	if _rotor_index() > 0:
		var air: Dictionary = result.air
		extra = WashTransport.derivative(air.v_air, _coupled_rpm(values),
			aircraft.model.propulsion, air_density(s), values.slice(0, _rotor_index()))
	extra.append(result.rpm_rate)
	_append_battery_rates(extra, result)
	extra.append_array(result.get("wheel_derivative", PackedFloat64Array()))
	return {loads = result.loads, derivative = extra, rotor_momentum = _coupled_rotor(s, values, time_s)}


func _append_battery_rates(values: PackedFloat64Array, response: Dictionary) -> void:
	if response.has("battery"):
		values.append_array(PackedFloat64Array([-response.battery.pack_current_a,
			response.battery.pack_terminal_power_w, response.battery.pack_loss_w]))


func _shaft_rate(s: PackedFloat64Array, rpm: float, time_s: float) -> float:
	var values: PackedFloat64Array = sim.continuous.duplicate()
	if values.is_empty():
		return NAN
	values[_rotor_index()] = rpm
	var result: Dictionary = _coupled_response(s, values, time_s)
	return result.rpm_rate if result.ok else NAN


## EL1d/EL2a: locate the first stop, conserve momentum through the numerical boundary projection, then resume
## the remaining tick with static friction. Only accepted state is published; located events are reported to
## the kernel (SF-04). The fixed-bus route declares its event instead and does not use this policy.
func _electric_step(combined: PackedFloat64Array, at: float, dt: float, derivative: Callable,
		first: PackedFloat64Array) -> Variant:
	var result: Dictionary
	if battery_is_dynamic():
		result = BatteryStep.advance(combined, at, dt, derivative, first,
			RB.SIZE + _rotor_index(), RB.SIZE + _rotor_index() + 1, _project_electric_stop)
	else:
		result = EventStep.advance(combined, at, dt, derivative, first,
			RB.SIZE + _rotor_index(), _project_electric_stop, "rotor_stop")
	if not result.get("ok", false):
		return PackedFloat64Array([NAN])
	return {state = result.state, events = result.events}


func _project_electric_stop(values: PackedFloat64Array, index: int) -> PackedFloat64Array:
	var out: PackedFloat64Array = values.duplicate()
	var impulse: float = float(aircraft.model.propulsion.rotor_inertia) * out[index] * TAU / 60.0
	var correction: PackedFloat64Array = RB.inertia_mul(RB.inertia_inverse(sim.inertia),
		M.scale(Propulsion.axis(aircraft.model.propulsion), impulse))
	for i: int in 3:
		out[RB.RATE + i] += correction[i]
	out[index] = 0.0
	return out


## Pure accepted-endpoint electrical telemetry; no dynamic state is stored in the definition.
func electrical_state() -> Dictionary:
	if not aircraft.get("ok", false) or not Propulsion.is_electric(aircraft.model.propulsion):
		return {ok = false}
	if battery_is_dynamic() and not _battery_values_valid(sim.continuous):
		return {ok = false}
	var point: Dictionary = _battery_point(sim.aux[AUX_RPM], sim.continuous) if battery_is_dynamic() else Propulsion.electric_source_state(sim.aux[AUX_RPM], propulsion_throttle(),
		aircraft.model.propulsion, propulsion_power_enabled())
	if point.get("ok", false):
		point.tick = sim.tick
		point.time_s = sim.time()
		point.rpm = sim.aux[AUX_RPM]
		point.enabled = propulsion_power_enabled()
		point.duty = propulsion_throttle() if propulsion_power_enabled() else 0.0
		if battery_is_dynamic():
			var index: int = _rotor_index() + 1
			point.remaining_charge_c = sim.continuous[index]
			point.consumed_charge_c = _battery_initial_charge() - sim.continuous[index]
			point.terminal_energy_j = sim.continuous[index + 1]
			point.pack_heat_j = sim.continuous[index + 2]
			point.exhausted = sim.continuous[index] == 0.0
	return point


## Aerodynamic-convention deflections from the servos' actual positions. The servos change once per tick (in
## _pre_step), while the loads run five times per tick (H2), so the last result is reused while the positions match.
## Callers only read the dictionary.
func _deflections(a: PackedFloat64Array) -> Dictionary:
	var flap: float = a[flap_aux_index()] if flaps_available() and _flap_aux_valid(a) else 0.0
	if _deflection_key.size() == 4 and _deflection_key[3] == flap and _deflection_key[0] == a[AUX_SERVO] and _deflection_key[1] == a[AUX_SERVO + 1] \
			and _deflection_key[2] == a[AUX_SERVO + 2]:
		return _deflection_cache
	var surfaces := _surface_angles_from_aux(a)
	_deflection_cache = Aero.deflections_from_surfaces(surfaces)
	if flaps_available():
		_deflection_cache.flap = deg_to_rad(flap * float(aircraft.model.flaps.max_angle_deg))
	_deflection_key = PackedFloat64Array([a[AUX_SERVO], a[AUX_SERVO + 1], a[AUX_SERVO + 2], flap])
	return _deflection_cache


## Propeller angular momentum (D9c): J_p·ω along body +x (clockwise seen from behind).
func rotor_momentum(aux: PackedFloat64Array) -> PackedFloat64Array:
	return Dynamics.rotor_momentum(aircraft.model, aux[AUX_RPM])


## Once per physics tick, before integration (deterministic): engine rpm follows the throttle with its lag (D5), or
## the shaft torque balance when the aircraft declares one (P51-06);
## each servo slews toward its command at the servo's rate (D6c), a full throw in servo_full_throw_time.
## SF-05: the gear's derived substep count while a wheel is within reach of the ground, otherwise one.
func _substeps(body: PackedFloat64Array, _continuous: PackedFloat64Array, _t: float) -> int:
	if not aircraft.get("ok", false) or not (aircraft.model.get("landing_gear") is Dictionary):
		return 1
	return Ground.substeps(body, current_landing_gear(), sim.dt(), ground_surfaces)


func _pre_step(aux: PackedFloat64Array, inputs: PackedFloat64Array, dt: float) -> PackedFloat64Array:
	if _weather_pending_reset or _shaft_pending_reset:
		return PackedFloat64Array([NAN]) # configure→reset boundary cannot advance an old layout/RNG
	if gear_is_retractable() and (not _gear_aux_valid(aux) or inputs.size() != _input_count() \
			or inputs[4] not in [0.0, 1.0] or not RetractableGear.valid_fraction(inputs[5])):
		return PackedFloat64Array([NAN])
	if flaps_available() and (not _flap_aux_valid(aux) or inputs.size() != _input_count() \
			or not RetractableGear.valid_fraction(inputs[flap_input_index()])):
		return PackedFloat64Array([NAN])
	var next_flap := 0.0
	if flaps_available():
		next_flap = Flaps.advance(aux[flap_aux_index()], inputs[flap_input_index()], dt, aircraft.model.flaps)
		# Manual down-elevator mix follows slowed flap travel, before failures and physical servos.
		# An elevator jam must still override the mixer; the recorded input remains pilot demand.
		inputs = inputs.duplicate()
		inputs[1] = clampf(inputs[1] - next_flap * aircraft.model.flaps.elevator_mix_per_flap_fraction, -1.0, 1.0)
	if _failures != null:
		# The incident module owns four primary channels; the gear actuator keeps
		# its separately recorded demand and never extends the failure snapshot ABI.
		var prepared_failure: Dictionary = _failures.prepare(inputs.slice(0, 4), aux, _failure_airborne())
		if not prepared_failure.get("ok", false):
			return PackedFloat64Array([NAN])
		inputs = _failures.effective_inputs(inputs)
		if failure_power_cut_active():
			# Like the weather RNG below, modes are rolled back on rejection and
			# remembered before stepped observers see the accepted boundary.
			engine_running = false
	var prop: Dictionary = aircraft.model.propulsion
	var rpm := 0.0
	if shaft_is_coupled() or turbine_is_continuous():
		rpm = aux[AUX_RPM] # the continuous endpoint owns RPM; the boundary mirror is read-only here
	elif engine_running and Turbine.is_turbine(prop):
		# AV-05: the turbine spools toward the ECU demand within its acceleration/deceleration schedules.
		rpm = Turbine.spool_step(aux[AUX_RPM], inputs[3], dt, prop)
	elif engine_running and Propulsion.has_shaft(prop):
		# G2 first slice (P51-06): torque balance at the current axial airspeed (calm air, as _loads).
		var s: PackedFloat64Array = sim.state
		var u := M.dot(M.v3(s[RB.VEL], s[RB.VEL + 1], s[RB.VEL + 2]), Propulsion.axis(prop))
		if not weather_is_calm():
			u = M.dot(air_data(s, sim.time()).v_air, Propulsion.axis(prop))
		rpm = Propulsion.shaft_step(aux[AUX_RPM], inputs[3], u, dt, prop, air_density(), engine_charge_ratio())
	elif engine_running:
		rpm = Propulsion.rpm_step(aux[AUX_RPM], inputs[3], dt, prop)
	var out := PackedFloat64Array([rpm, 0.0, 0.0, 0.0])
	var rate: float = aircraft.model.controls.servo_rate
	for k in 3:
		var effective_rate: float = rate if _failures == null else rate * _failures.servo_rate_factor(k)
		out[AUX_SERVO + k] = ControlActuators.rate_limit(aux[AUX_SERVO + k], inputs[k], effective_rate, dt)
	var lag := downwash_index()
	var anchors_end := AUX_ANCHORS + anchor_count() * Ground.ANCHOR_STRIDE
	if anchors_end > AUX_ANCHORS:
		# E3b1: stick/slip transitions from the committed state, with the steer the last tick used.
		var wheel_speeds: PackedFloat64Array = sim.continuous.slice(wheel_index()) if wheel_count() > 0 else PackedFloat64Array()
		out.append_array(Ground.anchor_step(sim.state, current_landing_gear(aux), aux[AUX_SERVO + 2], ground_surfaces,
			aux.slice(AUX_ANCHORS, anchors_end), wheel_count() > 0, wheel_speeds, _lake))
	if lag >= 0 and lag < aux.size():
		# E0a2b: the tail's downwash follows the wing's lift l/V late. Exact first-order lag over the tick, from the
		# committed state and the servos the last tick used; held through the RK stages like rpm.
		var s: PackedFloat64Array = sim.state
		var cl_now := _wing_cl(s, aux)
		var speed: float = air_data(s, sim.time()).V
		var length: float = aircraft.model.surfaces.horizontal.downwash_lag_length
		out.append(cl_now + (aux[lag] - cl_now) * M.exp_(-dt * speed / length))
	if gear_is_retractable():
		var index: int = gear_aux_index()
		var target: float = inputs[4]
		if target == 0.0 and _gear_weight_on_wheels(aux):
			target = 1.0
		out.append(RetractableGear.advance(aux[index], target, dt, aircraft.model.landing_gear))
		out.append(target)
	if flaps_available():
		out.append(next_flap)
	if _weather.has_turbulence():
		var index: int = turbulence_index()
		var next: Dictionary = Turbulence.step(aux.slice(index + 3, index + 6), _weather.turbulence_rms(),
			_weather.turbulence_tau(), dt, _weather.turbulence_seed(), sim.modes[1])
		if not next.ok:
			return PackedFloat64Array([NAN]) # H8 rolls back body, interval and RNG together.
		out.append_array(aux.slice(index + 3, index + 6))
		out.append_array(next.values)
		out.append(sim.time())
		sim.modes[1] = next.rng_state
	return out


## VAL-AUD-R02: aux index of the lagged wing lift-velocity proxy (m/s) (after the anchors), or −1 without a tail downwash lag.
func downwash_index() -> int:
	# The lag feeds only the local (strip) model's tail: none without an envelope (a pure-oracle model).
	if not aircraft.get("ok", false) or aircraft.model.get("envelope", {}).is_empty() \
			or not aircraft.model.get("surfaces", {}).get("horizontal", {}).has("downwash_lag_length"):
		return -1
	return AUX_ANCHORS + anchor_count() * Ground.ANCHOR_STRIDE


## Replay-tolerance component of aux entry i (H9 policy): rpm, servo, anchor or downwash.
func aux_component(i: int) -> String:
	if i == AUX_RPM:
		return "rpm"
	if i < AUX_ANCHORS:
		return "servo"
	if gear_is_retractable() and i >= gear_aux_index() and i < gear_aux_index() + GEAR_AUX_SIZE:
		return "servo" # normalized actuator fraction and binary target; same replay tolerance
	if flaps_available() and i == flap_aux_index():
		return "servo"
	if _weather.has_turbulence() and i >= turbulence_index():
		return "weather"
	return "downwash" if i == downwash_index() else "anchor"


## Historical helper name: returns the dimensional wing lift-velocity proxy (m/s), not CL.
func _wing_cl(s: PackedFloat64Array, aux: PackedFloat64Array, time_s: float = NAN) -> float:
	var air: Dictionary = air_data(s, time_s)
	return Aero.wing_wake_velocity(s, air, _deflections(aux), aircraft.model, _ground_up(s))


## M5-GE-1: the ground height (m above the NED datum) under the CG for the aero ground-effect factors, from the same
## terrain the wheels use. NAN when the aircraft has no aero.ground_effect module or flies above its reach, which is
## the unchanged byte-identical load path. Static solves (trim, linearisation, runway equilibrium) never pass a ground.
func _ground_up(s: PackedFloat64Array) -> float:
	if _ground_effect_reach <= 0.0:
		return NAN
	if -s[RB.POS + 2] >= _ground_effect_reach + environment.ground_max_height():
		return NAN
	return environment.terrain(s[RB.POS], s[RB.POS + 1])[0]


## Compatibility helper for tests/captures: one-shot runway start at (north, east), facing `heading` (rad, 0 = north).
## It does not change the persistent start_choice. Failure restores the normal trimmed start and returns false.
func reset_on_runway(north: float, east: float, heading: float) -> bool:
	var result := try_runway_start(north, east, heading)
	if result.ok:
		return true
	# Historical helper explicitly commits an airborne fallback after the refused
	# runway transaction. Its outcome and trace metadata retain the rejection reason.
	resetting.emit()
	_clear_scenery_damage(true)
	crash = {}
	var fallback_ok := _reset_airborne_start()
	start_error = str(result.message)
	runway_start_outcome.fallback = "trimmed_airborne" if fallback_ok else "failed"
	if fallback_ok:
		_capture_launch("airborne", "airborne_fallback", ground_field_id, start_error)
	return false


## E3b1: wheels with a stiction anchor (0 when the gear has no breakaway_factor).
func anchor_count() -> int:
	var gear: Dictionary = aircraft.get("model", {}).get("landing_gear", {}) if aircraft.get("ok", false) else {}
	return gear.contacts.size() if gear.has("breakaway_factor") else 0


## Number of rotating wheels enabled by a validated file-backed profile (zero for in-memory/legacy gear and Avanti).
func wheel_count() -> int:
	return _model_wheel_count(aircraft.get("model", {})) if aircraft.get("ok", false) else 0


## First continuous-state index holding wheel rim speeds, in landing_gear.contacts order.
func wheel_index() -> int:
	if not aircraft.get("ok", false):
		return 0
	if glow_is_active(): return GlowFlight.SIZE
	var index: int = _rotor_index()
	if shaft_is_coupled():
		index += 1 + (3 if battery_is_dynamic() else 0)
	elif turbine_is_continuous():
		index += 1
	return index


func _model_wheel_count(model: Dictionary) -> int:
	var profile: Dictionary = model.get("wheel_profile", {})
	var gear: Dictionary = model.get("landing_gear", {})
	if profile.get("status") != "applied" or gear.is_empty():
		return 0
	return gear.get("contacts", []).size()


func wheel_state_layout() -> String:
	var layout: Array = []
	if wheel_count() == 0:
		return "[]"
	for i in wheel_count():
		layout.append({index = wheel_index() + i, contact = aircraft.model.landing_gear.contacts[i].name, unit = "m/s rim speed"})
	return JSON.stringify(layout, "", true, true)


## Header lines for a flight trace of this session.
## Preparation/inspection metadata only. No new solver or checkpoint state is introduced.
func contact_contract() -> Dictionary:
	if not aircraft.get("ok", false):
		return {ok = false, errors = PackedStringArray(["Aircraft is unavailable."])}
	var result: Dictionary = ContactContract.describe(aircraft.model, soft_hull_contacts)
	result.format = "openrc-aircraft-contact-bindings v1"
	result.scenery_policy = SceneryDamage.POLICY_VERSION if not _collision_world.is_empty() else "not_selected"
	result.lake_identity = _lake_identity()
	return result


func trace_meta() -> Dictionary:
	var model: Dictionary = aircraft.model
	var prop: Dictionary = model.propulsion
	var turbine: bool = Turbine.is_turbine(prop)
	var propulsion_model: String = "turbine-ecu-spool-v1" if turbine else (
		"propeller-shaft-balance-v1" if Propulsion.has_shaft(prop) else "propeller-rpm-lag-v1")
	var scenario: String = "trimmed %s across view at %.1f m/s (D5: six-axis trim, calm air)" % [
		"level flight (engine running)" if start.get("mode", "level") == "level" else "power-off glide", float(start.get("V", NAN))]
	if str(_launch_metadata.get("launch_choice", "airborne")) == "runway":
		scenario = "runway threshold on field '%s' (idle engine, static equilibrium; experimental)" % str(_launch_metadata.get("launch_field_id", ""))
		if Propulsion.is_electric(prop):
			scenario = "runway threshold on field '%s' (electric source enabled, zero duty, rotor at rest; experimental)" % str(_launch_metadata.get("launch_field_id", ""))
		elif Propulsion.is_glow(prop):
			scenario = "runway threshold on field '%s' (warm glow engine stopped; explicit starter required; experimental)" % str(_launch_metadata.get("launch_field_id", ""))
	elif str(_launch_metadata.get("launch_choice", "")) == "failed":
		scenario = "start refused: " + str(_launch_metadata.get("launch_error", "unknown start error"))
	elif str(_launch_metadata.get("launch_kind", "")) == "checkpoint_restore":
		scenario = "checkpoint replay (original launch unknown)"
	var metadata: Dictionary = {
		metadata_schema = "openrc-flight-meta v2",
		scenario = scenario,
		selected_start_choice = _launch_metadata.get("selected_start_choice", start_choice),
		launch_choice = _launch_metadata.get("launch_choice", "unknown"),
		launch_kind = _launch_metadata.get("launch_kind", "unknown"),
		launch_field_id = _launch_metadata.get("launch_field_id", ""),
		launch_state = _launch_metadata.get("launch_state", "[]"),
		launch_aux = _launch_metadata.get("launch_aux", "[]"),
		launch_ground_anchors = _launch_metadata.get("launch_ground_anchors", "[]"),
		launch_engine_running = _launch_metadata.get("launch_engine_running", "false"),
		launch_error = _launch_metadata.get("launch_error", ""),
		aircraft = "%s (%s)" % [aircraft.model.get("id", "?"), aircraft_path],
		aircraft_input_format = AircraftData.FORMAT,
		aircraft_input_sha256 = aircraft.get("input_identity", {}).get("sha256", "unavailable: in-memory input"),
		aircraft_input_hash_convention = "sha256 of exact aircraft input file bytes",
		aircraft_semantic_sha256 = model.get("data_sha256", "unavailable"),
		aircraft_semantic_hash_convention = "sha256 of Godot JSON.stringify(parsed_input, indent=empty, sort_keys=true, full_precision=false); not file bytes",
		configuration = aircraft.model.get("configuration", "unspecified"),
		aero_model = "global-derivatives-v1" if model.get("envelope", {}).is_empty() else Aero.LOADS_LAW + " with bounded attached oracle",
		wing_polar_model = "tabulated-wing-v1 (experimental finite-wing strip reference)" if model.get("envelope", {}).has("wing_polar") else "legacy attached-to-flat-plate blend",
		ground_effect_model = ("image-induced-factor-v1 (aero.ground_effect: strip induced angle/drag and tail downwash from the field terrain height, exact above %.1f spans)" % GroundEffect.FADE_SPAN_RATIO) if GroundEffect.enabled(model) else "none",
		propulsion_model = propulsion_model,
		propwash_model = "tail-slipstream-axial-transport-v1" if WashTransport.enabled(prop) else (
			"none" if prop.get("slipstream", {}).is_empty() else "tail-slipstream-increment-v1"),
		continuous_layout = "axial wash increment m/s, slipstream.pieces order; RK4 coupled; checkpoint only" if WashTransport.enabled(prop) else "none",
		propulsion_features = JSON.stringify({
			propeller_normal_force = not turbine and prop.has("axis") and not prop.get("normal_force", PackedFloat64Array()).is_empty(),
			propeller_pfactor = not turbine and prop.has("axis") and not prop.get("pfactor_moment", PackedFloat64Array()).is_empty(),
			rotor_gyroscopic_coupling = float(prop.rotor_inertia) != 0.0,
			turbine_ram_flow = turbine and float(prop.get("ram_flow", 0.0)) != 0.0,
			turbine_ram_jet = turbine and prop.has("ram_jet"),
		}),
		engine_rpm_semantics = "turbine spool rpm" if turbine else "propeller shaft rpm",
		state_layout = JSON.stringify(RB.STATE_LAYOUT),
		aux_layout = JSON.stringify(AUX_LAYOUT),
		recording_start_tick = sim.tick,
		# The trace's sampled aux columns (aux_layout); E3b1 anchors are exact only in checkpoints (H8).
		recording_start_aux = JSON.stringify(Array(sim.aux.slice(0, AUX_LAYOUT.size())), "", true, true),
		recording_start_engine_running = JSON.stringify(engine_running),
		ground = "flat at 0 m; %s" % ("%d spring-damper gear contacts (E1) with tyre friction and nose-wheel steering, brakes off (E2)%s, on %s" % [aircraft.model.landing_gear.contacts.size(), ", stiction anchors (E3b1)" if anchor_count() > 0 else "", "field '%s' surfaces (E3a)" % ground_field_id if not ground_surfaces.is_empty() else "dry pavement"] if not aircraft.model.landing_gear.is_empty() else "no landing gear: any wheel contact is a crash (D9d)"),
		created_utc = Time.get_datetime_string_from_system(true),
		engine = "Godot " + Engine.get_version_info().string,
		dt_s = sim.dt(),
		mass_kg = sim.mass,
		inertia_kgm2 = "Jxx Jyy Jzz Jxy Jxz Jyz = %s" % " ".join(Array(sim.inertia).map(func(v): return str(v))),
		gravity_mps2 = sim.gravity,
		frames = "world NED (north, east, down); body FRD (forward, right, down); quaternion body->NED [w,x,y,z]",
		loads = "Fx..Mz: body-axis loads excluding gravity; tick 0 evaluates reset state/aux; tick k>0 evaluates state k-1 with aux k (after pre_step)",
		state_timing = "state and aux at tick k; aux advances before RK4 and is held through its stages; cmd_* drives that step (reset commands at tick 0)",
	}
	if glow_is_active():
		metadata.mass_contact_law = MASS_CONTACT_LAW
		metadata.mass_reference = "mass_kg and inertia_kgm2 are initial wet values; live mass/CG/inertia derive from continuous fuel at fixed initial datum"
	if soft_hull_contacts:
		metadata.hull_contact_model = HullContact.law()
	if not _collision_world.is_empty():
		metadata.scenery_collision_model = "openrc-swept-landscape-contact v1"
		metadata.collision_world_identity = str(_collision_world.identity)
	if not _lake.is_empty():
		metadata.lake_terrain_model = "bounded-lake-terrain-and-terminal-water-contact-v1"
		metadata.lake_id = str(_lake.id)
		metadata.lake_identity = _lake_identity()
		metadata.ground = "flat at 0 m outside lake bank; normalized basin terrain inside bank; no water buoyancy"
	if wheel_count() > 0:
		var profile: Dictionary = model.get("wheel_profile", {})
		metadata.metadata_schema = "openrc-flight-meta v6"
		metadata.wheel_state_model = "relative-wheel-rim-speed-rk4-v1"
		metadata.wheel_state_layout = wheel_state_layout()
		metadata.wheel_profile_status = str(profile.get("status", "unknown"))
		metadata.wheel_profile_sha256 = str(profile.get("profile_sha256", "unavailable"))
		metadata.wheel_profile_input_sha256 = str(profile.get("input_sha256", "unavailable"))
		metadata.wheel_profile_hash_convention = "profile_sha256 is canonical JSON for the selected aircraft profile; input_sha256 is SHA-256 of exact wheel_profiles.json bytes"
		metadata.recording_start_continuous = JSON.stringify(Array(sim.continuous), "", true, true)
		metadata.launch_continuous = str(_launch_metadata.get("launch_continuous", "[]"))
		var brake_profiles: Array = []
		for contact: Dictionary in aircraft.model.landing_gear.contacts:
			brake_profiles.append({contact = contact.name, availability = contact.get("brake_availability", "unspecified"),
				max_torque_nm = contact.get("brake_torque", 0.0)})
		metadata.wheel_brakes = JSON.stringify(brake_profiles, "", true, true)
		if not ground_surfaces.is_empty():
			metadata.ground = "%d profiled spring-damper gear contacts; deterministic bounded grass relief (GP-01, at most 7 mm), terrain-normal projection, field-scaled friction and wheel-radius-corrected rolling resistance; steering and continuous relative wheel spin; brakes off (no brake command exposed); field '%s'" % [
				model.landing_gear.contacts.size(), ground_field_id]
		else:
			metadata.ground = "%d profiled spring-damper gear contacts on flat 0 m dry-pavement fixture; per-contact wheel radius and inertia, steering, continuous relative wheel spin; brakes off (no brake command exposed)" % model.landing_gear.contacts.size()
	if not weather_is_calm():
		metadata.metadata_schema = "openrc-flight-meta v3"
		metadata.scenario = str(metadata.scenario).replace("calm air", "trim relative to moving air")
		metadata.weather_config = JSON.stringify(weather_configuration(), "", true, true)
		metadata.weather_model = "uniform-ned-repeating-cosine-v1"
		metadata.weather_evidence = "user-selected/authored practice conditions; not measured meteorology"
		metadata.weather_timing = "wind/TAS at row state time; loads_* wind and loads_t_s describe k1 (tick-1, current aux); reset uses t=0"
		if _weather.has_turbulence():
			metadata.metadata_schema = "openrc-flight-meta v4"
			metadata.weather_model = "uniform-ned-cosine-plus-temporal-ou-pcg32-normal53-v1"
			metadata.turbulence_aux_index = turbulence_index()
			metadata.turbulence_interval = "linear interpolation between exact OU tick samples; wall time tau; independent NED axes"
			metadata.recording_start_rng_state = str(sim.modes[1])
			metadata.recording_start_turbulence = JSON.stringify(Array(sim.aux.slice(turbulence_index())), "", true, true)
		metadata.recording_start_previous_state = JSON.stringify(Array(sim.previous), "", true, true)
	if not atmosphere_is_reference():
		metadata.metadata_schema = "openrc-flight-meta v5"
		metadata.weather_config = JSON.stringify(weather_configuration(), "", true, true)
		metadata.weather_model = "uniform-ned-cosine-plus-temporal-ou-pcg32-normal53-v1" if _weather.has_turbulence() else "uniform-ned-repeating-cosine-v1"
		metadata.weather_evidence = "user-selected/authored practice conditions; not measured meteorology"
		metadata.weather_timing = "wind/TAS at row state time; loads_* wind and loads_t_s describe k1 (tick-1, current aux); reset uses t=0"
		metadata.recording_start_previous_state = JSON.stringify(Array(sim.previous), "", true, true)
		metadata.atmosphere_model = _weather.atmosphere_law()
		metadata.atmosphere_state = JSON.stringify(_weather.atmosphere(), "", true, true) # field datum sample; rows query their own altitude
		metadata.atmosphere_scope = "dry ISA column; geometric altitude = field elevation - NED down; one body datum sample per stage; -500..11000 m; no extrapolation; fixed gravity" if _weather.has_vertical_atmosphere() else "uniform field density per flight; geometric field elevation; liquid-water RH; fixed gravity; not a vertical sounding"
		metadata.engine_atmosphere = "shaft: dry-air indicated torque, fixed friction; rpm-lag: prescribed rpm; turbine: existing density-scaled map (experimental)"
	if shaft_is_coupled():
		metadata.propulsion_model = "propeller-shaft-coupled-rk4-v1"
		metadata.shaft_integrator = shaft_integrator()
		metadata.rotor_coupling = "relative-spin-locked-inertia-reaction-v1"
		metadata.continuous_layout = "axial wash increment m/s, slipstream.pieces order, then propeller shaft rpm; RK4 coupled"
		metadata.recording_start_continuous = JSON.stringify(Array(sim.continuous), "", true, true)
		metadata.loads = "Fx..Mz: body-axis loads excluding gravity; k1 at previous body/continuous endpoint and current sampled servos; includes relative-spin reaction"
		metadata.state_timing = "body, continuous shaft RPM and mirrored aux at tick k; servos advance before RK4; shaft RPM/inflow/gyro/reaction evaluated at each stage"
		if metadata.has("weather_timing"):
			metadata.weather_timing = "wind/TAS at row state time; loads_* wind and loads_t_s describe k1 (tick-1 body/shaft, current sampled servos); reset uses t=0"
	if turbine_is_continuous():
		metadata.propulsion_model = Turbine.CONTINUOUS_LAW
		metadata.turbine_integrator = "rk4"
		metadata.continuous_layout = Turbine.CONTINUOUS_LAYOUT
		metadata.recording_start_continuous = JSON.stringify(Array(sim.continuous), "", true, true)
		metadata.loads = "Fx..Mz: body-axis loads excluding gravity; k1 at previous body/turbine RPM and current sampled servos; gyro only"
		metadata.state_timing = "body, continuous turbine RPM and mirrored aux at tick k; servos advance before RK4; turbine RPM/thrust/gyro evaluated at each stage"
		if metadata.has("weather_timing"):
			metadata.weather_timing = "wind/TAS at row state time; loads_* wind and loads_t_s describe k1 (tick-1 body/turbine, current sampled servos); reset uses t=0"
	if Propulsion.is_electric(prop):
		metadata.propulsion_model = electric_law()
		metadata.electric_configuration = JSON.stringify({motor = prop.motor, battery = prop.battery, esc = prop.esc}, "", true, true)
		metadata.electric_sample_timing = "accepted endpoint; current tick input and source-enabled mode"
		metadata.electric_stop = "first downward zero crossing; bounded RK4 localization; static bearing friction; no reverse"
		metadata.engine_atmosphere = "electric motor constants independent of density; propeller loads use stage density" if _weather.has_vertical_atmosphere() else "electric motor constants independent of density; propeller loads use field density"
		if battery_is_dynamic():
			metadata.continuous_layout = BATTERY_LAYOUT
			metadata.battery_model = "balanced-pack-ocv-resistance-no-regeneration-v1"
			metadata.battery_exhaustion = "remaining charge zero; all pack loads disconnected; bearing loss retained; not ESC LVC"
			metadata.battery_charge = "remaining coulombs integrated; SOC and consumed charge derived; terminal energy and pack heat integrated"
			metadata.battery_auxiliary = "prescribed pack-side current; no receiver/servo brownout or assistance model"
	if wheel_count() > 0:
		# The propulsion branches above describe wash/shaft/battery slots. Wheel speeds are appended after
		# every existing continuous slot, so add them last to keep the declared order accurate.
		var wheel_suffix := "wheel rim speeds in m/s, landing-gear contact order, appended continuous tail"
		var current_layout: String = str(metadata.continuous_layout)
		metadata.continuous_layout = wheel_suffix if current_layout == "none" else current_layout + "; " + wheel_suffix
		metadata.metadata_schema = "openrc-flight-meta v6"
	if glow_is_active():
		metadata.metadata_schema="openrc-flight-meta v7"
		metadata.propulsion_model=GlowFlight.LAW
		metadata.glow_identity=JSON.stringify(prop.glow.identity,"",true,true)
		metadata.glow_family=prop.glow.profile.family
		metadata.continuous_layout="rpm; fuel kg, temperature K, servo, admission, fuel transport kg/s, crank revolutions; running, reason, opportunities, fires, firing accumulator; mixture; shaft/prop/thrust/chemical work J"
		metadata.fuel_mass_policy="finite tank; uniform co-moving efflux; variable mass/CG/inertia; body datum remains initial wet CG"
		metadata.glow_recording_start=JSON.stringify(glow_state(),"",true,true)
	if not workshop_identity.is_empty():
		metadata.workshop = workshop_identity.duplicate(true)
		metadata.aircraft_input_hash_convention = "sha256 of exact frozen Workshop aircraft bytes"
	if _failures != null:
		metadata.failure_plan = JSON.stringify(_failures.plan(), "", true, true)
		metadata.failure_recording_start = JSON.stringify(_failures.snapshot(), "", true, true)
		metadata.failure_inputs = "pilot demand before failures; actual servo positions in aux; throttle follows resolved incident"
	if gear_is_retractable():
		metadata.metadata_schema = "openrc-flight-meta v8"
		metadata.gear_law = RetractableGear.LAW
		metadata.gear_trace_schema = "openrc-gear-trace v1"
		metadata.gear_aux_index = gear_aux_index()
		metadata.recording_start_gear = JSON.stringify(Array(sim.aux.slice(gear_aux_index(), gear_aux_index() + GEAR_AUX_SIZE)), "", true, true)
		metadata.input_layout = JSON.stringify(["roll", "pitch", "yaw", "throttle", "gear_down", "wheel_brake"])
		metadata.ground = "retractable tricycle; downlock point contacts; rudder nose steering; main wheel brakes; weight-on-wheels retraction interlock"
	if flaps_available():
		metadata.flap_base_metadata_schema = metadata.metadata_schema
		metadata.metadata_schema = "openrc-flight-meta v9"
		metadata.flap_law = Flaps.LAW
		metadata.flap_trace_schema = "openrc-flap-trace v1"
		metadata.flap_aux_index = flap_aux_index()
		metadata.flap_input_index = flap_input_index()
		metadata.flap_max_angle_deg = aircraft.model.flaps.max_angle_deg
		metadata.recording_start_flap = sim.aux[flap_aux_index()]
		var layout: Array = ["roll", "pitch", "yaw", "throttle"]
		if gear_is_retractable(): layout.append_array(["gear_down", "wheel_brake"])
		layout.append("flaps")
		metadata.input_layout = JSON.stringify(layout)
	metadata.runway_start_status = str(runway_start_outcome.get("status", "not_attempted"))
	metadata.runway_fallback = str(runway_start_outcome.get("fallback", "none"))
	metadata.aero_loads_law = Aero.LOADS_LAW if not model.get("envelope", {}).is_empty() else "global-derivatives-v1"
	metadata.wake_state_unit = Aero.WAKE_STATE_UNIT if downwash_index() >= 0 else "none"
	if turbine:
		metadata.turbine_loads_law = Turbine.LOADS_LAW
	return metadata


## Physics replay boundary, deliberately downstream of live input conditioning and menus.
## Owner configuration is fingerprinted in exact Variant encoding; derived caches are excluded.
func checkpoint() -> Dictionary:
	if not _flight_ready():
		return {}
	if gear_is_retractable() and (not _gear_aux_valid(sim.aux) or sim.inputs.size() != _input_count() \
			or sim.inputs[4] not in [0.0, 1.0] or not RetractableGear.valid_fraction(sim.inputs[5])):
		return {}
	if flaps_available() and (not _flap_aux_valid(sim.aux) or sim.inputs.size() != _input_count() \
			or not RetractableGear.valid_fraction(sim.inputs[flap_input_index()])):
		return {}
	var snapshot: Dictionary = sim.checkpoint()
	if snapshot.is_empty() or snapshot.modes.size() != (2 if _weather.has_turbulence() else 1) or snapshot.modes[0] < 0 or snapshot.modes[0] > 1:
		return {}
	if turbine_is_continuous() and (not is_finite(_turbine_rpm(sim.continuous)) \
			or (not engine_running and sim.continuous[0] != 0.0)):
		return {}
	var boundary: Dictionary = {format = "openrc-flight-checkpoint v1", configuration = _checkpoint_configuration(), simulation = snapshot}
	if not aircraft.model.get("envelope", {}).is_empty():
		boundary.aero_loads_law = Aero.LOADS_LAW
		boundary.wake_state_unit = Aero.WAKE_STATE_UNIT
	if Turbine.is_turbine(aircraft.model.propulsion):
		boundary.turbine_loads_law = Turbine.LOADS_LAW
	if gear_is_retractable():
		boundary.gear_law = RetractableGear.LAW
		boundary.gear_aux_index = gear_aux_index()
	if flaps_available():
		boundary.flap_law = Flaps.LAW
		boundary.flap_aux_index = flap_aux_index()
		boundary.flap_input_index = flap_input_index()
	if not weather_is_calm():
		boundary.format = "openrc-flight-checkpoint v2"
		boundary.weather_config = weather_configuration()
	if not atmosphere_is_reference():
		boundary.format = "openrc-flight-checkpoint v3"
		boundary.weather_config = weather_configuration()
	if _weather.has_vertical_atmosphere():
		boundary.atmosphere_law = _weather.atmosphere_law()
	if shaft_is_coupled():
		boundary.format = "openrc-flight-checkpoint v4"
		boundary.shaft_integrator = shaft_integrator()
		boundary.weather_config = weather_configuration()
	if Propulsion.is_electric(aircraft.model.propulsion):
		boundary.format = "openrc-flight-checkpoint v6" if battery_is_dynamic() else "openrc-flight-checkpoint v5"
		boundary.electric_law = electric_law()
	if turbine_is_continuous():
		boundary.format = "openrc-flight-checkpoint v8"
		boundary.turbine_law = Turbine.CONTINUOUS_LAW
		# Reference atmosphere ignores stored custom values. Do not make them change a pure-reference snapshot.
		boundary.weather_config = WeatherConfig.defaults() if weather_is_calm() and atmosphere_is_reference() else weather_configuration()
	if glow_is_active():
		boundary.format="openrc-flight-checkpoint v9"
		boundary.glow_law=GlowFlight.LAW
		boundary.mass_contact_law = MASS_CONTACT_LAW
	if wheel_count() > 0:
		boundary.wheel_state_layout = wheel_state_layout()
		boundary.wheel_profile_sha256 = str(aircraft.model.wheel_profile.get("profile_sha256", ""))
		boundary.wheel_profile_input_sha256 = str(aircraft.model.wheel_profile.get("input_sha256", ""))
	if not _collision_world.is_empty() or not _lake.is_empty():
		boundary.physics_format = str(boundary.format)
		boundary.format = "openrc-flight-checkpoint v7"
		if not _collision_world.is_empty():
			boundary.collision_world_identity = str(_collision_world.identity)
		if not _lake.is_empty():
			boundary.lake_identity = _lake_identity()
			boundary.lake_id = str(_lake.id)
		if not _collision_world.is_empty() and not _scenery_damage.is_empty():
			boundary.scenery_damage = _scenery_damage.duplicate(true)
	boundary.contact_state = contact_events()
	if not _contact_history_is_valid(boundary.contact_state, snapshot):
		return {}
	if _failures != null:
		boundary.failure_state = _failures.snapshot()
		if not _failures.can_restore(boundary.failure_state, sim.tick) \
				or (_failures.propulsion_cut_active() and not _failure_power_state_valid(snapshot)):
			return {}
		boundary.failure_physics_format = boundary.format
		boundary.format = FAILURE_CHECKPOINT_FORMAT
	return boundary


## A saved active source failure cannot advertise a running source to presentation or replay.
func _failure_power_state_valid(snapshot: Dictionary) -> bool:
	if not snapshot.get("modes") is PackedInt64Array or snapshot.modes.is_empty() or snapshot.modes[0] != 0:
		return false
	if glow_is_active():
		var continuous: Variant = snapshot.get("continuous")
		if not continuous is PackedFloat64Array or continuous.size() < GlowFlight.SIZE:
			return false
		return continuous[7] == 0.0 and continuous[8] == float(GlowFlight.REASONS.find("cut")) and continuous[5] == 0.0
	return true


func _checkpoint_configuration() -> String:
	return _configuration_for_weather(_weather)


func _configuration_for_weather(field: WeatherField) -> String:
	var config_hash := HashingContext.new()
	config_hash.start(HashingContext.HASH_SHA256)
	var parts: Array = [aircraft.model, ground_surfaces]
	if not aircraft.model.get("envelope", {}).is_empty():
		parts.append(Aero.LOADS_LAW + "; " + Aero.WAKE_STATE_UNIT)
	if Turbine.is_turbine(aircraft.model.propulsion):
		parts.append(Turbine.LOADS_LAW)
	if gear_is_retractable():
		parts.append(RetractableGear.LAW + "; inputs=6; aux=extension,accepted_down_target; airborne_up,runway_down")
	if flaps_available():
		parts.append(Flaps.LAW + "; appended normalized demand and sampled actuator; restart_up")
	if wheel_count() > 0:
		parts.append("wheel-state-layout:" + wheel_state_layout())
	if not field.is_calm() or field.has_atmosphere():
		parts.append(field.configuration())
	if field.has_vertical_atmosphere():
		parts.append(field.atmosphere_law() + "; datum=field_elevation-minus-NED-down; sample=stage-body-datum")
	if shaft_is_coupled():
		parts.append(BATTERY_LAYOUT if battery_is_dynamic() else "shaft-relative-rk4-locked-inertia-reaction-v1; wash-first,rpm-last")
	if Propulsion.is_electric(aircraft.model.propulsion):
		parts.append(electric_law())
	if turbine_is_continuous():
		parts.append(Turbine.CONTINUOUS_LAW + "; " + Turbine.CONTINUOUS_LAYOUT)
	if glow_is_active():
		parts.append(GlowFlight.LAW)
		parts.append(MASS_CONTACT_LAW)
	if soft_hull_contacts:
		# E3d1: soft hull contacts change the dynamics near the ground; legacy hashes stay unchanged.
		parts.append(HullContact.law())
	if not _collision_world.is_empty():
		parts.append("scenery-damage-policy:" + SceneryDamage.POLICY_VERSION)
		parts.append(SceneryDamage.THRESHOLDS_J)
		parts.append(SceneryDamage.BROKEN_PROFILES)
		parts.append("collision-world:" + str(_collision_world.identity))
	if not _lake.is_empty():
		parts.append("lake-geometry:" + _lake_identity())
	config_hash.update(var_to_bytes(parts))
	return config_hash.finish().hex_encode()


## Restoring switches to recorded-input replay and stays paused. No raw radio state is deserialized.
## A caller feeds sim.inputs and calls sim.step(); live-session saves are a separate future feature.
func restore_checkpoint(candidate: Dictionary) -> bool:
	var restored_failures: RefCounted = null
	if candidate.get("format") == FAILURE_CHECKPOINT_FORMAT:
		if typeof(candidate.get("failure_physics_format")) != TYPE_STRING \
				or candidate.failure_physics_format == FAILURE_CHECKPOINT_FORMAT \
				or not candidate.get("failure_state") is Dictionary or not candidate.get("simulation") is Dictionary:
			return false
		restored_failures = FailureRuntime.new()
		if typeof(candidate.simulation.get("tick")) != TYPE_INT \
				or not candidate.failure_state.get("plan") is Dictionary \
				or candidate.failure_state.plan.get("dt") != sim.dt() \
				or not restored_failures.restore(candidate.failure_state, candidate.simulation.tick):
			return false
		if not restored_failures.accepts_profile(FailureCatalog.profile_for_model(aircraft.model)):
			return false
		if restored_failures.propulsion_cut_active() and not _failure_power_state_valid(candidate.simulation):
			return false
		candidate = candidate.duplicate(true)
		candidate.format = candidate.failure_physics_format
		candidate.erase("failure_physics_format")
		candidate.erase("failure_state")
	elif candidate.has("failure_state") or candidate.has("failure_physics_format"):
		return false # older readers must never silently resume a damaged flight as a healthy one
	if not _has_valid_start() or typeof(candidate.get("format")) != TYPE_STRING \
			or candidate.format not in ["openrc-flight-checkpoint v1", "openrc-flight-checkpoint v2", "openrc-flight-checkpoint v3", "openrc-flight-checkpoint v4", "openrc-flight-checkpoint v5", "openrc-flight-checkpoint v6", "openrc-flight-checkpoint v7", "openrc-flight-checkpoint v8", "openrc-flight-checkpoint v9"] or typeof(candidate.get("configuration")) != TYPE_STRING \
			or not candidate.get("simulation") is Dictionary:
		return false
	var snapshot: Dictionary = candidate.simulation
	if not aircraft.model.get("envelope", {}).is_empty():
		if candidate.get("aero_loads_law") != Aero.LOADS_LAW or candidate.get("wake_state_unit") != Aero.WAKE_STATE_UNIT:
			return false
	elif candidate.has("aero_loads_law") or candidate.has("wake_state_unit"):
		return false
	if Turbine.is_turbine(aircraft.model.propulsion):
		if candidate.get("turbine_loads_law") != Turbine.LOADS_LAW:
			return false
	elif candidate.has("turbine_loads_law"):
		return false
	if gear_is_retractable():
		if candidate.get("gear_law") != RetractableGear.LAW or candidate.get("gear_aux_index") != gear_aux_index() \
				or not snapshot.get("aux") is PackedFloat64Array or not _gear_aux_valid(snapshot.aux) \
				or not snapshot.get("inputs") is PackedFloat64Array or snapshot.inputs.size() != _input_count() \
				or snapshot.inputs[4] not in [0.0, 1.0] or not RetractableGear.valid_fraction(snapshot.inputs[5]):
			return false
	elif candidate.has("gear_law") or candidate.has("gear_aux_index"):
		return false
	if flaps_available():
		if candidate.get("flap_law") != Flaps.LAW or candidate.get("flap_aux_index") != flap_aux_index() \
				or candidate.get("flap_input_index") != flap_input_index() \
				or not snapshot.get("aux") is PackedFloat64Array or not _flap_aux_valid(snapshot.aux) \
				or not snapshot.get("inputs") is PackedFloat64Array or snapshot.inputs.size() != _input_count() \
				or not RetractableGear.valid_fraction(snapshot.inputs[flap_input_index()]):
			return false
	elif candidate.has("flap_law") or candidate.has("flap_aux_index") or candidate.has("flap_input_index"):
		return false
	if glow_is_active():
		if candidate.get("mass_contact_law") != MASS_CONTACT_LAW:
			return false
	elif candidate.has("mass_contact_law"):
		return false
	var physics_format: String = str(candidate.get("physics_format", candidate.get("format", "")))
	if glow_is_active() != (physics_format=="openrc-flight-checkpoint v9") or (glow_is_active() and candidate.get("glow_law")!=GlowFlight.LAW):
		return false
	if physics_format not in ["openrc-flight-checkpoint v1", "openrc-flight-checkpoint v2", "openrc-flight-checkpoint v3", "openrc-flight-checkpoint v4", "openrc-flight-checkpoint v5", "openrc-flight-checkpoint v6", "openrc-flight-checkpoint v8", "openrc-flight-checkpoint v9"]:
		return false
	if turbine_is_continuous() != (physics_format == "openrc-flight-checkpoint v8") \
			or (turbine_is_continuous() and candidate.get("turbine_law") != Turbine.CONTINUOUS_LAW) \
			or (not turbine_is_continuous() and candidate.has("turbine_law")):
		return false
	var has_collision_world := not _collision_world.is_empty()
	var has_lake := not _lake.is_empty()
	if candidate.format == "openrc-flight-checkpoint v7":
		if (not has_collision_world and not has_lake) \
				or has_collision_world != candidate.has("collision_world_identity") \
				or (has_collision_world and candidate.get("collision_world_identity", "") != _collision_world.identity) \
				or has_lake != candidate.has("lake_identity") \
				or (has_lake and candidate.get("lake_identity", "") != _lake_identity()) \
				or (has_lake and candidate.get("lake_id", "") != str(_lake.id)):
			return false
	elif has_collision_world or has_lake or candidate.has("collision_world_identity") or candidate.has("lake_identity"):
		return false # Old snapshots do not identify terrain or obstacles used by deterministic tick filtering.
	if candidate.format != "openrc-flight-checkpoint v7" and candidate.has("scenery_damage"):
		return false
	var restored_damage: Dictionary = {}
	if candidate.has("scenery_damage"):
		if typeof(candidate.scenery_damage) != TYPE_DICTIONARY:
			return false
		restored_damage = candidate.scenery_damage.duplicate(true)
	if not _scenery_damage_is_valid(restored_damage, int(snapshot.get("tick", -1))):
		return false
	var electric: bool = Propulsion.is_electric(aircraft.model.propulsion)
	if electric != (physics_format in ["openrc-flight-checkpoint v5", "openrc-flight-checkpoint v6"]) \
			or (electric and candidate.get("electric_law") != electric_law()) \
			or battery_is_dynamic() != (physics_format == "openrc-flight-checkpoint v6"):
		return false
	if shaft_is_coupled() != (physics_format in ["openrc-flight-checkpoint v4", "openrc-flight-checkpoint v5", "openrc-flight-checkpoint v6", "openrc-flight-checkpoint v9"]) \
			or (shaft_is_coupled() and candidate.get("shaft_integrator") != shaft_integrator()):
		return false
	var restored_weather: WeatherField = _weather
	if physics_format in ["openrc-flight-checkpoint v2", "openrc-flight-checkpoint v3", "openrc-flight-checkpoint v4", "openrc-flight-checkpoint v5", "openrc-flight-checkpoint v6", "openrc-flight-checkpoint v8", "openrc-flight-checkpoint v9"]:
		var built: Dictionary = WeatherField.build(candidate.get("weather_config"))
		if not built.ok:
			return false
		if physics_format == "openrc-flight-checkpoint v2" and (built.field.is_calm() or built.field.has_atmosphere()):
			return false
		if physics_format == "openrc-flight-checkpoint v3" and not built.field.has_atmosphere():
			return false
		restored_weather = built.field
	elif not weather_is_calm() or not atmosphere_is_reference() or candidate.has("weather_config"):
		return false # a legacy physics-only boundary cannot hide non-calm forcing
	if restored_weather.has_vertical_atmosphere():
		if candidate.get("atmosphere_law") != restored_weather.atmosphere_law():
			return false
		for key in ["state", "previous"]:
			if not snapshot.get(key) is PackedFloat64Array or snapshot[key].size() != RB.SIZE \
					or not restored_weather.atmosphere(snapshot[key][RB.POS + 2]).get("ok", false):
				return false
	elif candidate.has("atmosphere_law"):
		return false
	if candidate.configuration != _configuration_for_weather(restored_weather):
		return false
	if wheel_count() > 0:
		var profile: Dictionary = aircraft.model.get("wheel_profile", {})
		if candidate.get("wheel_state_layout", "") != wheel_state_layout() \
				or candidate.get("wheel_profile_sha256", "") != str(profile.get("profile_sha256", "")) \
				or candidate.get("wheel_profile_input_sha256", "") != str(profile.get("input_sha256", "")):
			return false
	elif candidate.has("wheel_state_layout") or candidate.has("wheel_profile_sha256") or candidate.has("wheel_profile_input_sha256"):
		return false
	var turbulent: bool = restored_weather.has_turbulence()
	var expected_aux: int = turbulence_index() + 7 if turbulent else (
		turbulence_index() if _weather.has_turbulence() else sim.aux.size())
	var expected_modes: int = 2 if turbulent else 1
	if not sim.can_restore_checkpoint(snapshot, expected_aux, expected_modes) \
			or snapshot.modes[0] < 0 or snapshot.modes[0] > 1:
		return false
	if turbine_is_continuous() and snapshot.modes[0] == 0 and snapshot.continuous[0] != 0.0:
		return false
	if turbulent:
		var expected_time: float = max(0, snapshot.tick - 1) * snapshot.dt
		if snapshot.aux[expected_aux - 1] != expected_time:
			return false
		for axis: int in 3:
			if restored_weather.turbulence_rms()[axis] == 0.0 and (snapshot.aux[expected_aux - 7 + axis] != 0.0 or snapshot.aux[expected_aux - 4 + axis] != 0.0):
				return false
	for at in range(AUX_ANCHORS + 2, mini(snapshot.aux.size(), AUX_ANCHORS + anchor_count() * Ground.ANCHOR_STRIDE), Ground.ANCHOR_STRIDE):
		if snapshot.aux[at] != 0.0 and snapshot.aux[at] != 1.0:
			return false # an anchor is stuck or sliding, nothing in between
	var restored_contacts: Dictionary
	if candidate.has("contact_state"):
		if not _contact_history_is_valid(candidate.contact_state, snapshot):
			return false
		restored_contacts = candidate.contact_state.duplicate(true)
	else:
		restored_contacts = _legacy_contact_history(snapshot)
	resetting.emit() # close recording before the clock moves backwards
	# Layout was fully preflighted above; resize only at this owner-controlled environment boundary.
	var old_aux: PackedFloat64Array = sim.aux
	var old_modes: PackedInt64Array = sim.modes
	sim.aux = snapshot.aux.duplicate()
	sim.modes = snapshot.modes.duplicate()
	if not sim.restore_checkpoint(snapshot):
		sim.aux = old_aux
		sim.modes = old_modes
		return false
	if gear_is_retractable():
		_gear_requested_down = snapshot.inputs[4] == 1.0
		_wheel_brake_demand = snapshot.inputs[5]
		_gear_cache_fraction = -1.0
		_gear_request_inhibited = false
	_flap_requested = snapshot.inputs[flap_input_index()] if flaps_available() else 0.0
	_failures = restored_failures
	_scenery_damage = restored_damage
	_restore_contact_history(restored_contacts)
	soft_contacts = HullContact.contacts(sim.previous, sim.state, _hull_contact) if soft_hull_contacts else []
	_clear_pending_scenery_damage()
	_weather = restored_weather
	_weather_pending_reset = false
	_shaft_pending_reset = false
	_turbulence_aux_index = expected_aux - 7 if turbulent else -1
	# v1 checkpoints contain physics only, not the source flight's launch provenance. Never attribute the
	# restored state to this destination session's earlier launch. reset() will establish a new known launch.
	_launch_metadata = {
		selected_start_choice = "unknown", launch_choice = "unknown", launch_kind = "checkpoint_restore",
		launch_field_id = "", launch_state = "[]", launch_aux = "[]", launch_ground_anchors = "[]",
		launch_engine_running = "unknown", launch_error = "",
	}
	input_enabled = false
	crash = {}
	_last_scenery_event = null
	_last_lake_event = null
	pause_reason = "checkpoint restored (recorded inputs)"
	_deflection_key = PackedFloat64Array()
	scenery_damage_changed.emit()
	contact_events_changed.emit()
	return true


func _scenery_damage_is_valid(damage: Dictionary, snapshot_tick: int) -> bool:
	if snapshot_tick < 0:
		return false
	if damage.is_empty():
		return true
	var groups: Dictionary = {}
	for proxy: Dictionary in _collision_world.get("proxies", []):
		var damage_id: String = str(proxy.get("damage_id", ""))
		if damage_id.is_empty():
			continue
		var profile: String = str(proxy.get("damage_profile", ""))
		if not groups.has(damage_id):
			groups[damage_id] = { profile = profile, mixed = false, obstacles = {} }
		elif str(groups[damage_id].profile) != profile:
			groups[damage_id].mixed = true
		groups[damage_id].obstacles[str(proxy.get("id", ""))] = true
	for raw_id: Variant in damage.keys():
		if typeof(raw_id) != TYPE_STRING or str(raw_id).is_empty() or not groups.has(str(raw_id)):
			return false
		var record: Variant = damage[raw_id]
		if typeof(record) != TYPE_DICTIONARY:
			return false
		var installed: Dictionary = groups[str(raw_id)]
		if installed.mixed or typeof(record.get("profile")) != TYPE_STRING \
				or not SceneryDamage.profile_is_valid(str(record.profile)) or str(record.profile) == "none" \
				or str(record.profile) != str(installed.profile) \
				or typeof(record.get("state")) != TYPE_STRING or typeof(record.get("tick")) != TYPE_INT \
				or typeof(record.get("energy_j")) not in [TYPE_FLOAT, TYPE_INT] \
				or typeof(record.get("obstacle_id")) != TYPE_STRING or str(record.obstacle_id).is_empty():
			return false
		var state: String = str(record.state)
		var tick: int = int(record.tick)
		var energy: float = float(record.energy_j)
		if tick < 1 or tick > snapshot_tick or not is_finite(energy) \
				or energy < SceneryDamage.threshold_j(str(record.profile)) \
				or SceneryDamage.impact_state(str(record.profile), energy) != state \
				or not installed.obstacles.has(str(record.obstacle_id)):
			return false
		for field: String in ["point_ned", "normal_ned", "velocity_ned"]:
			var vector: Variant = record.get(field)
			if typeof(vector) != TYPE_PACKED_FLOAT64_ARRAY or vector.size() != 3:
				return false
			for component: float in vector:
				if not is_finite(component):
					return false
		var normal: PackedFloat64Array = record.normal_ned
		var normal_length: float = M.norm(normal)
		if not is_finite(normal_length) or normal_length <= 0.0:
			return false
	return true
