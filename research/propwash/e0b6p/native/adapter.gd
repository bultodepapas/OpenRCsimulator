# E0b6p research adapter. Install only into a disposable app copy.
extends RefCounted

const Oracle = preload("res://physics/slipstream.gd")
const Propulsion = preload("res://physics/propulsion.gd")
const Aero = preload("res://physics/aero.gd")
const EXTENSION_PATH: String = "res://tests/e0b6p_native/smooth_wake.gdextension"
const NATIVE_CLASS: StringName = &"OpenRCSmoothWake"

static var backend: Object = null
static var _load_attempted: bool = false
static var route_counts: Dictionary = {"native": 0, "kernel_calls": 0, "legacy": 0, "refused": 0}


static func available() -> bool:
	if backend != null and is_instance_valid(backend):
		return true
	if not ClassDB.class_exists(NATIVE_CLASS) and not _load_attempted:
		_load_attempted = true
		GDExtensionManager.load_extension(EXTENSION_PATH)
	if not ClassDB.class_exists(NATIVE_CLASS):
		return false
	var candidate: Variant = ClassDB.instantiate(NATIVE_CLASS)
	backend = candidate as Object
	return backend != null


static func reset_route_counts() -> void:
	route_counts = {"native": 0, "kernel_calls": 0, "legacy": 0, "refused": 0}


## Mirrors Slipstream.loads. Smooth profiles use the native whole-load kernel; legacy geometry stays byte-for-byte
## on the GDScript implementation. Native refusal is surfaced as six NaNs so Simulation's finite-load guard faults.
static func loads(state: PackedFloat64Array, air: Dictionary, d: Dictionary, model: Dictionary, rpm: float,
		rho: float, downwash_cl: float = NAN, transported_dv: PackedFloat64Array = PackedFloat64Array()) -> PackedFloat64Array:
	var prop: Dictionary = model.propulsion
	var slipstream: Dictionary = prop.get("slipstream", {})
	if slipstream.is_empty() or not slipstream.has("edge_fraction"):
		route_counts["legacy"] = int(route_counts["legacy"]) + 1
		return Oracle.loads(state, air, d, model, rpm, rho, downwash_cl, transported_dv)

	route_counts["native"] = int(route_counts["native"]) + 1
	var velocity: PackedFloat64Array = air.v_air
	if rpm < Propulsion.STOPPED_RPM and transported_dv.is_empty():
		return _zero_loads()
	var fade: float = Oracle.reverse_weight(velocity, rpm, prop)
	if not transported_dv.is_empty() and rpm < Propulsion.STOPPED_RPM:
		fade = 1.0 if velocity[0] >= 0.0 else 0.0
	if fade == 0.0:
		return _zero_loads()
	if not available():
		route_counts["refused"] = int(route_counts["refused"]) + 1
		return _non_finite_loads()
	var tq_full: PackedFloat64Array = Propulsion.thrust_torque(velocity, rpm, prop, rho)
	var thrust_torque: PackedFloat64Array = PackedFloat64Array([tq_full[0], tq_full[1]])
	var resolved_downwash: float = downwash_cl
	if is_nan(resolved_downwash) and model.surfaces.horizontal.has("free_slope"):
		resolved_downwash = Aero.wing_lift_coefficient(state, air, d, model)
	route_counts["kernel_calls"] = int(route_counts["kernel_calls"]) + 1
	var result: Variant = backend.call("loads", state, velocity, d, model, thrust_torque, rho, fade,
		resolved_downwash, transported_dv)
	if result is PackedFloat64Array and result.size() == 6 and _all_finite(result):
		return result
	route_counts["refused"] = int(route_counts["refused"]) + 1
	return _non_finite_loads()


static func _non_finite_loads() -> PackedFloat64Array:
	return PackedFloat64Array([NAN, NAN, NAN, NAN, NAN, NAN])


static func _zero_loads() -> PackedFloat64Array:
	return PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])


static func _all_finite(values: PackedFloat64Array) -> bool:
	for value: float in values:
		if not is_finite(value):
			return false
	return true


## Oracle forwards retained for research diagnostics that replace only the Slipstream preload.
static func wake(v: PackedFloat64Array, thrust: float, torque: float, prop: Dictionary, rho: float) -> Dictionary:
	return Oracle.wake(v, thrust, torque, prop, rho)


static func reverse_weight(v: PackedFloat64Array, rpm: float, prop: Dictionary) -> float:
	return Oracle.reverse_weight(v, rpm, prop)


static func immersion(piece: Dictionary, w: Dictionary, hub: PackedFloat64Array, prop: Dictionary,
		v: PackedFloat64Array, speed: float, model: Dictionary, shaft_axis: PackedFloat64Array = PackedFloat64Array()) -> Dictionary:
	return Oracle.immersion(piece, w, hub, prop, v, speed, model, shaft_axis)


static func profile_moments(profile: PackedFloat64Array, along: float, d2: float, rs: float, edge: float) -> PackedFloat64Array:
	return Oracle.profile_moments(profile, along, d2, rs, edge)
