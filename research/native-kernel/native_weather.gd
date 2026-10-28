## NK-3 draft weather ownership boundary. Preparation validates and detaches a
## snapshot once; matches only reads the live provider and captured values.
## No weather equation, rebuild, serialization, or hashing runs in matches.
extends RefCounted

const WeatherAdapter := preload("weather_adapter.gd")

const FIELD_VALUES := [
	"_config", "_atmosphere", "_atmosphere_active", "_vertical_air", "_rho", "_engine_charge",
	"_mean_ned", "_gust_ned", "_gust_duration_s", "_gust_period_s", "_gust_delay_s", "_has_gust",
	"_calm", "_turbulent", "_turbulence_rms", "_turbulence_tau", "_turbulence_seed",
]
const SPATIAL_VALUES := [
	"_config", "_reference_speed", "_roughness_length", "_displacement_height", "_wall_height", "_surface_top",
	"_free_air_join_height", "_direction_cosine", "_direction_sine", "_log_denominator", "_wall_scale",
	"_wall_scale_slope", "_gust_transition_height", "_gust_values", "_gust_max_duration", "_turbulence_rms", "_modes",
]
const THERMAL_VALUES := ["_config"]


class Identity:
	extends RefCounted
	var session: Node
	var session_script: Script
	var sim: Node
	var model: RefCounted
	var environment: RefCounted
	var environment_script: Script
	var field: RefCounted
	var field_script: Script
	var spatial: RefCounted
	var spatial_script: Script
	var thermal: RefCounted
	var thermal_script: Script
	var turbulence: Callable
	var dt: float
	var turbulence_index: int
	var turbulence_aux_index: int
	var aux_size: int
	var field_values: Dictionary
	var spatial_values: Dictionary
	var thermal_values: Dictionary


## A detached snapshot for the native decoder and an independent live guard.
## Rebuilding/serializing validated reference weather is allowed only here.
static func prepare(session: Node) -> Dictionary:
	var captured := WeatherAdapter.provider_identity(session)
	if not captured.get("ok", false):
		return {ok = false, reason = str(captured.get("reason", "weather provider refused"))}
	var identity := Identity.new()
	identity.session = session
	identity.session_script = session.get_script()
	identity.sim = session.sim
	identity.model = session.sim.model
	identity.environment = captured.environment
	identity.environment_script = identity.environment.get_script()
	identity.field = captured.field
	identity.field_script = identity.field.get_script()
	identity.spatial = captured.spatial
	identity.thermal = captured.thermal
	if identity.spatial != null:
		identity.spatial_script = identity.spatial.get_script()
	if identity.thermal != null:
		identity.thermal_script = identity.thermal.get_script()
	identity.turbulence = captured.turbulence
	identity.dt = captured.dt
	identity.turbulence_index = captured.turbulence_index
	identity.turbulence_aux_index = session._turbulence_aux_index
	identity.aux_size = session.sim.aux.size()
	identity.field_values = _capture_values(identity.field, FIELD_VALUES)
	identity.spatial_values = _capture_values(identity.spatial, SPATIAL_VALUES) if identity.spatial != null else {}
	identity.thermal_values = _capture_values(identity.thermal, THERMAL_VALUES) if identity.thermal != null else {}
	var snapshot: Dictionary = captured.prepared_snapshot.duplicate(true)
	_freeze_containers(snapshot)
	return {ok = true, snapshot = snapshot, identity = identity}


## The owner calls this before consuming a native tick. It checks provider and
## callback identity, layout and every live weather input without computing
## weather, allocating snapshots, serializing data, or calling into native code.
static func matches(session: Node, identity: Variant) -> bool:
	if not identity is Identity or session == null or not is_instance_valid(session) \
			or session != identity.session or session.get_script() != identity.session_script:
		return false
	if session.sim == null or not is_instance_valid(session.sim) or session.sim != identity.sim \
			or session.sim.model != identity.model or session._weather_pending_reset:
		return false
	if not _same_float(session.sim.dt(), identity.dt) or session.sim.aux.size() != identity.aux_size \
			or session._turbulence_aux_index != identity.turbulence_aux_index:
		return false
	var environment: RefCounted = session.environment
	if environment == null or not is_instance_valid(environment) or environment != identity.environment \
			or environment.get_script() != identity.environment_script or environment.turbulence != identity.turbulence:
		return false
	var field: RefCounted = environment.weather
	if field == null or not is_instance_valid(field) or field != identity.field \
			or field.get_script() != identity.field_script or not _values_match(field, identity.field_values):
		return false
	var spatial: Variant = field.get("_spatial")
	if spatial != identity.spatial:
		return false
	if spatial != null:
		if not is_instance_valid(spatial) or spatial.get_script() != identity.spatial_script \
				or not _values_match(spatial, identity.spatial_values):
			return false
		var thermal: Variant = spatial.get("_thermal_field")
		if thermal != identity.thermal:
			return false
		if thermal != null and (not is_instance_valid(thermal) or thermal.get_script() != identity.thermal_script \
				or not _values_match(thermal, identity.thermal_values)):
			return false
	return true


static func _capture_values(provider: RefCounted, fields: Array) -> Dictionary:
	var out := {}
	for key: String in fields:
		var value: Variant = provider.get(key)
		if value is Dictionary or value is Array:
			value = value.duplicate(true)
		elif typeof(value) in [TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_INT64_ARRAY,
				TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_STRING_ARRAY]:
			value = value.duplicate()
		out[key] = value
	_freeze_containers(out)
	return out


## Dictionary and Array are reference types. Make each detached container
## read-only; packed arrays retain Godot's copy-on-write value semantics.
static func _freeze_containers(value: Variant) -> void:
	if value is Dictionary:
		for key: Variant in value:
			_freeze_containers(value[key])
		value.make_read_only()
	elif value is Array:
		for item: Variant in value:
			_freeze_containers(item)
		value.make_read_only()


static func _values_match(provider: RefCounted, saved: Dictionary) -> bool:
	for key: String in saved:
		if not _same_value(provider.get(key), saved[key]):
			return false
	return true


## PackedFloat arrays compare bytes in the pinned engine, unlike scalar float
## equality. atan2 distinguishes +0 and -0 without a temporary byte buffer;
## it is only a sign test, never a weather or atmosphere calculation.
static func _same_float(left: float, right: float) -> bool:
	if left != right:
		return false
	return left != 0.0 or atan2(left, -1.0) == atan2(right, -1.0)


static func _same_value(left: Variant, right: Variant) -> bool:
	if typeof(left) != typeof(right):
		return false
	match typeof(left):
		TYPE_FLOAT:
			return _same_float(left, right)
		TYPE_DICTIONARY:
			if left.size() != right.size():
				return false
			for key: Variant in right:
				if not left.has(key) or not _same_value(left[key], right[key]):
					return false
			return true
		TYPE_ARRAY:
			if left.size() != right.size():
				return false
			for index: int in right.size():
				if not _same_value(left[index], right[index]):
					return false
			return true
		_:
			return left == right
