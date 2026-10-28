## NK-3 draft weather ownership boundary. Preparation validates and detaches a
## snapshot once; matches only reads the live provider and captured values.
## No weather equation, rebuild, serialization, or hashing runs in matches.
extends RefCounted

const WeatherAdapter := preload("weather_adapter.gd")
const M := preload("res://physics/math3d.gd")

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


class Watch:
	extends RefCounted
	const CONTAINER := 0
	const ZERO := 1
	const PACKED := 2
	var parent: Variant
	var key: Variant
	var kind: int
	var expected: Variant


class Identity:
	extends RefCounted
	var owner_kind: String = "fixed_wing"
	var session: Node
	var session_script: Script
	var sim: Node
	var sim_script: Script
	var model: RefCounted
	var model_script: Script
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
	var field_roots: Dictionary = {}
	var spatial_roots: Dictionary = {}
	var thermal_roots: Dictionary = {}
	var watches: Array[Watch] = []


## A detached snapshot for the native decoder and an independent live guard.
## Rebuilding/serializing validated reference weather is allowed only here.
static func prepare(session: Node) -> Dictionary:
	# This adapter covers the fixed-wing owner. Rotorcraft use a different
	# session and layout contract and need their own explicit admission.
	if session == null or not is_instance_valid(session) \
			or session.get_script() != load("res://sim/flight_session.gd") \
			or session.sim == null or session.sim.get_script() != load("res://sim/simulation.gd") \
			or session.sim.model == null or session.sim.model.get_script() != load("res://sim/vehicle_model.gd"):
		return {ok = false, reason = "unsupported fixed-wing session or simulation provider"}
	var captured := WeatherAdapter.provider_identity(session)
	if not captured.get("ok", false):
		return {ok = false, reason = str(captured.get("reason", "weather provider refused"))}
	return _prepare_captured(session, captured, "fixed_wing")


## Helicopter sessions support their own subset and have no OU index/pending
## fields. Keep the admission separate instead of fabricating those fields.
static func prepare_helicopter(session: Node) -> Dictionary:
	if session == null or not is_instance_valid(session) \
			or session.get_script() != load("res://sim/helicopter_flight_session.gd") \
			or session.sim == null or session.sim.get_script() != load("res://sim/simulation.gd") \
			or session.sim.model == null or session.sim.model.get_script() != load("res://sim/vehicle_model.gd"):
		return {ok = false, reason = "unsupported helicopter session or simulation provider"}
	var captured := WeatherAdapter.helicopter_provider_identity(session)
	if not captured.get("ok", false):
		return {ok = false, reason = str(captured.get("reason", "helicopter weather provider refused"))}
	return _prepare_captured(session, captured, "helicopter")


static func _prepare_captured(session: Node, captured: Dictionary, owner_kind: String) -> Dictionary:
	var identity := Identity.new()
	identity.owner_kind = owner_kind
	identity.session = session
	identity.session_script = session.get_script()
	identity.sim = session.sim
	identity.sim_script = identity.sim.get_script()
	identity.model = session.sim.model
	identity.model_script = identity.model.get_script()
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
	identity.turbulence_aux_index = session._turbulence_aux_index if owner_kind == "fixed_wing" else -1
	identity.aux_size = session.sim.aux.size()
	identity.field_values = _capture_values(identity.field, FIELD_VALUES, identity.field_roots, identity.watches)
	identity.spatial_values = _capture_values(identity.spatial, SPATIAL_VALUES, identity.spatial_roots,
		identity.watches) if identity.spatial != null else {}
	identity.thermal_values = _capture_values(identity.thermal, THERMAL_VALUES, identity.thermal_roots,
		identity.watches) if identity.thermal != null else {}
	identity.field_roots.make_read_only()
	identity.spatial_roots.make_read_only()
	identity.thermal_roots.make_read_only()
	identity.watches.make_read_only()
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
			or session.sim.get_script() != identity.sim_script or session.sim.model != identity.model \
			or session.sim.model.get_script() != identity.model_script:
		return false
	if identity.owner_kind == "fixed_wing":
		if session._weather_pending_reset or session._turbulence_aux_index != identity.turbulence_aux_index:
			return false
	elif identity.owner_kind == "helicopter":
		if not session._ready_to_fly:
			return false
	else:
		return false
	if not _same_float(session.sim.dt(), identity.dt) or session.sim.aux.size() != identity.aux_size:
		return false
	var environment: RefCounted = session.environment
	if environment == null or not is_instance_valid(environment) or environment != identity.environment \
			or environment.get_script() != identity.environment_script or environment.turbulence != identity.turbulence:
		return false
	var field: RefCounted = environment.weather
	if field == null or not is_instance_valid(field) or field != identity.field \
			or field.get_script() != identity.field_script \
			or not _values_match(field, identity.field_values, identity.field_roots):
		return false
	var spatial: Variant = field.get("_spatial")
	if spatial != identity.spatial:
		return false
	if spatial != null:
		if not is_instance_valid(spatial) or spatial.get_script() != identity.spatial_script \
				or not _values_match(spatial, identity.spatial_values, identity.spatial_roots):
			return false
		var thermal: Variant = spatial.get("_thermal_field")
		if thermal != identity.thermal:
			return false
		if thermal != null and (not is_instance_valid(thermal) or thermal.get_script() != identity.thermal_script \
				or not _values_match(thermal, identity.thermal_values, identity.thermal_roots)):
			return false
	return _watches_match(identity.watches)


static func _capture_values(provider: RefCounted, fields: Array, roots: Dictionary, watches: Array[Watch]) -> Dictionary:
	var out := {}
	for key: String in fields:
		var value: Variant = provider.get(key)
		if value is Dictionary or value is Array:
			roots[key] = value
			_capture_watches(value, watches)
			value = value.duplicate(true)
		elif typeof(value) in [TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_INT64_ARRAY,
				TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_STRING_ARRAY]:
			value = value.duplicate()
		out[key] = value
	_freeze_containers(out)
	return out


## Native deep equality checks ordinary nested value changes efficiently. It
## regards signed zeros as equal, so prepare a short watch list for zero-valued
## floats and packed float arrays. Also pin every container's identity: a
## replacement must not disconnect the captured live references in that list.
static func _capture_watches(container: Variant, watches: Array[Watch]) -> void:
	if container is Dictionary:
		for key: Variant in container:
			_capture_watch(container, key, container[key], watches)
	elif container is Array:
		for index: int in container.size():
			_capture_watch(container, index, container[index], watches)


static func _capture_watch(parent: Variant, key: Variant, child: Variant, watches: Array[Watch]) -> void:
	var kind := -1
	var expected: Variant
	if child is Dictionary or child is Array:
		kind = Watch.CONTAINER
		expected = child
	elif typeof(child) == TYPE_FLOAT and float(child) == 0.0:
		kind = Watch.ZERO
		expected = M.atan2_(float(child), -1.0) > 0.0
	elif typeof(child) in [TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY]:
		kind = Watch.PACKED
		expected = child.duplicate()
	if kind >= 0:
		var watch := Watch.new()
		watch.parent = parent
		watch.key = key
		watch.kind = kind
		watch.expected = expected
		watches.append(watch)
	if kind == Watch.CONTAINER:
		_capture_watches(child, watches)


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


static func _values_match(provider: RefCounted, saved: Dictionary, roots: Dictionary) -> bool:
	for key: String in saved:
		var value: Variant = provider.get(key)
		if roots.has(key):
			if not is_same(value, roots[key]) or value != saved[key]:
				return false
		elif not _same_value(value, saved[key]):
			return false
	return true


static func _watches_match(watches: Array[Watch]) -> bool:
	for watch: Watch in watches:
		var current: Variant = watch.parent[watch.key]
		match watch.kind:
			Watch.CONTAINER:
				if not is_same(current, watch.expected):
					return false
			Watch.ZERO:
				if typeof(current) != TYPE_FLOAT or float(current) != 0.0 \
						or (M.atan2_(float(current), -1.0) > 0.0) != watch.expected:
					return false
			Watch.PACKED:
				if typeof(current) != typeof(watch.expected) or current != watch.expected:
					return false
	return true


## PackedFloat arrays compare bytes in the pinned engine, unlike scalar float
## equality. atan2 distinguishes +0 and -0 without a temporary byte buffer;
## it is only a sign test, never a weather or atmosphere calculation.
static func _same_float(left: float, right: float) -> bool:
	if left != right:
		return false
	return left != 0.0 or M.atan2_(left, -1.0) == M.atan2_(right, -1.0)


static func _same_value(left: Variant, right: Variant) -> bool:
	if typeof(left) != typeof(right):
		return false
	return _same_float(left, right) if typeof(left) == TYPE_FLOAT else left == right
