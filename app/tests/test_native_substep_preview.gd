extends SceneTree
## NK-5b: a finite-liquid gas stage publishes, in its accepted-endpoint substep preview, the source-off shaft rate that
## _substeps_joint used to rebuild from LiquidFlight.properties and _coupled_response. On the reference and the native
## backend, each tick's published rate must equal that legacy response bit for bit, and the substep count with the rate
## must equal the count without it, through flight, idle, a ground rundown and engine-off starts just above the cutoff.
## The native half skips (passes) when no verified native library is installed for this platform.

const Flight := preload("res://sim/flight_session.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const LakeLoader := preload("res://data/lake_loader.gd")
const NativeStage := preload("res://sim/native_stage.gd")
const LiquidFlight := preload("res://sim/liquid_fuel_flight.gd")
const Weather := preload("res://physics/wind_config.gd")

const KEY := "source_off_rpm_rate"
var _checks := 0
var _failures := 0
var field: Dictionary
var lake: Dictionary


func _initialize() -> void:
	Engine.physics_ticks_per_second = 240
	_run.call_deferred()


func _run() -> void:
	var loaded_field: Dictionary = FieldLoader.load_from()
	var loaded_lake: Dictionary = LakeLoader.load_from(LakeLoader.DEFAULT_PATH)
	_check("field and lake load", loaded_field.ok and loaded_lake.ok)
	field = loaded_field.field
	lake = loaded_lake.lake
	for backend: String in [NativeStage.BACKEND_REFERENCE, NativeStage.BACKEND_NATIVE]:
		for id: String in ["p51d-mustang-120", "f4u-corsair-250"]:
			_case(backend, id)
	print("native substep preview: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _case(backend: String, id: String) -> void:
	var label := "%s/%s" % [backend, id]
	var stats := {ticks = 0, published = 0, unpublished = 0, refined = 0, negative = 0, explicit_air = 0, mismatch = ""}
	var flight := _session(backend, id, Flight.START_AIRBORNE)
	if flight == null:
		return
	if flight.stage_backend_identity().backend != backend:
		print("NK5B_SUBSTEP_PREVIEW_SKIP %s: %s" % [label, str(flight.stage_backend_status())])
		flight.free()
		return
	_check(label + " is a liquid gas aircraft with the substep preview", flight.liquid_fuel_is_active()
		and flight._substep_preview_supported())
	for tick: int in 360:
		_probe(flight, stats)
		flight.read_raw = func() -> Dictionary:
			return {roll = 0.04, pitch = 0.03, yaw = 0.0, throttle = 0.75 if tick < 240 else 0.0}
		if not _step(flight):
			break
	_check(label + " flew airborne and idle ticks", flight.sim.tick >= 359 and flight.sim.fault_reason.is_empty(),
		str(flight.sim.fault_reason))
	flight.free()
	# Spatial weather: the preview air carries an explicit propeller-point inflow.
	var weather: Dictionary = Weather.preset("spatial-gusty-v1")
	weather.spatial_wind.gusts.events[0].start_s = 0.0
	var gusty := _session(backend, id, Flight.START_AIRBORNE, weather)
	if gusty != null:
		gusty.read_raw = func() -> Dictionary:
			return {roll = 0.0, pitch = 0.02, yaw = 0.0, throttle = 0.6}
		for tick: int in 240:
			_probe(gusty, stats)
			if not _step(gusty):
				break
		_check(label + " flew spatial-weather ticks on the selected backend", gusty.sim.tick >= 239
			and gusty.sim.fault_reason.is_empty() and gusty.stage_backend_identity().backend == backend,
			"%s %s" % [gusty.sim.fault_reason, str(gusty.stage_backend_status())])
		_check(label + " spatial previews carried explicit propeller air", stats.explicit_air > 0, str(stats))
		gusty.free()
	var ground := _session(backend, id, Flight.START_RUNWAY)
	if ground == null:
		return
	ground.engine_running = false
	for tick: int in 720:
		_probe(ground, stats)
		if not _step(ground):
			break
	_check(label + " ran an engine-off ground rundown", ground.sim.tick >= 719 and ground.sim.fault_reason.is_empty(),
		str(ground.sim.fault_reason))
	# Engine-off restarts just above the cutoff: the refinement requests several substeps here.
	# The real kernel tick must integrate the legacy count: each RK4 piece evaluates the stage four times.
	var rotor: int = ground._rotor_index()
	var body: PackedFloat64Array = ground.sim.state.duplicate()
	var counted := {calls = 0}
	var reference_stage: Callable = ground.sim.model.stage
	if backend == NativeStage.BACKEND_REFERENCE:
		ground.sim.model.stage = func(s: PackedFloat64Array, z: PackedFloat64Array, t: float) -> Variant:
			counted.calls += 1
			return reference_stage.call(s, z, t)
	for rpm: float in [1.000001, 1.001, 1.01, 1.05, 2.0, 5.0]:
		ground.sim.continuous[rotor] = rpm
		ground.sim.aux[0] = rpm
		if not ground.sim.reset(body):
			_check(label + " cutoff fixture resets at %s RPM" % str(rpm), false)
			continue
		var legacy_count: int = _probe(ground, stats)
		var before: int = _stage_calls(ground, counted)
		ground.sim.step()
		var used: int = _stage_calls(ground, counted) - before
		_check(label + " cutoff tick at %s RPM is accepted with the legacy substep count" % str(rpm),
			ground.sim.fault_reason.is_empty() and legacy_count >= 1 and used == 4 * legacy_count,
			"legacy %d substeps; %d stage calls; fault '%s'" % [legacy_count, used, ground.sim.fault_reason])
	ground.sim.model.stage = reference_stage
	_check(label + " published source-off rates on its preview ticks", stats.published >= 300, str(stats))
	_check(label + " covered negative source-off rates and refined substep counts", stats.negative > 0 and stats.refined > 0,
		str(stats))
	_check(label + " every published rate equals the legacy response and keeps the legacy substep count",
		str(stats.mismatch).is_empty(), str(stats.mismatch))
	print("NK5B_SUBSTEP_PREVIEW %s %s" % [label, str(stats)])
	ground.free()


func _stage_calls(session: Node, counted: Dictionary) -> int:
	if session._native_stage != null:
		return int(session._native_stage.stage_stats().get("stage_calls", 0))
	return int(counted.calls)


## Emulate the kernel's tick start: the guarded pre-step installs this tick's context, then the first stage at the
## committed endpoint captures the preview that the kernel hands to _substeps_joint. Returns the legacy count or -1.
func _probe(session: Node, stats: Dictionary) -> int:
	var sim: Node = session.sim
	var aux: PackedFloat64Array = sim.aux.duplicate()
	var inputs: PackedFloat64Array = sim.inputs.duplicate()
	var modes: PackedInt64Array = sim.modes.duplicate()
	var next: PackedFloat64Array = session._kernel_pre_step(aux, inputs, sim.dt())
	sim.modes = modes # a turbulence draw advances the RNG: the real tick repeats it
	if next.size() != aux.size():
		return -1
	var saved_aux: PackedFloat64Array = sim.aux
	sim.aux = next
	var body: PackedFloat64Array = sim.state.duplicate()
	var values: PackedFloat64Array = sim.continuous.duplicate()
	var at: float = sim.time()
	var joint: Variant = sim.model.stage.call(body, values, at)
	sim.aux = saved_aux
	stats.ticks += 1
	if not joint is Dictionary or not joint.has("stage_context"):
		return session._substeps_joint(body, values, at, joint) if joint is Dictionary else -1
	var context: Dictionary = joint.stage_context
	if context.air.has("propulsion_air_body"):
		stats.explicit_air += 1
	var stripped: Dictionary = context.duplicate()
	stripped.erase(KEY)
	var stripped_joint: Dictionary = joint.duplicate()
	stripped_joint.stage_context = stripped
	var legacy: Dictionary = session._coupled_response(body, values.slice(0, session._liquid_index()), at,
		LiquidFlight.properties(session, values, true), false, stripped)
	var legacy_rate: float = float(legacy.get("rpm_rate", NAN)) if legacy.get("ok", false) else NAN
	var legacy_count: int = session._substeps_joint(body, values, at, stripped_joint)
	if not context.has(KEY):
		stats.unpublished += 1
		if is_finite(legacy_rate) and str(stats.mismatch).is_empty():
			stats.mismatch = "tick %d: finite legacy rate %s was not published" % [sim.tick, str(legacy_rate)]
		return legacy_count
	stats.published += 1
	var count: int = session._substeps_joint(body, values, at, joint)
	var rate: Variant = context[KEY]
	if legacy_rate < 0.0:
		stats.negative += 1
	if legacy_count > 1:
		stats.refined += 1
	if str(stats.mismatch).is_empty() and (not rate is float or var_to_bytes(rate) != var_to_bytes(legacy_rate)
			or count != legacy_count):
		stats.mismatch = "tick %d: published %s vs legacy %s; substeps %d vs %d" % [sim.tick, str(rate), str(legacy_rate),
			count, legacy_count]
	return legacy_count


func _step(session: Node) -> bool:
	var before: int = session.sim.tick
	var dt: float = session.sim.dt()
	session._physics_process(dt)
	session.sim._physics_process(dt)
	return session.sim.tick == before + 1


func _session(backend: String, id: String, start: String, weather: Dictionary = {}) -> Node:
	var session: Node = Flight.new()
	session.input_enabled = true
	session.crash_auto_restart = false
	session.soft_hull_contacts = true
	_check("select " + backend, session.setup_stage_backend(backend))
	session.setup(str(Catalog.entry(id).data), id)
	_check(id + " is flyable", session.is_flyable(), str(session.pause_reason))
	if not weather.is_empty():
		_check(id + " weather installs", session.setup_weather(weather), str(session.weather_error))
	_check(id + " field and lake install", session.set_field(field) and session.set_lake_context(lake))
	session.start_choice = start
	session.reset()
	session.read_raw = func() -> Dictionary:
		return {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.0}
	if not session.is_flyable():
		session.free()
		return null
	return session


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])
