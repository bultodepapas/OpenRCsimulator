## NK-3 configuration guard against disposable, real fixed-wing sessions.
## Checked runner: --path app --script <this file> -- --extension=<absolute .gdextension>.
extends SceneTree

const NativeConfiguration := preload("res://sim/native/native_configuration.gd")
const WeatherAdapter := preload("res://sim/native/weather_adapter.gd")
const ElectricAdapter := preload("res://sim/native/electric_stage_adapter.gd")
const LiquidAdapter := preload("res://sim/native/liquid_stage_adapter.gd")
const GlowAdapter := preload("res://sim/native/glow_stage_adapter.gd")
const Session := preload("res://sim/flight_session.gd")
const HelicopterSession := preload("res://sim/helicopter_flight_session.gd")
const VehicleModel := preload("res://sim/vehicle_model.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const LakeLoader := preload("res://data/lake_loader.gd")
const WeatherConfig := preload("res://physics/wind_config.gd")
const HELICOPTER_ID := "xcell-60-research"
const HELICOPTER_PATH := "res://data/aircraft/xcell_60_research.json"

var _native: Object
var _checks := 0
var _failures := PackedStringArray()
var _negative_zero: float


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
	var status: int = OK if GDExtensionManager.is_extension_loaded(extension) \
		else GDExtensionManager.load_extension(extension)
	if status != OK or not ClassDB.class_exists("OpenRCNativeKernel"):
		print("FAIL cannot load native configuration guard: ", status)
		quit(1)
		return
	_native = ClassDB.instantiate("OpenRCNativeKernel")
	if _native == null or not _native.has_method("prepare_configuration_guard") \
			or not _native.has_method("configuration_guard_matches"):
		print("FAIL native configuration guard methods missing")
		quit(1)
		return
	_negative_zero = PackedByteArray([0, 0, 0, 0, 0, 0, 0, 128]).decode_double(0)
	var fixtures := [
		{id = "jensen-das-ugly-stik-60", battery = "ideal", weather = "gusty", builder = WeatherAdapter.config_for},
		{id = "turbo-lumber-evolution", battery = "ideal", weather = "turbulent", builder = ElectricAdapter.config_for},
		{id = "turbo-lumber-evolution", battery = "pack", weather = "spatial-gusty-v1", builder = ElectricAdapter.config_for},
		{id = "p51d-mustang-120", battery = "ideal", weather = "standard-column", builder = LiquidAdapter.config_for},
		{id = "stik-glow-61fx-2t", battery = "ideal", weather = "calm", builder = GlowAdapter.config_for},
	]
	for fixture: Dictionary in fixtures:
		_check_fixture(fixture)
	_check_initial_liquid_context()
	_check_helicopters()
	if _failures.is_empty():
		print("NK3_NATIVE_CONFIGURATION_TEST verdict=pass checks=%d fixtures=%d" % [_checks, fixtures.size()])
		quit(0)
	else:
		for failure: String in _failures:
			print("FAIL ", failure)
		print("NK3_NATIVE_CONFIGURATION_TEST verdict=fail checks=%d failures=%d" % [_checks, _failures.size()])
		quit(1)


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)


func _session(fixture: Dictionary, label: String) -> Node:
	var session: Node = Session.new()
	session.input_enabled = true
	session.crash_auto_restart = false
	session.soft_hull_contacts = true
	session.setup(Catalog.data_for(fixture.id, fixture.battery), fixture.id)
	if not session.is_flyable() or not session.setup_weather(WeatherConfig.preset(fixture.weather)):
		_failures.append(label + ": setup refused: " + str(session.pause_reason) + " / " + str(session.weather_error))
		session.free()
		return null
	var field: Dictionary = FieldLoader.load_from()
	var lake: Dictionary = LakeLoader.load_from(LakeLoader.DEFAULT_PATH)
	if not field.ok or not lake.ok or not session.set_field(field.field) or not session.set_lake_context(lake.lake):
		_failures.append(label + ": field/lake refused")
		session.free()
		return null
	session.start_choice = Session.START_AIRBORNE
	session.reset()
	if session.sim.paused or not session.sim.fault_reason.is_empty() or not session.crash.is_empty():
		_failures.append(label + ": reset refused: " + str(session.pause_reason))
		session.free()
		return null
	return session


func _prepare_guard(session: Node, identity: Variant, label: String) -> bool:
	var result: Dictionary = _native.prepare_configuration_guard(session, identity)
	var ok: bool = result.get("ok", false)
	_check(ok, label + ": native guard prepare: " + str(result.get("reason", "")))
	return ok


func _check_initial_liquid_context() -> void:
	for id: String in ["p51d-mustang-120", "f4u-corsair-250", "sebart-avanti-s-a200-p100rx"]:
		var fixture := {id = id, battery = "ideal", weather = "calm", builder = LiquidAdapter.config_for}
		var label := "initial-empty-body/" + id
		var session := _session(fixture, label)
		if session == null: continue
		var config: Dictionary = LiquidAdapter.config_for(session)
		var prepared: Dictionary = _native.prepare_stage(config)
		_check(prepared.get("ok", false), label + ": stage prepared")
		if prepared.get("ok", false):
			var saved: PackedFloat64Array = session.sim.state
			session.sim.state = PackedFloat64Array()
			var eligible: bool = session._should_capture_substep_context(session.sim.state,
				session.sim.continuous, session.sim.time())
			if id != "sebart-avanti-s-a200-p100rx":
				_check(eligible, label + ": reproduces the empty-body preview predicate")
			_check(LiquidAdapter.set_context(session, _native, session.sim.aux, session.sim.inputs, session.sim.time()),
				label + ": first-setup context accepts no committed body")
			session.sim.state = saved
		session.free()


func _check_fixture(fixture: Dictionary) -> void:
	var label := "%s/%s/%s" % [fixture.id, fixture.battery, fixture.weather]
	var session := _session(fixture, label)
	if session == null:
		return
	var prepared: Dictionary = NativeConfiguration.prepare(session, fixture.builder)
	_check(prepared.get("ok", false), label + ": identity prepare " + str(prepared.get("reason", "")))
	if not prepared.get("ok", false):
		session.free()
		return
	var identity: Variant = prepared.identity
	var config: Dictionary = prepared.config
	var config_bytes := var_to_bytes(config)
	_check(config.is_read_only(), label + ": config root read-only")
	var weather: Dictionary = _native.prepare_weather_guard(session, prepared.weather_identity)
	_check(weather.get("ok", false) and _native.weather_guard_matches(session), label + ": weather guard")
	if not _prepare_guard(session, identity, label):
		session.free()
		return
	_check(_native.configuration_guard_matches(session), label + ": initial match")
	var native_stage: Dictionary = _native.prepare_stage(config)
	_check(native_stage.get("ok", false), label + ": native stage accepted exact config: " + str(native_stage.get("error", "")))
	if fixture.builder == LiquidAdapter.config_for and native_stage.get("ok", false):
		_check(LiquidAdapter.set_context(session, _native, session.sim.aux, session.sim.inputs, session.sim.time()),
			label + ": liquid context accepted")
		_check(_native.set_preview_context(session.sim.state, session.sim.continuous, true),
			label + ": valid preview capture accepted")
		_check(_native.stage(session.sim.state, session.sim.continuous, session.sim.time()).has("stage_context"),
			label + ": armed preview published")
		_check(_native.set_preview_context(PackedFloat64Array(), PackedFloat64Array(), false),
			label + ": disabled preview accepts an uninitialized body during setup")
		_check(not _native.stage(session.sim.state, session.sim.continuous, session.sim.time()).has("stage_context"),
			label + ": disabled preview clears previous capture")
		_check(not _native.set_preview_context(PackedFloat64Array(), PackedFloat64Array(), true),
			label + ": enabled preview still rejects an uninitialized body")
	_check_fields(session, session, NativeConfiguration.SESSION_FIELDS, label + ": session")
	_check_fields(session, session.environment, NativeConfiguration.ENVIRONMENT_FIELDS, label + ": environment")
	_check_fields(session, session.sim, NativeConfiguration.SIM_FIELDS, label + ": simulation")
	_check_fields(session, session.sim.model, NativeConfiguration.VEHICLE_FIELDS, label + ": vehicle")
	_check(config_bytes == var_to_bytes(config), label + ": detached config")
	_check_nested_model(session, label)
	_check_sizes_and_owners(session, label)
	var previous_stage: Callable = session.sim.model.stage
	session.sim.model.stage = func(_body: PackedFloat64Array, _values: PackedFloat64Array, _t: float) -> Dictionary: return {}
	_check(_native.configuration_guard_matches(session), label + ": installed stage checked separately")
	var refused: Dictionary = _native.prepare_configuration_guard(session, identity)
	_check(not refused.get("ok", true) and not _native.configuration_guard_matches(session),
		label + ": wrong reference stage refused and disarmed")
	session.sim.model.stage = previous_stage
	if not _prepare_guard(session, identity, label + ": restored stage"):
		session.free()
		return
	var old_fields: Dictionary = identity.session_values
	identity.session_values = {}
	refused = _native.prepare_configuration_guard(session, identity)
	_check(not refused.get("ok", true) and not _native.configuration_guard_matches(session),
		label + ": incomplete identity refused and disarmed")
	identity.session_values = old_fields
	if not _prepare_guard(session, identity, label + ": restored identity"):
		session.free()
		return
	_check(not NativeConfiguration.prepare(session, func(_s: Node) -> Dictionary: return {}).get("ok", true),
		label + ": unregistered builder refused")
	session.sim.step()
	_check(session.sim.tick == 1 and not session.sim.paused and session.sim.fault_reason.is_empty(), label + ": reference tick")
	_check(_native.configuration_guard_matches(session), label + ": match after reference tick")
	_check(_native.weather_guard_matches(session), label + ": weather match after reference tick")
	session.free()


func _changed(value: Variant) -> Variant:
	match typeof(value):
		TYPE_BOOL: return not value
		TYPE_INT: return value + 1
		TYPE_FLOAT: return value + 1.0
		TYPE_STRING: return value + "_changed"
		TYPE_CALLABLE: return func() -> void: pass
		TYPE_DICTIONARY:
			var changed: Dictionary = value.duplicate(true)
			changed["nk3_guard_probe"] = 1
			return changed
		TYPE_ARRAY:
			var changed: Array = value.duplicate(true)
			changed.append({})
			return changed
		TYPE_PACKED_FLOAT64_ARRAY:
			var changed: PackedFloat64Array = value.duplicate()
			if changed.is_empty(): changed.append(1.0)
			else: changed[0] += 1.0
			return changed
	return null


func _check_fields(session: Node, provider: Object, fields: Array, label: String) -> void:
	for name: String in fields:
		var original: Variant = provider.get(name)
		var changed: Variant = _changed(original)
		if changed == null:
			_failures.append(label + ": missing mutation for " + name)
			continue
		provider.set(name, changed)
		_check(not _native.configuration_guard_matches(session), label + ": changed " + name)
		provider.set(name, original)
		_check(_native.configuration_guard_matches(session), label + ": restored " + name)


## Find a floating scalar zero inside the actual live model, without changing
## container identity, so the test detects numeric equality masking ±0.
func _find_zero(value: Variant) -> Dictionary:
	if value is Dictionary:
		for key: Variant in value:
			var child: Variant = value[key]
			if typeof(child) == TYPE_FLOAT and child == 0.0 and not value.is_read_only():
				return {parent = value, key = key, old = child}
			var found := _find_zero(child)
			if not found.is_empty(): return found
	elif value is Array:
		for index: int in value.size():
			var child: Variant = value[index]
			if typeof(child) == TYPE_FLOAT and child == 0.0 and not value.is_read_only():
				return {parent = value, key = index, old = child}
			var found := _find_zero(child)
			if not found.is_empty(): return found
	return {}


func _find_packed_zero(value: Variant) -> Dictionary:
	if value is Dictionary:
		for key: Variant in value:
			var child: Variant = value[key]
			if child is PackedFloat64Array and not value.is_read_only():
				for index: int in child.size():
					if child[index] == 0.0:
						return {parent = value, key = key, old = child, index = index}
			var found := _find_packed_zero(child)
			if not found.is_empty(): return found
	elif value is Array:
		for key: int in value.size():
			var child: Variant = value[key]
			if child is PackedFloat64Array and not value.is_read_only():
				for index: int in child.size():
					if child[index] == 0.0:
						return {parent = value, key = key, old = child, index = index}
			var found := _find_packed_zero(child)
			if not found.is_empty(): return found
	return {}


func _check_nested_model(session: Node, label: String) -> void:
	var aircraft: Dictionary = session.aircraft
	var original_model: Dictionary = aircraft.model
	aircraft.model = original_model.duplicate(true)
	_check(not _native.configuration_guard_matches(session), label + ": replaced equal nested model")
	aircraft.model = original_model
	_check(_native.configuration_guard_matches(session), label + ": nested model restored")
	var zero := _find_zero(original_model)
	_check(not zero.is_empty(), label + ": found actual scalar zero")
	if not zero.is_empty():
		zero.parent[zero.key] = _negative_zero if atan2(float(zero.old), -1.0) > 0.0 else 0.0
		_check(not _native.configuration_guard_matches(session), label + ": scalar zero sign changed")
		zero.parent[zero.key] = zero.old
		_check(_native.configuration_guard_matches(session), label + ": scalar zero restored")
	var packed := _find_packed_zero(original_model)
	_check(not packed.is_empty(), label + ": found actual packed zero")
	if not packed.is_empty():
		var original: PackedFloat64Array = packed.old
		var changed := original.duplicate()
		changed[packed.index] = _negative_zero if atan2(original[packed.index], -1.0) > 0.0 else 0.0
		packed.parent[packed.key] = changed
		_check(not _native.configuration_guard_matches(session), label + ": packed zero sign changed")
		packed.parent[packed.key] = original
		_check(_native.configuration_guard_matches(session), label + ": packed zero restored")


func _check_sizes_and_owners(session: Node, label: String) -> void:
	var old_aux: PackedFloat64Array = session.sim.aux
	var next_aux := old_aux.duplicate()
	next_aux.append(0.0)
	session.sim.aux = next_aux
	_check(not _native.configuration_guard_matches(session), label + ": aux layout changed")
	session.sim.aux = old_aux
	var old_model: RefCounted = session.sim.model
	session.sim.model = VehicleModel.new()
	_check(not _native.configuration_guard_matches(session), label + ": model owner changed")
	session.sim.model = old_model
	_check(_native.configuration_guard_matches(session), label + ": model and aux restored")


func _check_helicopters() -> void:
	var field: Dictionary = FieldLoader.load_from()
	if not field.get("ok", false):
		_failures.append("helicopter field refused")
		return
	for start: String in ["airborne", "ground"]:
		for weather_id: String in ["calm", "gusty", "cool-dense"]:
			var label := "helicopter/%s/%s" % [start, weather_id]
			var session: Node = HelicopterSession.new()
			if not session.setup(HELICOPTER_PATH, HELICOPTER_ID) or not session.set_field(field.field) \
					or not session.set_start_choice(start) or not session.setup_weather(WeatherConfig.preset(weather_id)) \
					or not session.reset():
				_failures.append(label + ": reference setup/reset refused: " + str(session.start_error))
				session.free()
				continue
			var prepared: Dictionary = NativeConfiguration.prepare_helicopter(session)
			_check(prepared.get("ok", false), label + ": identity prepare " + str(prepared.get("reason", "")))
			if not prepared.get("ok", false):
				session.free()
				continue
			var identity: Variant = prepared.identity
			var model_snapshot: Dictionary = prepared.snapshot
			var snapshot_bytes := var_to_bytes(model_snapshot)
			_check(model_snapshot.is_read_only() and prepared.weather.is_read_only(), label + ": snapshots read-only")
			var weather: Dictionary = _native.prepare_weather_guard(session, prepared.weather_identity)
			_check(weather.get("ok", false) and _native.weather_guard_matches(session), label + ": weather guard")
			if not _prepare_guard(session, identity, label):
				session.free()
				continue
			var stage: Dictionary = _native.prepare_heli_stage(model_snapshot, prepared.weather)
			_check(stage.get("ok", false), label + ": native stage accepted exact snapshot: " + str(stage.get("error", "")))
			_check_fields(session, session, NativeConfiguration.HELICOPTER_SESSION_FIELDS, label + ": session")
			_check_fields(session, session.environment, NativeConfiguration.ENVIRONMENT_FIELDS, label + ": environment")
			_check_fields(session, session.sim, NativeConfiguration.SIM_FIELDS, label + ": simulation")
			_check_fields(session, session.sim.model, NativeConfiguration.VEHICLE_FIELDS, label + ": vehicle")
			_check(snapshot_bytes == var_to_bytes(model_snapshot), label + ": detached snapshot")
			_check_nested_helicopter(session, label)
			_check_sizes_and_owners(session, label)
			var previous: Callable = session.sim.model.stage
			session.sim.model.stage = func(_body: PackedFloat64Array, _values: PackedFloat64Array, _time: float) -> Dictionary: return {}
			_check(_native.configuration_guard_matches(session), label + ": installed stage checked separately")
			var refused: Dictionary = _native.prepare_configuration_guard(session, identity)
			_check(not refused.get("ok", true) and not _native.configuration_guard_matches(session),
				label + ": wrong reference stage refused and disarmed")
			session.sim.model.stage = previous
			if not _prepare_guard(session, identity, label + ": restored stage"):
				session.free()
				continue
			session.sim.step()
			_check(session.sim.tick == 1 and not session.sim.paused and session.sim.fault_reason.is_empty(),
				label + ": reference tick")
			_check(_native.configuration_guard_matches(session) and _native.weather_guard_matches(session),
				label + ": guards match after reference tick")
			session.free()


func _check_nested_helicopter(session: Node, label: String) -> void:
	var aircraft: Dictionary = session.aircraft
	var context: Dictionary = aircraft.context
	aircraft.context = context.duplicate(true)
	_check(not _native.configuration_guard_matches(session), label + ": equal context replacement")
	aircraft.context = context
	_check(_native.configuration_guard_matches(session), label + ": context restored")
	# Rotorcraft physics contexts are intentionally read-only. Only mutate an
	# actually writable scalar in the live aircraft/trim containers.
	var zero := _find_zero(aircraft)
	if zero.is_empty(): zero = _find_zero(session._trim)
	if not zero.is_empty():
		zero.parent[zero.key] = _negative_zero if atan2(float(zero.old), -1.0) > 0.0 else 0.0
		_check(not _native.configuration_guard_matches(session), label + ": scalar zero sign changed")
		zero.parent[zero.key] = zero.old
		_check(_native.configuration_guard_matches(session), label + ": scalar zero restored")
	var inertia: PackedFloat64Array = session.sim.inertia
	var found_packed := false
	for index: int in inertia.size():
		if inertia[index] == 0.0:
			var changed := inertia.duplicate()
			changed[index] = _negative_zero if atan2(inertia[index], -1.0) > 0.0 else 0.0
			session.sim.inertia = changed
			_check(not _native.configuration_guard_matches(session), label + ": packed zero sign changed")
			session.sim.inertia = inertia
			_check(_native.configuration_guard_matches(session), label + ": packed zero restored")
			found_packed = true
			break
	_check(found_packed, label + ": found actual packed zero")
