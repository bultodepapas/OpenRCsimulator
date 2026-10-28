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
const SPATIAL_CHECKPOINT_FORMAT := "openrc-flight-checkpoint v12"
const SPATIAL_RECEIPT_FORMAT := "openrc-spatial-weather-receipt v1"
const WindFlow := preload("res://physics/wind_aircraft_flow.gd")
signal failure_changed
## UI-FS-04: observational receipt after a reset transaction succeeds; never part of solver state.
signal statistics_lifecycle(receipt: Dictionary)
var statistics_generation: int = 0
var _statistics_operation: int = 0
var _statistics_reload_depth: int = 0
var _failures: RefCounted = null
var failure_error: String = ""


## One resolved episode per new flight. Restart reuses it; ordinary technical flights remain unchanged.
func setup_failures(config: Dictionary, seed_value: int) -> bool:
	if _reject_reset_publication_reentry(): return false
	var checked: Dictionary = FailureConfig.validate(config)
	if not checked.ok or sim == null or sim.tick != 0 or not physics_enabled or not _flight_ready():
		failure_error = "Failure settings require a valid physics flight at tick zero."
		return false
	var candidate: RefCounted = FailureRuntime.new()
	var request: Dictionary = FailureCatalog.request_for_model(checked.config, aircraft.model)
	if not candidate.begin(request, seed_value, sim.dt(), FailureCatalog.profile_for_model(aircraft.model)):
		failure_error = FailureRuntime.NO_ELIGIBLE_MESSAGE if candidate.last_error == FailureRuntime.NO_ELIGIBLE_MESSAGE \
			else "Failure seed or timestep is invalid."
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

const OutOfTrim := preload("res://sim/out_of_trim.gd")
## D6-TRIM-01: a non-zero airframe offset wraps the flight checkpoint, outermost, so a replay flies the same airframe.
const OUT_OF_TRIM_CHECKPOINT_FORMAT := "openrc-flight-checkpoint v13"
## D6-TRIM-01: the natural out-of-trim selection and its airframe draws ({} when off): config, seed, key, unit, drawn.
var _out_of_trim: Dictionary = {}
## Offsets [roll, pitch, yaw] in maximum-throw units that the aerodynamics add to the actual servo positions this flight
## (sim/out_of_trim.gd). Zero when off. The trims, the servo state and the start trim solver never contain them.
var _airframe_offset := PackedFloat64Array([0.0, 0.0, 0.0])
## Shared with the shell for the app session, never copied: airframe key -> {unit, intensity_percent, pilot_trim}.
var _out_of_trim_airframes: Dictionary = {}
var out_of_trim_error: String = ""


## One selection per new flight at tick zero, like setup_failures(); the next reset rigs the airframe. First flight only
## reuses the airframe recorded under `airframe_key` at the same intensity, and the trim the pilot gave it.
func setup_out_of_trim(config: Dictionary, seed_value: int, airframes: Dictionary = {}, airframe_key: String = "") -> bool:
	if _reject_reset_publication_reentry(): return false
	var checked: Dictionary = OutOfTrim.validate(config)
	if not checked.ok:
		out_of_trim_error = "; ".join(checked.errors)
		return false
	if not checked.config.enabled:
		_out_of_trim = {}
		out_of_trim_error = ""
		return true
	if sim == null or sim.tick != 0 or not physics_enabled or not _flight_ready():
		out_of_trim_error = "Out-of-trim settings require a valid physics flight at tick zero."
		return false
	if seed_value < 0 or seed_value > 4294967295:
		out_of_trim_error = "Out-of-trim seed must fit an unsigned 32-bit integer."
		return false
	_out_of_trim_airframes = airframes
	_out_of_trim = {config = checked.config, seed = seed_value, key = airframe_key, unit = PackedFloat64Array(), drawn = 0}
	if checked.config.mode == OutOfTrim.MODE_FIRST_FLIGHT:
		var record: Dictionary = OutOfTrim.carried_record(airframes.get(airframe_key), checked.config)
		if not record.is_empty():
			_out_of_trim.unit = record.unit
			_set_trims_from_start(record.pilot_trim)
	out_of_trim_error = ""
	return true


func out_of_trim_active() -> bool:
	return not _out_of_trim.is_empty()


## The airframe this flight flies: offsets in maximum-throw units and degrees, and the pilot's trim beyond the start trim.
func out_of_trim_status() -> Dictionary:
	if _out_of_trim.is_empty():
		return {active = false}
	var throws: Dictionary = throws_deg()
	return {active = true, mode = _out_of_trim.config.mode, intensity_percent = _out_of_trim.config.intensity_percent,
		offset = _airframe_offset.duplicate(), pilot_trim = _pilot_trim_offset(),
		offset_deg = {aileron = _airframe_offset[0] * float(throws.get("aileron", 0.0)),
			elevator = _airframe_offset[1] * float(throws.get("elevator", 0.0)),
			rudder = _airframe_offset[2] * float(throws.get("rudder", 0.0))}}


## The pilot's trim beyond the solved start trim [roll, pitch, yaw], in trim units.
func _pilot_trim_offset() -> PackedFloat64Array:
	if not _has_valid_start():
		return PackedFloat64Array([0.0, 0.0, 0.0])
	return PackedFloat64Array([float(trims.roll) - float(start.roll_command), float(trims.pitch) - float(start.pitch_command),
		float(trims.yaw) - float(start.get("yaw_command", 0.0))])


func _set_trims_from_start(pilot_trim: PackedFloat64Array) -> void:
	if not _has_valid_start():
		return
	trims = {roll = clampf(float(start.roll_command) + pilot_trim[0], -1.0, 1.0),
		pitch = clampf(float(start.pitch_command) + pilot_trim[1], -1.0, 1.0),
		yaw = clampf(float(start.get("yaw_command", 0.0)) + pilot_trim[2], -1.0, 1.0)}


## Reset staging: every flight rigs a new airframe; first flight only keeps one airframe all session. Off, a restart
## flies a true airframe again, even after restoring a recorded out-of-trim checkpoint.
func _stage_out_of_trim() -> void:
	if _out_of_trim.is_empty():
		if not OutOfTrim.is_zero(_airframe_offset):
			_airframe_offset = PackedFloat64Array([0.0, 0.0, 0.0])
			_deflection_key = PackedFloat64Array()
		return
	if _out_of_trim.config.mode == OutOfTrim.MODE_EVERY_FLIGHT or _out_of_trim.unit.is_empty():
		_out_of_trim.unit = OutOfTrim.draw(_out_of_trim.seed, _out_of_trim.drawn)
		_out_of_trim.drawn += 1
	_airframe_offset = OutOfTrim.offsets(_out_of_trim.unit, _out_of_trim.config.intensity_percent, throws_deg())
	_deflection_key = PackedFloat64Array()


## The trims a restart flies with: the solved start trim, plus the pilot's own trim on first flight only.
func _restore_out_of_trim_trims(carried: PackedFloat64Array) -> void:
	if _out_of_trim.is_empty():
		return
	var keep: bool = _out_of_trim.config.mode == OutOfTrim.MODE_FIRST_FLIGHT
	_set_trims_from_start(carried if keep else PackedFloat64Array([0.0, 0.0, 0.0]))


## First flight only: the shell's registry keeps this airframe and the pilot's trim for the next flight of the session.
func _remember_out_of_trim_airframe() -> void:
	if _out_of_trim.is_empty() or _out_of_trim.config.mode != OutOfTrim.MODE_FIRST_FLIGHT or _out_of_trim.unit.is_empty():
		return
	_out_of_trim_airframes[_out_of_trim.key] = {unit = _out_of_trim.unit.duplicate(),
		intensity_percent = _out_of_trim.config.intensity_percent, pilot_trim = _pilot_trim_offset()}

const EventStep: Script = preload("res://physics/event_step.gd")
const GlowFlight: Script = preload("res://physics/glow/flight.gd")
const FuelSample := preload("res://sim/fuel_sample.gd")
const CheckpointJson := preload("res://sim/checkpoint_json.gd")
## Fixed original wet-CG datum; live contact mobility and linear fuel sampling at swept crossing fractions.
const MASS_CONTACT_LAW := "fixed-datum-live-mass-contact-linear-fuel-v1"
const BatteryStep: Script = preload("res://physics/electric_battery_step.gd")
const BATTERY_LAW: String = "electric-ocv-resistance-coupled-events-v1"
const BATTERY_LAYOUT: String = "axial wash increment m/s, slipstream.pieces order, then propeller shaft rpm, remaining charge C, terminal energy J, pack heat J; RK4 coupled"
## BAT-10: Thevenin pack (docs/research/battery/BAT-04/specification.md §5). Sampled ESC slots have zero rate.
const PackEcm: Script = preload("res://physics/battery/pack_ecm.gd")
const EscSupervisor: Script = preload("res://physics/battery/esc_supervisor.gd")
const PACK_LAW: String = "electric-pack-ecm-coupled-events-v1"
const PACK_LAYOUT: String = "axial wash increment m/s, slipstream.pieces order, then propeller shaft rpm, weak-cell remaining charge C, terminal energy J, pack loss J, average-cell RC V, weak-cell RC V, pack temperature K, ESC sensed V, ESC limit, ESC phase, ESC timer s, ESC detected cells; RK4 coupled; ESC slots sampled at accepted endpoints"
const PACK_MODEL: String = "average-plus-weakest-cell-thevenin-lumped-thermal-no-regeneration-v1"
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
	if _reject_reset_publication_reentry(): return false
	if typeof(mode) != TYPE_STRING or mode not in ["split", "coupled-rk4"]:
		shaft_error = "shaft integrator must be split or coupled-rk4"
		return false
	if sim != null and sim.tick > 0:
		shaft_error = "shaft integration changes require a new flight"
		return false
	if mode == "coupled-rk4" and aircraft.get("ok", false) and not _supports_coupled_shaft(aircraft.model):
		shaft_error = "coupled-rk4 requires a propeller shaft model with positive rotor inertia"
		return false
	if mode == "split" and aircraft.get("ok", false) and (Propulsion.is_electric(aircraft.model.propulsion) or glow_is_active() or (liquid_fuel_is_active() and not Turbine.is_turbine(aircraft.model.propulsion))):
		shaft_error = "finite propeller propulsion requires coupled-rk4"
		return false
	if mode == _shaft_integrator:
		_shaft_explicit = true
		shaft_error = ""
		return true
	if sim == null:
		_shaft_explicit = true
		_shaft_integrator = mode
		_shaft_pending_reset = false
		shaft_error = ""
		return true
	var transaction := _begin_start_transaction()
	# Capture the old recorder boundary before selecting the new layout. Reading
	# that checkpoint may invoke a model validator, so preparation is guarded too.
	var intact: bool = sim._endpoint_guard_matches(transaction.kernel)
	for field: String in _START_OWNER_FIELDS:
		intact = intact and Sim._guard_values_equal(get(field), transaction.owner[field])
	if _reset_transaction_reentry or not intact:
		_refuse_start_transaction(transaction, "shaft preparation changed the installed owner")
		shaft_error = "shaft preparation changed the installed owner"
		return false
	_shaft_explicit = true
	_shaft_integrator = mode
	_shaft_pending_reset = true
	var callbacks: Dictionary = PropulsionRuntime.prepare_callbacks(self)
	if not callbacks.ok:
		_refuse_start_transaction(transaction, "shaft callback preparation failed")
		shaft_error = "shaft callback preparation failed: " + str(callbacks.get("errors", []))
		return false
	_install_continuous_callbacks(callbacks)
	shaft_error = ""
	_prepare_stage_backend()
	# Pending selection is accepted now. The explicit reset still constructs the
	# physical layout and owns statistics credit; no sample is published here.
	transaction.committed = true
	_reset_physical_committed = true
	sim.reset_observer_fault = ""
	sim._publish_committed_boundary(func() -> void:
		_reset_publication_active = true
		_reset_closing_context = transaction.closing
		resetting.emit()
		_reset_closing_context = {}
		_reset_publication_active = false, false, "shaft configuration", true)
	_end_start_transaction(transaction)
	if not sim.reset_observer_fault.is_empty():
		shaft_error = sim.reset_observer_fault
		pause_reason = "simulation fault: " + shaft_error
	return true


func shaft_integrator() -> String:
	return _shaft_integrator


func shaft_is_coupled() -> bool:
	return _shaft_integrator == "coupled-rk4"


func glow_is_active() -> bool:
	if _fact_glow != _FACT_UNKNOWN:
		return _fact_glow == 1
	var active: bool = aircraft.get("ok", false) and Propulsion.is_glow(aircraft.model.propulsion)
	if _facts_armed: _fact_glow = int(active)
	return active


func glow_state() -> Dictionary:
	return GlowFlight.telemetry(self) if glow_is_active() and _flight_ready() else {ok=false}


## FUEL-07: the start fill of a finite-fuel tank as a fraction (0, 1] of the authored full tank. Every reset
## refuels to it; checkpoints store both actual fuel and the selected reset/provenance policy.
var fuel_start_fill: float = 1.0
const FUEL_SESSION_FORMAT := "openrc-fuel-session v1"
var _fuel_start_fill_known := true


func set_fuel_start_fill(fill: float) -> bool:
	if _reject_reset_publication_reentry(): return false
	if not is_finite(fill) or fill <= 0.0 or fill > 1.0:
		return false
	if liquid_fuel_is_active() and fill * float(aircraft.model.propulsion.liquid_fuel.capacity_kg) <= float(aircraft.model.propulsion.liquid_fuel.unusable_kg):
		return false
	if glow_is_active() and fill * float(aircraft.model.propulsion.glow.capacity_fuel_kg) <= float(aircraft.model.propulsion.glow.unusable_fuel_kg):
		return false
	fuel_start_fill = fill
	_fuel_start_fill_known = true
	_trim_density = NAN # the selected launch inventory needs its own equilibrium on reset
	return true


## Fuel mass a reset loads into a finite tank.
func start_fuel_kg() -> float:
	if liquid_fuel_is_active():
		return float(aircraft.model.propulsion.liquid_fuel.capacity_kg) * fuel_start_fill
	var install: Dictionary = aircraft.model.propulsion.glow
	return float(install.get("capacity_fuel_kg", install.initial_fuel_kg)) * fuel_start_fill


func liquid_fuel_is_active() -> bool:
	return aircraft.get("ok", false) and not aircraft.model.propulsion.get("liquid_fuel", {}).is_empty()


func finite_fuel_is_active() -> bool:
	return glow_is_active() or liquid_fuel_is_active()


## Presentation reads accepted combustion state, separately from the ignition command.
func propulsion_source_running() -> bool:
	if not propulsion_power_enabled():
		return false
	if liquid_fuel_is_active():
		return LiquidFlight.valid(self, sim.continuous) and sim.continuous[_liquid_index() + 1] == 1.0
	if glow_is_active():
		return sim.continuous.size() >= GlowFlight.SIZE and sim.continuous[7] == 1.0
	return true


func _liquid_index() -> int:
	return wheel_index() + wheel_count()


func _liquid_properties(values: PackedFloat64Array) -> Dictionary:
	return LiquidFlight.properties(self, values)


## FUEL-06: one live mass-properties sample of the accepted state, the single source for presentation (HUD load
## factor, crash severity/effective mass/CG marker, fuel remaining). {ok, mass_kg, cg_body_m (body FRD from the
## fixed datum O), inertia and inverse (about the CG), fuel_remaining_kg, finite_fuel}. Finite fuel evaluates the
## shared fixed-datum kernel at the remaining tank mass; every other aircraft is its constant validated build.
func mass_properties() -> Dictionary:
	if liquid_fuel_is_active() and _flight_ready():
		return LiquidFlight.sample(self, sim.continuous)
	if glow_is_active() and _flight_ready():
		var context: Dictionary = GlowFlight.mass_context(self, sim.continuous)
		if not context.get("ok", false):
			return {ok = false}
		var sample: Dictionary = FuelSample.build(context.properties, context.tanks, context.remaining,
			sim.tick, sim.time(), true)
		sample.law = GlowFlight.LAW
		sample.registry_sha256 = str(aircraft.model.fuel_system.registry_sha256)
		return sample
	if sim == null or sim.inertia.size() != 6 or not is_finite(sim.mass) or sim.mass <= 0.0:
		return {ok = false}
	var properties := {ok = true, mass_kg = sim.mass, cg_body_m = PackedFloat64Array([0.0, 0.0, 0.0]),
		inertia = sim.inertia.duplicate(), inverse = RB.inertia_inverse(sim.inertia),
		fuel_remaining_kg = NAN, finite_fuel = false}
	return FuelSample.build(properties, [], {}, sim.tick, sim.time(), false)


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
	if not GlowFlight.valid(sim.continuous,install): return false
	var current: Dictionary=GlowFlight.unpack(sim.continuous,install)
	if current.is_empty() or current.running: return false
	var mode: int=int(sim.continuous[GlowFlight.SOURCE_MODE_INDEX])
	var line_fuel: float=sim.continuous[GlowFlight.LINE_FUEL_INDEX]
	var prime: float=install.settings.starter_prime_kg
	var available: float=current.fuel_kg-line_fuel-install.unusable_fuel_kg if mode==GlowFlight.MODE_MAIN_TANK else line_fuel
	# A starter does not refill a spent line or make unusable tank residue reachable.
	if mode==GlowFlight.MODE_STARVED or available<=prime: return false
	var rpm: float=maxf(sim.continuous[0],install.settings.minimum_start_rpm)
	var started: Dictionary=GlowFlight.Life.request_start(install.profile,install.settings,current,rpm,true)
	if not started.get("started",false): return false
	var next: Dictionary=started.state
	next.fuel_kg-=prime
	if mode==GlowFlight.MODE_FEED_LINE: line_fuel-=prime
	var source: Dictionary=GlowFlight.Source.evaluate(install.profile,rpm,GlowFlight.admission_at(install,next.air_fraction,rpm),sim.continuous[12],1.225*engine_charge_ratio(),true)
	if not source.ok: return false
	next.fuel_transport_kg_s=source.delivered_fuel_kg_s
	var candidate: PackedFloat64Array=GlowFlight.put_state(sim.continuous,next)
	candidate[0]=rpm
	candidate[GlowFlight.LINE_FUEL_INDEX]=line_fuel
	if not GlowFlight.valid(candidate,install): return false
	var mass: Dictionary=GlowFlight.properties(self,next.fuel_kg,line_fuel)
	if not mass.ok: return false
	var prop: Dictionary=aircraft.model.propulsion
	var impulse: float=prop.rotor_inertia*(rpm-sim.continuous[0])*TAU/60.0
	var correction: PackedFloat64Array=RB.inertia_mul(mass.inverse,M.scale(prop.axis,-impulse))
	var velocity_correction: PackedFloat64Array=M.cross(correction,mass.cg_body_m)
	for i in 3:
		sim.state[RB.RATE+i]+=correction[i]
		sim.state[RB.VEL+i]-=velocity_correction[i]
	sim.continuous=candidate
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
	if Propulsion.has_pack_ecm(prop):
		ratio += _pack_step_ratio(prop)
	elif Propulsion.has_dynamic_battery(prop):
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


## BAT-10: conservative sum of the pack's fastest eigenvalues times dt: charge/OCV feedback through Rm on the
## weakest cell, the shortest RC time constant and the ESC voltage filter. Thermal time constants are minutes.
func _pack_step_ratio(prop: Dictionary) -> float:
	var battery: Dictionary = prop.battery
	var knots: PackedFloat64Array = battery.soc_knots
	var nz: int = knots.size()
	var ocv: PackedFloat64Array = battery.ocv
	var slope: float = 0.0
	for row: int in ocv.size() / nz:
		for i: int in range(1, nz):
			slope = maxf(slope, (ocv[row * nz + i] - ocv[row * nz + i - 1]) / (knots[i] - knots[i - 1]))
	var weak_capacity: float = float(battery.weak_capacity_factor) * float(battery.group_capacity_c)
	var ratio: float = sim.dt() * float(battery.series) * slope / (float(prop.motor.resistance_ohm) * weak_capacity)
	var tau_min: float = INF
	for table: PackedFloat64Array in battery.rc_tau:
		for tau: float in table:
			tau_min = minf(tau_min, tau)
	if is_finite(tau_min):
		ratio += sim.dt() / tau_min
	return ratio + sim.dt() / float(battery.lvc_filter_s)


## Configure only at a launch boundary, then reset() to build the selected start in this air mass.
## Rejected settings never alter the existing flight, field or recorder.
func setup_weather(settings: Variant) -> bool:
	if _reject_reset_publication_reentry(): return false
	var built: Dictionary = WeatherField.build(settings)
	if not built.ok:
		weather_error = "; ".join(built.errors)
		return false
	if sim != null and sim.tick > 0:
		weather_error = "weather changes require a new flight or reset boundary"
		return false
	# Before setup there is no installed flight or recorder to close.
	if sim == null:
		_weather = built.field
		_weather_pending_reset = false
		weather_error = ""
		return true
	var transaction := _begin_start_transaction()
	# Even obtaining the old closing checkpoint can invoke the model validator.
	# Refuse before notification if that read attempted to change the owner.
	var intact: bool = sim._endpoint_guard_matches(transaction.kernel)
	for field: String in _START_OWNER_FIELDS:
		intact = intact and Sim._guard_values_equal(get(field), transaction.owner[field])
	if _reset_transaction_reentry or not intact:
		_refuse_start_transaction(transaction, "weather preparation changed the installed owner")
		weather_error = "weather preparation changed the installed owner"
		return false
	_weather = built.field
	_weather_pending_reset = true
	weather_error = ""
	_prepare_stage_backend()
	# This accepts a pending configuration, not a new physical start. Keep the
	# historical setup_weather(); reset() contract, with no tick or credit here.
	transaction.committed = true
	_reset_physical_committed = true # Post-acceptance presentation holds are legal.
	sim.reset_observer_fault = ""
	sim._publish_committed_boundary(func() -> void:
		_reset_publication_active = true
		_reset_closing_context = transaction.closing
		resetting.emit()
		_reset_closing_context = {}
		_reset_publication_active = false, false, "weather configuration", true)
	_end_start_transaction(transaction)
	if not sim.reset_observer_fault.is_empty():
		weather_error = sim.reset_observer_fault
		pause_reason = "simulation fault: " + weather_error
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


## Position of the fixed body datum O in world NED metres. Stage callers supply their own state;
## the empty argument is only the accepted-endpoint view used by presentation and recording.
func _atmosphere_position(s: PackedFloat64Array = PackedFloat64Array()) -> PackedFloat64Array:
	if not s.is_empty():
		return s.slice(RB.POS, RB.POS + 3) if s.size() == RB.SIZE else M.v3(NAN, NAN, NAN)
	return sim.state.slice(RB.POS, RB.POS + 3) if sim != null and sim.state.size() == RB.SIZE else M.v3(0.0, 0.0, 0.0)


func environment_at(s: PackedFloat64Array) -> Dictionary:
	return environment.air_world(_atmosphere_position(s))


func atmosphere_configuration(s: PackedFloat64Array = PackedFloat64Array()) -> Dictionary:
	return environment.air(_atmosphere_down(s))


func atmosphere_is_reference() -> bool:
	return not _weather.has_atmosphere()


func air_density(s: PackedFloat64Array = PackedFloat64Array()) -> float:
	return environment.air_density(_atmosphere_down(s))


func engine_charge_ratio(s: PackedFloat64Array = PackedFloat64Array()) -> float:
	return environment.engine_charge_ratio(_atmosphere_down(s))


## M5-W05b-R1: pure position/time query. Never substitute the committed position for an RK stage.
## Existing one-argument observers see wind at the accepted endpoint; legacy fields remain uniform.
func wind_at(time_s: float, s: PackedFloat64Array = PackedFloat64Array()) -> PackedFloat64Array:
	if _weather_pending_reset:
		return M.v3(NAN, NAN, NAN)
	return environment.wind_world(_atmosphere_position(s), time_s)


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
## The no-argument legacy datum sample remains available; spatial runway equilibrium also receives
## a fresh candidate-state Air callback so it never uses this one vector for all surfaces.
func _initial_wind(position_ned: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0])) -> PackedFloat64Array:
	var wind: PackedFloat64Array = _weather.sample_world(position_ned, 0.0)
	var initial: Dictionary = _initial_turbulence()
	for axis: int in 3:
		wind[axis] += initial.values[axis]
	return wind


func air_data(s: PackedFloat64Array, time_s: float = NAN) -> Dictionary:
	var at: float = sim.time() if is_nan(time_s) else time_s
	if _weather.is_spatial() and not _weather_pending_reset:
		var sampled := WindFlow.stage_air(s, aircraft.model, environment, at, air_density(s),
			Aero.SPATIAL_CONTINUATION_LAW, false)
		if sampled.ok:
			return sampled.air
		# Consumers already reject nonfinite flow; never substitute calm/datum flow on failure.
		return Air.compute(s, M.v3(NAN, NAN, NAN), air_density(s))
	return Air.compute(s, wind_at(at, s), air_density(s))


## Pure reset-time producer for each runway candidate; independent of the accepted tick and OU window.
func _initial_air_sampler(model: Dictionary) -> Callable:
	if not _weather.is_spatial():
		return Callable()
	return func(state: PackedFloat64Array, rho: float) -> Dictionary:
		return WindFlow.stage_air(state, model, environment, 0.0, rho, Aero.SPATIAL_CONTINUATION_LAW, false)


func _spatial_weather_receipt(field: WeatherField) -> Dictionary:
	return {format = SPATIAL_RECEIPT_FORMAT, field = field.spatial_identity(),
		content_sha256 = field.spatial_content_hash(), point_air_law = WindFlow.STAGE_AIR_LAW,
		aerodynamic_law = Aero.SPATIAL_CONTINUATION_LAW,
		clock = "simulation-seconds-plus-immutable-epoch-offset; reset-reuses-epoch-v1"}


## JSON changes dictionary key/numeric Variant types. Compare detached JSON structures without
## losing float64 precision; exact keys, values and law identities remain required.
static func spatial_receipt_matches(candidate: Variant, expected: Dictionary) -> bool:
	if typeof(candidate) != TYPE_DICTIONARY:
		return false
	return JSON.parse_string(JSON.stringify(candidate, "", true, true)) == \
		JSON.parse_string(JSON.stringify(expected, "", true, true))

const Commands := preload("res://input/commands.gd")
const ControlActuators := preload("res://physics/control_actuators.gd")
const Keyboard := preload("res://input/keyboard.gd")
const RcInput := preload("res://input/rc_input.gd")
const RcCalibration := preload("res://input/rc_calibration.gd")
const Sim := preload("res://sim/simulation.gd")
const VehicleModel := preload("res://sim/vehicle_model.gd")
const NativeStage := preload("res://sim/native_stage.gd")
const NATIVE_CHECKPOINT_FORMAT := "openrc-flight-checkpoint v14"

var _stage_backend_requested := "gdscript_reference"
var _native_stage: RefCounted = null
var stage_backend_error := ""


## Experimental launch-time choice. A live session cannot silently change solver identity.
func setup_stage_backend(mode: String) -> bool:
	if _reject_reset_publication_reentry(): return false
	if sim != null or mode not in [NativeStage.BACKEND_REFERENCE, NativeStage.BACKEND_NATIVE]:
		stage_backend_error = "stage backend must be native or gdscript_reference and selected before setup"
		return false
	_stage_backend_requested = mode
	stage_backend_error = ""
	return true


func stage_backend_identity() -> Dictionary:
	return _native_stage.backend_identity() if _native_stage != null and _native_stage.owns_stage(self) \
		else NativeStage.reference_identity()


func stage_backend_status() -> Dictionary:
	return {requested = _stage_backend_requested, identity = stage_backend_identity(), reason = stage_backend_error}


## Fresh candidate, never mutate the helper retained by an uncommitted start transaction. Called only outside
## kernel evaluation/publication, after the complete aircraft/environment/layout revision has been staged.
func _prepare_stage_backend(time_now := NAN, backend := "") -> void:
	if _native_stage != null:
		_native_stage.restore_reference_callback(self)
	_native_stage = null
	stage_backend_error = ""
	var selected: String = _stage_backend_requested if backend.is_empty() else backend
	if selected != NativeStage.BACKEND_NATIVE or sim == null or not aircraft.get("ok", false):
		return
	if _weather_pending_reset or _shaft_pending_reset:
		stage_backend_error = "pending configuration requires reset"
		return
	# Production opt-in is bounded by the qualified stock aircraft; the research adapter still tests components.
	if aircraft.model.get("id", "") != "jensen-das-ugly-stik-60" or not workshop_identity.is_empty() \
			or aircraft.get("input_identity", {}).get("sha256", "") != FileAccess.get_sha256(Scenarios.AIRCRAFT):
		stage_backend_error = "native stage currently qualifies only the stock Ugly Stik"
		return
	var candidate := NativeStage.new()
	var prepared: Dictionary = candidate.prepare(self)
	if not prepared.ok:
		stage_backend_error = str(prepared.reason)
		return
	_native_stage = candidate # selects the session-owned tick hook, rather than the research pre_tick wrapper
	if not candidate.install(self).is_valid():
		stage_backend_error = candidate.reason
		_native_stage = null
		return
	candidate.tick_context(self, sim.aux, sim.inputs, time_now)


func _refresh_stage_backend() -> void:
	if sim != null and not _reset_transaction_active and _stage_backend_requested == NativeStage.BACKEND_NATIVE:
		_prepare_stage_backend()


const Scenarios := preload("res://sim/scenarios.gd")
const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")
const AircraftData := preload("res://physics/aircraft_data.gd")
const Air := preload("res://physics/air_data.gd")
const Aero := preload("res://physics/aero.gd")
const Propulsion := preload("res://physics/propulsion.gd")
const PropulsionRuntime := preload("res://sim/aircraft_propulsion_runtime.gd")
const LiquidFlight := preload("res://sim/liquid_fuel_flight.gd")
const LiquidFuel := preload("res://physics/liquid_fuel.gd")
const MassInventory := preload("res://physics/mass_inventory.gd")
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
const IntendedHullSupport := preload("res://physics/intended_hull_support.gd")
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
## X8-07: a standing overhand throw from the runway edge in front of the pilot, for airplanes without landing gear. The
## airplane is placed at the release: wings level, body along the throw (angle of attack zero to it), slightly nose up,
## moving along the runway into its wind component at a ground-relative throw speed, motor already at full throttle.
## Estimated and borrowed values with sources: docs/research/skywalker-x8/X8-07/README.md.
const START_HAND_LAUNCH := "hand_launch"
const HAND_LAUNCH_RELEASE_HEIGHT_M := 1.9
const HAND_LAUNCH_SPEED_MPS := 6.5
const HAND_LAUNCH_CLIMB_RAD := 0.08726646259971647 # 5 degrees
const HAND_LAUNCH_THROTTLE := 1.0
const EXTERNAL_SPAWN_MAX_OFFSET_M := 100000.0
const EXTERNAL_SPAWN_MIN_HEIGHT_M := 1.0
const EXTERNAL_SPAWN_MAX_HEIGHT_M := 10000.0
const EXTERNAL_SPAWN_MAX_HEADING_RAD := 1000000.0
## D6e-R4: the throttle Home and Quick Flight trim every airplane for before placing it in the air or on the runway
## (level flight at this throttle: below it the airplane descends, above it climbs, and the trim stays until the pilot
## moves it). Tests, golden flights and the technical route keep the reference trim (trim_throttle NAN).
const CRUISE_TRIM_THROTTLE := 0.5
const PowerTrim := preload("res://physics/cruise_trim.gd")
const LaunchTrimCache := preload("res://sim/launch_trim_cache.gd")
const LaunchTrimJob: Script = preload("res://sim/launch_trim_job.gd")
## One detached successful trim survives Home/session replacement; every solver input is keyed exactly.
static var _launch_trim_cache := LaunchTrimCache.new()
## Menu speculation reconstructs the normal launch request, then destroys every temporary Node before starting work.
static func prepare_menu_trim(path: String, aircraft_id: String) -> Dictionary:
	var session: Node = load("res://sim/flight_session.gd").new()
	session.trim_throttle = CRUISE_TRIM_THROTTLE
	session.soft_hull_contacts = true
	session._begin_setup(path, aircraft_id, {})
	var preflight: Dictionary = session._prepare_aircraft_before_trim(session._load_selected_aircraft())
	var request: Dictionary = {}
	if preflight.get("ok", false):
		request = session._selected_airborne_trim_request(preflight.model)
	session._discard_staged_setup()
	session.free()
	if not preflight.get("ok", false):
		return {kind = "invalid", reason = str(preflight.get("message", "aircraft preflight failed"))}
	if request.get("kind", "") != "cruise":
		return {kind = "skipped", reason = "selected launch has no detached cruise-trim request"}
	var resolution: Dictionary = _launch_trim_cache.acquire_managed(request.arguments, true)
	# The cache keeps the private numeric result and job; the menu never receives a live worker handle.
	return {kind = str(resolution.kind), reason = str(resolution.get("reason", ""))}


static func poll_menu_trim() -> Dictionary:
	var status: Dictionary = _launch_trim_cache.poll_menu()
	status.stats = _launch_trim_cache.stats()
	return status


static func abandon_menu_trim() -> void:
	_launch_trim_cache.abandon_menu()


static func menu_trim_busy() -> bool:
	return _launch_trim_cache.menu_busy()


static func launch_trim_cache_stats() -> Dictionary:
	return _launch_trim_cache.stats()


## Menu hints from one load of the accepted data: {runway, hand_launch}. The selected field, equilibrium and clearance
## are checked on each launch. AircraftCatalog caches the answer per stock ID.
static func ground_start_support(aircraft_id: String) -> Dictionary:
	var catalog: Script = load("res://app_state/aircraft_catalog.gd")
	var entry: Dictionary = catalog.entry(aircraft_id)
	if entry.is_empty() or catalog.is_rotorcraft(aircraft_id) or str(entry.get("data", "")).is_empty():
		return {runway = false, hand_launch = false}
	var data := AircraftData.load_file(str(entry.data))
	if not data.get("ok", false):
		return {runway = false, hand_launch = false}
	var model: Dictionary = data.get("model", {})
	return {runway = _runway_model_supported(model), hand_launch = _hand_launch_model_supported(model)}


static func runway_aircraft_supported(aircraft_id: String) -> bool:
	return ground_start_support(aircraft_id).runway


static func runway_aircraft_ids() -> PackedStringArray:
	var result := PackedStringArray()
	var catalog: Script = load("res://app_state/aircraft_catalog.gd")
	for id: String in catalog.ids():
		if runway_aircraft_supported(id): result.append(id)
	return result


static func _runway_model_supported(model: Dictionary) -> bool:
	var gear: Dictionary = model.get("landing_gear", {})
	return not gear.is_empty() and gear.has("breakaway_factor") and not gear.get("contacts", []).is_empty()


## X8-07: a fixed-wing airplane without landing gear starts by hand instead of on the runway.
static func hand_launch_aircraft_supported(aircraft_id: String) -> bool:
	return ground_start_support(aircraft_id).hand_launch


static func _hand_launch_model_supported(model: Dictionary) -> bool:
	return not model.is_empty() and model.get("landing_gear", {}).is_empty()


## X8-07: where and which way the helper throws: the runway edge nearest the pilot, at the pilot's east coordinate
## (clamped to the runway), along the runway in the direction with a headwind component (east-bound in calm air and
## in a pure crosswind). wind_ned is the selected wind at release; heights are added by the caller.
static func hand_launch_release(field: Dictionary, wind_ned: PackedFloat64Array) -> Dictionary:
	if wind_ned.size() != 3 or not is_finite(wind_ned[1]):
		return {ok = false, message = "hand launch needs a finite field wind"}
	var pilot: Dictionary = field.get("pilot", {})
	for s in field.get("surfaces", []):
		if s.get("type", "") != "runway" or str(s.get("id", "")) != str(field.get("runway", s.get("id", ""))):
			continue
		var half_width: float = float(s.width_north_south) / 2.0
		var half_length: float = float(s.length_east_west) / 2.0
		var pilot_north: float = float(pilot.get("north", 0.0))
		var north: float = float(s.center_north) - half_width if pilot_north <= float(s.center_north) else float(s.center_north) + half_width
		var east: float = clampf(float(pilot.get("east", 0.0)), float(s.center_east) - half_length, float(s.center_east) + half_length)
		var heading: float = -PI / 2.0 if wind_ned[1] > 0.0 else PI / 2.0
		if not is_finite(north) or not is_finite(east):
			return {ok = false, message = "hand launch needs a finite runway and pilot position"}
		return {ok = true, north = north, east = east, heading = heading, message = ""}
	return {ok = false, message = "hand launch needs the field's runway to place the throw"}


## D6e-R1: explicitly selected operating point, not an aircraft cruise-speed claim. D6e-R3 offers it to every
## fixed-wing airplane: the bounded six-axis solve (cruise_trim.gd) still refuses a launch whose 50 % equilibrium it
## cannot bracket, so support here means "this launch may be asked for", never "it exists".
static func half_power_start_supported(aircraft_id: String) -> bool:
	if aircraft_id.is_empty():
		return false
	var catalog: Script = load("res://app_state/aircraft_catalog.gd")
	return not catalog.is_rotorcraft(aircraft_id)


func _selected_airborne_trim(model: Dictionary, down_m: float = -30.0) -> Dictionary:
	var request: Dictionary = _selected_airborne_trim_request(model, down_m)
	if request.kind == "inline":
		return request.result
	var arguments: Array = request.arguments
	var t: Dictionary = _launch_trim_cache.solve_level_at_throttle(
		float(arguments[0]), float(arguments[1]), float(arguments[2]), arguments[3],
		float(arguments[4]), arguments[5], float(arguments[6]), float(arguments[7]), float(arguments[8]))
	return _place_cruise_trim_result(t)


## Main-thread preparation shared by sync and staged setup. Only its object-free numeric request crosses the worker boundary.
func _selected_airborne_trim_request(model: Dictionary, down_m: float = -30.0) -> Dictionary:
	var query_model: Dictionary = _trim_model(model)
	var speed: float = query_model.get("start_speed", 15.0)
	var density: float = _weather.air_density(down_m)
	var charge: float = _weather.engine_charge_ratio(down_m)
	if not is_finite(density) or not is_finite(charge):
		return {kind = "inline", result = {ok = false, message = "starting altitude is outside the atmosphere's supported domain"}}
	var target: float = selected_trim_throttle()
	if is_nan(target):
		return {kind = "inline", result = Scenarios.trimmed_level_across_view(
			query_model, sim.gravity, query_model.controls.throw_rad, speed, density, charge)}
	if not half_power_start_supported(str(query_model.get("id", ""))):
		if start_choice == START_HALF_POWER:
			return {kind = "inline", result = {ok = false, message = "half-power airborne start is not qualified for this aircraft"}}
		# D6e-R4: a rotorcraft keeps its reference launch under the product's trim throttle.
		return {kind = "inline", result = Scenarios.trimmed_level_across_view(
			query_model, sim.gravity, query_model.controls.throw_rad, speed, density, charge)}
	if not is_finite(target) or target <= 0.0 or target > 1.0:
		return {kind = "inline", result = {ok = false, message = "trim throttle must be within 0..1 (got %s)" % str(target)}}
	# Search bounds limit this opt-in policy; they do not prescribe a flight speed.
	# D6e-R3: the level speed at half throttle lies between 1.3 and 2.0 times the slow start speed across the fleet
	# (Lumber 1.25, Vantage Jet 1.92); the bound leaves room for a thinner atmosphere without reaching the solver's limit.
	var arguments: Array = [speed, target, minf(PowerTrim.MAX_SEARCH_SPEED_MPS, 2.5 * speed),
		query_model, sim.gravity, query_model.controls.throw_rad, density, charge,
		PowerTrim.DEFAULT_MAX_ALPHA_RAD]
	return {kind = "cruise", model = query_model, arguments = arguments}


func _place_cruise_trim_result(trim_result: Dictionary) -> Dictionary:
	var placed: Dictionary = trim_result.duplicate(true)
	if placed.get("ok", false):
		placed.state = Scenarios.Trim.state_for(placed.V, placed.alpha, placed.gamma,
			PI / 2.0, M.v3(60.0, -40.0, -30.0), placed.beta, float(placed.get("bank", 0.0)))
	return placed


## D6e-R4: the throttle the selected launch is trimmed for; NAN names the reference trim.
func selected_trim_throttle() -> float:
	return CRUISE_TRIM_THROTTLE if start_choice == START_HALF_POWER else trim_throttle


## D6e-R4: true while the committed airplane launches trimmed for a throttle (START_HALF_POWER, or a finite
## trim_throttle on an airplane that offers the cruise trim); false for the reference trim and for rotorcraft.
func cruise_trim_active() -> bool:
	if is_nan(selected_trim_throttle()) or not aircraft.get("ok", false):
		return false
	return half_power_start_supported(str(aircraft.get("model", {}).get("id", "")))


## D6e-R4: re-solves a selected-throttle start when its requested throttle or launch air mass changed after setup.
## This runs before the runway early return so its flying trim follows a changed field atmosphere too.
## Failure leaves an invalid start, as the atmosphere refit does. Returns {ok, changed[, message]}.
func _refit_selected_trim() -> Dictionary:
	if not cruise_trim_active():
		return {ok = true, changed = false}
	var old_start: Dictionary = start
	var old_state: PackedFloat64Array = old_start.get("state", PackedFloat64Array())
	var density: float = air_density(old_state)
	var charge: float = engine_charge_ratio(old_state)
	var throttle_changed: bool = old_start.get("requested_throttle", NAN) != selected_trim_throttle()
	var atmosphere_changed: bool = _trim_density != density or _trim_charge != charge
	if not throttle_changed and not atmosphere_changed:
		return {ok = true, changed = false}
	var refit: Dictionary = _selected_airborne_trim(aircraft.model, _atmosphere_down(old_state))
	if not refit.ok:
		start = refit
		_trim_density = NAN
		_trim_charge = NAN
		return {ok = false, changed = true, message = "trim: " + str(refit.get("message", "trim failed"))}
	if Sim.state_is_valid(old_state):
		for axis: int in 3:
			refit.state[RB.POS + axis] = old_state[RB.POS + axis]
	start = refit
	_trim_density = density
	_trim_charge = charge
	trims = {roll = start.roll_command, pitch = start.pitch_command, yaw = start.get("yaw_command", 0.0)}
	return {ok = true, changed = true}


## Detached static query only. The normalized aircraft and fixed datum never change.
func _trim_model(model: Dictionary) -> Dictionary:
	var prop: Dictionary = model.get("propulsion", {})
	var properties: Dictionary = {}
	if Propulsion.is_glow(prop):
		var amounts := PackedFloat64Array([float(prop.glow.capacity_fuel_kg) * fuel_start_fill])
		if prop.glow.has("feed_line"):
			amounts.append(float(prop.glow.feed_line.reference_mass_kg))
		properties = MassInventory.evaluate_reference(prop.glow.mass_reference, amounts)
	elif not prop.get("liquid_fuel", {}).is_empty():
		properties = LiquidFuel.properties(prop.liquid_fuel,
			{str(prop.liquid_fuel.tank_id): float(prop.liquid_fuel.capacity_kg) * fuel_start_fill})
	if not properties.get("ok", false):
		return model
	var query: Dictionary = model.duplicate()
	query.mass_kg = properties.mass_kg
	query.inertia = properties.inertia
	query.trim_mass_properties = properties
	return query

## Closes the previous observers after accepted start/restore commit. Starts
## notify before tick0; restore notifies before its pause, without a tick sample.
## Physical commit has already succeeded; old recorders
## read reset_closing_context(), and a presentation hold may pause the new flight.
## Pending weather selection uses the same guarded closure without a tick.
## Shaft configuration retains its historical ordering pending migration.
signal resetting
var _reset_publication_active := false
var _reset_transaction_active := false
var _reset_transaction_reentry := false
var _reset_physical_committed := false
var _reset_closing_context := {}


## Detached previous-flight boundary, available only during reset notifications.
## An unavailable old checkpoint is explicit; never substitute the new flight.
func reset_closing_context() -> Dictionary:
	return _reset_closing_context.duplicate(true) if _reset_publication_active else {}


## One Session owner for start/restore preparation and publication. The kernel guard
## restores its declared fields/model; this bounded owner list covers the staged
## aircraft, initial-state builders and accepted histories. It is not a sandbox
## for arbitrary external data captured by a callback.
const _START_OWNER_FIELDS := ["_weather", "fuel_start_fill", "input_enabled", "aircraft", "start", "trims", "commands", "raw", "pause_reason", "start_error",
	"_launch_metadata", "_failures", "_gear_requested_down", "_wheel_brake_demand", "_gear_request_inhibited",
	"_gear_cache_fraction", "_gear_cache", "_flap_requested", "_weather_pending_reset", "_shaft_pending_reset",
	"_shaft_integrator", "_shaft_explicit", "_turbulence_aux_index", "_trim_density", "_trim_charge",
	"_fuel_start_fill_known", "_hull_contact", "_prop_disc", "_contact_bindings", "_ground_effect_reach",
	"_deflection_key", "_deflection_cache", "_has_committed_aircraft", "_pending_controller_start",
	"_scenery_damage", "soft_contacts", "prop_strike", "crash", "_last_scenery_event", "_last_lake_event",
	"_contact_tick", "_contact_events", "_active_hull_ids", "_soft_contacts_cache_tick",
	"_soft_contacts_cache_previous", "_soft_contacts_cache_state", "_pending_contact_tick", "_pending_crash",
	"_pending_crash_state", "_pending_scenery_event", "_pending_lake_event", "_pending_scenery_damage", "_pending_scenery_tick",
	"_out_of_trim", "_airframe_offset", "_native_stage", "stage_backend_error"]


func _begin_start_transaction() -> Dictionary:
	_reset_transaction_active = true
	_reset_transaction_reentry = false
	_reset_physical_committed = false
	var owner := {}
	for field: String in _START_OWNER_FIELDS:
		owner[field] = Sim._guard_copy(get(field))
	var transaction := {active = true, committed = false, owner = owner, kernel = sim._capture_endpoint_guard()}
	var closing: Dictionary = checkpoint()
	transaction.closing = {tick = sim.tick, checkpoint_available = not closing.is_empty(), checkpoint = closing.duplicate(true)}
	return transaction


func _end_start_transaction(transaction: Dictionary) -> void:
	transaction.active = false
	_reset_closing_context = {}
	_reset_publication_active = false
	_reset_transaction_active = false
	_reset_physical_committed = false


func _refuse_start_transaction(transaction: Dictionary, message: String, status := "numerical_unresolved") -> Dictionary:
	if transaction.get("active", false):
		# No reset, restore, derivative or observer publication is needed to roll
		# back synchronous staging. Preserve the original model reference too.
		sim._endpoint_guard_unchanged(transaction.kernel)
		for field: String in _START_OWNER_FIELDS:
			set(field, Sim._guard_copy(transaction.owner[field]))
		_end_start_transaction(transaction)
	return {ok = false, committed = false, ready = false, status = status, message = message}


func _stage_start_failures() -> bool:
	if _failures == null: return true
	var fresh := FailureRuntime.new()
	if not fresh.restore(_failures.snapshot(), sim.tick): return false
	fresh.restart()
	_failures = fresh
	return true


func _commit_start_candidate(candidate: Dictionary, transaction: Dictionary) -> Dictionary:
	if _reset_transaction_reentry:
		return _refuse_start_transaction(transaction, "reset preparation attempted owner transition reentry")
	if not candidate.get("ok", false):
		return _refuse_start_transaction(transaction, str(candidate.get("message", "invalid reset candidate")))
	var committed: bool = sim.commit_prepared_reset(candidate, func() -> void:
		transaction.committed = true
		_reset_physical_committed = true
		_reset_publication_active = true
		_reset_closing_context = transaction.closing
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
		_reset_closing_context = {}
		_reset_publication_active = false)
	if not committed:
		return _refuse_start_transaction(transaction, "prepared reset context changed before commit")
	_end_start_transaction(transaction)
	if not sim.reset_observer_fault.is_empty():
		start_error = sim.reset_observer_fault
		pause_reason = "simulation fault: " + start_error
		return {ok = true, committed = true, ready = false, status = "observer_fault",
			observer_fault = start_error, message = start_error}
	sim.set_paused(not holds.is_empty())
	return {ok = true, committed = true, ready = true, status = "converged", message = ""}


func _reject_reset_publication_reentry() -> bool:
	if not _reset_transaction_active: return false
	_reset_transaction_reentry = true
	if sim != null: sim.note_reset_publication_reentry()
	return true

## Emitted when the detached scenery damage state changes or a session reset/restore succeeds.
signal scenery_damage_changed
## Accepted contact observations changed, including decisions made between integration steps.
## Consumers read the detached contact_events() snapshot; no signal is emitted for rejected candidates.
signal contact_events_changed
## D6e-R2: the in-flight rate switch changed the profile; `active` is rates_active() afterwards.
signal rate_profile_changed(active: bool)

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
const FIXED_BRAKE_INPUT_LAW := "fixed-gear-shared-wheel-brake-input-v1"
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
## D6e-R4: the throttle the launch is trimmed for. NAN selects the reference trim (level flight at the aircraft's slow
## start speed, the kernel's fixture); a value in (0, 1] trims every airplane that offers the cruise trim at that
## throttle, in the air (START_AIRBORNE) and as the runway start's flying trim (START_RUNWAY). START_HALF_POWER is
## the explicit airborne 0.5. Select it before setup(); reset() refits a later selection.
var trim_throttle: float = NAN
## A controllerless owner drives this session explicitly, one validated tick packet at a time.
var external_driver_enabled := false
var _external_pending_packet: Dictionary = {}
var _external_packet_ready := false
var _external_spawn_heading_rad := 0.0
var _external_spawn_heading_set := false
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
## "sport": full roll travel with normal expo, pitch and yaw. Aircraft without rates fly full throws.
## The live scene starts in sport; the technical session default stays full.
var rate_profile := "full"
## D6e-R5: keep the two-position switch paired with the selected high profile.
## Sport uses full aileron travel and the normal elevator/rudder response.
var _high_rate_profile := "full"
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
## F4U-17: presentation interlocks by name ("wing_fold") that hold the throttle at idle while set. They act where
## commands become solver inputs, so recordings carry the held throttle and replay exactly.
var throttle_holds := {}
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
var _soft_contacts_cache_tick: int = -1
var _soft_contacts_cache_previous := PackedFloat64Array()
var _soft_contacts_cache_state := PackedFloat64Array()
var soft_hull_contacts := false:
	set(value):
		if _reject_reset_publication_reentry(): return
		soft_hull_contacts = value
		_soft_contacts_cache_tick = -1
		_refresh_stage_backend()
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
		if _reject_reset_publication_reentry(): return
		environment.surfaces = value
		_refresh_stage_backend()
## H2: last deflections built by _deflections() and the servo positions they belong to (cleared with each aircraft).
var _deflection_key := PackedFloat64Array()
var _deflection_cache := {}
## GP-07c: the field's airframe sliding friction as a flat table for soft hull contacts (set_field, or a flight log's
## header on replay); empty = the HullContact default everywhere. Setting it re-prepares the hull contact, so the
## physics and the checkpoint configuration always use the same table.
var airframe_surfaces: PackedFloat64Array:
	get:
		return _airframe_surfaces
	set(value):
		if _reject_reset_publication_reentry(): return
		_airframe_surfaces = value.duplicate()
		if sim != null and aircraft.get("ok", false):
			_hull_contact = _prepare_hull_contact()
		_refresh_stage_backend()
var _airframe_surfaces := PackedFloat64Array()
## The field id the surfaces came from ("" = none: pavement), and why they could not be built ("" = fine).
var ground_field_id := ""
## M5-GE-1: CG height above the ground beyond which no wing strip is in ground effect; 0 = no aero.ground_effect module.
var _ground_effect_reach: float = 0.0
var surface_error := ""
## Last refused replacement; unlike surface_error this does not invalidate the installed field.
var field_update_error := ""
var _field_installed := false
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
var _staged_trim_job: Dictionary = {}
const _STAGED_IDLE := 0
const _STAGED_BEGINNING := 1
const _STAGED_READY := 2
const _STAGED_FINISHING := 3
const _STAGED_CANCELLING := 4
const _STAGED_DONE := 5
var _staged_phase := _STAGED_IDLE
var _staged_cancel := false
var _staged_completed := false
var _staged_preflight: Dictionary = {}
var _staged_request: Dictionary = {}
var _staged_resolution: Dictionary = {}
var workshop_presentation_identity: Dictionary = {}
var workshop_identity: Dictionary = {}


func setup(path := Scenarios.AIRCRAFT, expected_id: String = "", frozen_data: Dictionary = {}) -> void:
	if _reject_reset_publication_reentry(): return
	if _staged_phase in [_STAGED_BEGINNING, _STAGED_READY, _STAGED_FINISHING, _STAGED_CANCELLING]: return
	_begin_setup(path, expected_id, frozen_data)
	_finish_setup(_prepare_aircraft(_load_selected_aircraft()))


## Compatibility wrapper for callers that do not overlap setup with other main-thread work.
## false means cancellation or a duplicate call; validation failures still complete as an invalid session.
func setup_staged(path: String, expected_id: String, frozen_data: Dictionary, frame: Signal,
		should_cancel: Callable) -> bool:
	if not begin_staged_setup(path, expected_id, frozen_data, should_cancel):
		return false
	return await finish_staged_setup(frame, should_cancel)


## Prepare privately and reserve/adopt at most one managed worker before returning to the caller.
## The Simulation stays detached and neither aircraft/start nor the shared cache is published here.
func begin_staged_setup(path: String, expected_id: String, frozen_data: Dictionary,
		should_cancel: Callable) -> bool:
	if _reject_reset_publication_reentry() or _staged_phase != _STAGED_IDLE or sim != null:
		return false
	_staged_phase = _STAGED_BEGINNING
	if _staged_cancel_requested(should_cancel):
		_staged_phase = _STAGED_DONE
		return false
	_begin_setup(path, expected_id, frozen_data)
	if _staged_cancel_requested(should_cancel):
		_discard_staged_setup()
		_staged_phase = _STAGED_DONE
		return false
	var data: Dictionary = _load_selected_aircraft()
	if _staged_cancel_requested(should_cancel):
		_discard_staged_setup()
		_staged_phase = _STAGED_DONE
		return false
	_staged_preflight = _prepare_aircraft_before_trim(data)
	if _staged_cancel_requested(should_cancel):
		_discard_staged_setup()
		_clear_staged_preparation()
		_staged_phase = _STAGED_DONE
		return false
	if _staged_preflight.get("ok", false):
		_staged_request = _selected_airborne_trim_request(_staged_preflight.model)
		if _staged_cancel_requested(should_cancel):
			_discard_staged_setup()
			_clear_staged_preparation()
			_staged_phase = _STAGED_DONE
			return false
		if _staged_request.kind != "inline":
			_staged_resolution = _launch_trim_cache.acquire_managed(_staged_request.arguments, false, self)
			if _staged_resolution.get("kind", "") == "pending":
				_staged_trim_job = _staged_resolution
	_staged_phase = _STAGED_READY
	return true


## Complete a begun transaction once. A busy foreign worker is waited out without starting a second solve.
func finish_staged_setup(frame: Signal, should_cancel: Callable) -> bool:
	if _staged_phase != _STAGED_READY:
		return false
	_staged_phase = _STAGED_FINISHING
	if _staged_cancel_requested(should_cancel):
		await _cancel_staged_owned(frame)
		return false
	if not _staged_preflight.get("ok", false):
		var invalid: Dictionary = _staged_preflight
		_clear_staged_preparation()
		_staged_phase = _STAGED_DONE
		_finish_setup(invalid, false)
		_staged_completed = true
		return true

	var candidate_start: Dictionary = {}
	var cache_trim_result: Dictionary = {}
	if _staged_request.kind == "inline":
		candidate_start = _staged_request.result
	else:
		while _staged_resolution.get("kind", "") == "wait":
			await frame
			if _staged_cancel_requested(should_cancel):
				await _cancel_staged_owned(frame)
				return false
			_staged_resolution = _launch_trim_cache.acquire_managed(_staged_request.arguments, false, self)
			if _staged_resolution.get("kind", "") == "pending":
				_staged_trim_job = _staged_resolution
		if _staged_resolution.get("kind", "") == "pending":
			var cancelled := _staged_cancel_requested(should_cancel)
			var progress: Dictionary = _launch_trim_cache.poll_managed(_staged_trim_job)
			while not progress.get("complete", false):
				await frame
				if _staged_cancel_requested(should_cancel):
					cancelled = true
				progress = _launch_trim_cache.poll_managed(_staged_trim_job)
			if cancelled or _staged_cancel_requested(should_cancel):
				await _cancel_staged_owned(frame)
				return false
			cache_trim_result = progress.result
		else:
			cache_trim_result = _staged_resolution.get("result", {ok = false,
				message = str(_staged_resolution.get("reason", "launch trim solve unavailable"))})
		candidate_start = _place_cruise_trim_result(cache_trim_result)

	if _staged_cancel_requested(should_cancel):
		await _cancel_staged_owned(frame)
		return false
	var prepared: Dictionary = _finish_aircraft_prepare(_staged_preflight, candidate_start)
	if _staged_cancel_requested(should_cancel):
		await _cancel_staged_owned(frame)
		return false
	if not _staged_trim_job.is_empty():
		_finish_staged_trim_job(prepared.get("ok", false))
	_clear_staged_preparation()
	_staged_phase = _STAGED_DONE
	_finish_setup(prepared, false)
	_staged_completed = true
	return true


## Read-only lifecycle state for an owner that may outlive this detached Session.
func staged_setup_pending() -> bool:
	return _staged_phase != _STAGED_IDLE and _staged_phase != _STAGED_DONE


## Completion includes invalid aircraft; cancellation never completes setup.
func staged_setup_completed() -> bool:
	return _staged_completed


## A caller abandoning a begun transaction waits for its own worker, then releases without publication.
## If finish is already running, it owns the drain and observes this cancellation flag.
func cancel_staged_setup(frame: Signal) -> void:
	if _staged_phase == _STAGED_IDLE or _staged_phase == _STAGED_DONE:
		return
	_staged_cancel = true
	if _staged_phase == _STAGED_BEGINNING:
		return # a reentrant cancellation is observed by begin's next guard
	if _staged_phase == _STAGED_FINISHING or _staged_phase == _STAGED_CANCELLING:
		while _staged_phase == _STAGED_FINISHING or _staged_phase == _STAGED_CANCELLING:
			await frame
		return
	_staged_phase = _STAGED_CANCELLING
	await _cancel_staged_owned(frame)


func _cancel_staged_owned(frame: Signal) -> void:
	if not _staged_trim_job.is_empty():
		var progress: Dictionary = _launch_trim_cache.poll_managed(_staged_trim_job)
		while not progress.get("complete", false):
			await frame
			progress = _launch_trim_cache.poll_managed(_staged_trim_job)
		_finish_staged_trim_job(false)
	_discard_staged_setup()
	_clear_staged_preparation()
	_staged_phase = _STAGED_DONE


func _clear_staged_preparation() -> void:
	_staged_preflight = {}
	_staged_request = {}
	_staged_resolution = {}
	_staged_cancel = false


func _finish_staged_trim_job(retain_success: bool) -> void:
	_launch_trim_cache.finish_managed(_staged_trim_job, retain_success)
	_staged_trim_job = {}


func _notification(what: int) -> void:
	if what != NOTIFICATION_PREDELETE:
		return
	if not _staged_trim_job.is_empty():
		_finish_staged_trim_job(false)
	# Before setup commits, Simulation is deliberately not a child of this Session.
	if sim != null and is_instance_valid(sim) and sim.get_parent() == null:
		sim.free()
		sim = null


func _begin_setup(path: String, expected_id: String, frozen_data: Dictionary) -> void:
	aircraft_path = path
	expected_aircraft_id = expected_id
	_frozen_aircraft = frozen_data.duplicate(true)
	sim = Sim.new()
	sim.modes = PackedInt64Array([1])
	sim.faulted.connect(_on_sim_faulted)
	sim.stepped.connect(_on_sim_stepped)


func _finish_setup(prepared: Dictionary, reset_invalid := true) -> void:
	if prepared.ok:
		_commit_aircraft(prepared)
	else:
		_set_initial_failure(prepared)
	if not physics_enabled:
		sim.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(sim)
	if not prepared.ok and not reset_invalid:
		# A rejected staged candidate must not enter reset's synchronous trim retry/cache path.
		_fail_selected_start(str(prepared.get("message", "aircraft unavailable")))
	else:
		reset()


func _staged_cancel_requested(should_cancel: Callable) -> bool:
	if _staged_cancel:
		return true
	var requested := should_cancel.is_valid() and bool(should_cancel.call())
	return _staged_cancel or requested


func _discard_staged_setup() -> void:
	if sim != null:
		if sim.get_parent() != null:
			sim.get_parent().remove_child(sim)
		sim.free()
	sim = null
	_frozen_aircraft = {}


## Disables all automatic input and physics callbacks. Call after setup and before adding this node to the tree.
func configure_external_driver() -> bool:
	if external_driver_enabled or sim == null or is_inside_tree() or is_node_ready() or sim.tick != 0 \
			or not physics_enabled or not _has_valid_start():
		return false
	external_driver_enabled = true
	input_enabled = false
	calibration = null
	if radio.connected:
		radio.disconnect_device()
	_external_pending_packet.clear()
	_external_packet_ready = false
	set_process_input(false)
	set_physics_process(false)
	sim.set_physics_process(false)
	return true


## Installs a fresh trimmed airborne reset at local terrain height + `height_m`, facing `heading_rad` from north.
## Call only for a configured external session before tree entry and before its first accepted tick.
func external_spawn_airborne(north: float, east: float, height_m: float, heading_rad: float) -> bool:
	if not external_driver_enabled or sim == null or is_inside_tree() or is_node_ready() or sim.tick != 0 \
			or not _has_valid_start() or not physics_enabled or not holds.is_empty():
		return false
	if not is_finite(north) or not is_finite(east) or not is_finite(height_m) or not is_finite(heading_rad) \
			or absf(north) > EXTERNAL_SPAWN_MAX_OFFSET_M or absf(east) > EXTERNAL_SPAWN_MAX_OFFSET_M \
			or height_m < EXTERNAL_SPAWN_MIN_HEIGHT_M or height_m > EXTERNAL_SPAWN_MAX_HEIGHT_M \
			or absf(heading_rad) > EXTERNAL_SPAWN_MAX_HEADING_RAD:
		return false
	var terrain: PackedFloat64Array = environment.terrain(north, east)
	if terrain.is_empty() or not is_finite(terrain[0]):
		return false
	var altitude_m: float = float(terrain[0]) + height_m
	var down_m: float = -altitude_m
	if not is_finite(altitude_m) or not is_finite(_weather.air_density(down_m)) \
			or not is_finite(_weather.engine_charge_ratio(down_m)):
		return false
	var candidate_state: PackedFloat64Array = start.state.duplicate()
	candidate_state[RB.POS] = north
	candidate_state[RB.POS + 1] = east
	candidate_state[RB.POS + 2] = down_m
	if not Sim.state_is_valid(candidate_state):
		return false
	start.state = candidate_state
	start_choice = START_AIRBORNE
	_external_spawn_heading_rad = wrapf(heading_rad, -PI, PI)
	_external_spawn_heading_set = true
	reset()
	return sim.tick == 0 and _flight_ready() and not sim.paused and Sim.state_is_valid(sim.state)


func _load_selected_aircraft() -> Dictionary:
	return _frozen_aircraft.duplicate(true) if not _frozen_aircraft.is_empty() else AircraftData.load_file(aircraft_path)


func _ready() -> void:
	if external_driver_enabled:
		set_process_input(false)
		set_physics_process(false)
		if sim != null:
			sim.set_physics_process(false)
		return
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	if external_controller_selection:
		return
	radio.confirmed_gamepad_connection = _confirmed_direct_gamepad
	var pads := Input.get_connected_joypads()
	if not pads.is_empty():
		_on_joy_connection_changed(pads[0], true)


## Technical/direct flights have no ControllerService to certify live polling.
func _confirmed_direct_gamepad(id: int) -> bool:
	if external_driver_enabled or external_controller_selection or not is_inside_tree() or not get_window().has_focus():
		return false
	if id != radio.device_id or not Input.get_connected_joypads().has(id) or not Input.is_joy_known(id):
		return false
	var info: Dictionary = device_info.call(id)
	return RcInput.key_for(id, info) == radio.device_key


func _input(event: InputEvent) -> void:
	if external_driver_enabled:
		return
	radio.set_auxiliary_enabled(not sim.paused and calibration == null and holds.is_empty())
	if event is InputEventJoypadMotion:
		radio.on_motion(event.device, event.axis, event.axis_value)
	elif event is InputEventJoypadButton:
		radio.on_button(event.device, event.button_index, event.pressed)


func _on_joy_connection_changed(device: int, is_connected: bool) -> void:
	if external_driver_enabled:
		return
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
	if external_driver_enabled or not radio.connected or radio.profile.get("kind", "") != "radio":
		return false
	calibration = RcCalibration.new(radio.profile)
	radio.set_auxiliary_enabled(false)
	_failsafe("calibrating radio")
	return true


## [Enter]: next calibration step. When the wizard finishes, the profile is used and saved for this device.
func advance_calibration() -> void:
	if external_driver_enabled or calibration == null:
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
	# Holds are legal publication bookkeeping after physical commit, not from
	# a preparation evaluator that must leave the previous owner untouched.
	if _reset_transaction_active and not _reset_physical_committed:
		_reject_reset_publication_reentry()
		return
	radio.set_auxiliary_enabled(false)
	if external_controller_selection and not holds.has(reason) and radio.connected and radio.is_gamepad():
		radio.require_neutral(true)
	holds[reason] = true
	sim.set_paused(true)


## Lifts one hold. The flight stays paused until resume() (or the crash hold ends and restarts it).
func release(reason: String) -> void:
	# Holds are legal publication bookkeeping after physical commit, not from
	# a preparation evaluator that must leave the previous owner untouched.
	if _reset_transaction_active and not _reset_physical_committed:
		_reject_reset_publication_reentry()
		return
	holds.erase(reason)


## Compatibility preflight before a profile is persisted or activated.
func controller_profile_rejection(_profile: Dictionary) -> String:
	return ""


## Called only at a paused, explicit shell selection boundary; never by device enumeration.
func apply_controller_selection(device: int, info: Dictionary, profile: Dictionary, initial_start := false) -> bool:
	if external_driver_enabled:
		return false
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


## E3a: the wheels roll on this field's surfaces (a validated FieldLoader field).
## Initial invalid data refuses flight; a refused replacement retains the installed field.
## Accepted installation emits no reset; call reset() afterwards to restart on it.
func set_field(field: Dictionary, table_path := GroundSurfaces.DEFAULT_PATH) -> bool:
	if _reject_reset_publication_reentry(): return false
	var table := GroundSurfaces.load_table(table_path)
	var built := GroundSurfaces.build(table.table, field) if table.ok else table
	var airframe := GroundSurfaces.build_airframe(table.table, field) if built.ok else built
	if not built.ok or not airframe.ok:
		built = built if not built.ok else airframe
		field_update_error = "ground surfaces invalid: " + str(built.errors[0] if not built.errors.is_empty() else "unknown")
		if _field_installed:
			return false
		surface_error = field_update_error
		ground_surfaces = PackedFloat64Array()
		airframe_surfaces = PackedFloat64Array()
		ground_field_id = ""
		_runway_field = {}
		pause_reason = surface_error
		sim.set_paused(true)
		printerr(surface_error)
		return false
	surface_error = ""
	field_update_error = ""
	ground_surfaces = built.rects
	airframe_surfaces = airframe.rects
	# The builder validated this provenance against the exact legacy rectangles.
	# It changes observation identity only, never the existing support force law.
	environment.install_ground_registry(built.regions)
	ground_field_id = str(field.get("id", "?"))
	_runway_field = field.duplicate(true)
	_field_installed = true
	_refresh_stage_backend()
	return true


## Installs one normalized lake at a launch/reset boundary. Invalid or stale identities leave the current lake intact.
func set_lake_context(normalized_lake: Dictionary) -> bool:
	if _reject_reset_publication_reentry(): return false
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
	_refresh_stage_backend()
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
	var dynamic_mass: bool = finite_fuel_is_active()
	sim.model.post_tick = Callable(self, "_resolve_collision_step") if _has_collision_query() and not dynamic_mass else Callable()
	sim.model.post_tick_joint = Callable(self, "_resolve_mass_contact_step") if dynamic_mass else Callable()


func _prepare_hull_contact() -> Dictionary:
	# X8-08: a tolerant (foam) hull carries its own terminal thresholds; absent, the shared ones apply.
	var tolerance: Dictionary = aircraft.model.get("crash_tolerance", {})
	if finite_fuel_is_active():
		return HullContact.prepare_geometry(aircraft.model.crash_hull, _lake, airframe_surfaces, tolerance)
	return HullContact.prepare(aircraft.model.crash_hull, sim.mass, sim.inertia, _lake, airframe_surfaces, tolerance)


## Installs one normalized, detached world at a flight boundary. Proxy data contains scalar NED geometry only.
func set_collision_world(world: Dictionary) -> bool:
	if _reject_reset_publication_reentry(): return false
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


## Imports a detached world-owned damage snapshot into an external session.
func import_external_scenery_damage(damage: Dictionary, tick: int) -> bool:
	if not external_driver_enabled or sim == null or not _scenery_damage_is_valid(damage, tick):
		return false
	var detached: Dictionary = damage.duplicate(true)
	if detached == _scenery_damage:
		return true
	_scenery_damage = detached
	_clear_pending_scenery_damage()
	scenery_damage_changed.emit()
	return true


func last_scenery_event() -> SceneryCollision.Event:
	return _last_scenery_event


func last_lake_event() -> LakeCollision.WaterEvent:
	return _last_lake_event


## Whether this flight can fly at all: valid aircraft and start, no simulation fault (menus disable Continue).
func is_flyable() -> bool:
	return _flight_ready()


## Whether resume() would fly now: a valid flight with no calibration, menu hold, or crash.
func can_resume() -> bool:
	return calibration == null and holds.is_empty() and crash.is_empty() and _flight_ready() and not _controller_lost \
		and (not external_controller_selection or not radio.connected or radio.armed)


## The pilot's explicit "continue" (never automatic). Refused during calibration, menu holds, or a crash
## (the crash restarts by itself; flying on would pass through the ground).
func resume() -> void:
	if _reject_reset_publication_reentry(): return
	if calibration != null or not holds.is_empty() or not crash.is_empty():
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
	var preflight: Dictionary = _prepare_aircraft_before_trim(data)
	if not preflight.get("ok", false):
		return preflight
	var candidate_start: Dictionary = _selected_airborne_trim(preflight.model)
	return _finish_aircraft_prepare(preflight, candidate_start)


## All data, identity, propulsion, contact and timestep validation before trim. Shared by sync and staged setup.
func _prepare_aircraft_before_trim(data: Dictionary) -> Dictionary:
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
	if not model.get("propulsion", {}).get("liquid_fuel", {}).is_empty() \
			and not Turbine.is_turbine(model.propulsion) and _shaft_explicit and not shaft_is_coupled():
		return {ok = false, data = data, start = {ok = false}, trims = neutral_trims,
			message = "finite propeller propulsion requires coupled-rk4"}
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
	return {ok = true, data = data, model = model, trims = neutral_trims}


## Full result validation is shared by synchronous and worker-produced trim candidates.
func _finish_aircraft_prepare(preflight: Dictionary, candidate_start: Dictionary) -> Dictionary:
	var data: Dictionary = preflight.data
	var model: Dictionary = preflight.model
	var neutral_trims: Dictionary = preflight.trims
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
	_native_stage = null # the transaction retains the previous helper/model until commit or rollback
	aircraft = prepared.data
	_drop_tick_facts()
	# SF-01: the session installs one VehicleModel. Propulsion and contact callbacks are configured on it below
	# through the kernel's compatibility properties; the laws themselves still live in this session.
	var vehicle: VehicleModel = VehicleModel.new()
	vehicle.input_size = _input_count()
	vehicle.identity = { vehicle = "fixed-wing", loads_law = Aero.LOADS_LAW }
	vehicle.loads = _loads
	vehicle.pre_tick = _kernel_pre_step
	vehicle.rotor_momentum = rotor_momentum
	if not sim.set_model(vehicle):
		push_error("Cannot install the fixed-wing vehicle model")
	_gear_cache.clear()
	_gear_cache_fraction = -1.0
	_contact_bindings = ContactContract.describe(aircraft.model, soft_hull_contacts)
	if not _shaft_explicit:
		_shaft_integrator = "coupled-rk4" if Propulsion.is_electric(aircraft.model.propulsion) or glow_is_active() or (liquid_fuel_is_active() and not Turbine.is_turbine(aircraft.model.propulsion)) else "split"
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
	_install_continuous_callbacks(prepared)


## Install only an already prepared callback set; this does not advance state.
func _install_continuous_callbacks(prepared: Dictionary) -> void:
	_native_stage = null
	for field: String in PropulsionRuntime.CALLBACK_FIELDS:
		sim.model.set(field, prepared[field])
	if sim.model.stage.is_valid() and _substep_preview_supported():
		sim.model.substeps = Callable()
		sim.model.substeps_joint = _substeps_joint
	else:
		sim.model.substeps_joint = Callable()
		sim.model.substeps = _substeps
	var declared: Array[Dictionary] = []
	for event: Variant in prepared.get("events", []):
		declared.append(event)
	sim.model.events = declared


## Family-independent accepted-endpoint observation; never called from a force evaluation.
func propulsion_observation() -> Dictionary:
	return PropulsionRuntime.observe(self)


func _set_initial_failure(prepared: Dictionary) -> void:
	aircraft = prepared.get("data", {})
	_drop_tick_facts()
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
	# X8-03: an elevon aircraft has an elevon end point and an exactly zero rudder throw instead of a rudder.
	var elevon: bool = controls.get("layout", "") == "elevon"
	for axis in (["aileron", "elevator", "elevon"] if elevon else ["aileron", "elevator", "rudder"]):
		if not throws.has(axis) or not is_finite(float(throws[axis])) or throws[axis] <= 0.0:
			return false
	if elevon and float(throws.get("rudder", NAN)) != 0.0:
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
		# _set_initial_failure() keeps the validation message in start; the pilot needs the cause, not a generic refusal.
		var message: String = str(start.get("message", ""))
		return message if not message.is_empty() else "aircraft data is invalid"
	return "trimmed starting condition is invalid: " + str(start.get("message", "no valid trim"))


func _on_sim_faulted(reason: String) -> void:
	_drop_tick_facts()
	if _failures != null:
		_failures.rollback()
	_clear_pending_scenery_damage()
	_clear_pending_contacts()
	pause_reason = "simulation fault: " + reason


func _on_sim_stepped(tick: int, _time_s: float, _state: PackedFloat64Array,
		_loads: PackedFloat64Array, _inputs: PackedFloat64Array, _aux: PackedFloat64Array) -> void:
	_drop_tick_facts()
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


## GP-19 derived presentation cache, never serialized or used by physics.
var _hull_scrape_cache_key := PackedByteArray()
var _hull_scrape_cache := {}
var _hull_scrape_cache_tick := -1


## Accepted endpoint instantaneous friction power. Guard pending configuration
## BEFORE reading live mass/source layouts. First scope is flat solid ground.
func hull_scrape_observation() -> Dictionary:
	var result := {schema = "openrc-hull-friction-observation", version = 1,
		tick = _contact_tick, generation = statistics_generation, law_identity = HullContact.law(),
		available = false, sampling = "accepted_endpoint_instantaneous_power", contacts = [], reason = "flight_not_ready"}
	if sim == null or not _flight_ready():
		return result
	if not soft_hull_contacts or _hull_contact.is_empty():
		result.reason = "soft_hull_unavailable"
		return result
	if _contact_tick < 0 or _contact_tick != sim.tick:
		result.reason = "no_current_accepted_hull_tick"
		return result
	# State/layout/field binding changes invalidate even at the same clock value.
	# The owner-supplied accepted state is observed once; render only drains audio.
	# A key always contains the tick, so a first call at a new tick cannot hit: skip
	# serializing the bindings (about 16 kB per 240 Hz tick) until a same-tick call.
	var key := PackedByteArray()
	if sim.tick == _hull_scrape_cache_tick:
		key = var_to_bytes([sim.tick, statistics_generation, sim.state, sim.continuous,
			_hull_contact, _contact_bindings, _lake, environment.surfaces, environment._ground_support])
		if key == _hull_scrape_cache_key:
			return _hull_scrape_cache.duplicate(true)
	var diagnostics := {}
	if finite_fuel_is_active():
		var properties := mass_properties()
		var sampled := HullContact.loads_at_properties(sim.state, _hull_contact, properties, diagnostics)
		if not sampled.ok:
			result.reason = "live_mass_contact_unavailable"
			return result
	else:
		HullContact.loads(sim.state, _hull_contact, [], diagnostics)
	if not diagnostics.available:
		result.reason = str(diagnostics.reason)
		return result
	var probes: Array = _contact_bindings.get("hull_probes", [])
	var rows: Array = []
	for diagnostic: Dictionary in diagnostics.rows:
		var index: int = diagnostic.index
		if index < 0 or index >= probes.size():
			result.reason = "hull_binding_unavailable"
			return result
		var support := environment.sample_support(diagnostic.point_ned,
			diagnostic.relative_tangent_velocity_ned_mps, sim.time())
		var row := diagnostic.duplicate(true)
		row.erase("index")
		row.contact_id = str(probes[index].id)
		row.material_id = str(support.get("material_id", "")) if support.get("ok", false) else ""
		rows.append(row)
	result.contacts = rows
	result.available = true
	result.reason = ""
	_hull_scrape_cache_tick = sim.tick
	_hull_scrape_cache_key = key
	_hull_scrape_cache = result.duplicate(true) if not key.is_empty() else {}
	return result


func contact_events() -> Dictionary:
	return {format = "openrc-aircraft-contact-state v1", tick = _contact_tick,
		active_hull_ids = _active_hull_ids.duplicate(), events = _contact_events.duplicate(true),
		prop_strike = prop_strike.duplicate(true)}


## GP-14: factual accepted-state observation, independent of physical damage and pause.
## Keep the historical contact checkpoint envelope unchanged. The pure flight detector
## owns episode/crash deduplication; reading this receipt never mutates simulation state.
func accident_observation() -> Dictionary:
	var touching: bool = sim != null and _contact_tick == sim.tick and not _active_hull_ids.is_empty()
	var gear_up := false
	if touching and _contact_tick > 0 and gear_is_retractable() and _gear_aux_valid(sim.aux) \
			and not _contact_bindings.get("support_points", []).is_empty():
		# Current retract law has an exact fully-down endpoint, not a 95% mechanical lock.
		# Pilot intent is irrelevant: a deliberately commanded gear-up landing is an accident.
		gear_up = sim.aux[gear_aux_index()] < 1.0
	var intended := hull_support_observation()
	return {schema = "openrc-aircraft-accident-observation", version = 1,
		tick = _contact_tick, generation = statistics_generation,
		gear_up_contact = gear_up, ground_contact = touching,
		intended_support = bool(intended.facts.get("intended_support", false)) if intended.available else false,
		terminal = not crash.is_empty()}


## Optional authored intent over the SAME accepted hull IDs. Initial scope is the
## declared flat solid hull law: its unit normal/height are [0,0,-1]/0m, not the
## separate wheel micro-relief gradient. No trial geometry or history is evaluated.
func hull_support_observation() -> Dictionary:
	var result := {schema = "openrc-aircraft-hull-support-observation", version = 1,
		tick = _contact_tick, generation = statistics_generation, available = false,
		identity = "", facts = {}, reason = "intended_hull_support_absent"}
	if sim == null or not aircraft.get("ok", false) or not aircraft.model.has("intended_hull_support"):
		return result
	var prepared: Variant = _contact_bindings.get("intended_hull_support")
	var authored: Variant = aircraft.model.intended_hull_support
	result.reason = "intended_hull_support_binding_invalid"
	if not prepared is Dictionary or not authored is Dictionary \
		or not IntendedHullSupport.matches_model(authored, aircraft.model) or var_to_bytes(prepared) != var_to_bytes(authored):
		return result
	result.identity = str(prepared.identity)
	if not soft_hull_contacts:
		result.reason = "intended_hull_support_requires_soft_hull"
		return result
	if not _lake.is_empty():
		result.reason = "intended_hull_support_lake_scope_unavailable"
		return result
	if _contact_tick <= 0 or _contact_tick != sim.tick:
		result.reason = "no_current_accepted_hull_tick"
		return result
	var facts := IntendedHullSupport.evaluate(prepared, _active_hull_ids,
		sim.state.slice(RB.ATT, RB.ATT + 4), PackedFloat64Array([0.0, 0.0, -1.0]),
		sim.state.slice(RB.RATE, RB.RATE + 3), HullContact.law())
	if not facts.ok:
		result.reason = "intended_hull_support_query_invalid"
		return result
	result.available = true
	result.facts = facts
	result.reason = ""
	return result


## The observer owns the accepted-tick presentation sample; the next input guard can reuse it.
func _refresh_soft_contacts() -> void:
	soft_contacts = HullContact.contacts(sim.previous, sim.state, _hull_contact)
	_soft_contacts_cache_previous = sim.previous.duplicate()
	_soft_contacts_cache_state = sim.state.duplicate()
	_soft_contacts_cache_tick = sim.tick


func _observe_contact_tick(tick: int) -> void:
	_contact_tick = tick
	_contact_events.clear()
	if tick == 0:
		_active_hull_ids.clear()
		prop_strike = {}
	if not soft_hull_contacts or not aircraft.get("ok", false):
		_soft_contacts_cache_tick = -1
		_active_hull_ids.clear()
		return
	_refresh_soft_contacts()
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
	_hull_scrape_cache_key = PackedByteArray()
	_hull_scrape_cache = {}
	_hull_scrape_cache_tick = -1
	_contact_tick = -1
	_soft_contacts_cache_tick = -1
	_contact_events.clear()
	_active_hull_ids.clear()
	_clear_pending_contacts()


func _restore_contact_history(record: Dictionary) -> void:
	_hull_scrape_cache_key = PackedByteArray()
	_hull_scrape_cache = {}
	_hull_scrape_cache_tick = -1
	_contact_tick = int(record.tick)
	_soft_contacts_cache_tick = -1
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
	if external_driver_enabled:
		return # fleet-owned damage is imported/published by the external world coordinator
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
	if _reject_reset_publication_reentry(): return {ok = false, message = "reset publication is in progress"}
	return _trim_at_start_candidate(speed, mode)


func _trim_at_start_candidate(speed: float, mode: String) -> Dictionary:
	var m: Dictionary = _trim_model(aircraft.model)
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
	if _reject_reset_publication_reentry(): return
	if start.get("ok", false) and is_finite(altitude) and Sim.state_is_valid(start.state):
		var s: PackedFloat64Array = start.state
		s[RB.POS + 2] = -altitude
		start.state = s


## [F5] Reloads the aircraft data file, re-trims and restarts: tune a coefficient without restarting the app.
## Invalid data keeps the current aircraft flying. Returns a message for the panel.
func reload() -> String:
	if _reject_reset_publication_reentry(): return "reload refused: reset publication is in progress"
	_statistics_reload_depth += 1
	var result: String = _reload_impl()
	_statistics_reload_depth -= 1
	if result.begins_with("aircraft reloaded:"):
		_statistics_committed("reload")
	return result


func _reload_impl() -> String:
	if calibration != null:
		return "reload refused during radio calibration; finish or cancel calibration first"
	var transaction := _begin_start_transaction()
	if _reset_transaction_reentry:
		_refuse_start_transaction(transaction, "reload preparation attempted owner transition reentry")
		return "reload failed; previous aircraft and flight retained: owner transition reentry"
	var prepared := _prepare_aircraft(_load_selected_aircraft())
	if not prepared.ok:
		_refuse_start_transaction(transaction, str(prepared.message))
		return "reload failed; previous aircraft and flight retained: %s" % prepared.message
	if _failures != null and not _failures.accepts_profile(FailureCatalog.profile_for_model(prepared.data.model)):
		_refuse_start_transaction(transaction, "propulsion failure profile changed")
		return "reload failed; the propulsion failure profile changed; start a new flight"
	if start_choice == START_RUNWAY:
		var runway_candidate: Dictionary = _validate_runway_candidate(prepared)
		if not runway_candidate.ok:
			_refuse_start_transaction(transaction, str(runway_candidate.message))
			return "reload failed; previous aircraft and flight retained: %s" % runway_candidate.message
	var pilot_trim: PackedFloat64Array = _pilot_trim_offset() # D6-TRIM-01: the reloaded start trim replaces trims
	_commit_aircraft(prepared) # Reversible owner staging until the common physical commit.
	if out_of_trim_active():
		_set_trims_from_start(pilot_trim) # the reset below carries it on first flight only
	var receipt := _reset_impl(false, transaction)
	if not receipt.get("committed", false):
		_refuse_start_transaction(transaction, str(receipt.get("message", "selected reset refused")))
		return "reload failed; previous aircraft and flight retained: " + str(receipt.get("message", "selected reset refused"))
	if receipt.get("status", "") == "observer_fault":
		return "aircraft reloaded: observer fault; simulation paused: " + str(receipt.message)
	if str(_launch_metadata.get("launch_choice", "")) == "runway":
		return "aircraft reloaded: runway start on field '%s'" % str(_launch_metadata.get("launch_field_id", ""))
	if str(_launch_metadata.get("launch_choice", "")) == START_HAND_LAUNCH:
		return "aircraft reloaded: hand launch on field '%s'" % str(_launch_metadata.get("launch_field_id", ""))
	return "aircraft reloaded: trimmed at %.0f m/s, throttle %d %%" % [start.V, roundi(start.throttle * 100.0)]





## Preflights the selected runway route before reload emits `resetting` or replaces active data.
func _validate_runway_candidate(prepared: Dictionary) -> Dictionary:
	if not surface_error.is_empty():
		return { ok = false, message = surface_error }
	if _runway_field.is_empty():
		return { ok = false, message = "runway start needs a loaded field" }
	var field_id: String = str(_runway_field.get("id", ""))
	if field_id.is_empty() or ground_field_id != field_id:
		return { ok = false, message = "runway field does not match the installed contact surfaces" }
	var data: Dictionary = prepared.get("data", {})
	if not data.get("ok", false):
		return { ok = false, message = "aircraft data is invalid" }
	var model: Dictionary = data.get("model", {})
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
	var solved: Dictionary = GroundStart.solve(_trim_model(model), ground_surfaces, float(spot.north), float(spot.east), float(spot.heading),
		deflections, input_values[2], rpm, density, sim.gravity, _initial_wind(), _model_wheel_count(model) > 0,
		environment_at if _weather.has_vertical_atmosphere() else Callable(), _initial_air_sampler(_trim_model(model)))
	return { ok = true, message = "" } if solved.ok else { ok = false, message = "runway start: " + str(solved.message) }


func _poll_controller(integrate := true) -> bool:
	if external_driver_enabled:
		return false
	radio.poll(read_axis, sim.dt(), read_button, integrate and not sim.paused and calibration == null and holds.is_empty())
	if external_controller_selection and (not radio.input_error.is_empty() or not radio.profile_error.is_empty()):
		controller_disconnected()
		pause_reason = "Invalid controller input. Review the device and select it again in Controls."
		return false
	return true


func _physics_process(_delta: float) -> void:
	if external_driver_enabled:
		return
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
	_session_after_input()


## Session guards run before the Simulation child, matching the normal callback order.
## Returns true only when one kernel tick may follow.
func _session_after_input() -> bool:
	# D9d: any crash-hull point at or below the ground is a crash. E1: the wheels are spring-damper contacts instead
	# (aircraft with a landing_gear section); a leg pushed past its travel is a crash too.
	if not crash.is_empty():
		if not crash_auto_restart:
			return false
		crash.ticks_left -= 1
		if crash.ticks_left <= 0:
			reset()
		return false
	if physics_enabled and not sim.paused and _flight_ready() and Sim.state_is_valid(sim.state):
		if soft_hull_contacts:
			if _soft_contacts_cache_tick != sim.tick or _soft_contacts_cache_previous != sim.previous \
					or _soft_contacts_cache_state != sim.state:
				_refresh_soft_contacts()
			# Glow terminal hull decisions already ran with the previous fuel snapshot inside the accepted tick.
			var hit: Dictionary = {index = -1} if finite_fuel_is_active() else HullContact.terminal(sim.previous, sim.state, _hull_contact)
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
	return physics_enabled and not sim.paused and sim.fault_reason.is_empty() \
		and crash.is_empty() and _flight_ready() and Sim.state_is_valid(sim.state)


## Stage one controllerless pilot sample. A rejected packet leaves the last staged packet intact.
func prepare_external_tick(packet: Dictionary) -> Dictionary:
	if not external_driver_enabled:
		return {ok = false, errors = ["external driver is not configured"]}
	var errors: Array[String] = []
	var required := ["roll", "pitch", "yaw", "throttle"]
	var allowed := ["roll", "pitch", "yaw", "throttle", "gear_down", "flaps", "brake"]
	var normalized_packet: Dictionary = {}
	for raw_key: Variant in packet.keys():
		if typeof(raw_key) not in [TYPE_STRING, TYPE_STRING_NAME]:
			errors.append("unsupported packet field: %s" % str(raw_key))
			continue
		var key: String = str(raw_key)
		if not allowed.has(key):
			errors.append("unsupported packet field: %s" % key)
		elif normalized_packet.has(key):
			errors.append("duplicate packet field: %s" % key)
		else:
			normalized_packet[key] = packet[raw_key]
	for key: String in required:
		if not normalized_packet.has(key):
			errors.append("missing required field: %s" % key)
		elif not _external_number_is_in_range(normalized_packet[key], 0.0 if key == "throttle" else -1.0, 1.0):
			errors.append("%s must be a finite number in [%s, 1]" % [key, "0" if key == "throttle" else "-1"])
	if normalized_packet.has("gear_down"):
		if typeof(normalized_packet.gear_down) != TYPE_BOOL:
			errors.append("gear_down must be a bool")
		elif not gear_is_retractable():
			errors.append("gear_down is unsupported by this aircraft")
	if normalized_packet.has("flaps"):
		if not _external_number_is_in_range(normalized_packet.flaps, 0.0, 1.0):
			errors.append("flaps must be a finite number in [0, 1]")
		elif not flaps_available():
			errors.append("flaps are unsupported by this aircraft")
	if normalized_packet.has("brake"):
		if not _external_number_is_in_range(normalized_packet.brake, 0.0, 1.0):
			errors.append("brake must be a finite number in [0, 1]")
		elif float(normalized_packet.brake) > 0.0 and not wheel_brake_available():
			errors.append("brake is unsupported without explicitly available wheel brake hardware")
	if not errors.is_empty():
		return {ok = false, errors = errors}
	var staged: Dictionary = {}
	for key: String in required:
		staged[key] = float(normalized_packet[key])
	for key: String in ["gear_down", "flaps", "brake"]:
		if normalized_packet.has(key):
			staged[key] = normalized_packet[key] if key == "gear_down" else float(normalized_packet[key])
	_external_pending_packet = staged
	_external_packet_ready = true
	return {ok = true, errors = []}


## Consume one staged packet through the ordinary session guards and one kernel tick.
func step_external_tick() -> bool:
	if not external_driver_enabled or not _external_packet_ready or sim == null:
		return false
	if not physics_enabled or not sim.fault_reason.is_empty() or not holds.is_empty() \
			or calibration != null or not _flight_ready() or sim.stop_at_tick >= 0 and sim.tick >= sim.stop_at_tick:
		_discard_external_packet()
		return false
	var packet: Dictionary = _external_pending_packet
	commands = {roll = packet.roll, pitch = packet.pitch, yaw = packet.yaw, throttle = packet.throttle}
	raw = commands.duplicate()
	if packet.has("gear_down"):
		_gear_requested_down = packet.gear_down
	if packet.has("flaps"):
		_flap_requested = packet.flaps
	if packet.has("brake"):
		_wheel_brake_demand = packet.brake
	sim.inputs = _inputs()
	var previous_tick: int = sim.tick
	if not _session_after_input() or sim.paused or not sim.fault_reason.is_empty():
		_discard_external_packet()
		return false
	sim.step()
	var accepted: bool = sim.tick == previous_tick + 1 and sim.fault_reason.is_empty()
	_discard_external_packet()
	return accepted


func _discard_external_packet() -> void:
	_external_pending_packet.clear()
	_external_packet_ready = false


func _external_number_is_in_range(value: Variant, minimum: float, maximum: float) -> bool:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
		return false
	var number := float(value)
	return is_finite(number) and number >= minimum and number <= maximum


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
	if liquid_fuel_is_active():
		return LiquidFlight.contact_sampler(self, previous_values, candidate_values)
	if not glow_is_active() or previous_values.size() != GlowFlight.SIZE + wheel_count() \
			or candidate_values.size() != previous_values.size():
		return Callable()
	var before_context: Dictionary = GlowFlight.mass_context(self, previous_values)
	if not before_context.get("ok", false) or not GlowFlight.mass_context(self, candidate_values).get("ok", false):
		return Callable()
	var before: float = previous_values[1]
	var after: float = candidate_values[1]
	var before_line: float = previous_values[GlowFlight.LINE_FUEL_INDEX]
	var after_line: float = candidate_values[GlowFlight.LINE_FUEL_INDEX]
	var contact_tick: int = sim.tick + 1
	var start_time: float = sim.time()
	var dt: float = sim.dt()
	return func(fraction: float) -> Dictionary:
		if not is_finite(fraction) or fraction < 0.0 or fraction > 1.0:
			return {ok = false, reason = "contact mass fraction is outside the tick"}
		var total: float = lerpf(before, after, fraction)
		var line: float = lerpf(before_line, after_line, fraction)
		# Interpolate inventories only. Discrete supply modes change at events and
		# are not meaningful on this geometric interpolation of accepted endpoints.
		var properties: Dictionary = GlowFlight.properties(self, total, line)
		if not properties.get("ok", false):
			return {ok = false}
		var remaining: Dictionary = {str(before_context.tanks[0].id): total-line}
		if before_context.tanks.size()>1: remaining[str(before_context.tanks[1].id)]=line
		var result: Dictionary = FuelSample.build(properties, before_context.tanks, remaining,
			contact_tick, start_time + fraction * dt, true)
		result.sample_boundary = "swept_contact_linear_inventory"
		result.impact_fraction = fraction
		result.law = GlowFlight.LAW
		result.registry_sha256 = str(aircraft.model.fuel_system.registry_sha256)
		return result


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
	if finite_fuel_is_active():
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
	var speed := sqrt(s[RB.VEL] ** 2 + s[RB.VEL + 1] ** 2 + s[RB.VEL + 2] ** 2)
	var prev: PackedFloat64Array = sim.previous
	var sink: float = (s[RB.POS + 2] - prev[RB.POS + 2]) / sim.dt()
	if not impact_state.is_empty():
		sink = M.q_rotate(RB._att(s), RB._slice3(s, RB.VEL))[2]
	crash = { speed = speed, sink = sink, ticks_left = roundi(CRASH_HOLD_S / sim.dt()), why = why, impact = impact }
	sim.set_paused(true)
	pause_reason = "CRASH at %.1f m/s (sink %.1f m/s%s) - %s" % [speed, sink, "" if why.is_empty() else ", " + why, "restarting" if crash_auto_restart else "[R] restart"]
	print(pause_reason)
	_append_contact_event(ContactEvents.impact_event(impact, _contact_bindings, _impact_policy(impact)))


## The shell may retain an armed radio when restarting under the same device/profile ownership.
func reset(preserve_radio_readiness := false) -> void:
	if _reject_reset_publication_reentry(): return
	var result := _reset_impl(preserve_radio_readiness)
	if not result.get("committed", false):
		if not result.get("ok", false) and calibration == null:
			start_error = str(result.get("message", "reset refused"))
			# Only an owner with no previous accepted physical frame is parked.
			if not Sim.state_is_valid(sim.state): _fail_selected_start(start_error)
		return
	if _statistics_reload_depth == 0 and calibration == null:
		_statistics_committed("restart")


func _statistics_committed(cause: String) -> void:
	_statistics_operation += 1
	var previous: int = statistics_generation
	statistics_generation += 1
	statistics_lifecycle.emit({operation_id = _statistics_operation, cause = cause,
		old_generation = previous, generation = statistics_generation, success = true})


func _reset_impl(preserve_radio_readiness := false, supplied_transaction: Dictionary = {}) -> Dictionary:
	if calibration != null:
		return {ok = false, committed = false, message = "reset refused during radio calibration"}
	var transaction := supplied_transaction if not supplied_transaction.is_empty() else _begin_start_transaction()
	if _reset_transaction_reentry:
		return _refuse_start_transaction(transaction, "reset preparation attempted owner transition reentry")
	_fuel_start_fill_known = true
	_shaft_pending_reset = false
	var pilot_trim: PackedFloat64Array = _pilot_trim_offset() # D6-TRIM-01: before a refit replaces the start trim
	var selection_refit: Dictionary = _refit_selected_trim()
	if not selection_refit.ok:
		return _refuse_start_transaction(transaction, str(selection_refit.message))
	_stage_out_of_trim()
	var result: Dictionary
	if start_choice == START_RUNWAY:
		_restore_out_of_trim_trims(pilot_trim)
		result = _reset_selected_runway_start(transaction)
		runway_start_outcome = result.duplicate(true)
		if not result.ok:
			return _refuse_start_transaction(transaction, str(result.get("message", "runway start refused")))
		# Private receipt: ordinary public GroundStart result keys stay unchanged.
		result = result.duplicate(true)
		result.committed = bool(transaction.committed)
	else:
		var start_density: float = air_density(start.get("state", PackedFloat64Array()))
		var start_charge: float = engine_charge_ratio(start.get("state", PackedFloat64Array()))
		if aircraft.get("ok", false) and (_trim_density != start_density or _trim_charge != start_charge):
			var old_start: Dictionary = start
			var speed: float = float(old_start.get("V", aircraft.model.get("start_speed", 15.0)))
			if not is_finite(speed) or speed <= 0.0:
				speed = float(aircraft.model.get("start_speed", 15.0))
			var cruise: bool = cruise_trim_active()
			var refit: Dictionary = _selected_airborne_trim(aircraft.model, _atmosphere_down(old_start.get("state", PackedFloat64Array()))) if cruise else _trim_at_start_candidate(speed, str(old_start.get("mode", "level")))
			if not refit.ok:
				return _refuse_start_transaction(transaction, "atmosphere trim refused: " + str(refit.message))
			if cruise:
				start = refit
				_trim_density = start_density
				_trim_charge = start_charge
			if Sim.state_is_valid(old_start.get("state", PackedFloat64Array())):
				for axis: int in 3:
					start.state[RB.POS + axis] = old_start.state[RB.POS + axis]
		# D6e-R1: a restart must restore the solved equilibrium, including pilot-adjusted trim.
		if _has_valid_start():
			trims = {roll = start.roll_command, pitch = start.pitch_command, yaw = start.get("yaw_command", 0.0)}
		# D6-TRIM-01: on a first-flight-only airframe the pilot's own trim survives restarts and crashes.
		_restore_out_of_trim_trims(pilot_trim)
		if start_choice == START_AIRBORNE or start_choice == START_HALF_POWER:
			result = _reset_airborne_candidate(PackedFloat64Array(), NAN, NAN, ["airborne", "trimmed_airborne", ""], transaction)
		elif start_choice == START_HAND_LAUNCH:
			result = _reset_hand_launch_start(transaction)
		else:
			return _refuse_start_transaction(transaction, "unsupported start choice '%s'" % start_choice)
	if not result.ok:
		return _refuse_start_transaction(transaction, str(result.get("message", "selected start refused")))
	_remember_out_of_trim_airframe()
	if result.get("status", "") == "observer_fault": return result
	if external_controller_selection and radio.connected:
		_pending_controller_start = float(commands.throttle) if radio.is_rate_throttle() else -1.0
		radio.require_neutral(preserve_radio_readiness and not radio.is_gamepad())
		sim.set_paused(true)
		pause_reason = "Restart ready. Release controls and continue explicitly."
	return result


## Prepares the ordinary trimmed flight in the common start transaction. X8-07: a hand launch passes its
## ground-relative release state (no wind added), throttle and rpm, and its launch identity.
## Boolean compatibility boundary for existing technical probes. The receipt
## helper below remains the same shared transaction, not a second reset path.
func _reset_airborne_start(release := PackedFloat64Array(), release_throttle := NAN, release_rpm := NAN,
		launch := ["airborne", "trimmed_airborne", ""]) -> bool:
	if _reject_reset_publication_reentry(): return false
	return bool(_reset_airborne_candidate(release, release_throttle, release_rpm, launch).get("committed", false))


func _reset_airborne_candidate(release := PackedFloat64Array(), release_throttle := NAN, release_rpm := NAN,
		launch := ["airborne", "trimmed_airborne", ""], supplied_transaction: Dictionary = {}) -> Dictionary:
	var transaction := supplied_transaction if not supplied_transaction.is_empty() else _begin_start_transaction()
	if not _has_valid_start():
		return _refuse_start_transaction(transaction, _start_failure_reason())
	_flap_requested = 0.0
	var gear_aux := _initial_gear_aux(false)
	if not _stage_start_failures():
		return _refuse_start_transaction(transaction, "failure state cannot be prepared")
	var weather_aux: PackedFloat64Array = _restart_weather_aux()
	var thrown: bool = release.size() == RB.SIZE
	var initial: PackedFloat64Array = start.state.duplicate() if _has_valid_start() else PackedFloat64Array()
	if thrown and _has_valid_start():
		initial = release.duplicate()
	if _external_spawn_heading_set and initial.size() == RB.SIZE and not thrown:
		var trim_euler: PackedFloat64Array = M.q_to_euler(M.quat(initial[RB.ATT], initial[RB.ATT + 1],
			initial[RB.ATT + 2], initial[RB.ATT + 3]))
		var spawned_attitude: PackedFloat64Array = M.q_from_euler(_external_spawn_heading_rad,
			trim_euler[1], trim_euler[2])
		for axis: int in 4:
			initial[RB.ATT + axis] = spawned_attitude[axis]
	if _has_valid_start() and not weather_is_calm() and not thrown:
		var attitude: PackedFloat64Array = M.quat(initial[RB.ATT], initial[RB.ATT + 1], initial[RB.ATT + 2], initial[RB.ATT + 3])
		var wind_body: PackedFloat64Array = M.q_rotate(M.q_conj(attitude), _initial_wind(initial.slice(RB.POS, RB.POS + 3)))
		for axis: int in 3:
			initial[RB.VEL + axis] += wind_body[axis]
	commands = Commands.neutral_commands()
	if _has_valid_start():
		commands.throttle = release_throttle if thrown else start.throttle
		engine_running = commands.throttle > 0.0 if thrown else start.get("mode", "level") != "glide"
	else:
		commands.throttle = 0.0
		engine_running = false
	# Inputs first: synchronous paths (capture, --trace) never tick this node, so they must start trimmed too.
	sim.inputs = _inputs()
	# Engine at its trimmed rpm and servos already at the trimmed surface positions.
	var start_rpm: float = (release_rpm if thrown else float(start.get("rpm", 0.0))) if _has_valid_start() else 0.0
	var aux := PackedFloat64Array([start_rpm, sim.inputs[0], sim.inputs[1], sim.inputs[2]])
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
	sim.continuous = _settled_continuous(initial, aux)
	_prepare_stage_backend(0.0)
	var result := _commit_start_candidate(sim.prepare_reset(initial), transaction)
	if result.get("committed", false):
		_capture_launch(str(launch[0]), str(launch[1]), str(launch[2]), str(result.get("observer_fault", "")))
	return result


## X8-07: installs the hand-launch release through the airborne start. A refusal installs nothing; the caller fails
## the selected start instead of falling back.
func _reset_hand_launch_start(transaction: Dictionary) -> Dictionary:
	if not aircraft.get("ok", false) or not _has_valid_start():
		return {ok = false, message = _start_failure_reason()}
	if not _hand_launch_model_supported(aircraft.model):
		return {ok = false, message = "hand launch is offered to airplanes without landing gear"}
	if _runway_field.is_empty():
		return {ok = false, message = "hand launch needs a loaded field"}
	# Placement is independent of wind direction. Spatial weather needs its actual release
	# location and height before selecting the along-runway heading; it has no time-only sample.
	var release: Dictionary = hand_launch_release(_runway_field,
		M.v3(0.0, 0.0, 0.0) if _weather.is_spatial() else _weather.sample(0.0))
	if not release.ok:
		return release
	var terrain: PackedFloat64Array = environment.terrain(release.north, release.east)
	if terrain.is_empty() or not is_finite(terrain[0]):
		return {ok = false, message = "hand launch: no terrain height at the release point"}
	var down: float = -(float(terrain[0]) + HAND_LAUNCH_RELEASE_HEIGHT_M)
	if _weather.is_spatial():
		var local_wind: PackedFloat64Array = _weather.sample_world(M.v3(release.north, release.east, down), 0.0)
		if local_wind.size() != 3 or not Aero._spatial_finite(local_wind, 3):
			return {ok = false, message = "hand launch: spatial wind is invalid at the release point"}
		release = hand_launch_release(_runway_field, local_wind)
		if not release.ok:
			return release
	var state: PackedFloat64Array = Scenarios.Trim.state_for(HAND_LAUNCH_SPEED_MPS, 0.0,
		HAND_LAUNCH_CLIMB_RAD, float(release.heading), M.v3(release.north, release.east, down))
	if not Sim.state_is_valid(state):
		return {ok = false, message = "hand launch: invalid release state"}
	var rpm: float = _hand_launch_rpm(state)
	if not is_finite(rpm) or rpm < 0.0:
		return {ok = false, message = "hand launch: no full-throttle motor operating point at the release"}
	var field_id: String = str(_runway_field.get("id", ""))
	return _reset_airborne_candidate(state, HAND_LAUNCH_THROTTLE, rpm,
		[START_HAND_LAUNCH, "hand_launch_release", field_id], transaction)


## The motor already runs at the launch throttle when the airplane leaves the hand (steady shaft speed at the throw's
## axial airspeed). Non-electric shafts use the steady torque balance.
func _hand_launch_rpm(state: PackedFloat64Array) -> float:
	var prop: Dictionary = aircraft.model.propulsion
	var u: float = M.dot(M.v3(state[RB.VEL], state[RB.VEL + 1], state[RB.VEL + 2]), Propulsion.axis(prop))
	var rho: float = air_density(state)
	if _weather.is_spatial():
		var stage := WindFlow.stage_air(state, aircraft.model, environment, 0.0, rho,
			Aero.SPATIAL_CONTINUATION_LAW, false)
		if not stage.ok:
			return NAN
		var inflow := Propulsion.stage_air_velocity(state, stage.air, prop)
		if not inflow.get("ok", false):
			return NAN
		u = M.dot(inflow.velocity_body, Propulsion.axis(prop))
	if Propulsion.is_electric(prop):
		var point: Dictionary = Propulsion.steady_operating_point(HAND_LAUNCH_THROTTLE, u, prop, rho)
		return float(point.rpm) if point.get("ok", false) else NAN
	return Propulsion.steady_rpm(HAND_LAUNCH_THROTTLE, u, prop, rho, engine_charge_ratio(state))


func _reset_selected_runway_start(transaction: Dictionary = {}) -> Dictionary:
	if not surface_error.is_empty():
		return { ok = false, message = surface_error }
	if not aircraft.get("ok", false) or not start.get("ok", false):
		return { ok = false, message = _start_failure_reason() }
	if not _runway_model_supported(aircraft.model):
		return { ok = false, message = "runway start needs landing gear with stiction data" }
	if _runway_field.is_empty():
		return { ok = false, message = "runway start needs a loaded field" }
	var field_id: String = str(_runway_field.get("id", ""))
	if field_id.is_empty() or ground_field_id != field_id:
		return { ok = false, message = "runway field does not match the installed contact surfaces" }
	if anchor_count() == 0:
		return { ok = false, message = "runway start needs landing gear with stiction data" }
	var spot: Dictionary = GroundStart.threshold(_runway_field)
	if not spot.ok:
		return { ok = false, message = "runway start: " + str(spot.message) }
	var result: Dictionary = _apply_runway_start(float(spot.north), float(spot.east), float(spot.heading), transaction)
	if not result.ok:
		return result
	_capture_launch("runway", "runway_threshold", field_id, str(result.get("observer_fault", "")))
	return result


## Solves and installs a runway pose. It never selects or falls back to another start.
func _apply_runway_start(north: float, east: float, heading: float, supplied_transaction: Dictionary = {}) -> Dictionary:
	if not _has_valid_start() or anchor_count() == 0:
		return {ok = false, status = "invalid_input", message = "runway start needs valid aircraft data, trim, and stiction gear"}
	var transaction := supplied_transaction if not supplied_transaction.is_empty() else _begin_start_transaction()
	if _reset_transaction_reentry:
		return _refuse_start_transaction(transaction, "reset preparation attempted owner transition reentry")
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
	var solved: Dictionary = GroundStart.solve(_trim_model(aircraft.model), ground_surfaces, north, east, heading, _deflections(aux), aux[AUX_SERVO+2],
		rpm, density, sim.gravity, _initial_wind(), wheel_count() > 0,
		environment_at if _weather.has_vertical_atmosphere() else Callable(), _initial_air_sampler(_trim_model(aircraft.model)))
	if not solved.ok:
		_refuse_start_transaction(transaction, str(solved.message))
		solved.message = "runway start: " + str(solved.message)
		return solved
	aux.append_array(solved.anchors)
	if downwash_index() >= 0:
		aux.append(0.0)
	if not _stage_start_failures():
		return _refuse_start_transaction(transaction, "runway start: failure state cannot be prepared")
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
	_prepare_stage_backend(0.0)
	var receipt := _commit_start_candidate(sim.prepare_reset(solved.state), transaction)
	if not receipt.ok:
		return {ok = false, status = "numerical_unresolved", message = "runway start: " + str(receipt.message), diagnostics = solved.get("diagnostics", {})}
	if receipt.status == "observer_fault":
		solved.merge(receipt, true)
		return solved
	solved.status = "converged"
	return solved


## Explicit launch transaction. A rejected attempt leaves the current flight intact.
## Rejection is diagnostic; the caller may separately choose an airborne fallback.
func try_runway_start(north: float, east: float, heading: float) -> Dictionary:
	if _reject_reset_publication_reentry(): return {ok = false, status = "publication_reentry", message = "reset publication is in progress"}
	var result := _apply_runway_start(north, east, heading)
	runway_start_outcome = result.duplicate(true)
	if result.ok:
		_capture_launch("runway", "runway_threshold", ground_field_id, str(result.get("observer_fault", "")))
		if _statistics_reload_depth == 0 and calibration == null:
			_statistics_committed("restart") # Accepted physical reset, even if an observer faulted.
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
		"launch_trim_throttle": _launch_trim_label(),
		"launch_error": error_text,
	}


## D6e-R4: the throttle the launched start was solved for ("reference" for the slow level trim).
func _launch_trim_label() -> String:
	var requested: float = float(start.get("requested_throttle", NAN)) if _has_valid_start() else NAN
	return String.num(requested, 4) if is_finite(requested) else "reference"


func _has_valid_start() -> bool:
	return aircraft.get("ok", false) and start.get("ok", false) and sim != null and surface_error.is_empty()


func _flight_ready() -> bool:
	return _has_valid_start() and not _weather_pending_reset and not _shaft_pending_reset and sim.fault_reason.is_empty()


## Radios supply transmitter-shaped commands. Calibrated joysticks use simulator rates.
func rate_profile_available() -> bool:
	return aircraft.get("ok", false) and aircraft.model.controls.has("rates") and not external_driver_enabled \
		and not (radio.connected and radio.profile.get("kind", "radio") == "radio")


## D6e: true while the aircraft's normal or sport profile shapes the sticks.
func rates_active() -> bool:
	return rate_profile in ["normal", "sport"] and rate_profile_available()


## Effective shaping profile, also used by the HUD and recorder. External drivers provide post-rate commands.
func effective_rate_profile() -> String:
	return rate_profile if rates_active() and not external_driver_enabled else "full"


func rate_profile_label() -> String:
	match effective_rate_profile():
		"normal": return "Rates: normal"
		"sport": return "Rates: sport"
	return "Rates: full"


## D6e-R5: two-position dual rates: normal ⇄ the selected high profile (sport or full). Refused when the aircraft
## has no controls.rates or a radio is connected (it keeps its own rates). Only the input layer changes: the next tick
## samples the new shaping, and flight logs record post-rate inputs, so a replay reproduces the switch exactly.
func toggle_rate_profile() -> bool:
	if not rate_profile_available():
		return false
	if rate_profile == "normal":
		rate_profile = _high_rate_profile
	else:
		_high_rate_profile = rate_profile
		rate_profile = "normal"
	rate_profile_changed.emit(rates_active())
	return true


## Manual elevator trim, degrees trailing edge up (+ = nose up). Only changes the command offset;
## the normal tick sampler and servo apply it. No force, attitude, throttle or speed is changed here.
func adjust_elevator_trim(delta_deg: float) -> bool:
	if not is_finite(delta_deg) or not physics_enabled or not input_enabled or not _flight_ready() \
			or sim.paused or not holds.is_empty() or not crash.is_empty() or calibration != null:
		return false
	var throw_deg: float = aircraft.model.controls.throw_deg.elevator
	trims.pitch = clampf(float(trims.pitch) + delta_deg / throw_deg, -1.0, 1.0)
	_remember_out_of_trim_airframe()
	return true


## Keyboard trim in normalized maximum-throw units; the fault remains downstream of this command.
func adjust_aileron_trim(delta_units: float) -> bool:
	if not is_finite(delta_units) or not physics_enabled or not input_enabled or not _flight_ready() \
			or sim.paused or not holds.is_empty() or not crash.is_empty() or calibration != null:
		return false
	trims.roll = clampf(float(trims.roll) + delta_units, -1.0, 1.0)
	_remember_out_of_trim_airframe()
	return true


## D6-TRIM-01: rudder trim in normalized maximum-throw units (+ = trailing edge right, nose right), like the aileron's.
## Refused on an aircraft without a rudder.
func adjust_rudder_trim(delta_units: float) -> bool:
	if not is_finite(delta_units) or not physics_enabled or not input_enabled or not _flight_ready() \
			or sim.paused or not holds.is_empty() or not crash.is_empty() or calibration != null \
			or throws_deg().has("elevon") or float(throws_deg().get("rudder", 0.0)) <= 0.0:
		return false
	trims.yaw = clampf(float(trims.yaw) + delta_units, -1.0, 1.0)
	_remember_out_of_trim_airframe()
	return true


## Stick commands plus trims in maximum-throw units. Reduced rates never attenuate the trim correction.
func flown_commands() -> Dictionary:
	var c := commands.duplicate()
	if rates_active() and not external_driver_enabled:
		var profile: Dictionary = aircraft.model.controls.rates.normal
		# Gamepad conditioning has already applied expo. Joysticks supply calibrated linear axes.
		var with_expo := not (radio.connected and radio.is_gamepad())
		c = Commands.shape_sticks(c, profile, with_expo)
		if rate_profile == "sport":
			# Preserve the centre response and device expo; only the roll travel limit changes.
			c.roll = Commands.expo(commands.roll, profile.aileron_expo if with_expo else 0.0)
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


## F4U-17: set or release a named throttle hold (see throttle_holds).
func set_throttle_hold(reason: String, active: bool) -> void:
	if active:
		throttle_holds[reason] = true
	else:
		throttle_holds.erase(reason)


func _inputs() -> PackedFloat64Array:
	var f := flown_commands()
	var values := PackedFloat64Array([f.roll, f.pitch, f.yaw, 0.0 if not throttle_holds.is_empty() else f.throttle])
	if gear_is_retractable():
		values.append(1.0 if _gear_requested_down else 0.0)
	if wheel_brake_input_index() >= 0:
		values.append(_wheel_brake_demand)
	if flaps_available(): values.append(_flap_requested)
	return values


func flaps_available() -> bool:
	if _fact_flaps != _FACT_UNKNOWN:
		return _fact_flaps == 1
	var available: bool = aircraft.get("ok", false) and Flaps.enabled(aircraft.model)
	if _facts_armed: _fact_flaps = int(available)
	return available


func _input_count() -> int:
	return 4 + (1 if gear_is_retractable() else 0) + (1 if wheel_brake_input_index() >= 0 else 0) + (1 if flaps_available() else 0)


func flap_input_index() -> int:
	return (_input_count() - 1) if flaps_available() else -1


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
	var speed: float = air_data(sim.state).V * sqrt(air_density(sim.state) / 1.225)
	return {available = true, actual = actual, requested = requested,
		angle_deg = actual * spec.max_angle_deg, target_deg = requested * spec.max_angle_deg,
		moving = absf(actual - requested) > 1e-10, limit_mps = spec.max_speed_mps,
		overspeed = actual > 0.001 and speed > spec.max_speed_mps}


func gear_is_retractable() -> bool:
	if _fact_gear_retractable != _FACT_UNKNOWN:
		return _fact_gear_retractable == 1
	var retractable: bool = aircraft.get("ok", false) and RetractableGear.enabled(aircraft.model.get("landing_gear", {}))
	if _facts_armed: _fact_gear_retractable = int(retractable)
	return retractable


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


## Shared demand is admitted only for explicitly installed, provenance-bearing brake hardware.
## Retraction and brake hardware are independent capabilities; the old retractable input layout stays fixed.
func wheel_brake_available() -> bool:
	if _fact_wheel_brake != _FACT_UNKNOWN:
		return _fact_wheel_brake == 1
	var available: bool = _wheel_brake_hardware()
	if _facts_armed: _fact_wheel_brake = int(available)
	return available


func _wheel_brake_hardware() -> bool:
	if typeof(aircraft.get("ok")) != TYPE_BOOL or not aircraft.ok or not aircraft.get("model") is Dictionary:
		return false
	var profile: Variant = aircraft.model.get("wheel_profile")
	var gear: Variant = aircraft.model.get("landing_gear")
	if not profile is Dictionary or typeof(profile.get("status")) != TYPE_STRING or profile.status != "applied" \
			or not gear is Dictionary or not gear.get("contacts") is Array \
			or gear.contacts.is_empty() or gear.contacts.size() > 16:
		return false
	var available := false
	for candidate: Variant in gear.contacts:
		if not candidate is Dictionary: return false
		var contact: Dictionary = candidate
		var source: Variant = contact.get("wheel_provenance")
		var torque: Variant = contact.get("brake_torque")
		if typeof(contact.get("brake_availability")) != TYPE_STRING \
				or contact.brake_availability not in ["none", "unspecified", "available"] \
				or not source is Dictionary or typeof(source.get("brake_availability")) != TYPE_STRING \
				or source.brake_availability != contact.brake_availability or not source.get("brake_torque") is Dictionary \
				or typeof(torque) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(torque)) or float(torque) < 0.0:
			return false
		var quantity: Dictionary = source.brake_torque
		if typeof(quantity.get("value")) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(quantity.value)) \
				or float(quantity.value) != float(torque) or typeof(quantity.get("unit")) != TYPE_STRING or quantity.unit != "N·m" \
				or typeof(quantity.get("kind")) != TYPE_STRING or quantity.kind not in ["manual", "measured", "borrowed", "estimated", "derived"] \
				or typeof(quantity.get("source")) != TYPE_STRING or quantity.source.strip_edges().is_empty():
			return false
		if contact.brake_availability == "available":
			if float(torque) <= 0.0: return false
			available = true
		elif float(torque) != 0.0:
			return false
	return available


func wheel_brake_input_index() -> int:
	return 5 if gear_is_retractable() else 4 if wheel_brake_available() else -1


func set_wheel_brake(amount: float) -> bool:
	if not RetractableGear.valid_fraction(amount):
		return false
	if amount == 0.0:
		_wheel_brake_demand = 0.0 # releases clear even while a menu/focus hold is active
		return true
	if not wheel_brake_available() or not physics_enabled or not input_enabled or not _flight_ready() \
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
	if liquid_fuel_is_active():
		return LiquidFlight.evaluate(s, sim.continuous, t, self).get("loads", PackedFloat64Array([NAN, NAN, NAN, NAN, NAN, NAN]))
	if turbine_is_continuous():
		var result: Dictionary = _turbine_evaluate(s, sim.continuous, t)
		return result.get("loads", PackedFloat64Array([NAN, NAN, NAN, NAN, NAN, NAN]))
	return _wash_loads(s, sim.continuous, t)


## Fixed layout: one turbine RPM, then optional wheel rim speeds. No independent aux rotor state.
func _turbine_rpm(values: PackedFloat64Array) -> float:
	if values.size() != 1 + wheel_count() + (2 if liquid_fuel_is_active() else 0) and values.size() != 1 + wheel_count():
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
func _turbine_evaluate(s: PackedFloat64Array, values: PackedFloat64Array, stage_time: float,
		properties: Dictionary = {}, source_enabled: bool = true) -> Dictionary:
	var rpm: float = _turbine_rpm(values)
	if sim.modes.size() != (2 if _weather.has_turbulence() else 1) or sim.modes[0] not in [0, 1]:
		return {}
	if not is_finite(rpm) or (not liquid_fuel_is_active() and not engine_running and rpm != 0.0):
		return {} # A hot cutoff needs AV-05b; do not invent a cold/hot rundown law here.
	var prop: Dictionary = aircraft.model.propulsion
	var a: PackedFloat64Array = sim.aux
	var air: Dictionary = air_data(s, stage_time)
	var density: float = air_density(s)
	var propulsion_air: Dictionary = Propulsion.stage_air_velocity(s, air, prop)
	if not propulsion_air.get("ok", false):
		return {}
	var inlet_air: PackedFloat64Array = propulsion_air.velocity_body
	var turbine_loads: PackedFloat64Array = Turbine.loads(inlet_air, rpm, prop, density) if source_enabled else PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	var lag: int = downwash_index()
	var out: PackedFloat64Array = Dynamics.loads_from_air(s, aircraft.model, _deflections(a), rpm,
		density, air, a[lag] if lag >= 0 and lag < a.size() else NAN, PackedFloat64Array(), _ground_up(s), turbine_loads)
	if out.size() != 6:
		return {}
	var ground: Dictionary = _ground_evaluation(s, a, values, air if gear_is_retractable() else {}, properties)
	if not ground.get("ok", false):
		return {}
	var ground_loads: PackedFloat64Array = ground.loads
	for at: int in ground_loads.size():
		out[at] += ground_loads[at]
	var rate: float = Turbine.spool_rate(rpm, Turbine.demand_rpm(propulsion_throttle(), prop) if source_enabled else 0.0, prop) if liquid_fuel_is_active() else (Turbine.spool_rate(rpm, Turbine.demand_rpm(propulsion_throttle(), prop), prop) if engine_running else 0.0)
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
	if not is_finite(rpm) or (turbine_is_continuous() and not liquid_fuel_is_active() and not engine_running and rpm != 0.0):
		return {ok = false}
	var air: Dictionary = air_data(sim.state, sim.time())
	var propulsion_air: Dictionary = Propulsion.stage_air_velocity(sim.state, air, prop)
	if not propulsion_air.get("ok", false):
		return {ok = false}
	var inlet_air: PackedFloat64Array = propulsion_air.velocity_body
	var density: float = air_density()
	var axial_speed: float = M.dot(inlet_air, prop.axis)
	var firing: bool = propulsion_power_enabled()
	if liquid_fuel_is_active():
		firing = firing and sim.continuous[_liquid_index() + 1] == 1.0
	return {ok = true, tick = sim.tick, time_s = sim.time(), rpm = rpm,
		demand_rpm = Turbine.demand_rpm(propulsion_throttle(), prop) if firing else 0.0,
		engine_running = firing, axial_airspeed_m_s = axial_speed,
		intake_air_velocity_body_m_s = inlet_air,
		mass_flow_kg_s = Turbine.mass_flow(rpm, prop, density, axial_speed) if firing else 0.0,
		gross_thrust_n = Turbine.gross_thrust(rpm, prop, density, axial_speed) if firing else 0.0,
		net_thrust_n = Turbine.thrust(rpm, axial_speed, prop, density) if firing else 0.0,
		fuel_flow_kg_s = Turbine.fuel_flow(rpm, prop) if firing else 0.0,
		fuel_mass_policy = "finite_single_store" if liquid_fuel_is_active() else "prescribed_fuel"}


func _wash_loads(s: PackedFloat64Array, transported_dv: PackedFloat64Array, stage_time: float) -> PackedFloat64Array:
	var prop: Dictionary = aircraft.model.propulsion
	var expected: int = prop.slipstream.pieces.size() if WashTransport.enabled(prop) else 0
	if transported_dv.size() != expected + wheel_count():
		return PackedFloat64Array([NAN, NAN, NAN, NAN, NAN, NAN]) # Simulation rejects before any piece indexing.
	var a: PackedFloat64Array = sim.aux
	var lag := downwash_index()
	var wash_state: PackedFloat64Array = transported_dv if wheel_count() == 0 else transported_dv.slice(0, expected)
	var air: Dictionary = air_data(s, stage_time)
	var out := Dynamics.loads_from_air(s, aircraft.model, _deflections(a), a[AUX_RPM],
		air_density(s), air, a[lag] if lag >= 0 and lag < a.size() else NAN, wash_state, _ground_up(s))
	var ground: Dictionary = _ground_evaluation(s, a, transported_dv, air if gear_is_retractable() else {})
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
		return WashTransport.stage_derivative(s, legacy_air, sim.aux[AUX_RPM], aircraft.model.propulsion,
			air_density(s), lagged)
	var expected: int = _rotor_index()
	if lagged.size() != expected + wheel_count():
		return PackedFloat64Array([NAN])
	var air: Dictionary = air_data(s, stage_time)
	var out: PackedFloat64Array = WashTransport.stage_derivative(s, air, sim.aux[AUX_RPM], aircraft.model.propulsion,
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
	var air: Dictionary = air_data(s, stage_time)
	var out: PackedFloat64Array = Dynamics.loads_from_air(s, aircraft.model, _deflections(a), a[AUX_RPM],
		air_density(s), air, a[lag] if lag >= 0 and lag < a.size() else NAN, values.slice(0, expected),
		_ground_up(s))
	var ground: Dictionary = _ground_evaluation(s, a, values, air if gear_is_retractable() else {})
	if not ground.get("ok", false):
		return {}
	var ground_loads: PackedFloat64Array = ground.loads
	for i in ground_loads.size():
		out[i] += ground_loads[i]
	var derivative: PackedFloat64Array = WashTransport.stage_derivative(s, air, a[AUX_RPM],
		aircraft.model.propulsion, air_density(s), values.slice(0, expected)) if expected > 0 else PackedFloat64Array()
	derivative.append_array(ground.derivative)
	if derivative.size() != values.size():
		return {}
	return {loads = out, derivative = derivative, rotor_momentum = rotor_momentum(a)}


## Legacy gear keeps its original contact law; a file-backed wheel profile opts into terrain and wheel-spin state.
func _ground_evaluation(s: PackedFloat64Array, aux: PackedFloat64Array, values: PackedFloat64Array, stage_air: Dictionary = {}, properties: Dictionary = {}) -> Dictionary:
	# Stage-local queries: the normalized model/layout does not change during this evaluation.
	var retractable: bool = gear_is_retractable()
	if retractable and (not _gear_aux_valid(aux) or sim.inputs.size() != _input_count() or stage_air.is_empty()):
		return {ok = false, loads = PackedFloat64Array([NAN]), derivative = PackedFloat64Array([NAN])}
	var gear: Dictionary = current_landing_gear(aux)
	var steer: float = aux[AUX_SERVO + 2]
	var brake_index: int = wheel_brake_input_index()
	var brake: float = sim.inputs[brake_index] if brake_index >= 0 else 0.0
	var anchors: PackedFloat64Array = aux.slice(AUX_ANCHORS, AUX_ANCHORS + anchor_count() * Ground.ANCHOR_STRIDE)
	var hull: PackedFloat64Array = PackedFloat64Array()
	if soft_hull_contacts:
		var glow: bool = glow_is_active()
		if glow or not properties.is_empty():
			if _hull_contact.is_empty() or (glow and values.size() < GlowFlight.SIZE):
				return {ok = false, loads = PackedFloat64Array([NAN]), derivative = PackedFloat64Array([NAN])}
			# Geometry reach is independent of fuel; avoid any new mass/contact work in free flight.
			if -s[RB.POS + 2] <= float(_hull_contact.reach):
				var sampled: Dictionary = HullContact.loads_at_properties(s, _hull_contact, properties if not properties.is_empty() else GlowFlight.properties(self, values[1], values[GlowFlight.LINE_FUEL_INDEX]))
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
	if retractable:
		var drag_delta := PackedFloat64Array()
		if stage_air.has("spatial_air_law") and aux[gear_aux_index()] > 0.0:
			drag_delta = stage_air.ambient_delta_body_at.call(aircraft.model.landing_gear.retraction.drag_center)
		hull = _add_loads(hull, RetractableGear.drag_loads(s, stage_air.v_air, aircraft.model.landing_gear, aux[gear_aux_index()], air_density(s), drag_delta))
	var wheel_total: int = wheel_count()
	if wheel_total == 0:
		return {ok = true, loads = _add_loads(Ground.loads(s, gear, steer, ground_surfaces, anchors,
			PackedFloat64Array(), brake, _lake), hull), derivative = PackedFloat64Array()}
	var first_wheel: int = wheel_index()
	if values.size() != first_wheel + wheel_total:
		return {ok = false, loads = PackedFloat64Array([NAN]), derivative = PackedFloat64Array([NAN])}
	var speeds: PackedFloat64Array = values.slice(first_wheel, first_wheel + wheel_total)
	for speed in speeds:
		if not is_finite(speed):
			return {ok = false, loads = PackedFloat64Array([NAN]), derivative = PackedFloat64Array([NAN])}
	var evaluation: Dictionary = Ground.evaluate(s, gear, steer, ground_surfaces, anchors, speeds, brake, false, _lake)
	var loads: PackedFloat64Array = evaluation.get("loads", PackedFloat64Array())
	var rates: PackedFloat64Array = evaluation.get("derivative", PackedFloat64Array())
	if (not loads.is_empty() and loads.size() != 6) or rates.size() != wheel_total:
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
	return WashTransport.stage_settled(s, air, aux[AUX_RPM], aircraft.model.propulsion, air_density(s))


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
		if battery_is_pack():
			out.append_array(_pack_initial_block(s))
		elif battery_is_dynamic():
			out.append_array(PackedFloat64Array([_battery_initial_charge(), 0.0, 0.0]))
	# Wheels begin at zero relative rim speed on both airborne and runway starts.
	for _i in wheel_count():
		out.append(0.0)
	if liquid_fuel_is_active():
		out.append_array(LiquidFlight.initial(self))
	return out


func battery_is_dynamic() -> bool:
	return aircraft.get("ok", false) and Propulsion.has_dynamic_battery(aircraft.model.propulsion)


func battery_is_pack() -> bool:
	return aircraft.get("ok", false) and Propulsion.has_pack_ecm(aircraft.model.propulsion)


## Battery slots after the shaft rpm: three for the OCV/resistance pack, 9 + 2K for pack_ecm.
func _battery_block_size() -> int:
	if battery_is_pack():
		return PackEcm.block_size(aircraft.model.propulsion.battery)
	return 3 if battery_is_dynamic() else 0


## Connection at reset: rested pack at the start position's air temperature, ESC cell detection, open limit.
func _pack_initial_block(s: PackedFloat64Array) -> PackedFloat64Array:
	var prop: Dictionary = aircraft.model.propulsion
	var made: Dictionary = PackEcm.initial_block(prop.battery, prop.motor, prop.esc.low_voltage_cutoff, _pack_ambient_k(s))
	if made.get("ok", false):
		return made.block
	var invalid := PackedFloat64Array()
	invalid.resize(PackEcm.block_size(prop.battery))
	invalid.fill(NAN)
	return invalid


func _pack_ambient_k(s: PackedFloat64Array) -> float:
	var air: Dictionary = environment_at(s.slice(0, RB.SIZE) if s.size() >= RB.SIZE else s)
	return float(air.get("temperature_k", NAN))


func electric_law() -> String:
	if battery_is_pack():
		return PACK_LAW
	return BATTERY_LAW if battery_is_dynamic() else ELECTRIC_LAW


func _rotor_index() -> int:
	if _fact_rotor_index != _FACT_UNKNOWN:
		return _fact_rotor_index
	var prop: Dictionary = aircraft.model.propulsion
	var index: int = prop.slipstream.pieces.size() if WashTransport.enabled(prop) else 0
	if _facts_armed: _fact_rotor_index = index
	return index


func _battery_initial_charge() -> float:
	var battery: Dictionary = aircraft.model.propulsion.battery
	if battery.get("kind") == "pack_ecm":
		return PackEcm.weak_initial_charge_c(battery)
	return 3600.0 * float(battery.capacity_ah) * float(battery.initial_soc)


## Charge is the sole depletion state; SOC and consumed coulombs are derived.
func _battery_values_valid(values: PackedFloat64Array, trial: bool = false) -> bool:
	var at: int = _rotor_index() + 1
	var size: int = _battery_block_size()
	if values.size() != at + size + wheel_count():
		return false
	for i: int in range(at, at + size):
		if not is_finite(values[i]):
			return false
	if battery_is_pack():
		var battery: Dictionary = aircraft.model.propulsion.battery
		var phase: float = values[at + PackEcm.phase_index(battery)]
		var cells: float = values[at + PackEcm.cells_index(battery)]
		var limit: float = values[at + PackEcm.limit_index(battery)]
		if values[at + PackEcm.temperature_index(battery)] <= 0.0 or limit < 0.0 or limit > 1.0 \
				or phase != floorf(phase) or phase < 0.0 or phase > 3.0 or cells != floorf(cells) or cells < 1.0 \
				or values[at + PackEcm.timer_index(battery)] < 0.0:
			return false
	return (trial or values[at] >= 0.0) and values[at] <= _battery_initial_charge() \
		and values[at + 1] >= 0.0 and values[at + 2] >= 0.0


func _battery_point(rpm: float, values: PackedFloat64Array, dynamics_only: bool = false,
		s: PackedFloat64Array = PackedFloat64Array(), air: Dictionary = {}) -> Dictionary:
	if not _battery_values_valid(values, true):
		return {ok = false}
	var charge: float = values[_rotor_index() + 1]
	var prop: Dictionary = aircraft.model.propulsion
	if battery_is_pack():
		# Stage-local ambient temperature and bay airflow; the ESC limit is the sampled slot inside the block.
		var at: int = _rotor_index() + 1
		var block: PackedFloat64Array = values.slice(at, at + _battery_block_size())
		var body: PackedFloat64Array = s if s.size() == RB.SIZE else sim.state
		var v_air: PackedFloat64Array = air.v_air if air.has("v_air") else air_data(body, sim.time()).v_air
		var cooling: float = float(prop.battery.cooling_airflow_fraction) * M.norm(v_air)
		return Propulsion.electric_pack_state(rpm, propulsion_throttle(), prop, propulsion_power_enabled(), block,
			_pack_ambient_k(body), cooling, charge < 0.0, dynamics_only)
	var soc: float = maxf(0.0, charge / (3600.0 * float(prop.battery.capacity_ah)))
	return Propulsion.electric_source_state(rpm, propulsion_throttle(), prop, propulsion_power_enabled(), soc, charge < 0.0, dynamics_only)


func _coupled_rpm(values: PackedFloat64Array, trial: bool = false) -> float:
	if glow_is_active():
		return values[0] if values.size()==GlowFlight.SIZE+wheel_count() and is_finite(values[0]) and (trial or values[0]>=0.0) else NAN
	var prop: Dictionary = aircraft.model.propulsion
	var count: int = prop.slipstream.pieces.size() if WashTransport.enabled(prop) else 0
	if values.size() not in [count + 1 + _battery_block_size() + wheel_count(), count + 1 + _battery_block_size() + wheel_count() + (2 if liquid_fuel_is_active() else 0)] \
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
func _coupled_response(s: PackedFloat64Array, values: PackedFloat64Array, time_s: float,
		properties: Dictionary = {}, source_enabled: bool = true, preview: Dictionary = {},
		capture_pre_reaction: bool = false) -> Dictionary:
	var prop: Dictionary = aircraft.model.propulsion
	var electric: bool = Propulsion.is_electric(prop)
	var trial_rpm: float = _coupled_rpm(values, electric)
	if not is_finite(trial_rpm):
		return {ok = false}
	var rpm: float = maxf(0.0, trial_rpm) if electric else trial_rpm
	var air: Dictionary = preview.air if preview.has("air") else air_data(s, time_s)
	var propulsion_air: Dictionary = Propulsion.stage_air_velocity(s, air, prop)
	if not propulsion_air.get("ok", false):
		return {ok = false, message = str(propulsion_air.get("message", "invalid propulsion inflow"))}
	var prop_air: PackedFloat64Array = propulsion_air.velocity_body
	var battery_point: Dictionary = {}
	var rate: float
	if battery_is_dynamic():
		battery_point = _battery_point(rpm, values, true, s, air)
		if not battery_point.get("ok", false):
			return {ok = false}
		var load_torque: float = Propulsion.prop_torque(rpm, M.dot(prop_air, Propulsion.axis(prop)), prop, air_density(s))
		rate = (float(battery_point.shaft_torque_nm) - load_torque) / float(prop.rotor_inertia) * 60.0 / TAU
	else:
		rate = Propulsion.shaft_rate(rpm, propulsion_throttle(), M.dot(prop_air, Propulsion.axis(prop)),
			prop, air_density(s), engine_charge_ratio(s), propulsion_power_enabled() and source_enabled)
	if not is_finite(rate):
		return {ok = false}
	var a: PackedFloat64Array = sim.aux
	var lag: int = downwash_index()
	var external: PackedFloat64Array
	var ground: Dictionary
	if preview.has("pre_reaction_loads"):
		external = preview.pre_reaction_loads.duplicate()
		ground = {ok = true, derivative = preview.get("wheel_derivative", PackedFloat64Array())}
	else:
		external = Dynamics.loads_from_air(s, aircraft.model, _deflections(a), rpm,
			air_density(s), air, a[lag] if lag >= 0 and lag < a.size() else NAN, values.slice(0, _rotor_index()), _ground_up(s))
		ground = _ground_evaluation(s, a, values, air if gear_is_retractable() else {}, properties)
		if not ground.get("ok", false):
			return {ok = false}
		var ground_loads: PackedFloat64Array = ground.loads
		for i: int in ground_loads.size():
			external[i] += ground_loads[i]
	var stage_inertia: PackedFloat64Array = sim.inertia if properties.is_empty() else properties.inertia
	var stage_inverse: PackedFloat64Array = RB.inertia_inverse(sim.inertia) if properties.is_empty() else properties.inverse
	if not properties.is_empty() and not preview.has("pre_reaction_loads"):
		var shift: PackedFloat64Array = M.cross(properties.cg_body_m, external.slice(0, 3))
		for axis: int in 3:
			external[3 + axis] -= shift[axis]
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
	elif not electric and not Propulsion.is_glow(prop) and Propulsion.has_rotor_dynamics(prop) \
			and not (propulsion_power_enabled() and source_enabled) \
			and rpm <= Propulsion.STOPPED_RPM and rate == 0.0:
		# The combustion shaft's scalar law already suppresses negative torque below STOPPED_RPM,
		# but coupling can still create negative relative spin from body acceleration. Resolve the
		# stopped engine's authored zero-speed friction as bounded static shaft friction here.
		var shaft_friction: PackedFloat64Array = prop.shaft.friction
		var friction_limit: float = float(shaft_friction[0])
		var w: PackedFloat64Array = s.slice(RB.RATE, RB.RATE + 3)
		var body_momentum: PackedFloat64Array = RB.inertia_mul(stage_inertia, w)
		var rotor_momentum: PackedFloat64Array = Dynamics.rotor_momentum(aircraft.model, rpm)
		var free_body: PackedFloat64Array = RB.inertia_mul(stage_inverse,
			M.sub(external.slice(3, 6), M.cross(w, M.add(body_momentum, rotor_momentum))))
		var required: float = float(prop.rotor_inertia) * M.dot(Propulsion.axis(prop), free_body)
		var drive_air: PackedFloat64Array = prop_air if air.has(Propulsion.STAGE_PROPULSION_AIR_KEY) else air.v_air
		var drive: float = -Propulsion.prop_torque(rpm, M.dot(drive_air, Propulsion.axis(prop)), prop, air_density(s))
		if not is_finite(friction_limit) or friction_limit < 0.0 or not is_finite(required) or not is_finite(drive):
			return {ok = false}
		if absf(drive - required) <= friction_limit:
			locked = true
			rate = required / float(prop.rotor_inertia) * 60.0 / TAU
		elif drive - required < -friction_limit:
			return {ok = false} # unsupported reverse breakaway; do not clamp a negative RPM stage
		else:
			# A body-driven forward breakaway uses the moving side of the authored friction curve.
			rate = (drive - friction_limit) / float(prop.rotor_inertia) * 60.0 / TAU
	var pre_reaction_loads: PackedFloat64Array = external.duplicate() if capture_pre_reaction else PackedFloat64Array()
	var response: Dictionary = RotorCoupling.response(M.v3(s[RB.RATE], s[RB.RATE + 1], s[RB.RATE + 2]),
		M.v3(external[3], external[4], external[5]), stage_inertia, stage_inverse,
		Propulsion.axis(prop), prop.rotor_inertia, rpm * TAU / 60.0, rate * prop.rotor_inertia * TAU / 60.0)
	if not response.ok:
		return response
	if locked:
		response.spin_acceleration = 0.0
		response.reaction = PackedFloat64Array([0.0, 0.0, 0.0])
	for i: int in 3:
		external[3 + i] += response.reaction[i]
	response.loads = external
	if capture_pre_reaction:
		response.pre_reaction_loads = pre_reaction_loads
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
	var air: Dictionary = result.air
	var wash: PackedFloat64Array = WashTransport.stage_derivative(s, air, _coupled_rpm(values),
		aircraft.model.propulsion, air_density(s), values.slice(0, _rotor_index())) if _rotor_index() > 0 else PackedFloat64Array()
	wash.append(result.rpm_rate)
	_append_battery_rates(wash, result)
	wash.append_array(result.get("wheel_derivative", PackedFloat64Array()))
	return wash


## One response per RK stage; both the old separate callbacks and this joint path keep the same arithmetic.
func _coupled_evaluate(s: PackedFloat64Array, values: PackedFloat64Array, time_s: float) -> Dictionary:
	var capture_context: bool = _should_capture_substep_context(s, values, time_s)
	var result: Dictionary = _coupled_response(s, values, time_s, {}, true, {}, capture_context)
	if not result.ok:
		return {}
	var extra: PackedFloat64Array = PackedFloat64Array()
	if _rotor_index() > 0:
		var air: Dictionary = result.air
		extra = WashTransport.stage_derivative(s, air, _coupled_rpm(values),
			aircraft.model.propulsion, air_density(s), values.slice(0, _rotor_index()))
	extra.append(result.rpm_rate)
	_append_battery_rates(extra, result)
	extra.append_array(result.get("wheel_derivative", PackedFloat64Array()))
	var joint: Dictionary = {loads = result.loads, derivative = extra, rotor_momentum = _coupled_rotor(s, values, time_s)}
	var stage_context: Dictionary = _substep_stage_context(result)
	if not stage_context.is_empty():
		joint.stage_context = stage_context
	return joint


func _should_capture_substep_context(body: PackedFloat64Array, values: PackedFloat64Array, at: float) -> bool:
	if at != sim.time() or not _substep_preview_supported() or body != sim.state or values != sim.continuous:
		return false
	var rotor_index: int = _rotor_index()
	return rotor_index >= 0 and rotor_index < values.size() and is_finite(values[rotor_index]) \
		and values[rotor_index] > Propulsion.STOPPED_RPM


func _substep_preview_supported() -> bool:
	if not aircraft.get("ok", false) or not shaft_is_coupled():
		return false
	var prop: Dictionary = aircraft.model.propulsion
	return not Propulsion.is_electric(prop) and not Propulsion.is_glow(prop) \
		and not Turbine.is_turbine(prop) and Propulsion.has_rotor_dynamics(prop) \
		and (liquid_fuel_is_active() or not propulsion_power_enabled())


func _substep_stage_context(response: Dictionary) -> Dictionary:
	if not response.has("pre_reaction_loads") or not response.has("air") or not response.has("wheel_derivative"):
		return {}
	return {air = response.air, pre_reaction_loads = response.pre_reaction_loads,
		wheel_derivative = response.wheel_derivative}


func _append_battery_rates(values: PackedFloat64Array, response: Dictionary) -> void:
	if response.has("battery") and response.battery.has("rates"):
		values.append_array(response.battery.rates)
	elif response.has("battery"):
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
		if result.get("ok", false) and battery_is_pack():
			result.state = _supervise_pack(result.state, dt)
	else:
		result = EventStep.advance(combined, at, dt, derivative, first,
			RB.SIZE + _rotor_index(), _project_electric_stop, "rotor_stop")
	if not result.get("ok", false):
		return PackedFloat64Array([NAN])
	return {state = result.state, events = result.events}


## BAT-11: the ESC samples its filtered pack voltage at the accepted endpoint and holds the new output limit
## for the next tick. Only the zero-rate supervisor slots change; the integrated state is untouched.
func _supervise_pack(state: PackedFloat64Array, dt: float) -> PackedFloat64Array:
	var battery: Dictionary = aircraft.model.propulsion.battery
	var profile: Dictionary = aircraft.model.propulsion.esc.low_voltage_cutoff
	var at: int = RB.SIZE + _rotor_index() + 1
	var decided: PackedFloat64Array = EscSupervisor.step(profile, state[at + PackEcm.limit_index(battery)],
		int(state[at + PackEcm.phase_index(battery)]), state[at + PackEcm.timer_index(battery)],
		int(state[at + PackEcm.cells_index(battery)]), state[at + PackEcm.sense_index(battery)], propulsion_throttle(), dt)
	var out: PackedFloat64Array = state.duplicate()
	out[at + PackEcm.limit_index(battery)] = decided[0]
	out[at + PackEcm.phase_index(battery)] = decided[1]
	out[at + PackEcm.timer_index(battery)] = decided[2]
	return out


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
		if battery_is_pack():
			_add_pack_telemetry(point, _rotor_index() + 1)
	return point


## BAT-14: pack identity and sampled ESC state for presentation; pure reads of the accepted endpoint.
func _add_pack_telemetry(point: Dictionary, at: int) -> void:
	var prop: Dictionary = aircraft.model.propulsion
	var battery: Dictionary = prop.battery
	var profile: Dictionary = prop.esc.low_voltage_cutoff
	var cells: int = int(sim.continuous[at + PackEcm.cells_index(battery)])
	point.pack_id = battery.pack_id
	point.display_name = battery.display_name
	point.chemistry = battery.chemistry
	point.series = battery.series
	point.parallel = battery.parallel
	point.rated_capacity_ah = battery.rated_capacity_ah
	point.pack_loss_j = sim.continuous[at + PackEcm.LOSS]
	point.esc_sensed_voltage_v = sim.continuous[at + PackEcm.sense_index(battery)]
	point.esc_limit = sim.continuous[at + PackEcm.limit_index(battery)]
	point.esc_detected_cells = cells
	point.esc_cutoff_voltage_v = EscSupervisor.cutoff_voltage(profile, cells)
	point.esc_state = EscSupervisor.state_name(profile, int(sim.continuous[at + PackEcm.phase_index(battery)]))


## Aerodynamic-convention deflections from the servos' actual positions. The servos change once per tick (in
## _pre_step), while the loads run five times per tick (H2), so the last result is reused while the positions match.
## Callers only read the dictionary.
func _deflections(a: PackedFloat64Array) -> Dictionary:
	var flap: float = a[flap_aux_index()] if flaps_available() and _flap_aux_valid(a) else 0.0
	if _deflection_key.size() == 4 and _deflection_key[3] == flap and _deflection_key[0] == a[AUX_SERVO] and _deflection_key[1] == a[AUX_SERVO + 1] \
			and _deflection_key[2] == a[AUX_SERVO + 2]:
		return _deflection_cache
	var surfaces: Dictionary
	if OutOfTrim.is_zero(_airframe_offset):
		surfaces = _surface_angles_from_aux(a)
	else:
		# D6-TRIM-01: the air sees the airframe's rigging offsets on top of the servo positions.
		surfaces = Commands.surface_deflections_deg({roll = a[AUX_SERVO] + _airframe_offset[0],
			pitch = a[AUX_SERVO + 1] + _airframe_offset[1], yaw = a[AUX_SERVO + 2] + _airframe_offset[2]}, throws_deg())
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
## SF-05: contact refinement plus a bounded RK domain refinement for the engine-off combustion cutoff.
func _substeps(body: PackedFloat64Array, continuous: PackedFloat64Array, at: float) -> int:
	return _substeps_with_context(body, continuous, at, {})


func _substeps_joint(body: PackedFloat64Array, continuous: PackedFloat64Array, at: float,
		current_joint: Dictionary) -> int:
	var stage_context: Variant = current_joint.get("stage_context", {})
	if typeof(stage_context) != TYPE_DICTIONARY or not _substep_stage_context_is_valid(stage_context):
		stage_context = {}
	return _substeps_with_context(body, continuous, at, stage_context)


func _substep_stage_context_is_valid(stage_context: Dictionary) -> bool:
	if not stage_context.has_all(["air", "pre_reaction_loads", "wheel_derivative"]) \
			or typeof(stage_context.air) != TYPE_DICTIONARY:
		return false
	var air_velocity: Variant = stage_context.air.get("v_air", PackedFloat64Array())
	var external: Variant = stage_context.pre_reaction_loads
	var wheel_derivative: Variant = stage_context.wheel_derivative
	if not air_velocity is PackedFloat64Array or air_velocity.size() != 3 \
			or not external is PackedFloat64Array or external.size() != 6 \
			or not wheel_derivative is PackedFloat64Array:
		return false
	for value: float in air_velocity:
		if not is_finite(value):
			return false
	for value: float in external:
		if not is_finite(value):
			return false
	for value: float in wheel_derivative:
		if not is_finite(value):
			return false
	return true


func _substeps_with_context(body: PackedFloat64Array, continuous: PackedFloat64Array, at: float,
		preview: Dictionary) -> int:
	var count: int = 1
	if aircraft.get("ok", false) and aircraft.model.get("landing_gear") is Dictionary:
		count = Ground.substeps(body, current_landing_gear(), sim.dt(), ground_surfaces)
	# The inherited combustion law changes to zero rate at STOPPED_RPM. Near that boundary, one full RK4
	# half-stage can fall below zero even though the physical interval should advance only into the static branch.
	# Refine that tick so each intermediate evaluation stays in-domain. This changes integration resolution only:
	# it introduces no stop impulse, new friction law or projected endpoint. The margin accommodates stage-rate drift.
	var source_may_stop_this_tick: bool = not propulsion_power_enabled() or liquid_fuel_is_active()
	if shaft_is_coupled() and not Propulsion.is_electric(aircraft.model.propulsion) \
			and not Propulsion.is_glow(aircraft.model.propulsion) \
			and Propulsion.has_rotor_dynamics(aircraft.model.propulsion) \
			and source_may_stop_this_tick and continuous.size() > _rotor_index():
		var rpm: float = continuous[_rotor_index()]
		if is_finite(rpm) and rpm > Propulsion.STOPPED_RPM:
			var shaft_values: PackedFloat64Array = continuous.slice(0, _liquid_index()) if liquid_fuel_is_active() \
				else continuous.duplicate()
			var properties: Dictionary = LiquidFlight.properties(self, continuous, true) if liquid_fuel_is_active() else {}
			# Finite-fuel exhaust can turn off the source partway through this same tick. Estimate the
			# off-source domain rate even while its current latch is on so the event locator's remainder is safe.
			var response: Dictionary = _coupled_response(body, shaft_values, at, properties, false, preview)
			if not response.get("ok", false):
				# A bad preview cannot justify an unrefined step. Return an over-cap request so the
				# kernel rejects the tick without committing a potentially malformed RK stage.
				count = maxi(count, Sim.MAX_SUBSTEPS + 1)
			else:
				var rpm_rate: float = float(response.get("rpm_rate", NAN))
				if not is_finite(rpm_rate):
					count = maxi(count, Sim.MAX_SUBSTEPS + 1)
				elif rpm_rate < 0.0:
					var stage_drop: float = sim.dt() * -rpm_rate * 1.25
					var required_steps: float = stage_drop / rpm
					if not is_finite(stage_drop) or not is_finite(required_steps) \
							or required_steps > Sim.MAX_SUBSTEPS:
						count = maxi(count, Sim.MAX_SUBSTEPS + 1)
					else:
						var safe_steps: int = maxi(1, ceili(required_steps))
						count = maxi(count, safe_steps)
	return count


## NK-2a: capability and layout answers that depend only on the committed aircraft data, memoized for one
## kernel tick. The kernel's pre_tick arms the memo; the accepted (stepped) or rejected (faulted) tick drops
## it, so data replaced or edited between ticks (load, Workshop, tests) is always read afresh. Direct
## `_pre_step` calls and solves outside the kernel step never arm it.
const _FACT_UNKNOWN := -2
var _facts_armed := false
var _fact_glow := _FACT_UNKNOWN
var _fact_gear_retractable := _FACT_UNKNOWN
var _fact_wheel_brake := _FACT_UNKNOWN
var _fact_flaps := _FACT_UNKNOWN
var _fact_wheel_count := _FACT_UNKNOWN
var _fact_anchor_count := _FACT_UNKNOWN
var _fact_downwash_index := _FACT_UNKNOWN
var _fact_rotor_index := _FACT_UNKNOWN


func _kernel_pre_step(aux: PackedFloat64Array, inputs: PackedFloat64Array, dt: float) -> PackedFloat64Array:
	_drop_tick_facts()
	_facts_armed = true
	if _native_stage != null and not _native_stage.configuration_matches(self):
		stage_backend_error = "native prepared configuration changed outside an accepted boundary; reset required"
		return PackedFloat64Array() # kernel rejects before any native stage can use stale coefficients
	var next := _pre_step(aux, inputs, dt)
	if _native_stage != null and next.size() == aux.size():
		_native_stage.tick_context(self, next, inputs)
	return next


func _drop_tick_facts() -> void:
	_facts_armed = false
	_fact_glow = _FACT_UNKNOWN
	_fact_gear_retractable = _FACT_UNKNOWN
	_fact_wheel_brake = _FACT_UNKNOWN
	_fact_flaps = _FACT_UNKNOWN
	_fact_wheel_count = _FACT_UNKNOWN
	_fact_anchor_count = _FACT_UNKNOWN
	_fact_downwash_index = _FACT_UNKNOWN
	_fact_rotor_index = _FACT_UNKNOWN


func _pre_step(aux: PackedFloat64Array, inputs: PackedFloat64Array, dt: float) -> PackedFloat64Array:
	if _weather_pending_reset or _shaft_pending_reset:
		return PackedFloat64Array([NAN]) # configure→reset boundary cannot advance an old layout/RNG
	if gear_is_retractable() and (not _gear_aux_valid(aux) or inputs.size() != _input_count() \
			or inputs[4] not in [0.0, 1.0] or not RetractableGear.valid_fraction(inputs[5])):
		return PackedFloat64Array([NAN])
	if not gear_is_retractable() and wheel_brake_input_index() >= 0 and (inputs.size() != _input_count() \
			or not RetractableGear.valid_fraction(inputs[wheel_brake_input_index()])):
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
		# G2 first slice (P51-06): keep the sampled legacy inflow arithmetic unless an experimental stage Air
		# supplies a complete point velocity. That override already includes body rotation and ambient spatial delta.
		var s: PackedFloat64Array = sim.state
		var stage_air: Dictionary = air_data(s, sim.time())
		var u: float
		var has_explicit_stage_air: bool = stage_air.has(Propulsion.STAGE_PROPULSION_AIR_KEY)
		if has_explicit_stage_air:
			var propulsion_air: Dictionary = Propulsion.stage_air_velocity(s, stage_air, prop)
			if not propulsion_air.get("ok", false):
				return PackedFloat64Array([NAN])
			u = M.dot(propulsion_air.velocity_body, Propulsion.axis(prop))
		else:
			u = M.dot(M.v3(s[RB.VEL], s[RB.VEL + 1], s[RB.VEL + 2]), Propulsion.axis(prop))
		if not has_explicit_stage_air and not weather_is_calm():
			u = M.dot(stage_air.v_air, Propulsion.axis(prop))
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
		var wheel_speeds: PackedFloat64Array = sim.continuous.slice(wheel_index(), wheel_index() + wheel_count()) if wheel_count() > 0 else PackedFloat64Array()
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
	if _fact_downwash_index != _FACT_UNKNOWN:
		return _fact_downwash_index
	# The lag feeds only the local (strip) model's tail: none without an envelope (a pure-oracle model).
	var index: int = -1
	if aircraft.get("ok", false) and not aircraft.model.get("envelope", {}).is_empty() \
			and aircraft.model.get("surfaces", {}).get("horizontal", {}).has("downwash_lag_length"):
		index = AUX_ANCHORS + anchor_count() * Ground.ANCHOR_STRIDE
	if _facts_armed: _fact_downwash_index = index
	return index


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
	if _reject_reset_publication_reentry(): return false
	var result := try_runway_start(north, east, heading)
	if result.ok:
		return true
	# Historical helper explicitly commits an airborne fallback after the refused
	# runway transaction. Its outcome and trace metadata retain the rejection reason.
	var fallback := _reset_airborne_candidate()
	start_error = str(result.message)
	runway_start_outcome.fallback = "trimmed_airborne" if fallback.get("committed", false) else "failed"
	if fallback.get("status", "") == "observer_fault":
		runway_start_outcome.committed = true
		runway_start_outcome.ready = false
		runway_start_outcome.fallback_status = "observer_fault"
		runway_start_outcome.observer_fault = str(fallback.message)
		start_error += "; airborne fallback observer fault: " + str(fallback.message)
	if fallback.get("committed", false):
		_capture_launch("airborne", "airborne_fallback", ground_field_id, start_error)
		if _statistics_reload_depth == 0 and calibration == null:
			_statistics_committed("restart")
	return false


## E3b1: wheels with a stiction anchor (0 when the gear has no breakaway_factor).
func anchor_count() -> int:
	if _fact_anchor_count != _FACT_UNKNOWN:
		return _fact_anchor_count
	var gear: Dictionary = aircraft.get("model", {}).get("landing_gear", {}) if aircraft.get("ok", false) else {}
	var count: int = gear.contacts.size() if gear.has("breakaway_factor") else 0
	if _facts_armed: _fact_anchor_count = count
	return count


## Number of rotating wheels enabled by a validated file-backed profile (zero for in-memory/legacy gear and Vantage Jet).
func wheel_count() -> int:
	if _fact_wheel_count != _FACT_UNKNOWN:
		return _fact_wheel_count
	var count: int = _model_wheel_count(aircraft.get("model", {})) if aircraft.get("ok", false) else 0
	if _facts_armed: _fact_wheel_count = count
	return count


## First continuous-state index holding wheel rim speeds, in landing_gear.contacts order.
func wheel_index() -> int:
	if not aircraft.get("ok", false):
		return 0
	if glow_is_active(): return GlowFlight.SIZE
	var index: int = _rotor_index()
	if shaft_is_coupled():
		index += 1 + _battery_block_size()
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
		launch_trim_throttle = _launch_metadata.get("launch_trim_throttle", "unknown"),
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
		wing_polar_model = ("tabulated-wing-v1 (experimental finite-wing strip reference)" + ("; spanwise stall progression g = %s" % model.envelope.wing_polar.spanwise_progression if model.envelope.wing_polar.has("spanwise_progression") else "")) if model.get("envelope", {}).has("wing_polar") else "legacy attached-to-flat-plate blend",
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
	if finite_fuel_is_active():
		metadata.mass_contact_law = MASS_CONTACT_LAW
		metadata.mass_reference = "mass_kg and inertia_kgm2 are initial wet values; live mass/CG/inertia derive from continuous fuel at fixed initial datum"
	if soft_hull_contacts:
		metadata.hull_contact_model = HullContact.law()
		if model.get("intended_hull_support") is Dictionary:
			metadata.intended_hull_support_model = IntendedHullSupport.LAW
			metadata.intended_hull_support_identity = str(model.intended_hull_support.identity)
			metadata.intended_hull_support_scope = "legacy-flat-solid-only-v1"
		if aircraft.model.has("crash_tolerance"):
			# X8-08: the aircraft's own terminal thresholds replace the law's shared ones.
			metadata.hull_contact_tolerance = aircraft.model.crash_tolerance.duplicate()
		if not _lake.is_empty():
			metadata.hull_lake_normal_model = HullContact.LAKE_NORMAL_LAW
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
		metadata.wheel_rolling_law = Ground.ROLLING_LAW
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
		metadata.propeller_inflow_law = Propulsion.ELECTRIC_INFLOW_LAW
		metadata.electric_configuration = JSON.stringify({motor = prop.motor, battery = prop.battery, esc = prop.esc}, "", true, true)
		metadata.electric_sample_timing = "accepted endpoint; current tick input and source-enabled mode"
		metadata.electric_stop = "first downward zero crossing; bounded RK4 localization; static bearing friction; no reverse"
		metadata.engine_atmosphere = "electric motor constants independent of density; propeller loads use stage density" if _weather.has_vertical_atmosphere() else "electric motor constants independent of density; propeller loads use field density"
		if battery_is_pack():
			metadata.continuous_layout = PACK_LAYOUT
			metadata.battery_model = PACK_MODEL
			metadata.battery_pack = JSON.stringify({id = prop.battery.pack_id, sha256 = prop.battery.pack_sha256,
				template = prop.battery.template_id, template_sha256 = prop.battery.template_sha256,
				series = prop.battery.series, parallel = prop.battery.parallel, branches = prop.battery.branches}, "", true, true)
			metadata.battery_exhaustion = "weak-cell remaining charge zero at the template data floor; all pack loads disconnected; ESC LVC acts earlier"
			metadata.battery_charge = "weak-cell coulombs integrated; average-cell SOC derived from consumed charge; terminal energy and pack loss integrated"
			metadata.battery_auxiliary = "prescribed pack-side current; no receiver/servo brownout model"
			metadata.battery_esc = "sampled at accepted endpoints from the filtered pack voltage; output limit held for the next tick"
		elif battery_is_dynamic():
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
		metadata.metadata_schema="openrc-flight-meta v10"
		metadata.propulsion_model=GlowFlight.LAW
		metadata.glow_identity=JSON.stringify(prop.glow.identity,"",true,true)
		metadata.glow_fuel_tank_id = str(prop.glow.fuel_tank.id)
		metadata.glow_feed_line_inventory_id = str(prop.glow.get("feed_line", {}).get("liquid_inventory_id", ""))
		metadata.glow_fuel_registry_sha256 = str(model.fuel_system.registry_sha256)
		metadata.glow_family=prop.glow.profile.family
		metadata.continuous_layout=GlowFlight.CONTINUOUS_LAYOUT
		if wheel_count() > 0: # GP-06a: rim speeds follow the glow slots (wheel_index() == GlowFlight.SIZE)
			metadata.continuous_layout += "; wheel rim speeds in m/s, landing-gear contact order, appended continuous tail"
		metadata.fuel_mass_policy="finite tank; uniform co-moving efflux; variable mass/CG/inertia; body datum remains initial wet CG"
		if not _fuel_start_fill_known:
			metadata.fuel_start_fill_known = false
		elif fuel_start_fill != 1.0:
			metadata.fuel_start_fill=fuel_start_fill # FUEL-07: start fill of the authored full tank
		metadata.glow_recording_start=JSON.stringify(glow_state(),"",true,true)
	if liquid_fuel_is_active():
		metadata.liquid_fuel_model = LiquidFlight.LAW
		metadata.liquid_fuel_schema = LiquidFuel.FORMAT
		metadata.continuous_layout += "; " + LiquidFlight.LAYOUT
		metadata.fuel_mass_policy = "finite single store; co-moving efflux; fixed authored reference datum"
		metadata.fuel_consumption_law = str(prop.liquid_fuel.law)
		metadata.fuel_store_id = str(prop.liquid_fuel.tank_id)
		metadata.fuel_capacity_kg = float(prop.liquid_fuel.capacity_kg)
		metadata.fuel_unusable_kg = float(prop.liquid_fuel.unusable_kg)
		metadata.fuel_state_index = _liquid_index()
		metadata.fuel_start_fill_known = _fuel_start_fill_known
		metadata.fuel_start_fill = fuel_start_fill
		if turbine:
			metadata.fuel_cutoff_law = LiquidFlight.CUTOFF_LAW
	if not workshop_identity.is_empty():
		metadata.workshop = workshop_identity.duplicate(true)
	if not workshop_presentation_identity.is_empty():
		metadata.workshop_presentation = workshop_presentation_identity.duplicate(true)
		metadata.aircraft_input_hash_convention = "sha256 of exact frozen Workshop aircraft bytes"
	if _failures != null:
		metadata.failure_plan = JSON.stringify(_failures.plan(), "", true, true)
		metadata.failure_recording_start = JSON.stringify(_failures.snapshot(), "", true, true)
		metadata.failure_inputs = "pilot demand before failures; actual servo positions in aux; throttle follows resolved incident"
	if out_of_trim_active() or not OutOfTrim.is_zero(_airframe_offset):
		metadata.airframe_trim_offset = JSON.stringify(Array(_airframe_offset), "", true, true)
		metadata.airframe_trim_law = "D6-TRIM-01 rigging offsets in maximum-throw units [roll, pitch, yaw], added to the actual servo positions for the aerodynamics only; inputs and aux exclude them"
		if out_of_trim_active():
			metadata.out_of_trim = JSON.stringify({mode = _out_of_trim.config.mode,
				intensity_percent = _out_of_trim.config.intensity_percent, unit = Array(_out_of_trim.unit)}, "", true, true)
	if gear_is_retractable():
		metadata.metadata_schema = "openrc-flight-meta v8"
		metadata.gear_law = RetractableGear.LAW
		metadata.gear_trace_schema = "openrc-gear-trace v1"
		metadata.gear_aux_index = gear_aux_index()
		metadata.recording_start_gear = JSON.stringify(Array(sim.aux.slice(gear_aux_index(), gear_aux_index() + GEAR_AUX_SIZE)), "", true, true)
		metadata.input_layout = JSON.stringify(["roll", "pitch", "yaw", "throttle", "gear_down", "wheel_brake"])
		metadata.ground = "retractable tricycle; downlock point contacts; rudder nose steering; main wheel brakes; weight-on-wheels retraction interlock"
	if not gear_is_retractable() and wheel_brake_available():
		metadata.fixed_brake_input_law = FIXED_BRAKE_INPUT_LAW
		metadata.wheel_brake_input_index = wheel_brake_input_index()
		metadata.input_layout = JSON.stringify(["roll", "pitch", "yaw", "throttle", "wheel_brake"])
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
		elif wheel_brake_available(): layout.append("wheel_brake")
		layout.append("flaps")
		metadata.input_layout = JSON.stringify(layout)
	metadata.runway_start_status = str(runway_start_outcome.get("status", "not_attempted"))
	metadata.runway_fallback = str(runway_start_outcome.get("fallback", "none"))
	metadata.aero_loads_law = Aero.LOADS_LAW if not model.get("envelope", {}).is_empty() else "global-derivatives-v1"
	metadata.wake_state_unit = Aero.WAKE_STATE_UNIT if downwash_index() >= 0 else "none"
	if turbine:
		metadata.turbine_loads_law = Turbine.LOADS_LAW
	if _weather.is_spatial():
		metadata.spatial_weather_schema = SPATIAL_RECEIPT_FORMAT
		metadata.spatial_weather_receipt = JSON.stringify(_spatial_weather_receipt(_weather), "", true, true)
		metadata.weather_model = "flat-site-spatial-wind-v1"
		metadata.weather_timing = "datum wind/TAS at row position/time; loads_* at previous body position and k1 time; all surface/prop points use that stage time"
		metadata.spatial_aero_model = Aero.SPATIAL_CONTINUATION_LAW
		metadata.spatial_aero_limits = "continuous local section surrogate; held reference wake; datum body residuals; no dynamic stall or measured RC qualification"
	# Preserve frozen reference trace bytes; absence denotes the historical reference backend.
	var backend := stage_backend_identity()
	if backend.backend == NativeStage.BACKEND_NATIVE:
		metadata.stage_backend = backend
	return metadata


## Physics replay boundary, deliberately downstream of live input conditioning and menus.
## Owner configuration is fingerprinted in exact Variant encoding; derived caches are excluded.
## JSON is a bounded carrier of native Variant bytes, preserving float64 and int64/RNG bits.
func checkpoint_json() -> String:
	return CheckpointJson.encode(checkpoint())


func restore_checkpoint_json(text: String) -> bool:
	var decoded: Dictionary = CheckpointJson.decode(text)
	return decoded.get("ok", false) and restore_checkpoint(decoded.snapshot)


func checkpoint() -> Dictionary:
	if not _flight_ready():
		return {}
	if _native_stage != null and not _native_stage.configuration_matches(self):
		return {}
	if gear_is_retractable() and (not _gear_aux_valid(sim.aux) or sim.inputs.size() != _input_count() \
			or sim.inputs[4] not in [0.0, 1.0] or not RetractableGear.valid_fraction(sim.inputs[5])):
		return {}
	if not gear_is_retractable() and wheel_brake_input_index() >= 0 and (sim.inputs.size() != _input_count() \
			or not RetractableGear.valid_fraction(sim.inputs[wheel_brake_input_index()])):
		return {}
	if flaps_available() and (not _flap_aux_valid(sim.aux) or sim.inputs.size() != _input_count() \
			or not RetractableGear.valid_fraction(sim.inputs[flap_input_index()])):
		return {}
	var snapshot: Dictionary = sim.checkpoint()
	if snapshot.is_empty() or snapshot.modes.size() != (2 if _weather.has_turbulence() else 1) or snapshot.modes[0] < 0 or snapshot.modes[0] > 1:
		return {}
	if turbine_is_continuous() and (not is_finite(_turbine_rpm(sim.continuous)) \
			or (not liquid_fuel_is_active() and not engine_running and sim.continuous[0] != 0.0)):
		return {}
	if liquid_fuel_is_active() and not LiquidFlight.valid(self, sim.continuous):
		return {}
	var boundary: Dictionary = {format = "openrc-flight-checkpoint v1", configuration = _checkpoint_configuration(), simulation = snapshot}
	if finite_fuel_is_active():
		boundary.fuel_session = {format = FUEL_SESSION_FORMAT, start_fill = fuel_start_fill,
			selection_known = _fuel_start_fill_known}
	if not aircraft.model.get("envelope", {}).is_empty():
		boundary.aero_loads_law = Aero.LOADS_LAW
		boundary.wake_state_unit = Aero.WAKE_STATE_UNIT
	if Turbine.is_turbine(aircraft.model.propulsion):
		boundary.turbine_loads_law = Turbine.LOADS_LAW
	if gear_is_retractable():
		boundary.gear_law = RetractableGear.LAW
		boundary.gear_aux_index = gear_aux_index()
	if not gear_is_retractable() and wheel_brake_available():
		boundary.fixed_brake_input_law = FIXED_BRAKE_INPUT_LAW
		boundary.wheel_brake_input_index = wheel_brake_input_index()
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
		boundary.weather_config = WeatherConfig.defaults() if weather_is_calm() and atmosphere_is_reference() else weather_configuration()
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
	if liquid_fuel_is_active():
		boundary.liquid_physics_format = boundary.format
		boundary.format = "openrc-flight-checkpoint v11"
		boundary.liquid_law = LiquidFlight.LAW
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
	if _weather.is_spatial():
		boundary.spatial_physics_format = boundary.format
		boundary.format = SPATIAL_CHECKPOINT_FORMAT
		boundary.spatial_weather_receipt = _spatial_weather_receipt(_weather)
	if not OutOfTrim.is_zero(_airframe_offset):
		boundary.airframe_physics_format = boundary.format
		boundary.format = OUT_OF_TRIM_CHECKPOINT_FORMAT
		boundary.airframe_trim_offset = _airframe_offset.duplicate()
	var backend := stage_backend_identity()
	if backend.backend == NativeStage.BACKEND_NATIVE:
		boundary.stage_physics_format = boundary.format
		boundary.format = NATIVE_CHECKPOINT_FORMAT
		boundary.stage_backend = backend
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
	var backend := stage_backend_identity()
	if backend.backend == NativeStage.BACKEND_NATIVE:
		parts.append(backend)
	if not aircraft.model.get("envelope", {}).is_empty():
		parts.append(Aero.LOADS_LAW + "; " + Aero.WAKE_STATE_UNIT)
	if Turbine.is_turbine(aircraft.model.propulsion):
		parts.append(Turbine.LOADS_LAW)
	if gear_is_retractable():
		parts.append(RetractableGear.LAW + "; inputs=6; aux=extension,accepted_down_target; airborne_up,runway_down")
	if not gear_is_retractable() and wheel_brake_available():
		parts.append(FIXED_BRAKE_INPUT_LAW + "; input=4; shared wheel brake demand")
	if flaps_available():
		parts.append(Flaps.LAW + "; appended normalized demand and sampled actuator; restart_up")
	if wheel_count() > 0:
		parts.append("wheel-state-layout:" + wheel_state_layout())
		parts.append(Ground.ROLLING_LAW)
	if not field.is_calm() or field.has_atmosphere():
		parts.append(field.configuration())
	if field.is_spatial():
		parts.append(_spatial_weather_receipt(field))
	if field.has_vertical_atmosphere():
		parts.append(field.atmosphere_law() + "; datum=field_elevation-minus-NED-down; sample=stage-body-datum")
	if shaft_is_coupled():
		parts.append(PACK_LAYOUT if battery_is_pack() else BATTERY_LAYOUT if battery_is_dynamic() else "shaft-relative-rk4-locked-inertia-reaction-v1; wash-first,rpm-last")
	if Propulsion.is_electric(aircraft.model.propulsion):
		parts.append(electric_law())
		parts.append(Propulsion.ELECTRIC_INFLOW_LAW)
	if turbine_is_continuous():
		parts.append(Turbine.CONTINUOUS_LAW + "; " + Turbine.CONTINUOUS_LAYOUT)
	if glow_is_active():
		parts.append(GlowFlight.LAW)
		parts.append(MASS_CONTACT_LAW)
	if liquid_fuel_is_active():
		parts.append(LiquidFlight.LAW + "; " + LiquidFlight.LAYOUT)
		parts.append(MASS_CONTACT_LAW)
		if Turbine.is_turbine(aircraft.model.propulsion):
			parts.append(LiquidFlight.CUTOFF_LAW)
	if soft_hull_contacts:
		# E3d1: soft hull contacts change the dynamics near the ground; legacy hashes stay unchanged.
		parts.append(HullContact.law())
		if not _lake.is_empty():
			parts.append(HullContact.LAKE_NORMAL_LAW)
		# GP-07c: and their friction follows the field's airframe surfaces.
		parts.append(airframe_surfaces)
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
	if _reject_reset_publication_reentry(): return false
	var transaction := _begin_start_transaction()
	var restored := false
	if not _reset_transaction_reentry:
		restored = _restore_checkpoint_impl(candidate, transaction)
	if not restored:
		_refuse_start_transaction(transaction, "checkpoint restore refused")
		return false
	_end_start_transaction(transaction)
	if not sim.reset_observer_fault.is_empty():
		start_error = sim.reset_observer_fault
		pause_reason = "simulation fault: " + start_error
		_launch_metadata.launch_error = start_error
	# This existing receipt enters the service's noncredit replay branch; it
	# does not credit a restarted flight or restored flight time.
	_statistics_committed("checkpoint_restore")
	return true


func _restore_checkpoint_impl(candidate: Dictionary, transaction: Dictionary) -> bool:
	if typeof(candidate.get("format")) != TYPE_STRING: return false
	var recorded_backend := NativeStage.reference_identity()
	if candidate.format == NATIVE_CHECKPOINT_FORMAT:
		if not candidate.get("stage_backend") is Dictionary \
				or candidate.stage_backend.get("backend") != NativeStage.BACKEND_NATIVE \
				or typeof(candidate.get("stage_physics_format")) != TYPE_STRING \
				or candidate.stage_physics_format == NATIVE_CHECKPOINT_FORMAT:
			return false
		recorded_backend = candidate.stage_backend.duplicate(true)
		candidate = candidate.duplicate(true)
		candidate.format = candidate.stage_physics_format
		candidate.erase("stage_physics_format")
		candidate.erase("stage_backend")
	elif candidate.has("stage_backend") or candidate.has("stage_physics_format"):
		return false
	if recorded_backend != stage_backend_identity():
		return false
	# D6-TRIM-01: the outermost layer names the airframe the recorded flight flew; without it the airframe is true.
	var restored_airframe_offset := PackedFloat64Array([0.0, 0.0, 0.0])
	if candidate.get("format") == OUT_OF_TRIM_CHECKPOINT_FORMAT:
		if typeof(candidate.get("airframe_physics_format")) != TYPE_STRING \
				or candidate.airframe_physics_format == OUT_OF_TRIM_CHECKPOINT_FORMAT \
				or not OutOfTrim.valid_offsets(candidate.get("airframe_trim_offset")):
			return false
		restored_airframe_offset = candidate.airframe_trim_offset.duplicate()
		candidate = candidate.duplicate(true)
		candidate.format = candidate.airframe_physics_format
		candidate.erase("airframe_physics_format")
		candidate.erase("airframe_trim_offset")
	elif candidate.has("airframe_trim_offset") or candidate.has("airframe_physics_format"):
		return false
	var spatial_boundary: bool = candidate.get("format") == SPATIAL_CHECKPOINT_FORMAT
	if spatial_boundary:
		var spatial_built := WeatherField.build(candidate.get("weather_config"))
		if not spatial_built.ok or not spatial_built.field.is_spatial() \
				or not spatial_receipt_matches(candidate.get("spatial_weather_receipt"), _spatial_weather_receipt(spatial_built.field)) \
				or candidate.get("spatial_physics_format") not in ["openrc-flight-checkpoint v2", "openrc-flight-checkpoint v3", "openrc-flight-checkpoint v4", "openrc-flight-checkpoint v5", "openrc-flight-checkpoint v6", "openrc-flight-checkpoint v7", "openrc-flight-checkpoint v8", "openrc-flight-checkpoint v9", "openrc-flight-checkpoint v11", FAILURE_CHECKPOINT_FORMAT]:
			return false
		candidate = candidate.duplicate(true)
		candidate.format = candidate.spatial_physics_format
		candidate.erase("spatial_physics_format")
		candidate.erase("spatial_weather_receipt")
	elif candidate.has("spatial_weather_receipt") or candidate.has("spatial_physics_format"):
		return false
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
	# Liquid v11 wraps the existing propulsion checkpoint, including a scenery v7 wrapper.
	var liquid_format: String = str(candidate.get("physics_format", candidate.get("format", "")))
	if liquid_fuel_is_active() != (liquid_format == "openrc-flight-checkpoint v11"):
		return false
	if liquid_fuel_is_active():
		if candidate.get("liquid_law") != LiquidFlight.LAW or candidate.get("liquid_physics_format") not in ["openrc-flight-checkpoint v4", "openrc-flight-checkpoint v8"]:
			return false
		candidate = candidate.duplicate(true)
		if candidate.format == "openrc-flight-checkpoint v7":
			candidate.physics_format = candidate.liquid_physics_format
		else:
			candidate.format = candidate.liquid_physics_format
		candidate.erase("liquid_physics_format")
		candidate.erase("liquid_law")
	elif candidate.has("liquid_physics_format") or candidate.has("liquid_law"):
		return false
	if not _has_valid_start() or typeof(candidate.get("format")) != TYPE_STRING \
			or candidate.format not in ["openrc-flight-checkpoint v1", "openrc-flight-checkpoint v2", "openrc-flight-checkpoint v3", "openrc-flight-checkpoint v4", "openrc-flight-checkpoint v5", "openrc-flight-checkpoint v6", "openrc-flight-checkpoint v7", "openrc-flight-checkpoint v8", "openrc-flight-checkpoint v9"] or typeof(candidate.get("configuration")) != TYPE_STRING \
			or not candidate.get("simulation") is Dictionary:
		return false
	var snapshot: Dictionary = candidate.simulation
	# The integrated fuel state proves exact continuation; launch selection separately owns reset/provenance.
	# Legacy boundaries retain the destination reset setting and explicitly mark its source selection unknown.
	var restored_fuel_fill: float = fuel_start_fill
	var restored_fuel_fill_known: bool = false
	if candidate.has("fuel_session"):
		var fuel_session: Variant = candidate.fuel_session
		if not finite_fuel_is_active() or not fuel_session is Dictionary or fuel_session.size() != 3 \
				or fuel_session.get("format") != FUEL_SESSION_FORMAT \
				or typeof(fuel_session.get("start_fill")) not in [TYPE_FLOAT, TYPE_INT] \
				or typeof(fuel_session.get("selection_known")) != TYPE_BOOL:
			return false
		var serialized_fuel_fill: float = float(fuel_session.start_fill)
		if not is_finite(serialized_fuel_fill) or serialized_fuel_fill <= 0.0 or serialized_fuel_fill > 1.0:
			return false
		if liquid_fuel_is_active() and serialized_fuel_fill * float(aircraft.model.propulsion.liquid_fuel.capacity_kg) <= float(aircraft.model.propulsion.liquid_fuel.unusable_kg):
			return false
		if glow_is_active() and serialized_fuel_fill * float(aircraft.model.propulsion.glow.capacity_fuel_kg) <= float(aircraft.model.propulsion.glow.unusable_fuel_kg):
			return false
		restored_fuel_fill_known = bool(fuel_session.selection_known)
		if restored_fuel_fill_known:
			restored_fuel_fill = serialized_fuel_fill
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
	if not gear_is_retractable() and wheel_brake_available():
		if typeof(candidate.get("fixed_brake_input_law")) != TYPE_STRING or candidate.fixed_brake_input_law != FIXED_BRAKE_INPUT_LAW \
				or typeof(candidate.get("wheel_brake_input_index")) != TYPE_INT or candidate.wheel_brake_input_index != 4 \
				or not snapshot.get("inputs") is PackedFloat64Array or snapshot.inputs.size() != _input_count() \
				or not RetractableGear.valid_fraction(snapshot.inputs[4]):
			return false
	elif candidate.has("fixed_brake_input_law") or candidate.has("wheel_brake_input_index"):
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
	if finite_fuel_is_active():
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
	if restored_weather.is_spatial() != spatial_boundary:
		return false # spatial forcing must never hide inside an older checkpoint envelope
	if spatial_boundary:
		var candidate_environment := SimEnvironment.new()
		candidate_environment.weather = restored_weather
		var tick_value: Variant = snapshot.get("tick")
		var dt_value: Variant = snapshot.get("dt")
		if typeof(tick_value) != TYPE_INT or tick_value < 0 or typeof(dt_value) != TYPE_FLOAT \
				or not is_finite(dt_value) or dt_value <= 0.0:
			return false
		for key: String in ["state", "previous"]:
			var body: Variant = snapshot.get(key)
			if not body is PackedFloat64Array or body.size() != RB.SIZE:
				return false
			var at: float = float(tick_value if key == "state" else maxi(0, tick_value - 1)) * dt_value
			var sampled := WindFlow.stage_air(body, aircraft.model, candidate_environment, at,
				restored_weather.air_density(body[RB.POS + 2]), Aero.SPATIAL_CONTINUATION_LAW, false)
			if not sampled.ok:
				return false
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
	if turbine_is_continuous() and not liquid_fuel_is_active() and snapshot.modes[0] == 0 and snapshot.continuous[0] != 0.0:
		return false
	if liquid_fuel_is_active() and not LiquidFlight.valid(self, snapshot.continuous):
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
	if _reset_transaction_reentry: return false
	# Final kernel validation uses the existing owner-controlled width staging.
	# The common transaction restores it silently on any precommit refusal.
	sim.aux = snapshot.aux.duplicate()
	sim.modes = snapshot.modes.duplicate()
	sim.inputs = snapshot.inputs.duplicate()
	_weather = restored_weather
	_weather_pending_reset = false
	_shaft_pending_reset = false
	_airframe_offset = restored_airframe_offset
	_deflection_key = PackedFloat64Array()
	_prepare_stage_backend(float(snapshot.tick) * float(snapshot.dt), str(recorded_backend.backend))
	if recorded_backend != stage_backend_identity():
		return false
	return sim.restore_checkpoint(snapshot, func() -> void:
		transaction.committed = true
		_reset_physical_committed = true
		_reset_publication_active = true
		_reset_closing_context = transaction.closing
		resetting.emit()
		if gear_is_retractable():
			_gear_requested_down = snapshot.inputs[4] == 1.0
			_gear_cache_fraction = -1.0
			_gear_request_inhibited = false
		_wheel_brake_demand = snapshot.inputs[wheel_brake_input_index()] if wheel_brake_input_index() >= 0 else 0.0
		_flap_requested = snapshot.inputs[flap_input_index()] if flaps_available() else 0.0
		fuel_start_fill = restored_fuel_fill
		_fuel_start_fill_known = restored_fuel_fill_known
		_failures = restored_failures
		_scenery_damage = restored_damage
		_restore_contact_history(restored_contacts)
		if soft_hull_contacts:
			_refresh_soft_contacts()
		else:
			soft_contacts = []
			_soft_contacts_cache_tick = -1
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
			launch_engine_running = "unknown", launch_trim_throttle = "unknown", launch_error = "",
		}
		input_enabled = false
		crash = {}
		_last_scenery_event = null
		_last_lake_event = null
		pause_reason = "checkpoint restored (recorded inputs)"
		_airframe_offset = restored_airframe_offset
		_deflection_key = PackedFloat64Array()
		scenery_damage_changed.emit()
		contact_events_changed.emit()
		_reset_closing_context = {}
		_reset_publication_active = false)


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
