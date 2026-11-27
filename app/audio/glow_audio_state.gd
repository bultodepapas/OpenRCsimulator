extends RefCounted
## F5b: the glow keys flight audio reads (GlowAudioPump.TELEMETRY_KEYS) at the accepted endpoint, with the values
## GlowFlight.telemetry gives them, built from the accepted state and the native glow stage's firing fraction
## (FlightSession.presented_glow_firing) instead of telemetry's full point() evaluation: about 350 µs per frame on a glow
## aircraft. Telemetry has no max_rpm, load or throttle key, so neither has this; flight audio supplies those.
## Empty: the caller evaluates session.glow_state().

const GlowFlight := preload("res://physics/glow/flight.gd")
const GlowProp := preload("res://physics/glow/propeller.gd")
const Propulsion := preload("res://physics/propulsion.gd")
const M := preload("res://physics/math3d.gd")


## [Propulsion.thrust_torque(v_air, rpm, prop, rho)[1], Propulsion.prop_torque(rpm, 0.0, prop, rho)] for flight
## audio's shaft load. For a glow propeller both rebuild and validate a blade evaluator on every call (about 20 µs
## each). The native glow stage's blade model answers both (FlightSession.presented_glow_blade_torques); otherwise, in
## a frozen native flight (NK-6p), the evaluator GlowFlight prepared from the same installation at reset answers with
## the same arithmetic and the same query checks.
static func shaft_torques(session: Node, prop: Dictionary, v_air: PackedFloat64Array, rpm: float) -> PackedFloat64Array:
	var rho: float = session.air_density()
	if Propulsion.is_glow(prop) and session.has_method("presented_glow_blade_torques"):
		var native: PackedFloat64Array = session.presented_glow_blade_torques(rpm, M.dot(v_air, Propulsion.axis(prop)), rho)
		if native.size() == 2:
			return native
	if Propulsion.is_glow(prop) and session.aircraft.is_read_only() \
			and session.has_meta(GlowFlight.PROPELLER_EVALUATOR_META) \
			and session.get_meta(GlowFlight.EVALUATOR_IDENTITY_META, {}) == prop.glow.identity:
		var evaluator: Variant = session.get_meta(GlowFlight.PROPELLER_EVALUATOR_META)
		var moving: Dictionary = GlowProp.evaluate_prepared(evaluator, rpm, M.dot(v_air, Propulsion.axis(prop)), rho)
		var still: Dictionary = GlowProp.evaluate_prepared(evaluator, rpm, 0.0, rho)
		return PackedFloat64Array([moving.torque_nm if moving.ok else NAN, still.torque_nm if still.ok else NAN])
	return PackedFloat64Array([Propulsion.thrust_torque(v_air, rpm, prop, rho)[1], Propulsion.prop_torque(rpm, 0.0, prop, rho)])


static func build(session: Node) -> Dictionary:
	var firing: float = session.presented_glow_firing()
	if not is_finite(firing):
		return {}
	var values: PackedFloat64Array = session.sim.continuous
	var install: Dictionary = session.aircraft.model.propulsion.glow
	var state: Dictionary = GlowFlight.unpack(values, install)
	# point() replaces an empty tank's amount with its connected trial value; telemetry then reports that instead.
	if state.is_empty() or not (float(state.fuel_kg) > 0.0):
		return {}
	var prepared: Dictionary = session.get_meta(GlowFlight.VIBRATION_EVALUATOR_META, {})
	if session.get_meta(GlowFlight.EVALUATOR_IDENTITY_META, {}) != install.identity or prepared.is_empty():
		return {}
	var running: bool = bool(state.running) and float(state.fuel_kg) > float(install.get("unusable_fuel_kg", 0.0))
	return {
		ok = true,
		family = state.family,
		rpm = values[0],
		running = running,
		firing_fraction = firing,
		blade_count = install.propeller.blades,
		phase_revolutions = state.phase_revolutions,
		opportunity_count = state.opportunity_count,
		fire_count = state.fire_count,
		firing_accumulator = state.firing_accumulator,
		fuel_kg = state.fuel_kg,
		source_vibration = GlowFlight.Vibration.evaluate(prepared, values[6] * TAU, values[0] * TAU / 60.0, 0.0,
			firing if running else 0.0),
	}
