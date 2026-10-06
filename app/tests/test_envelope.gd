# D9a: the full-envelope aerodynamics. The linear model stays the oracle where the flow is attached (exactly equal),
# the coefficients are finite and continuous over every attitude, the lift peaks at the labeled CL_max, and the
# airplane really stalls in slow flight (at 8.6–9.5 m/s) instead of parachuting at 7 m/s like the linear model.
# Run: godot --headless --path . --script res://tests/test_envelope.gd
extends SceneTree

const AD := preload("res://physics/aircraft_data.gd")
const Aero := preload("res://physics/aero.gd")
const Air := preload("res://physics/air_data.gd")
const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const Scenarios := preload("res://sim/scenarios.gd")
const FlightSession := preload("res://sim/flight_session.gd")
const Maneuvers := preload("res://sim/maneuvers.gd")

var _failures := 0
var _count := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	print(("ok   " if ok else "FAIL ") + label + "  " + detail)
	if not ok:
		_failures += 1


func _state(V: float, alpha: float, beta: float, rates: PackedFloat64Array) -> PackedFloat64Array:
	return RB.make_state(M.v3(0, 0, -50), M.v3(V * cos(alpha) * cos(beta), V * sin(beta), V * sin(alpha) * cos(beta)),
		M.q_from_euler(0.3, 0.1, -0.2), rates)


func _initialize() -> void:
	var data := AD.load_file(Scenarios.AIRCRAFT)
	var model: Dictionary = data.model
	var env: Dictionary = model.envelope
	var linear := model.duplicate()
	linear.erase("envelope")

	# 1. Conservative independent oracle box: V>=12, body angles<=3deg, rates<=0.4,
	# controls<=0.02rad keeps wing AND tail effective angles inside 8deg including incidence.
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var exact := true
	var tested := 0
	while tested < 500:
		var s := _state(rng.randf_range(12.0, 40.0), deg_to_rad(rng.randf_range(-3.0, 3.0)), deg_to_rad(rng.randf_range(-3.0, 3.0)),
			M.v3(rng.randf_range(-0.4, 0.4), rng.randf_range(-0.4, 0.4), rng.randf_range(-0.4, 0.4)))
		var air := Air.compute(s, M.v3(0, 0, 0))
		var tip_y: float = env.station_ys[env.station_ys.size() - 1] # outermost strip: the largest local α change
		if absf(_station_alpha(air, s, tip_y, -1.0)) >= deg_to_rad(8.0) or absf(_station_alpha(air, s, tip_y, 1.0)) >= deg_to_rad(8.0):
			continue
		tested += 1
		var d := { elevator = rng.randf_range(-0.02, 0.02), aileron_right = rng.randf_range(-0.02, 0.02), aileron_left = rng.randf_range(-0.02, 0.02), rudder = rng.randf_range(-0.02, 0.02) }
		exact = exact and Aero.loads(s, air, d, model, 1.225) == Aero.loads(s, air, d, linear, 1.225)
	_check("oracle: small local wing AND tail angles including deflection → loads identical to the linear model (500 states)", exact)
	# A fast roll at low speed stalls the down-going tip even though the body α is moderate (D9b): not the oracle.
	var tip := _state(9.0, deg_to_rad(7.0), 0.0, M.v3(3.0, 0.0, 0.0))
	var tip_air := Air.compute(tip, M.v3(0, 0, 0))
	_check("tip stall: 9 m/s, α 7°, rolling 3 rad/s → the right tip is past the stall (loads differ)", rad_to_deg(_station_alpha(tip_air, tip, env.station_ys[env.station_ys.size() - 1], 1.0)) > 12.1
		and Aero.loads(tip, tip_air, zero_d(), model, 1.225) != Aero.loads(tip, tip_air, zero_d(), linear, 1.225))

	# 2. Every attitude: finite and continuous coefficients (α −180…180°, β −90…90°, steps of 0.1°).
	var zero := { elevator = 0.0, aileron_right = 0.0, aileron_left = 0.0, rudder = 0.0 }
	var rates0 := M.v3(0, 0, 0)
	var finite := true
	var worst_jump := 0.0
	var prev := {}
	var cl_peak := -9.0
	var cl_peak_at := 0.0
	var cl_low := 9.0
	for k in range(-1800, 1801):
		var c := Aero.coefficients({ alpha = deg_to_rad(k * 0.1), beta = 0.0 }, rates0, zero, model.aero, env)
		for key in c:
			finite = finite and is_finite(c[key])
			if not prev.is_empty():
				worst_jump = maxf(worst_jump, absf(c[key] - prev[key]))
		if c.CL > cl_peak:
			cl_peak = c.CL
			cl_peak_at = k * 0.1
		cl_low = minf(cl_low, c.CL)
		prev = c
	prev = {}
	for k in range(-900, 901):
		var c := Aero.coefficients({ alpha = 0.05, beta = deg_to_rad(k * 0.1) }, rates0, zero, model.aero, env)
		for key in c:
			finite = finite and is_finite(c[key])
			if not prev.is_empty():
				worst_jump = maxf(worst_jump, absf(c[key] - prev[key]))
		prev = c
	_check("every α and β: finite coefficients", finite)
	_check("continuous: largest change per 0.1° < 0.05", worst_jump < 0.05, "%.4f" % worst_jump)
	_check("lift peaks at CL_max %.2f inside the blend" % env.CL_max, absf(cl_peak - env.CL_max) < 0.002 and deg_to_rad(cl_peak_at) >= env.a1 and deg_to_rad(cl_peak_at) <= env.a2, "%.4f at %.1f°" % [cl_peak, cl_peak_at])
	_check("negative lift bottoms at CL_min %.2f" % env.CL_min, absf(cl_low - env.CL_min) < 0.002, "%.4f" % cl_low)
	_check("stall starts outside the ±8° oracle region", rad_to_deg(env.a1) >= 8.0 and rad_to_deg(env.n1) >= 8.0, "+%.1f° / −%.1f°" % [rad_to_deg(env.a1), rad_to_deg(env.n1)])
	var c90 := Aero.coefficients({ alpha = PI / 2.0, beta = 0.0 }, rates0, zero, model.aero, env)
	var c180 := Aero.coefficients({ alpha = PI, beta = 0.0 }, rates0, zero, model.aero, env)
	var c179 := Aero.coefficients({ alpha = PI - 0.02, beta = 0.0 }, rates0, zero, model.aero, env)
	_check("α 90°: flat-plate drag CD0 + CD90, ~no lift, strong nose-down moment", absf(c90.CD - (model.aero.CD0 + env.CD90)) < 1e-9 and absf(c90.CL) < 1e-9 and c90.Cm < -0.5, str(c90))
	_check("tail first (α 180°): pitch equilibrium is unstable (Cm grows with α)", c179.Cm < c180.Cm, "%.4f → %.4f" % [c179.Cm, c180.Cm])
	var k90 := Aero.coefficients({ alpha = 0.0, beta = PI / 2.0 }, rates0, zero, model.aero, env)
	_check("knife edge (β 90°): weathervane and side force still there", k90.Cn > 0.05 and k90.CY < -0.3, str(k90))

	# 3. Data: a stall inside the oracle region is refused, and so is a missing envelope.
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Scenarios.AIRCRAFT))
	raw.aero.envelope.CL_max.value = 0.6
	var bad := AD.validate_and_derive(raw)
	_check("refused: CL_max 0.6 would stall inside the oracle region", not bad.ok and "oracle" in str(bad.errors), str(bad.errors))
	raw = JSON.parse_string(FileAccess.get_file_as_string(Scenarios.AIRCRAFT))
	raw.aero.erase("envelope")
	_check("refused: no envelope", not AD.validate_and_derive(raw).ok)

	# 4. Flown: slow flight at idle, elevator holding altitude, until the wing gives up.
	var session := FlightSession.new()
	session.setup()
	root.add_child(session)
	var stall := _slow_flight_stall_speed(session)
	var vs := sqrt(2.0 * model.mass_kg * 9.80665 / (1.225 * model.reference.S * env.CL_max))
	_check("full envelope: flown stall within 5%% of 1-g CL_max speed %.2f" % vs, absf(stall/vs-1.0) < 0.05, "%.2f m/s" % stall)
	session.aircraft.model.erase("envelope") # the linear oracle in the same loop
	var stall_linear := _slow_flight_stall_speed(session)
	_check("linear oracle: holds altitude below 90% of physical CL_max speed (unphysical)", stall_linear < 0.9*vs, "%.2f m/s" % stall_linear)

	# 5. Flying backwards (a tail slide): the full envelope keeps everything finite.
	session.aircraft = AD.load_file(Scenarios.AIRCRAFT)
	session.reset()
	session.input_enabled = false
	session.sim.reset(RB.make_state(M.v3(0, 0, -60), M.v3(-8.0, 0.5, 1.0), M.q_from_euler(0.0, 1.2, 0.1), M.v3(0.2, -0.5, 0.1)))
	var ok_finite := true
	for i in 720:
		session.sim.step()
		for x in session.sim.state:
			ok_finite = ok_finite and is_finite(x)
	_check("tail slide at −8 m/s: 3 s of flight stay finite", ok_finite, str(session.sim.state))

	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)


func zero_d() -> Dictionary:
	return { elevator = 0.0, aileron_right = 0.0, aileron_left = 0.0, rudder = 0.0 }


## Local α of a half-wing station (side −1 left, +1 right), as physics/aero.gd computes it.
func _station_alpha(air: Dictionary, s: PackedFloat64Array, y: float, side: float) -> float:
	var v: PackedFloat64Array = air.v_air
	return atan2(v[2] + side * s[RB.RATE] * y, v[0] - side * s[RB.RATE + 2] * y)


## Airspeed when the altitude-holding airplane first sinks 0.5 m below its start (the wing can no longer hold it).
func _slow_flight_stall_speed(session: Node) -> float:
	var tr: RefCounted = Maneuvers.fly(session, Maneuvers.all().slow_flight)
	for r in tr.row_count():
		if tr.value(r, "alt_m") < Maneuvers.SLOW_FLIGHT.altitude - 0.5:
			return tr.value(r, "speed_mps")
	return 0.0
