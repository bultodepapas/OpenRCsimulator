# GP-02: independent analytic checks for wheel spin, contact loads, braking and dissipation.
# The fixtures isolate Ground.evaluate from aerodynamic and rigid-body integration; they are not physical calibration.
# Run: godot --headless --path . --script res://tests/test_ground_physics.gd
extends SceneTree

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const Ground := preload("res://physics/ground_wheels.gd")
const Terrain := preload("res://physics/ground_terrain.gd")

const BODY_MASS := 10.0

var _count := 0
var _failures := 0
var _report: Dictionary = {"evidence_kind": "synthetic analytic fixture", "checks": []}


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	_report.checks.append({"name": label, "passed": ok, "detail": detail})
	print(("ok   " if ok else "FAIL ") + label + ("" if detail.is_empty() else "  " + detail))
	if not ok:
		_failures += 1


func _state(alt: float, speed: float, down_speed := 0.0) -> PackedFloat64Array:
	return RB.make_state(M.v3(0.0, 0.0, -alt), M.v3(speed, 0.0, down_speed),
		M.q_from_euler(0.0, 0.0, 0.0), M.v3(0.0, 0.0, 0.0))


func _contact(radius := 0.2, inertia := 0.1, max_brake := 0.0, stiffness := 1000.0, lateral := 0.0) -> Dictionary:
	return {
		"name": "analytic-wheel",
		"position": M.v3(0.0, lateral, 0.2),
		"stiffness": stiffness,
		"damping": 0.0,
		"max_compression": 0.5,
		"max_steering": 0.0,
		"wheel_radius": radius,
		"wheel_inertia": inertia,
		"spin_relaxation": 0.03,
		"brake_torque": max_brake,
	}


func _gear(contacts: Array, crr := 0.04, mu := 0.8) -> Dictionary:
	return {
		"contacts": contacts,
		"reach": 0.5,
		"rolling_resistance": crr,
		"side_friction": mu,
		"tan_peak_slip": tan(deg_to_rad(6.0)),
	}


func _evaluate(state: PackedFloat64Array, gear: Dictionary, speeds: PackedFloat64Array,
		brake := 0.0, surfaces := PackedFloat64Array()) -> Dictionary:
	return Ground.evaluate(state, gear, 0.0, surfaces, PackedFloat64Array(), speeds, brake)


func _normal_load_and_airborne() -> void:
	var gear := _gear([_contact()])
	var loads := PackedFloat64Array()
	for compression in [0.0, 0.025, 0.05, 0.1]:
		var altitude: float = 0.2 - compression
		var result := _evaluate(_state(altitude, 2.0), gear, PackedFloat64Array([2.0]))
		var expected: float = compression * 1000.0
		var wheels: Array = result.wheels
		var actual: float = wheels[0].normal_load
		loads.append(actual)
		_check("flat contact normal load is k·compression (%.2f N)" % expected,
			absf(actual - expected) < 1e-10, "got %.12f N" % actual)
	_report.normal_loads_n = loads

	var airborne := _evaluate(_state(1.0, 2.0), gear, PackedFloat64Array([2.0]))
	_check("airborne wheel has no body load", airborne.loads.is_empty(), str(airborne.loads))
	_check("airborne wheel retains rim speed with exactly zero derivative",
		airborne.derivative.size() == 1 and airborne.derivative[0] == 0.0,
		str(airborne.derivative))
	_check("airborne wheel reports no ground contacts", airborne.wheels.is_empty(), str(airborne.wheels))

	var no_load := _evaluate(_state(0.21, 2.0), gear, PackedFloat64Array([2.0]))
	_check("zero-compression wheel contributes no force or spin change",
		no_load.loads.is_empty() and no_load.derivative.size() == 1 and no_load.derivative[0] == 0.0,
		"loads=%s, rim derivative=%s" % [str(no_load.loads), str(no_load.derivative)])


func _spinup_and_dissipation() -> void:
	var radius := 0.2
	var inertia := 0.1
	var effective_mass := inertia / (radius * radius)
	var gear := _gear([_contact(radius, inertia)])
	var speed := 0.5
	var result := _evaluate(_state(0.1, speed), gear, PackedFloat64Array([0.0]))
	var wheel: Dictionary = result.wheels[0]
	var expected_tire_force := -minf(0.8 * 100.0, effective_mass / 0.03) * speed
	var expected_rolling_force := -0.04 * 100.0
	var expected_rate := -expected_tire_force / effective_mass
	_check("zero-rim wheel spins up from the analytic relaxation force",
		absf(wheel.slip_force - expected_tire_force) < 1e-10 and absf(result.derivative[0] - expected_rate) < 1e-10,
		"tire force %.12f N; rim acceleration %.12f m/s²" % [wheel.slip_force, result.derivative[0]])
	_check("wheel spin-up torque is the opposite tire torque",
		absf(inertia / radius * result.derivative[0] + wheel.slip_force * radius) < 1e-10,
		"spin torque %.12f N·m; tire torque %.12f N·m" %
			[inertia / radius * result.derivative[0], wheel.slip_force * radius])
	_check("rolling drag is a separate force and is not used to spin up the wheel",
		absf(wheel.rolling_force - expected_rolling_force) < 1e-10
			and absf(wheel.longitudinal_force - expected_tire_force - expected_rolling_force) < 1e-10,
		"rolling %.12f N; combined %.12f N" % [wheel.rolling_force, wheel.longitudinal_force])
	var body_power: float = result.loads[0] * speed
	var wheel_power: float = effective_mass * 0.0 * result.derivative[0]
	var total_power: float = body_power + wheel_power
	_check("initial body plus wheel power is non-positive during spin-up",
		total_power <= 1e-12, "body %.12f W; wheel %.12f W; total %.12f W" % [body_power, wheel_power, total_power])
	_report.spinup = {
		"speed_mps": speed,
		"initial_rim_speed_mps": 0.0,
		"normal_load_n": wheel.normal_load,
		"slip_force_n": wheel.slip_force,
		"rolling_force_n": wheel.rolling_force,
		"rim_acceleration_mps2": result.derivative[0],
		"body_plus_wheel_power_w": total_power,
	}

	var reverse := _evaluate(_state(0.1, -2.0), gear, PackedFloat64Array([-2.0]))
	var reverse_power: float = reverse.loads[0] * -2.0 + effective_mass * -2.0 * reverse.derivative[0]
	_check("reverse rolling also removes energy", reverse_power <= 1e-12,
		"force %.12f N; power %.12f W" % [reverse.loads[0], reverse_power])
	_report.reverse_power_w = reverse_power


func _brake_law() -> void:
	var with_brakes := _gear([_contact(0.2, 0.1, 2.0)])
	var without_brakes := _gear([_contact(0.2, 0.1, 0.0)])
	var state := _state(0.1, 2.0)
	var rim := PackedFloat64Array([2.0])
	var applied := _evaluate(state, with_brakes, rim, 1.0)
	var unapplied := _evaluate(state, with_brakes, rim, 0.0)
	var no_hardware := _evaluate(state, without_brakes, rim, 1.0)
	var brake_wheel: Dictionary = applied.wheels[0]
	var effective_mass := 0.1 / (0.2 * 0.2)
	_check("brake command applies the declared torque with the correct rim-speed sign",
		absf(brake_wheel.brake_torque - 2.0) < 1e-12
			and absf(applied.derivative[0] + 2.0 / 0.2 / effective_mass) < 1e-12,
		"torque %.12f N·m; rim acceleration %.12f m/s²" % [brake_wheel.brake_torque, applied.derivative[0]])
	_check("brake work is dissipative at positive rim speed",
		applied.loads[0] * 2.0 + effective_mass * 2.0 * applied.derivative[0] <= 1e-12,
		"body force %.12f N; total power %.12f W" %
			[applied.loads[0], applied.loads[0] * 2.0 + effective_mass * 2.0 * applied.derivative[0]])
	_check("zero brake command has zero brake torque",
		unapplied.wheels[0].brake_torque == 0.0, str(unapplied.wheels[0]))
	_check("a wheel with no brake hardware ignores brake input exactly",
		no_hardware.wheels[0].brake_torque == 0.0
			and no_hardware.loads == unapplied.loads
			and no_hardware.derivative == unapplied.derivative,
		"with hardware %s; no hardware %s" % [str(unapplied), str(no_hardware)])
	_report.brake = {
		"maximum_torque_nm": brake_wheel.brake_torque,
		"rim_acceleration_mps2": applied.derivative[0],
		"body_plus_wheel_power_w": applied.loads[0] * 2.0 + effective_mass * 2.0 * applied.derivative[0],
	}


func _rhs(u: float, rim: float, gear: Dictionary, brake: float) -> PackedFloat64Array:
	var result := _evaluate(_state(0.1, u), gear, PackedFloat64Array([rim]), brake)
	var body_force: float = result.loads[0] if not result.loads.is_empty() else 0.0
	return PackedFloat64Array([body_force / BODY_MASS, result.derivative[0]])


func _rollout(hz: int, brake: float, stop_speed := -1.0, seconds := 0.5) -> Dictionary:
	var radius := 0.2
	var inertia := 0.1
	var gear := _gear([_contact(radius, inertia, 2.0)])
	var dt := 1.0 / float(hz)
	var u := 2.0
	var rim := 2.0
	var distance := 0.0
	var time := 0.0
	var hit := false
	var ticks := ceili(seconds * hz)
	if stop_speed >= 0.0:
		ticks = ceili(8.0 * hz)
	for i in ticks:
		if stop_speed >= 0.0 and u <= stop_speed:
			hit = true
			break
		var k1 := _rhs(u, rim, gear, brake)
		var k2 := _rhs(u + 0.5 * dt * k1[0], rim + 0.5 * dt * k1[1], gear, brake)
		var k3 := _rhs(u + 0.5 * dt * k2[0], rim + 0.5 * dt * k2[1], gear, brake)
		var k4 := _rhs(u + dt * k3[0], rim + dt * k3[1], gear, brake)
		var next_u := u + dt / 6.0 * (k1[0] + 2.0 * k2[0] + 2.0 * k3[0] + k4[0])
		var next_rim := rim + dt / 6.0 * (k1[1] + 2.0 * k2[1] + 2.0 * k3[1] + k4[1])
		distance += 0.5 * (u + next_u) * dt
		u = next_u
		rim = next_rim
		time += dt
	if stop_speed >= 0.0 and u <= stop_speed:
		hit = true
	return {"u": u, "rim": rim, "distance": distance, "time": time, "hit": hit}


func _flat_slope_and_gradient() -> void:
	var empty := PackedFloat64Array()
	_check("empty terrain table is exactly flat", Terrain.sample(0.31, -0.72, empty) == PackedFloat64Array([0.0, 0.0, 0.0]))

	# A wide runway rectangle over a rough catchall produces a repeatable analytic slope.
	var surfaces := PackedFloat64Array([
		-10.0, 10.0, -10.0, 10.0, 0.8, 2.5,
		-INF, INF, -INF, INF, 0.7, 7.5,
	])
	var north := 0.0
	var east := 0.0
	var terrain := Terrain.sample(north, east, surfaces)
	var norm := sqrt(1.0 + terrain[1] * terrain[1] + terrain[2] * terrain[2])
	var epsilon := 1e-4
	var north_fd := (Terrain.sample(north + epsilon, east, surfaces)[0]
		- Terrain.sample(north - epsilon, east, surfaces)[0]) / (2.0 * epsilon)
	var east_fd := (Terrain.sample(north, east + epsilon, surfaces)[0]
		- Terrain.sample(north, east - epsilon, surfaces)[0]) / (2.0 * epsilon)
	_check("terrain analytical gradients match central finite differences",
		absf(north_fd - terrain[1]) < 1e-6 and absf(east_fd - terrain[2]) < 1e-6,
		"north %.9f / %.9f; east %.9f / %.9f" % [terrain[1], north_fd, terrain[2], east_fd])

	var compression := 0.1
	var altitude: float = 0.2 + terrain[0] - compression * norm
	var gear := _gear([_contact()])
	var result := Ground.evaluate(_state(altitude, 0.0), gear, 0.0, surfaces,
		PackedFloat64Array(), PackedFloat64Array([0.0]))
	var wheel: Dictionary = result.wheels[0]
	var expected: PackedFloat64Array = PackedFloat64Array([-terrain[1] / norm, -terrain[2] / norm, -1.0 / norm])
	var force_per_load := PackedFloat64Array([result.loads[0] / wheel.normal_load,
		result.loads[1] / wheel.normal_load, result.loads[2] / wheel.normal_load])
	_check("sloped contact force follows the terrain normal in NED",
		absf(wheel.normal_load - 100.0) < 1e-8
			and absf(force_per_load[0] - expected[0]) < 1e-10
			and absf(force_per_load[1] - expected[1]) < 1e-10
			and absf(force_per_load[2] - expected[2]) < 1e-10,
		"normal %s; force/load %s" % [str(expected), str(force_per_load)])
	_report.terrain_slope = {"height_up_m": terrain[0], "gradient_n": terrain[1], "gradient_e": terrain[2],
		"normal_load_n": wheel.normal_load, "force_per_load_ned": expected}


func _asymmetric_surface_pair() -> void:
	# One runway strip occupies east > 0; the other wheel stands on the rough catchall.
	var surfaces := PackedFloat64Array([
		-10.0, 10.0, 0.0, 10.0, 0.8, 2.5,
		-10.0, 10.0, -10.0, 0.0, 0.7, 7.5,
		-INF, INF, -INF, INF, 0.7, 7.5,
	])
	var radius := Ground.REFERENCE_RADIUS
	var contacts := [_contact(radius, 0.001, 0.0, 500.0, 0.3), _contact(radius, 0.001, 0.0, 500.0, -0.3)]
	var gear := _gear(contacts)
	var result := _evaluate(_state(0.1, 2.0), gear, PackedFloat64Array([2.0, 2.0]), 0.0, surfaces)
	var runway: Dictionary = result.wheels[0]
	var rough: Dictionary = result.wheels[1]
	var runway_ratio: float = runway.rolling_force / runway.normal_load
	var rough_ratio: float = rough.rolling_force / rough.normal_load
	_check("each wheel uses its own runway or rough rolling coefficient",
		int(runway.surface_index) != int(rough.surface_index)
			and absf(runway_ratio + 0.04 * 2.5) < 1e-9
			and absf(rough_ratio + 0.04 * 7.5) < 1e-9,
		"indices %d/%d; rolling/load %.9f/%.9f" %
			[int(runway.surface_index), int(rough.surface_index), runway_ratio, rough_ratio])
	_check("rough-side drag gives the expected negative yaw moment",
		result.loads.size() == 6 and result.loads[5] < -0.5,
		"Mz %.9f N·m; wheel drag %.9f / %.9f N" %
			[result.loads[5], runway.rolling_force, rough.rolling_force])
	_report.asymmetric_surfaces = {
		"runway_surface_index": runway.surface_index,
		"rough_surface_index": rough.surface_index,
		"runway_normal_load_n": runway.normal_load,
		"rough_normal_load_n": rough.normal_load,
		"runway_rolling_force_n": runway.rolling_force,
		"rough_rolling_force_n": rough.rolling_force,
		"yaw_moment_nm": result.loads[5],
	}


func _spin_timestep_refinement() -> void:
	var h240 := _rollout(240, 0.0, -1.0, 0.5)
	var h480 := _rollout(480, 0.0, -1.0, 0.5)
	var h960 := _rollout(960, 0.0, -1.0, 0.5)
	var coarse_error := absf(h240.u - h480.u) / maxf(absf(h480.u), 1e-12)
	var fine_error := absf(h480.u - h960.u) / maxf(absf(h960.u), 1e-12)
	_check("wheel spin-up is stable and converges under 240/480/960 Hz RK4 refinement",
		is_finite(h240.u) and is_finite(h480.u) and is_finite(h960.u)
			and coarse_error < 0.01 and fine_error < 0.001,
		"body speed %.9f / %.9f / %.9f m/s; relative differences %.6f / %.6f" %
			[h240.u, h480.u, h960.u, coarse_error, fine_error])
	_check("wheel rim speed converges under the same refinement",
		absf(h480.rim - h960.rim) / maxf(absf(h960.rim), 1e-12) < 0.001,
		"%.9f / %.9f m/s at 480/960 Hz" % [h480.rim, h960.rim])
	_report.refinement = {
		"hz": [240, 480, 960],
		"body_speed_mps": [h240.u, h480.u, h960.u],
		"rim_speed_mps": [h240.rim, h480.rim, h960.rim],
		"coarse_relative_error": coarse_error,
		"fine_relative_error": fine_error,
	}


func _stopping_distance() -> void:
	var coast := _rollout(480, 0.0, 0.1)
	var braked := _rollout(480, 1.0, 0.1)
	_check("brakes shorten the synthetic coupled body-and-wheel stopping distance",
		coast.hit and braked.hit and braked.distance < coast.distance,
		"coast %.6f m / %.6f s; braked %.6f m / %.6f s" %
			[coast.distance, coast.time, braked.distance, braked.time])
	_report.stopping = {
		"speed_threshold_mps": 0.1,
		"coast_distance_m": coast.distance,
		"coast_time_s": coast.time,
		"braked_distance_m": braked.distance,
		"braked_time_s": braked.time,
	}




func _spinning_anchor_release() -> void:
	var gear := _gear([_contact()])
	var state := _state(0.1, 0.0)
	var spin := PackedFloat64Array([2.0])
	var stuck := PackedFloat64Array([0.0, 0.0, 1.0])
	var free := PackedFloat64Array([0.0, 0.0, 0.0])
	var spinning := Ground.evaluate(state, gear, 0.0, PackedFloat64Array(), stuck, spin)
	var sliding := Ground.evaluate(state, gear, 0.0, PackedFloat64Array(), free, spin)
	_check("stationary axle with spinning tire uses sliding force even before anchor update", spinning.loads == sliding.loads and spinning.derivative == sliding.derivative)
	_check("residual wheel spin releases a static anchor", Ground.anchor_step(state, gear, 0.0, PackedFloat64Array(), stuck, spin) == free)
	_check("residual wheel spin cannot acquire a static anchor", Ground.anchor_step(state, gear, 0.0, PackedFloat64Array(), free, spin) == free)


func _low_resistance_surface() -> void:
	# A valid smooth pad has rolling factor 0.5. The size correction represents
	# vegetation excess, not a discount that can make a small wheel propel itself.
	var contact := _contact(0.01, 0.000001)
	var gear := _gear([contact])
	gear.rolling_reference_radius = 0.09
	# Smooth-pad endpoints and unchanged rough-terrain controls (radius scale = 3).
	for sample in [[0.5, 0.02], [0.75, 0.03], [1.0, 0.04], [2.5, 0.22], [7.5, 0.82]]:
		var factor: float = sample[0]
		var surface := PackedFloat64Array([-INF, INF, -INF, INF, 1.0, factor])
		_check("rolling-factor fixture is admitted %.2f" % factor, Terrain.is_valid_surface_table(surface))
		var coefficient := Ground.coefficients(gear, contact, surface, M.v3(0.0, 0.0, 0.0))
		var expected: float = sample[1]
		_check("only positive terrain excess receives wheel-size scaling %.2f" % factor,
			absf(coefficient[1] - expected) < 1e-12, "got %.12f expected %.12f" % [coefficient[1], expected])
		for speed in [-2.0, 2.0]:
			var result := _evaluate(_state(0.1, speed), gear, PackedFloat64Array([speed]), 0.0, surface)
			var power: float = result.wheels[0].rolling_force * speed
			_check("rolling removes energy factor %.2f speed %.1f" % [factor, speed], power <= 0.0,
				"rolling power %.12f W" % power)


func _initialize() -> void:
	_low_resistance_surface()
	_normal_load_and_airborne()
	_flat_slope_and_gradient()
	_asymmetric_surface_pair()
	_spinup_and_dissipation()
	_brake_law()
	_spin_timestep_refinement()
	_stopping_distance()
	_spinning_anchor_release()
	_report.check_count = _count
	_report.failure_count = _failures
	print("GP_JSON " + JSON.stringify(_report))
	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)
