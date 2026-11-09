extends SceneTree

const Rotor = preload("res://physics/rotorcraft/main_rotor.gd")
const Flight = preload("res://physics/rotorcraft/flight_dynamics.gd")
const Data = preload("res://physics/rotorcraft_data.gd")
const M = preload("res://physics/math3d.gd")
const RB = preload("res://physics/rigid_body.gd")
const Session = preload("res://sim/helicopter_flight_session.gd")
const Weather = preload("res://physics/wind_config.gd")
const ImpactDetector = preload("res://physics/rotorcraft/impact_detector.gd")

var checks: int = 0
var failures: int = 0


func check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", label)


func close(label: String, actual: float, expected: float, tolerance: float = 1.0e-12) -> void:
	check(label, is_finite(actual) and absf(actual - expected) <= tolerance * maxf(1.0, absf(expected)))


# The transition endpoints and pole used here are finite positive binary64s.
func adjacent(value: float, direction: int) -> float:
	var bytes: PackedByteArray = PackedFloat64Array([value]).to_byte_array()
	bytes.encode_u64(0, bytes.decode_u64(0) + direction)
	return bytes.decode_double(0)


func evaluate(model: Dictionary, omega: float, air: PackedFloat64Array) -> Dictionary:
	return Rotor.evaluate(model, omega, 4.0, air, M.v3(0.0, 0.0, 0.0), 0.1, 0.0, 0.0, 0.0, 0.0)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for fixture: Array in [
		["xcell", "res://data/aircraft/xcell_60_research.json", 20.0],
		["hx700 laboratory", "res://data/aircraft/hx700_electric_3d_experimental.json", 25.0],
	]:
		var data: Dictionary = Data.load_file(fixture[1])
		check(str(fixture[0]) + " data loads", data.ok)
		if data.ok:
			_exercise(str(fixture[0]), data.context.main_model, float(fixture[2]))
	_session_reporting()
	print("HELI H02 rotor domain diagnostics: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)


func _exercise(name: String, model: Dictionary, high_crossflow: float) -> void:
	var zero: PackedFloat64Array = M.v3(0.0, 0.0, 0.0)
	var air: PackedFloat64Array = M.v3(high_crossflow, 0.0, 1.0)
	var air_before: PackedByteArray = air.to_byte_array()
	var stopped: Dictionary = Rotor.domain_diagnostics(model, 0.0, air)
	check(name + " stopped ratio unavailable", stopped.ok and stopped.regime == "inactive"
		and stopped.mu_squared == null and not stopped.standard_member_required)
	check(name + " diagnostic retains actual hub vector", stopped.hub_air_velocity_body_frd_m_s == air)
	close(name + " crossflow excludes axial flow", stopped.hub_crossflow_m_s, high_crossflow)
	check(name + " diagnostic input remains unchanged", air.to_byte_array() == air_before)
	air[0] = -high_crossflow
	close(name + " result owns a detached hub vector", stopped.hub_air_velocity_body_frd_m_s[0], high_crossflow)
	air[0] = high_crossflow
	check(name + " numerical algebraic limit is explicitly reported",
		stopped.standard_algebraic_mu_squared_limit == 2.0 and stopped.source_identified_mu_indicator_limit == 0.15)
	for low_crossflow: float in [0.0, 3.0]:
		var low_air: PackedFloat64Array = M.v3(low_crossflow, 0.0, 1.0)
		var low_endpoints: PackedFloat64Array = Rotor.low_rpm_transition(model, low_crossflow)
		for seam: int in [0, 1]:
			for direction: int in [-1, 0, 1]:
				var omega: float = low_endpoints[seam] if direction == 0 else adjacent(low_endpoints[seam], direction)
				var d: Dictionary = Rotor.domain_diagnostics(model, omega, low_air)
				var row: Dictionary = evaluate(model, omega, low_air)
				var expected: String = "startup_only" if omega <= low_endpoints[0] else ("blend" if omega < low_endpoints[1] else "standard")
				check(name + " ordinary seam " + str([low_crossflow, seam, direction]),
					d.ok and d.regime == expected and row.ok
					and d.standard_member_required == (omega > low_endpoints[0]))
	var endpoints: PackedFloat64Array = Rotor.low_rpm_transition(model, high_crossflow)
	close(name + " upper endpoint is capped", endpoints[1], 0.20 * model.omega_nominal_rad_s)
	for seam: int in [0, 1]:
		var point: float = endpoints[seam]
		for direction: int in [-1, 0, 1]:
			var omega: float = point if direction == 0 else adjacent(point, direction)
			var d: Dictionary = Rotor.domain_diagnostics(model, omega, air)
			var expected: String = "startup_only" if omega <= endpoints[0] else ("blend" if omega < endpoints[1] else "standard")
			check(name + " seam classification " + str([seam, direction]), d.ok and d.regime == expected
				and d.standard_member_required == (omega > endpoints[0]))
			if d.ok:
				close(name + " endpoint diagnostic " + str([seam, direction]), d.transition_lower_rad_s, endpoints[0])
				close(name + " head diagnostic " + str([seam, direction]), d.head_speed_rad_s, omega)
				var actual: Dictionary = evaluate(model, omega, air)
				if d.standard_member_required and d.standard_algebraic_mu_valid == false:
					check(name + " required invalid member is refused " + str([seam, direction]), not actual.ok)
	# At the first float above the lower seam the blend weight can round to
	# zero, but the standard member is still evaluated and can refuse.
	var first_blend: float = adjacent(endpoints[0], 1)
	var first: Dictionary = Rotor.domain_diagnostics(model, first_blend, air)
	check(name + " invalid member activates immediately above lower seam", first.standard_member_required
		and first.standard_weight == 0.0 and first.standard_algebraic_mu_valid == false
		and not evaluate(model, first_blend, air).ok)
	# Locate floats on either side of the algebraic pole without treating either
	# the pole margin or the source μ indicator as a physical flight envelope.
	var pole: float = high_crossflow / (sqrt(2.0) * model.rotor_radius_m)
	var lower: float = pole
	var upper: float = pole
	for _i: int in range(8):
		lower = adjacent(lower, -1)
		upper = adjacent(upper, 1)
	var invalid: Dictionary = Rotor.domain_diagnostics(model, lower, air)
	var valid: Dictionary = Rotor.domain_diagnostics(model, upper, air)
	check(name + " pole has a refused side", invalid.regime == "blend"
		and invalid.standard_algebraic_mu_valid == false and not evaluate(model, lower, air).ok)
	check(name + " pole has an accepted algebraic side", valid.regime == "blend"
		and valid.standard_algebraic_mu_valid == true and valid.pole_factor > 0.0
		and evaluate(model, upper, air).ok)
	var near_pole: float = pole * (1.0 + 1.0e-6)
	var near: Dictionary = Rotor.domain_diagnostics(model, near_pole, air)
	var near_load: Dictionary = evaluate(model, near_pole, air)
	check(name + " positive pole margin remains extremely small", near.ok and near.pole_factor > 0.0
		and near.pole_factor < 3.0e-6 and near.standard_weight > 0.0 and not near.mu_below_source_indicator)
	check(name + " accepted local flap derivative is large", near_load.ok and absf(near_load.flap_rate_a1_rad_s) > 100.0)
	var opposite_air: PackedFloat64Array = M.v3(-high_crossflow, 0.0, -1.0)
	var opposite: Dictionary = Rotor.domain_diagnostics(model, near_pole, opposite_air)
	var opposite_load: Dictionary = evaluate(model, near_pole, opposite_air)
	check(name + " signed hub components retained", opposite.ok and opposite.hub_air_velocity_body_frd_m_s == opposite_air
		and opposite.mu_z < 0.0)
	close(name + " crossflow square is sign independent", opposite.mu_squared, near.mu_squared)
	var negative_axial: Dictionary = evaluate(model, near_pole, M.v3(high_crossflow, 0.0, -1.0))
	var zero_axial: Dictionary = evaluate(model, near_pole, M.v3(high_crossflow, 0.0, 0.0))
	check(name + " signed pole probes evaluate", opposite_load.ok and negative_axial.ok and zero_axial.ok)
	if near_load.ok and negative_axial.ok and zero_axial.ok:
		close(name + " pole contribution reverses with axial flow",
			near_load.flap_rate_a1_rad_s - zero_axial.flap_rate_a1_rad_s,
			-(negative_axial.flap_rate_a1_rad_s - zero_axial.flap_rate_a1_rad_s), 1.0e-10)
	# Underflow or overflow in a derived ratio is represented as unavailable,
	# without changing the active startup-law calculation.
	var tiny: Dictionary = Rotor.domain_diagnostics(model, 1.0e-300, M.v3(3.0, 0.0, 0.0))
	check(name + " overflowing derived ratio is unavailable", tiny.ok and tiny.regime == "startup_only"
		and tiny.mu_squared == null and tiny.standard_algebraic_mu_valid == null)
	check(name + " negative and nonfinite inputs refused",
		not Rotor.domain_diagnostics(model, -1.0, zero).ok
		and not Rotor.domain_diagnostics(model, NAN, zero).ok
		and not Rotor.domain_diagnostics(model, 1.0, M.v3(0.0, INF, 0.0)).ok
		and not Rotor.domain_diagnostics(model, 1.0, PackedFloat64Array()).ok
		and not Rotor.domain_diagnostics(model.duplicate(), 1.0, zero).ok)
	# Flight checks the same actual hub air velocity, including rate × arm.
	var cg: PackedFloat64Array = M.v3(high_crossflow - 1.0, 0.0, 1.0)
	var rate: PackedFloat64Array = M.v3(0.0, -1.0 / absf(model.hub_z_m), 0.0)
	var arm: PackedFloat64Array = M.v3(model.hub_x_m, model.hub_y_m, model.hub_z_m)
	var hub: PackedFloat64Array = M.add(cg, M.cross(rate, arm))
	var hub_diag: Dictionary = Rotor.domain_diagnostics(model, near_pole, hub)
	check(name + " diagnostics accept the same stage hub airflow used by the flight precheck", hub_diag.ok
		and hub_diag.hub_air_velocity_body_frd_m_s == hub
		and Flight._main_rotor_domain(model, near_pole, cg, rate) == hub_diag.standard_algebraic_mu_valid)
	close(name + " body-rate contribution changes the hub crossflow", hub_diag.hub_crossflow_m_s, high_crossflow)


func _session_reporting() -> void:
	var session: Node = Session.new()
	session.input_enabled = false
	session.physics_enabled = false
	root.add_child(session)
	check("reference session prepares with steady wind", session.setup() \
		and session.setup_weather(Weather.preset("steady")) and session.reset())
	if not session.is_flyable():
		print("Session setup refused: ", session.start_error)
		session.free()
		return
	var trial: PackedFloat64Array = session.sim.state.duplicate()
	var attitude: PackedFloat64Array = M.q_from_euler(0.35, 0.12, -0.08)
	for i: int in 4: trial[RB.ATT + i] = attitude[i]
	trial[RB.VEL] = 21.0
	trial[RB.VEL + 1] = 1.0
	trial[RB.VEL + 2] = 0.4
	trial[RB.RATE] = 0.2
	trial[RB.RATE + 1] = -4.0
	trial[RB.RATE + 2] = 0.3
	var continuous: PackedFloat64Array = session.sim.continuous.duplicate()
	var model: Dictionary = session.aircraft.context.main_model
	continuous[0] = model.omega_nominal_rad_s * 0.105
	var wind: PackedFloat64Array = session.wind_at(session.sim.time(), trial)
	var qnorm: float = sqrt(M.dot(attitude.slice(1, 4), attitude.slice(1, 4)) + attitude[0] * attitude[0])
	for i: int in 4: attitude[i] /= qnorm
	var body_velocity: PackedFloat64Array = trial.slice(RB.VEL, RB.VEL + 3)
	var air_cg: PackedFloat64Array = M.q_rotate(M.q_conj(attitude), \
		M.sub(M.q_rotate(attitude, body_velocity), wind))
	var arm: PackedFloat64Array = M.v3(model.hub_x_m, model.hub_y_m, model.hub_z_m)
	var hub: PackedFloat64Array = M.add(air_cg, M.cross(trial.slice(RB.RATE, RB.RATE + 3), arm))
	var expected: Dictionary = Rotor.domain_diagnostics(model, continuous[0], hub)
	var invalid_continuous: PackedFloat64Array = continuous.duplicate()
	check("trial has active invalid blend using actual hub airflow", expected.ok and expected.regime == "blend" \
		and expected.standard_member_required and expected.standard_algebraic_mu_valid == false \
		and hub.to_byte_array() != air_cg.to_byte_array() and M.norm(wind) > 0.0)
	var accepted_body: PackedByteArray = session.sim.state.to_byte_array()
	var accepted_continuous: PackedByteArray = session.sim.continuous.to_byte_array()
	var accepted_tick: int = session.sim.tick
	# Inject a detached RK trial while the real accepted frame remains intact.
	session.sim.model.stage = func(_body: PackedFloat64Array, _continuous: PackedFloat64Array, time: float) -> Dictionary:
		return session._stage(trial, continuous, time)
	session.sim.step()
	var diagnostic: Dictionary = session.stage_domain_diagnostics()
	check("refused trial rolls back and publishes a pause reason", session.sim.paused \
		and session.sim.tick == accepted_tick and session.sim.state.to_byte_array() == accepted_body \
		and session.sim.continuous.to_byte_array() == accepted_continuous \
		and session.pause_reason.contains("Hub air-relative FRD") and session.pause_reason.contains("algebraic mu²") \
		and session.pause_reason.contains("not a validated aircraft limit"))
	check("runtime receipt matches failed trial hub-domain API", var_to_bytes(diagnostic) == var_to_bytes(expected))
	check("reference-native oracle failure message remains unchanged", \
		session._stage_failure == "main-rotor advance ratio exceeds the kernel domain at this speed")
	if diagnostic.get("ok", false):
		diagnostic.hub_air_velocity_body_frd_m_s[0] += 100.0
		check("runtime receipt is detached", \
			session.stage_domain_diagnostics().hub_air_velocity_body_frd_m_s.to_byte_array() == hub.to_byte_array())
	continuous[0] = -1.0
	session._stage(trial, continuous, session.sim.time())
	check("direct trial does not replace the published fault receipt", var_to_bytes(session.stage_domain_diagnostics()) == var_to_bytes(expected) \
		and session._stage_failure.contains("crossed zero speed"))
	session.sim.model.stage = Callable(session, "_stage")
	check("accepted reset clears the published domain fault", session.reset() and session.stage_domain_diagnostics().is_empty())
	session.sim.model.stage = func(_body: PackedFloat64Array, _continuous: PackedFloat64Array, time: float) -> Dictionary:
		return session._stage(trial, continuous, time)
	session.sim.step()
	check("unrelated terminal refusal clears the prior domain receipt", session.stage_domain_diagnostics().is_empty() \
		and not session.pause_reason.contains("Hub air-relative FRD"))
	session.free()
	_second_stage_precedence(trial, invalid_continuous, expected)


func _second_stage_precedence(trial: PackedFloat64Array, invalid_continuous: PackedFloat64Array, expected: Dictionary) -> void:
	var session: Node = Session.new()
	session.input_enabled = false
	session.physics_enabled = false
	root.add_child(session)
	check("second-stage fixture prepares steady reference hover", session.setup() \
		and session.setup_weather(Weather.preset("steady")) and session.reset())
	if not session.is_flyable():
		session.free()
		return
	var accepted_body: PackedFloat64Array = session.sim.state.duplicate()
	var accepted_continuous: PackedFloat64Array = session.sim.continuous.duplicate()
	var accepted_tick: int = session.sim.tick
	session._impact_geometry = {ok = false, error = "injected contact refusal"}
	var contact: Dictionary = ImpactDetector.evaluate(accepted_body, accepted_body, accepted_continuous,
		session.aircraft.context, session.aircraft.skids, session.ground_surfaces, session.shaft_phase,
		session._collision_world, session._impact_geometry, session.environment.lake)
	check("competing prepared contact geometry actually refuses", not contact.ok \
		and contact.error == "injected contact refusal")
	var calls := [0]
	var first_ok := [false]
	var second_refused := [false]
	session.sim.model.stage = func(body: PackedFloat64Array, continuous: PackedFloat64Array, time: float) -> Dictionary:
		calls[0] += 1
		if calls[0] == 1:
			var first: Dictionary = session._stage(body, continuous, time)
			first_ok[0] = not first.is_empty()
			return first
		var second: Dictionary = session._stage(trial, invalid_continuous, time)
		second_refused[0] = second.is_empty()
		return second
	session.sim.step()
	check("first stage succeeds and second RK stage refuses", calls[0] == 2 and first_ok[0] and second_refused[0])
	check("refused second-stage tick preserves the accepted frame", session.sim.paused \
		and session.sim.tick == accepted_tick and session.sim.state.to_byte_array() == accepted_body.to_byte_array() \
		and session.sim.continuous.to_byte_array() == accepted_continuous.to_byte_array() \
		and session._pending_impact.is_empty() \
		and session.sim.fault_reason == "step rejected: RK joint stage evaluation is nonfinite or malformed")
	check("earlier rotor refusal and trial receipt beat speculative contact", \
		session._stage_failure == "main-rotor advance ratio exceeds the kernel domain at this speed" \
		and var_to_bytes(session.stage_domain_diagnostics()) == var_to_bytes(expected) \
		and session.pause_reason.contains("Hub air-relative FRD") \
		and not session.pause_reason.contains("Contact detection refused"))
	session.free()
