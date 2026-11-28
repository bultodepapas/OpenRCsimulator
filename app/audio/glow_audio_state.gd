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


## GlowFlight.Vibration.evaluate(...). NK-6s: for a read-only prepared geometry that evaluate's own check accepted
## once, the native kernel computes the numbers (evaluate cost 10-16 µs per frame) and this assembles the same read-only
## dictionary; any refusal, and every other case, runs evaluate for its exact answer.
static func vibration(prepared: Dictionary, crank_phase: float, omega: float, alpha: float, firing: float) -> Dictionary:
	var geometry: Variant = prepared.get("prepared", null)
	var kernel := _vibration_kernel()
	if kernel != null and prepared.get("ok", false) and geometry is Dictionary and (geometry as Dictionary).is_read_only():
		if not is_same(geometry, _checked_geometry) and GlowFlight.Vibration._valid_prepared(geometry):
			_checked_geometry = geometry
		if is_same(geometry, _checked_geometry):
			var cycle: int = int(geometry.cycle_revolutions)
			var r: PackedFloat64Array = kernel.glow_vibration(PackedFloat64Array([float(geometry.crank_radius_m),
				float(geometry.connecting_rod_m), float(geometry.reciprocating_mass_kg),
				float(geometry.cosine_1x_displacement_m), float(geometry.cosine_2x_displacement_m), float(cycle)]),
				crank_phase, omega, alpha, firing)
			if r.size() == 11 and r[0] == 1.0:
				var result: Dictionary = {
					ok = true,
					errors = PackedStringArray(),
					family = geometry.family,
					cycle_revolutions = cycle,
					firing_order = 1.0 / float(cycle),
					phase_rad = r[1],
					omega_rad_s = omega,
					alpha_rad_s2 = alpha,
					constant_speed_assumption = alpha == 0.0,
					source_force_n = r[2],
					order_1x_force_cosine_n = r[3],
					order_1x_force_sine_n = r[4],
					order_2x_force_cosine_n = r[5],
					order_2x_force_sine_n = r[6],
					order_1x_force_peak_n = r[7],
					order_2x_force_peak_n = r[8],
					opportunity_frequency_hz = r[9],
					mean_successful_fire_rate_hz = r[10],
				}
				result.make_read_only()
				return result
	return GlowFlight.Vibration.evaluate(prepared, crank_phase, omega, alpha, firing)


## NK-6s test hook: false always runs GlowFlight.Vibration.evaluate.
static var native_vibration_enabled := true
static var _kernel: Object = null
static var _kernel_unavailable := false
static var _checked_geometry: Variant = null # the read-only prepared geometry evaluate's check accepted (main thread)


static func _vibration_kernel() -> Object:
	if not native_vibration_enabled:
		return null
	if _kernel == null and not _kernel_unavailable and ClassDB.class_exists(&"OpenRCNativeKernel"):
		var candidate: Object = ClassDB.instantiate(&"OpenRCNativeKernel")
		if candidate != null and candidate.has_method(&"glow_vibration"):
			_kernel = candidate
		else:
			_kernel_unavailable = true
	return _kernel


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
		source_vibration = vibration(prepared, values[6] * TAU, values[0] * TAU / 60.0, 0.0, firing if running else 0.0),
	}
