## Disposable real-session tests for NK-3 weather snapshots and live ownership.
## Run with the checked Godot runner, --path app, and this script as --script.
extends SceneTree

const NativeWeather := preload("native_weather.gd")
const WeatherAdapter := preload("weather_adapter.gd")
const Session := preload("res://sim/flight_session.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const WeatherConfig := preload("res://physics/wind_config.gd")
const WeatherField := preload("res://physics/wind_field.gd")
const SimEnvironment := preload("res://sim/environment.gd")
const VehicleModel := preload("res://sim/vehicle_model.gd")
const AIRCRAFT := "jensen-das-ugly-stik-60"

var _failures := PackedStringArray()
var _checks := 0
var _negative_zero: float


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_negative_zero = PackedByteArray([0, 0, 0, 0, 0, 0, 0, 128]).decode_double(0)
	var presets: Array[Dictionary] = WeatherConfig.presets()
	for preset: Dictionary in presets:
		_check_preset(preset)
	_check_signed_zero()
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
	var snapshot: Dictionary = prepared.snapshot
	var snapshot_bytes := var_to_bytes(snapshot)
	_check(snapshot.is_read_only(), label + ": snapshot read-only")
	if snapshot.has("spatial"):
		_check(snapshot.spatial.is_read_only() and snapshot.spatial.thermal.is_read_only(),
			label + ": nested snapshot read-only")
	_check(NativeWeather.matches(session, identity), label + ": initial match")
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
	_check_owner(session, identity, label)
	for index: int in 2:
		session.sim.step()
		_check(not session.sim.paused and session.sim.fault_reason.is_empty() and session.sim.tick == index + 1,
			label + ": tick advanced")
		_check(NativeWeather.matches(session, identity), label + ": matches after tick")
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
		_check(not NativeWeather.matches(session, identity), label + ": changed " + field_name)
		provider.set(field_name, original)
		_check(NativeWeather.matches(session, identity), label + ": restored " + field_name)


func _check_nested_spatial(session: Node, identity: Variant, spatial: RefCounted, label: String) -> void:
	var config: Dictionary = spatial.get("_config")
	var original_extent: float = config.domain.half_extent_north_m
	config.domain.half_extent_north_m += 1.0
	_check(not NativeWeather.matches(session, identity), label + ": nested spatial domain")
	config.domain.half_extent_north_m = original_extent
	_check(NativeWeather.matches(session, identity), label + ": nested spatial restored")
	var domain: Dictionary = config.domain
	config.domain = domain.duplicate(true)
	_check(not NativeWeather.matches(session, identity), label + ": replaced nested container")
	config.domain = domain
	_check(NativeWeather.matches(session, identity), label + ": restored nested container")
	var transition: float = spatial.get("_gust_transition_height")
	spatial.set("_gust_transition_height", transition + 1.0)
	_check(not WeatherAdapter.provider_identity(session).get("ok", false), label + ": mutated transition refuses prepare")
	spatial.set("_gust_transition_height", transition)
	var thermal: Variant = spatial.get("_thermal_field")
	if thermal != null:
		var thermal_config: Dictionary = thermal.get("_config")
		if not thermal_config.cells.is_empty():
			var original_radius: float = thermal_config.cells[0].radius_m
			thermal_config.cells[0].radius_m += 1.0
			_check(not NativeWeather.matches(session, identity), label + ": nested thermal agenda")
			thermal_config.cells[0].radius_m = original_radius
			_check(NativeWeather.matches(session, identity), label + ": nested thermal restored")


func _check_owner(session: Node, identity: Variant, label: String) -> void:
	var original_environment: RefCounted = session.environment
	session.environment = SimEnvironment.new()
	_check(not NativeWeather.matches(session, identity), label + ": replaced environment")
	session.environment = original_environment
	_check(NativeWeather.matches(session, identity), label + ": restored environment")
	var old_field: RefCounted = session.environment.weather
	var other: Dictionary = WeatherField.build(old_field.configuration())
	session.environment.weather = other.field
	_check(not NativeWeather.matches(session, identity), label + ": replaced weather provider")
	session.environment.weather = old_field
	_check(NativeWeather.matches(session, identity), label + ": restored weather provider")
	var callback: Callable = session.environment.turbulence
	session.environment.turbulence = func(_time: float) -> PackedFloat64Array: return PackedFloat64Array()
	_check(not NativeWeather.matches(session, identity), label + ": replaced callback")
	session.environment.turbulence = callback
	_check(NativeWeather.matches(session, identity), label + ": restored callback")
	var old_model: RefCounted = session.sim.model
	session.sim.model = VehicleModel.new()
	_check(not NativeWeather.matches(session, identity), label + ": replaced model")
	session.sim.model = old_model
	_check(NativeWeather.matches(session, identity), label + ": restored model")
	session._weather_pending_reset = true
	_check(not NativeWeather.matches(session, identity), label + ": pending reset")
	session._weather_pending_reset = false
	var old_index: int = session._turbulence_aux_index
	session._turbulence_aux_index = old_index + 1
	_check(not NativeWeather.matches(session, identity), label + ": changed turbulence index")
	session._turbulence_aux_index = old_index
	var old_aux: PackedFloat64Array = session.sim.aux.duplicate()
	var changed_aux := old_aux.duplicate()
	changed_aux.append(0.0)
	session.sim.aux = changed_aux
	_check(not NativeWeather.matches(session, identity), label + ": changed auxiliary size")
	session.sim.aux = old_aux
	var old_dt: float = session.sim._fixed_dt
	session.sim._fixed_dt = 0.5
	_check(not NativeWeather.matches(session, identity), label + ": changed dt")
	session.sim._fixed_dt = old_dt
	_check(NativeWeather.matches(session, identity), label + ": owner restored")


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
	var field: RefCounted = session._weather
	var saved: Dictionary = field.get("_config")
	var elevation: float = saved.field_elevation_m
	saved.field_elevation_m = _negative_zero
	_check(not NativeWeather.matches(session, prepared.identity), "signed-zero: scalar elevation mutation")
	saved.field_elevation_m = elevation
	var mean: PackedFloat64Array = field.get("_mean_ned")
	var changed_mean := mean.duplicate()
	changed_mean[0] = _negative_zero
	field.set("_mean_ned", changed_mean)
	_check(not NativeWeather.matches(session, prepared.identity), "signed-zero: packed mean mutation")
	field.set("_mean_ned", mean)
	_check(NativeWeather.matches(session, prepared.identity), "signed-zero: restored")
	session.free()
	var spatial_session := _session(WeatherConfig.preset("spatial-thermal-soaring-v2"), "signed-zero-spatial")
	if spatial_session == null:
		return
	var spatial_prepared: Dictionary = NativeWeather.prepare(spatial_session)
	if not spatial_prepared.get("ok", false):
		_failures.append("signed-zero-spatial: prepare failed")
		spatial_session.free()
		return
	var spatial: RefCounted = spatial_session._weather.get("_spatial")
	var spatial_config: Dictionary = spatial.get("_config")
	var spatial_epoch: float = spatial_config.identity.epoch_offset_s
	spatial_config.identity.epoch_offset_s = _negative_zero
	_check(not NativeWeather.matches(spatial_session, spatial_prepared.identity), "signed-zero: spatial epoch mutation")
	_check(not NativeWeather.prepare(spatial_session).get("ok", false), "signed-zero: spatial mismatch refuses prepare")
	spatial_config.identity.epoch_offset_s = spatial_epoch
	var thermal: RefCounted = spatial.get("_thermal_field")
	var thermal_config: Dictionary = thermal.get("_config")
	var thermal_epoch: float = thermal_config.identity.epoch_offset_s
	thermal_config.identity.epoch_offset_s = _negative_zero
	_check(not NativeWeather.matches(spatial_session, spatial_prepared.identity), "signed-zero: thermal epoch mutation")
	_check(not NativeWeather.prepare(spatial_session).get("ok", false), "signed-zero: thermal mismatch refuses prepare")
	thermal_config.identity.epoch_offset_s = thermal_epoch
	_check(NativeWeather.matches(spatial_session, spatial_prepared.identity), "signed-zero: spatial restored")
	spatial_session.free()
	var nested := {values = PackedFloat64Array([0.0])}
	var watches: Array[NativeWeather.Watch] = []
	NativeWeather._capture_watches(nested, watches)
	nested.values[0] = _negative_zero
	_check(not NativeWeather._watches_match(watches), "signed-zero: nested packed array mutation")
	nested.values[0] = 0.0
	_check(NativeWeather._watches_match(watches), "signed-zero: nested packed array restored")
