# E0b5: first-order axial speed transport, one float64 state per neutral tail piece.
# Source-model approximation, not a pure dead time or measured Stik calibration.
# Selig 2010 §III: lag time depends on disc flow speed and propeller-to-surface distance.
# Geometry, reverse occupancy and wash direction remain instantaneous. Swirl is excluded by the loader.
extends RefCounted

const Slipstream = preload("res://physics/slipstream.gd")
const Propulsion = preload("res://physics/propulsion.gd")


static func enabled(prop: Dictionary) -> bool:
	return prop.get("slipstream", {}).has("transport_speed_floor")


## [equilibrium increment (m/s), convection speed (m/s)]. The positive floor is an estimated
## zero-flow decay regularizer, declared with provenance; it is not a measured transport velocity.
static func target(v: PackedFloat64Array, rpm: float, prop: Dictionary, rho: float) -> PackedFloat64Array:
	var tq: PackedFloat64Array = Propulsion.thrust_torque(v, rpm, prop, rho)
	var wake: Dictionary = Slipstream.wake(v, tq[0], tq[1], prop, rho)
	var source: float = wake.dv
	if rpm < Propulsion.STOPPED_RPM or Slipstream.reverse_weight(v, rpm, prop) == 0.0:
		source = 0.0
	return PackedFloat64Array([source, maxf(wake.u + wake.w, prop.slipstream.transport_speed_floor)])


static func settled(v: PackedFloat64Array, rpm: float, prop: Dictionary, rho: float) -> PackedFloat64Array:
	var out: PackedFloat64Array = PackedFloat64Array()
	if enabled(prop):
		var values: PackedFloat64Array = target(v, rpm, prop, rho)
		out.resize(prop.slipstream.pieces.size())
		out.fill(values[0])
	return out


## Evaluated at the same RK stage as body loads: dv' = (dv_equilibrium - dv) / tau,
## tau = (piece.root.x - hub.x) / max(u + w_disc, speed_floor). Axial shafts only.
static func derivative(v: PackedFloat64Array, rpm: float, prop: Dictionary, rho: float,
		lagged: PackedFloat64Array) -> PackedFloat64Array:
	var values: PackedFloat64Array = target(v, rpm, prop, rho)
	var out: PackedFloat64Array = lagged.duplicate()
	for i in out.size():
		var distance: float = prop.slipstream.pieces[i].root[0] - prop.slipstream.hub[0]
		out[i] = (values[0] - lagged[i]) * values[1] / distance
	return out


## W05c-R2: same source flow and propeller point as the explicit powered stage. Existing callers retain
## their exact target arithmetic when no point override is present. This does not change the lag law.
static func stage_target(body: PackedFloat64Array, air: Dictionary, rpm: float, prop: Dictionary,
		rho: float) -> PackedFloat64Array:
	if not air.has("propulsion_air_body") and not air.has("wake_source_delta_body"):
		return target(air.v_air, rpm, prop, rho)
	var point := Propulsion.stage_air_velocity(body, air, prop)
	var source := Slipstream.source_air(air)
	if not point.ok or not _finite(source, 3):
		return PackedFloat64Array([NAN, NAN])
	var tq := Propulsion.thrust_torque(point.velocity_body, rpm, prop, rho)
	if not _finite(tq, 3):
		return PackedFloat64Array([NAN, NAN])
	var wake := Slipstream.wake(source, tq[0], tq[1], prop, rho)
	var equilibrium: float = wake.dv
	if rpm < Propulsion.STOPPED_RPM or Slipstream.reverse_weight(source, rpm, prop) == 0.0:
		equilibrium = 0.0
	return PackedFloat64Array([equilibrium, maxf(wake.u + wake.w, prop.slipstream.transport_speed_floor)])


static func stage_derivative(body: PackedFloat64Array, air: Dictionary, rpm: float, prop: Dictionary,
		rho: float, lagged: PackedFloat64Array) -> PackedFloat64Array:
	if not air.has("propulsion_air_body") and not air.has("wake_source_delta_body"):
		return derivative(air.v_air, rpm, prop, rho, lagged)
	var values := stage_target(body, air, rpm, prop, rho)
	var out := lagged.duplicate()
	if not _finite(values, 2) or lagged.size() != prop.slipstream.pieces.size():
		return PackedFloat64Array([NAN])
	for i in out.size():
		var distance: float = prop.slipstream.pieces[i].root[0] - prop.slipstream.hub[0]
		out[i] = (values[0] - lagged[i]) * values[1] / distance
	return out


static func stage_settled(body: PackedFloat64Array, air: Dictionary, rpm: float, prop: Dictionary,
		rho: float) -> PackedFloat64Array:
	if not air.has("propulsion_air_body") and not air.has("wake_source_delta_body"):
		return settled(air.v_air, rpm, prop, rho)
	var out := PackedFloat64Array()
	if enabled(prop):
		var values := stage_target(body, air, rpm, prop, rho)
		if not _finite(values, 2):
			return PackedFloat64Array([NAN])
		out.resize(prop.slipstream.pieces.size())
		out.fill(values[0])
	return out


static func _finite(value: PackedFloat64Array, size: int) -> bool:
	if value.size() != size:
		return false
	for component: float in value:
		if not is_finite(component):
			return false
	return true
