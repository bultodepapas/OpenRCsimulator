# AV-05: the turbojet branch (physics/turbine.gd) and its loader (aircraft_data.gd _turbine), on an in-memory engine
# block whose numbers are chosen for hand calculation, not the Avanti's data (test_avanti_handling.gd flies those).
# Run: godot --headless --path . --script res://tests/test_turbine.gd
extends SceneTree

const AircraftData := preload("res://physics/aircraft_data.gd")
const Turbine := preload("res://physics/turbine.gd")
const Propulsion := preload("res://physics/propulsion.gd")
const Dynamics := preload("res://physics/dynamics.gd")
const M := preload("res://physics/math3d.gd")

var _failures := 0
var _count := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	print(("ok   " if ok else "FAIL ") + label + "  " + detail)
	if not ok:
		_failures += 1


static func _t(rows: Array, unit: String) -> Dictionary:
	return { value = rows, unit = unit, kind = "estimated", source = "test fixture" }


static func _q(value: Variant, unit: String) -> Dictionary:
	return { value = value, unit = unit, kind = "estimated", source = "test fixture" }


## Idle 40k, max 150k rpm; 100 N bench at max; 0.2 kg/s at max; constant 30k rpm/s up, 60k rpm/s down.
static func fixture() -> Dictionary:
	return {
		kind = "turbine",
		thrust_line_offset = _q([0.0, 0.0, 0.05], "m"),
		intake_offset = _q([-0.3, 0.0, 0.0], "m"),
		engine = {
			idle_rpm = _q(40000, "rpm"),
			max_rpm = _q(150000, "rpm"),
			static_thrust = _t([[0, 0], [40000, 2], [150000, 100]], "rpm, N"),
			mass_flow = _t([[0, 0.0001], [40000, 0.06], [150000, 0.2]], "rpm, kg/s"),
			fuel_flow = _t([[40000, 0.001], [150000, 0.005]], "rpm, kg/s"),
			throttle_map = _t([[0, 40000], [1, 150000]], "1, rpm"),
			accel_limit = _t([[0, 30000], [150000, 30000]], "rpm, rpm/s"),
			decel_limit = _t([[0, 60000], [150000, 60000]], "rpm, rpm/s"),
			installed_factor = _q(0.9, "1"),
			governor_tau = _q(0.1, "s"),
			rotor_inertia = _q(0.0001, "kg·m2"),
			rotor_sense = _q(-1, "1"),
		},
	}


func _load(node: Dictionary) -> Array:
	var errors := PackedStringArray()
	var prop := AircraftData._turbine(errors, node)
	return [prop, errors]


func _initialize() -> void:
	var loaded := _load(fixture())
	var prop: Dictionary = loaded[0]
	_check("loader accepts a complete turbine block", (loaded[1] as PackedStringArray).is_empty() and not prop.is_empty(), str(loaded[1]))
	if prop.is_empty():
		quit(1)
		return

	# Loader refusals: each is a data mistake that must not fly.
	var bad := {
		"propeller keys on a turbine": func(n: Dictionary) -> void: n.engine.ct_table = _t([[0, 0.1], [1, 0]], "1"),
		"throttle map not ending at max_rpm": func(n: Dictionary) -> void: n.engine.throttle_map = _t([[0, 40000], [1, 140000]], "1, rpm"),
		"rpm not increasing in a table": func(n: Dictionary) -> void: n.engine.static_thrust = _t([[0, 0], [90000, 2], [80000, 100]], "rpm, N"),
		"wrong table unit": func(n: Dictionary) -> void: n.engine.mass_flow = _t([[0, 0.1], [150000, 0.2]], "rpm, kg/min"),
		"rotor sense not ±1": func(n: Dictionary) -> void: n.engine.rotor_sense = _q(0.5, "1"),
		"idle above max": func(n: Dictionary) -> void: n.engine.idle_rpm = _q(160000, "rpm"),
	}
	for label in bad:
		var node := fixture()
		bad[label].call(node)
		_check("loader refuses: " + label, not (_load(node)[1] as PackedStringArray).is_empty())
	var errors := PackedStringArray()
	AircraftData._propulsion(errors, { kind = "rocket" })
	_check("loader refuses an unknown propulsion kind", not errors.is_empty(), str(errors))

	# Steady state and thrust (momentum theory: F = k·F_static − ṁ·u).
	_check("throttle 0 → idle, 1 → max, 0.5 → linear map", Turbine.steady_rpm(0.0, prop) == 40000.0 and Turbine.steady_rpm(1.0, prop) == 150000.0 and Turbine.steady_rpm(0.5, prop) == 95000.0)
	_check("Propulsion.steady_rpm dispatches to the turbine", Propulsion.steady_rpm(0.5, 30.0, prop, 1.225) == 95000.0)
	var f0 := Turbine.thrust(150000.0, 0.0, prop, 1.225)
	_check("static installed thrust at max = 0.9 × 100 N", absf(f0 - 90.0) < 1e-9, "%.6f N" % f0)
	var f50 := Turbine.thrust(150000.0, 50.0, prop, 1.225)
	_check("ram drag at 50 m/s = ṁ·u = 0.2 × 50 N", absf(f0 - f50 - 10.0) < 1e-9, "%.6f N" % f50)
	_check("idle thrust turns into drag at speed (ram drag > idle gross)", Turbine.thrust(40000.0, 40.0, prop, 1.225) < 0.0, "%.3f N" % Turbine.thrust(40000.0, 40.0, prop, 1.225))
	_check("half density halves thrust and ram drag", absf(Turbine.thrust(150000.0, 50.0, prop, 0.6125) - 0.5 * f50) < 1e-9)
	_check("stopped shaft: no thrust", Turbine.thrust(0.0, 30.0, prop, 1.225) == 0.0)
	# Ram recovery (optional data): ṁ = ṁ0(1 + c·u²), V_jet = sqrt(V_j0² + k·u²). At max: ṁ0 0.2, V_j0 = 90/0.2 = 450 m/s.
	var ram_node := fixture()
	ram_node.engine.ram_flow = _q(1.0 / 193000.0, "s2/m2")
	ram_node.engine.ram_jet = _t([[40000, 1.0], [150000, 3.0]], "rpm, 1")
	var rp: Dictionary = _load(ram_node)[0]
	var mf := 0.2 * (1.0 + 4900.0 / 193000.0)
	var expected := mf * (sqrt(450.0 * 450.0 + 3.0 * 4900.0) - 70.0)
	_check("ram recovery at 70 m/s: ṁ0(1 + u²/193000)(sqrt(V_j0² + 3u²) − u)", absf(Turbine.thrust(150000.0, 70.0, rp, 1.225) - expected) < 1e-9,
		"%.4f N (plain law %.4f N)" % [Turbine.thrust(150000.0, 70.0, rp, 1.225), Turbine.thrust(150000.0, 70.0, prop, 1.225)])
	_check("ram recovery leaves the static thrust unchanged", absf(Turbine.thrust(150000.0, 0.0, rp, 1.225) - 90.0) < 1e-9)

	# Loads: along the axis, moment r × F about the CG, no reaction torque.
	var l := Propulsion.loads(M.v3(0.0, 0.0, 0.0), 150000.0, prop, 1.225)
	_check("loads: thrust on body +x, no side/vertical force, no roll torque", absf(l[0] - 90.0) < 1e-9 and l[1] == 0.0 and l[2] == 0.0 and l[3] == 0.0)
	_check("loads: thrust line 5 cm above the CG pitches nose down by 4.5 N·m", absf(l[4] + 4.5) < 1e-9, "My %.6f" % l[4])
	# Inlet normal force: at 40 m/s and 0.1 rad of α the captured air's cross momentum ṁ·w pushes the intakes
	# (0.3 m ahead of the CG) toward the flow: −ṁ·w along z, a nose-up (destabilizing) pitching moment.
	var w := 40.0 * sin(0.1)
	var li := Propulsion.loads(M.v3(40.0 * cos(0.1), 0.0, w), 150000.0, prop, 1.225)
	_check("inlet normal force −ṁ·w on body z, nose-up moment ṁ·w·0.3 m", absf(li[2] + 0.2 * w) < 1e-9 and absf(li[4] - (-4.5 + 0.2 * w * 0.3)) < 1e-9,
		"Fz %.4f N, My %.4f N·m" % [li[2], li[4]])
	_check("axial ram drag in the loads = ṁ·u", absf(li[0] - (90.0 - 0.2 * 40.0 * cos(0.1))) < 1e-9)

	# Spool: constant schedules make the times exact: (150k − 40k)/30k = 3.667 s up, /60k = 1.833 s down (+ governor tail).
	var dt := 1.0 / 240.0
	var rpm := 40000.0
	var t_up := -1.0
	var overshoot := false
	for i in roundi(6.0 / dt):
		rpm = Turbine.spool_step(rpm, 1.0, dt, prop)
		overshoot = overshoot or rpm > 150000.0
		if t_up < 0.0 and rpm >= 0.95 * 150000.0:
			t_up = (i + 1) * dt
	var expected_up := (0.95 * 150000.0 - 40000.0) / 30000.0
	_check("spool-up idle → 95 %% max on the acceleration limit: %.3f s" % expected_up, absf(t_up - expected_up) < 2.0 * dt, "%.4f s" % t_up)
	_check("spool-up never overshoots the demand", not overshoot and absf(rpm - 150000.0) < 1.0, "%.3f rpm" % rpm)
	var t_down := -1.0
	for i in roundi(4.0 / dt):
		rpm = Turbine.spool_step(rpm, 0.0, dt, prop)
		if t_down < 0.0 and rpm <= 40000.0 + 0.05 * 110000.0:
			t_down = (i + 1) * dt
	var expected_down := 0.95 * 110000.0 / 60000.0
	_check("spool-down to within 5 %% of idle on the deceleration limit: %.3f s" % expected_down, absf(t_down - expected_down) < 2.0 * dt, "%.4f s" % t_down)
	_check("spool-down settles on idle, not below", absf(rpm - 40000.0) < 1.0 and rpm >= 40000.0 - 1e-6, "%.3f" % rpm)

	# Timestep split: 240 Hz vs 480 Hz over a throttle step agree to 0.5 % of the range at every common instant.
	var a := 40000.0
	var b := 40000.0
	var worst := 0.0
	for i in 480:
		var throttle := 1.0 if i < 240 else 0.3
		a = Turbine.spool_step(a, throttle, dt, prop)
		b = Turbine.spool_step(Turbine.spool_step(b, throttle, dt / 2.0, prop), throttle, dt / 2.0, prop)
		worst = maxf(worst, absf(a - b))
	_check("spool split 240/480 Hz within 0.5 % of the rpm range", worst < 0.005 * 110000.0, "worst %.1f rpm" % worst)

	# Rotor: I·ω along −x for a counter-clockwise (from behind) spool.
	var h := Dynamics.rotor_momentum({ propulsion = prop }, 150000.0)
	_check("rotor momentum −I·ω along x (counter-clockwise)", absf(h[0] + 0.0001 * 150000.0 * TAU / 60.0) < 1e-12 and h[1] == 0.0 and h[2] == 0.0, "%.5f N·m·s" % h[0])

	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)
