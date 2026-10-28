## Disposable real-session tests for both GDScript and native weather guards.
## Run with the checked Godot runner, --path app, this script as --script,
## and -- --extension=<absolute research .gdextension>.
extends SceneTree

const NativeWeather := preload("native_weather.gd")
const WeatherAdapter := preload("weather_adapter.gd")
const Session := preload("res://sim/flight_session.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const WeatherConfig := preload("res://physics/wind_config.gd")
const WeatherField := preload("res://physics/wind_field.gd")
const SimEnvironment := preload("res://sim/environment.gd")
const VehicleModel := preload("res://sim/vehicle_model.gd")
const HelicopterSession := preload("res://sim/helicopter_flight_session.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const AIRCRAFT := "jensen-das-ugly-stik-60"
const HELICOPTER_ID := "xcell-60-research"
const HELICOPTER_PATH := "res://data/aircraft/xcell_60_research.json"

var _failures := PackedStringArray()
var _checks := 0
var _negative_zero: float
var _native: Object


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var extension := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--extension="):
			extension = argument.trim_prefix("--extension=")
	if extension.is_empty():
		print("FAIL native extension path is required")
		quit(1)
		return
	var load_status: int = OK if GDExtensionManager.is_extension_loaded(extension) \
		else GDExtensionManager.load_extension(extension)
	if load_status != OK or not ClassDB.class_exists("OpenRCNativeKernel"):
		print("FAIL cannot load native weather guard: ", load_status)
		quit(1)
		return
	_native = ClassDB.instantiate("OpenRCNativeKernel")
	if _native == null or not _native.has_method("prepare_weather_guard") \
			or not _native.has_method("weather_guard_matches"):
		print("FAIL native weather guard methods missing")
		quit(1)
		return
	_negative_zero = PackedByteArray([0, 0, 0, 0, 0, 0, 0, 128]).decode_double(0)
	var presets: Array[Dictionary] = WeatherConfig.presets()
	for preset: Dictionary in presets:
		_check_preset(preset)
	_check_signed_zero()
	_check_fallback_dt()
	_check_script_replacement()
	_check_helicopters()
	if _failures.is_empty():
		print("NK3_NATIVE_WEATHER_TEST verdict=pass checks=%d presets=%d" % [_checks, presets.size()])
		quit(0)
	else:
		for failure: String in _failures:
			print("FAIL ", failure)
		print("NK3_NATIVE_WEATHER_TEST verdict=fail checks=%d failures=%d" % [_checks, _failures.size()])
		quit(1)


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)


func _prepare_guard(session: Node, identity: Variant, label: String) -> bool:
	var result: Dictionary = _native.prepare_weather_guard(session, identity)
	var ok: bool = result.get("ok", false)
	_check(ok, label + ": native prepare " + str(result.get("reason", "")))
	return ok


func _matches(session: Node, identity: Variant) -> bool:
	var gdscript: bool = NativeWeather.matches(session, identity)
	var native: bool = _native.weather_guard_matches(session)
	if gdscript != native:
		_failures.append("native/GDScript guard disagreement")
	return gdscript and native


func _session(config: Dictionary, label: String) -> Node:
	var session: Node = Session.new()
	session.setup(str(Catalog.entry(AIRCRAFT).data), AIRCRAFT)
	if not session.is_flyable() or not session.setup_weather(config):
		_failures.append(label + ": session/weather setup failed: " + str(session.weather_error))
		session.free()
		return null
	session.reset()
	if session.sim.paused or not session.sim.fault_reason.is_empty():
		_failures.append(label + ": reset failed: " + str(session.sim.fault_reason))
		session.free()
		return null
	return session


func _check_preset(preset: Dictionary) -> void:
	var label := str(preset.id)
	var session := _session(preset.config, label)
	if session == null:
		return
	var prepared: Dictionary = NativeWeather.prepare(session)
	_check(prepared.get("ok", false), label + ": prepare")
	if not prepared.get("ok", false):
		session.free()
		return
	var identity: Variant = prepared.identity
	if not _prepare_guard(session, identity, label):
		session.free()
		return
	var snapshot: Dictionary = prepared.snapshot
	var snapshot_bytes := var_to_bytes(snapshot)
	_check(snapshot.is_read_only(), label + ": snapshot read-only")
	if snapshot.has("spatial"):
		_check(snapshot.spatial.is_read_only() and snapshot.spatial.thermal.is_read_only(),
			label + ": nested snapshot read-only")
	_check(_matches(session, identity), label + ": initial match")
	_check(snapshot_bytes == var_to_bytes(WeatherAdapter.snapshot(session._weather)), label + ": exact snapshot")
	var field: RefCounted = session._weather
	_check_values(session, identity, field, NativeWeather.FIELD_VALUES, label + ": field")
	var spatial: Variant = field.get("_spatial")
	if spatial != null:
		_check_values(session, identity, spatial, NativeWeather.SPATIAL_VALUES, label + ": spatial")
		var thermal: Variant = spatial.get("_thermal_field")
		if thermal != null:
			_check_values(session, identity, thermal, NativeWeather.THERMAL_VALUES, label + ": thermal")
		_check_nested_spatial(session, identity, spatial, label)
	_check(snapshot_bytes == var_to_bytes(snapshot), label + ": snapshot detached")
	if label == "calm":
		var saved_values: Dictionary = identity.field_values
		identity.field_values = {}
		var refused: Dictionary = _native.prepare_weather_guard(session, identity)
		_check(not refused.get("ok", true) and not _native.weather_guard_matches(session),
			label + ": incomplete identity refuses and disarms")
		identity.field_values = saved_values
		if not _prepare_guard(session, identity, label + ": restored identity"):
			session.free()
			return
	_check_owner(session, identity, label)
	for index: int in 2:
		session.sim.step()
		_check(not session.sim.paused and session.sim.fault_reason.is_empty() and session.sim.tick == index + 1,
			label + ": tick advanced")
		_check(_matches(session, identity), label + ": matches after tick")
	session.free()


func _changed(value: Variant) -> Variant:
	match typeof(value):
		TYPE_BOOL:
			return not value
		TYPE_INT:
			return value + 1
		TYPE_FLOAT:
			return value + 1.0
		TYPE_DICTIONARY:
			var changed: Dictionary = value.duplicate(true)
			changed["nk3_guard_probe"] = 1
			return changed
		TYPE_PACKED_FLOAT64_ARRAY:
			var changed: PackedFloat64Array = value.duplicate()
			if changed.is_empty():
				changed.append(1.0)
			else:
				changed[0] += 1.0
			return changed
	return null


func _check_values(session: Node, identity: Variant, provider: RefCounted, fields: Array, label: String) -> void:
	for field_name: String in fields:
		var original: Variant = provider.get(field_name)
		var changed: Variant = _changed(original)
		if changed == null:
			_failures.append(label + ": no mutation for " + field_name)
			continue
		provider.set(field_name, changed)
		_check(not _matches(session, identity), label + ": changed " + field_name)
		provider.set(field_name, original)
		_check(_matches(session, identity), label + ": restored " + field_name)


func _check_nested_spatial(session: Node, identity: Variant, spatial: RefCounted, label: String) -> void:
	var config: Dictionary = spatial.get("_config")
	var original_extent: float = config.domain.half_extent_north_m
	config.domain.half_extent_north_m += 1.0
	_check(not _matches(session, identity), label + ": nested spatial domain")
	config.domain.half_extent_north_m = original_extent
	_check(_matches(session, identity), label + ": nested spatial restored")
	var domain: Dictionary = config.domain
	config.domain = domain.duplicate(true)
	_check(not _matches(session, identity), label + ": replaced nested container")
	config.domain = domain
	_check(_matches(session, identity), label + ": restored nested container")
	var transition: float = spatial.get("_gust_transition_height")
	spatial.set("_gust_transition_height", transition + 1.0)
	_check(not WeatherAdapter.provider_identity(session).get("ok", false), label + ": mutated transition refuses prepare")
	var bad_guard: Dictionary = _native.prepare_weather_guard(session, identity)
	_check(not bad_guard.get("ok", true) and not _native.weather_guard_matches(session),
		label + ": stale native prepare refuses and disarms")
	spatial.set("_gust_transition_height", transition)
	if not _prepare_guard(session, identity, label + ": restored transition"):
		return
	var thermal: Variant = spatial.get("_thermal_field")
	if thermal != null:
		var thermal_config: Dictionary = thermal.get("_config")
		if not thermal_config.cells.is_empty():
			var original_radius: float = thermal_config.cells[0].radius_m
			thermal_config.cells[0].radius_m += 1.0
			_check(not _matches(session, identity), label + ": nested thermal agenda")
			thermal_config.cells[0].radius_m = original_radius
			_check(_matches(session, identity), label + ": nested thermal restored")


func _check_owner(session: Node, identity: Variant, label: String) -> void:
	var original_environment: RefCounted = session.environment
	session.environment = SimEnvironment.new()
	_check(not _matches(session, identity), label + ": replaced environment")
	session.environment = original_environment
	_check(_matches(session, identity), label + ": restored environment")
	var old_field: RefCounted = session.environment.weather
	var other: Dictionary = WeatherField.build(old_field.configuration())
	session.environment.weather = other.field
	_check(not _matches(session, identity), label + ": replaced weather provider")
	session.environment.weather = old_field
	_check(_matches(session, identity), label + ": restored weather provider")
	var callback: Callable = session.environment.turbulence
	session.environment.turbulence = func(_time: float) -> PackedFloat64Array: return PackedFloat64Array()
	_check(not _matches(session, identity), label + ": replaced callback")
	session.environment.turbulence = callback
	_check(_matches(session, identity), label + ": restored callback")
	var old_model: RefCounted = session.sim.model
	session.sim.model = VehicleModel.new()
	_check(not _matches(session, identity), label + ": replaced model")
	session.sim.model = old_model
	_check(_matches(session, identity), label + ": restored model")
	session._weather_pending_reset = true
	_check(not _matches(session, identity), label + ": pending reset")
	session._weather_pending_reset = false
	var old_index: int = session._turbulence_aux_index
	session._turbulence_aux_index = old_index + 1
	_check(not _matches(session, identity), label + ": changed turbulence index")
	session._turbulence_aux_index = old_index
	var old_aux: PackedFloat64Array = session.sim.aux.duplicate()
	var changed_aux := old_aux.duplicate()
	changed_aux.append(0.0)
	session.sim.aux = changed_aux
	_check(not _matches(session, identity), label + ": changed auxiliary size")
	session.sim.aux = old_aux
	var old_dt: float = session.sim._fixed_dt
	session.sim._fixed_dt = 0.5
	_check(not _matches(session, identity), label + ": changed dt")
	session.sim._fixed_dt = old_dt
	_check(_matches(session, identity), label + ": owner restored")


func _check_signed_zero() -> void:
	var config: Dictionary = WeatherConfig.upgrade_column(WeatherConfig.defaults(),
		{atmosphere_mode = "standard_column", field_elevation_m = 0.0})
	var session := _session(config, "signed-zero")
	if session == null:
		return
	var prepared: Dictionary = NativeWeather.prepare(session)
	if not prepared.get("ok", false):
		_failures.append("signed-zero: prepare failed")
		session.free()
		return
	if not _prepare_guard(session, prepared.identity, "signed-zero"):
		session.free()
		return
	var field: RefCounted = session._weather
	var saved: Dictionary = field.get("_config")
	var elevation: float = saved.field_elevation_m
	saved.field_elevation_m = _negative_zero
	_check(not _matches(session, prepared.identity), "signed-zero: scalar elevation mutation")
	saved.field_elevation_m = elevation
	var mean: PackedFloat64Array = field.get("_mean_ned")
	var changed_mean := mean.duplicate()
	changed_mean[0] = _negative_zero
	field.set("_mean_ned", changed_mean)
	_check(not _matches(session, prepared.identity), "signed-zero: packed mean mutation")
	field.set("_mean_ned", mean)
	_check(_matches(session, prepared.identity), "signed-zero: restored")
	session.free()
	var spatial_session := _session(WeatherConfig.preset("spatial-thermal-soaring-v2"), "signed-zero-spatial")
	if spatial_session == null:
		return
	var spatial_prepared: Dictionary = NativeWeather.prepare(spatial_session)
	if not spatial_prepared.get("ok", false):
		_failures.append("signed-zero-spatial: prepare failed")
		spatial_session.free()
		return
	if not _prepare_guard(spatial_session, spatial_prepared.identity, "signed-zero-spatial"):
		spatial_session.free()
		return
	var spatial: RefCounted = spatial_session._weather.get("_spatial")
	var spatial_config: Dictionary = spatial.get("_config")
	var spatial_epoch: float = spatial_config.identity.epoch_offset_s
	spatial_config.identity.epoch_offset_s = _negative_zero
	_check(not _matches(spatial_session, spatial_prepared.identity), "signed-zero: spatial epoch mutation")
	_check(not NativeWeather.prepare(spatial_session).get("ok", false), "signed-zero: spatial mismatch refuses prepare")
	spatial_config.identity.epoch_offset_s = spatial_epoch
	var free_air: Array = spatial_config.profile.free_air_wind_ned_mps
	var free_air_down: float = free_air[2]
	free_air[2] = _negative_zero
	_check(not _matches(spatial_session, spatial_prepared.identity), "signed-zero: nested array mutation")
	free_air[2] = free_air_down
	var thermal: RefCounted = spatial.get("_thermal_field")
	var thermal_config: Dictionary = thermal.get("_config")
	var thermal_epoch: float = thermal_config.identity.epoch_offset_s
	thermal_config.identity.epoch_offset_s = _negative_zero
	_check(not _matches(spatial_session, spatial_prepared.identity), "signed-zero: thermal epoch mutation")
	_check(not NativeWeather.prepare(spatial_session).get("ok", false), "signed-zero: thermal mismatch refuses prepare")
	thermal_config.identity.epoch_offset_s = thermal_epoch
	_check(_matches(spatial_session, spatial_prepared.identity), "signed-zero: spatial restored")
	spatial_session.free()
	var nested := {values = PackedFloat64Array([0.0])}
	var watches: Array[NativeWeather.Watch] = []
	NativeWeather._capture_watches(nested, watches)
	nested.values[0] = _negative_zero
	_check(not NativeWeather._watches_match(watches), "signed-zero: nested packed array mutation")
	nested.values[0] = 0.0
	_check(NativeWeather._watches_match(watches), "signed-zero: nested packed array restored")


func _check_fallback_dt() -> void:
	var session := _session(WeatherConfig.defaults(), "fallback-dt")
	if session == null:
		return
	session.sim._fixed_dt = 0.0
	var prepared: Dictionary = NativeWeather.prepare(session)
	if not prepared.get("ok", false) or not _prepare_guard(session, prepared.identity, "fallback-dt"):
		_failures.append("fallback-dt: prepare refused")
		session.free()
		return
	_check(_matches(session, prepared.identity), "fallback-dt: initial match")
	var original_rate := Engine.physics_ticks_per_second
	Engine.physics_ticks_per_second = original_rate + 1
	_check(not _matches(session, prepared.identity), "fallback-dt: changed engine tick rate")
	Engine.physics_ticks_per_second = original_rate
	_check(_matches(session, prepared.identity), "fallback-dt: engine tick rate restored")
	session.free()


func _check_script_replacement() -> void:
	for name: String in ["session", "simulation", "model"]:
		var session := _session(WeatherConfig.defaults(), "script-" + name)
		if session == null:
			continue
		var prepared: Dictionary = NativeWeather.prepare(session)
		if not prepared.get("ok", false) or not _prepare_guard(session, prepared.identity, "script-" + name):
			_failures.append("script-" + name + ": prepare refused")
			session.free()
			continue
		match name:
			"session": session.set_script(null)
			"simulation": session.sim.set_script(null)
			"model": session.sim.model.set_script(null)
		_check(not _matches(session, prepared.identity), "script-" + name + ": replacement refused")
		session.free()


func _check_helicopters() -> void:
	var loaded: Dictionary = FieldLoader.load_from()
	if not loaded.get("ok", false):
		_failures.append("helicopter field failed to load")
		return
	var started := 0
	for weather_id: String in ["calm", "steady", "crosswind", "gusty", "updraft", "hot-high", "cool-dense"]:
		var label := "helicopter-" + weather_id
		var session: Node = HelicopterSession.new()
		if not session.setup(HELICOPTER_PATH, HELICOPTER_ID) or not session.set_field(loaded.field) \
				or not session.setup_weather(WeatherConfig.preset(weather_id)):
			_failures.append(label + ": setup failed: " + str(session.weather_error))
			session.free()
			continue
		if not session.reset():
			if weather_id == "hot-high" and str(session.start_error).contains("hover trim line search could not reduce the full-force residual"):
				print("helicopter hot-high reset refused by reference: ", session.start_error)
			else:
				_failures.append(label + ": reset failed: " + str(session.start_error))
			session.free()
			continue
		started += 1
		var prepared: Dictionary = NativeWeather.prepare_helicopter(session)
		_check(prepared.get("ok", false), label + ": weather prepare")
		if not prepared.get("ok", false) or not _prepare_guard(session, prepared.identity, label):
			_failures.append(label + ": guard prepare failed")
			session.free()
			continue
		var identity: Variant = prepared.identity
		_check(identity.owner_kind == "helicopter" and identity.turbulence_index == -1,
			label + ": explicit owner and turbulence layout")
		_check(_matches(session, identity), label + ": initial match")
		_check_values(session, identity, session.environment.weather, NativeWeather.FIELD_VALUES, label + ": field")
		var callback: Callable = session.environment.turbulence
		session.environment.turbulence = func(_time: float) -> PackedFloat64Array: return PackedFloat64Array()
		_check(not _matches(session, identity), label + ": callback replacement")
		_check(not NativeWeather.prepare_helicopter(session).get("ok", true), label + ": callback prepare refusal")
		session.environment.turbulence = callback
		session._ready_to_fly = false
		_check(not _matches(session, identity), label + ": readiness changed")
		_check(not NativeWeather.prepare_helicopter(session).get("ok", true), label + ": unready prepare refusal")
		session._ready_to_fly = true
		var original_field: RefCounted = session.environment.weather
		for unsupported: String in ["turbulent", "standard-column", "spatial-realistic-v1"]:
			_check(not session.setup_weather(WeatherConfig.preset(unsupported)) and session.environment.weather == original_field,
				label + ": unsupported " + unsupported + " refused by reference")
		_check(_matches(session, identity), label + ": original provider restored")
		session.sim.step()
		_check(session.sim.tick == 1 and not session.sim.paused and session.sim.fault_reason.is_empty(),
			label + ": reference tick advanced")
		_check(_matches(session, identity), label + ": matches after reference tick")
		session.free()
	_check(started >= 6, "helicopter: insufficient healthy reference starts")
