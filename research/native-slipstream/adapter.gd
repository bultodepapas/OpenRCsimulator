# Gate P experiment only. Installed into a temporary project by run.py.
extends RefCounted
const Oracle := preload("res://physics/slipstream.gd")
const Propulsion := preload("res://physics/propulsion.gd")
static var backend: Object

static func available() -> bool:
	if backend == null:
		if not ClassDB.class_exists("OpenRCNativeSlipstream"):
			GDExtensionManager.load_extension("res://tests/gate_p/slipstream.gdextension")
		if ClassDB.class_exists("OpenRCNativeSlipstream"):
			backend = ClassDB.instantiate("OpenRCNativeSlipstream")
	return backend != null

static func loads(state: PackedFloat64Array, air: Dictionary, d: Dictionary, model: Dictionary,
		rpm: float, rho: float) -> PackedFloat64Array:
	if rpm < Propulsion.STOPPED_RPM:
		return PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	if not available():
		return PackedFloat64Array([NAN, NAN, NAN, NAN, NAN, NAN])
	var tq: PackedFloat64Array = Propulsion.thrust_torque(air.v_air, rpm, model.propulsion, rho)
	var result: PackedFloat64Array = backend.tail_loads(state, air.v_air, d, model,
		PackedFloat64Array([tq[0], tq[1]]), rho)
	# Dynamics indexes six components before the simulation finiteness guard runs.
	# Signal refusal through that guard without an out-of-bounds engine error.
	if result.size() != 6:
		return PackedFloat64Array([NAN, NAN, NAN, NAN, NAN, NAN])
	return result

# Preserve the benchmark's diagnostic helpers. Only loads is replaced by native code.
static func wake(v: PackedFloat64Array, thrust: float, torque: float, prop: Dictionary, rho: float) -> Dictionary:
	return Oracle.wake(v, thrust, torque, prop, rho)

static func immersion(piece: Dictionary, w: Dictionary, hub: PackedFloat64Array, prop: Dictionary,
		v: PackedFloat64Array, speed: float, model: Dictionary, shaft_axis := PackedFloat64Array()) -> Dictionary:
	return Oracle.immersion(piece, w, hub, prop, v, speed, model, shaft_axis)
