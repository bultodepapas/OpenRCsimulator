# VAL-4: actual FlightSession/Simulation metamorphic checks, outside res://.
extends SceneTree

const AD = preload("res://physics/aircraft_data.gd")
const Aero = preload("res://physics/aero.gd")
const Air = preload("res://physics/air_data.gd")
const RB = preload("res://physics/rigid_body.gd")
const M = preload("res://physics/math3d.gd")
const Session = preload("res://sim/flight_session.gd")
const Simulation = preload("res://sim/simulation.gd")
const SEED: int = 64007
const TICKS: int = 240
const MIRROR_SIGNS: Array = [1, -1, 1, 1, -1, 1, 1, -1, 1, -1, -1, 1, -1]

var _groups: Dictionary = {}
var _coverage: Dictionary = {attached = 0, blended = 0, local = 0, moving_servo = 0, lag_transient = 0}
var _cases: int = 0


func check(group: String, error: float, limit: float, label: String) -> void:
	if not _groups.has(group):
		_groups[group] = {checks = 0, failures = 0, max_error = 0.0, limit = limit, worst = ""}
	var row: Dictionary = _groups[group]
	row.checks += 1
	if not is_finite(error) or error > limit:
		row.failures += 1
	if not is_finite(error) or error > row.max_error:
		row.max_error = error if is_finite(error) else 1e300
		row.worst = label


func mirror(s: PackedFloat64Array) -> PackedFloat64Array:
	var out: PackedFloat64Array = s.duplicate()
	for i: int in out.size():
		out[i] *= MIRROR_SIGNS[i]
	return out


func scaled_state(s: PackedFloat64Array, scale: float) -> PackedFloat64Array:
	var out: PackedFloat64Array = s.duplicate()
	for i: int in 3:
		out[RB.POS + i] *= scale
		out[RB.VEL + i] *= sqrt(scale)
		out[RB.RATE + i] /= sqrt(scale)
	return out


func scaled_array(values: PackedFloat64Array, scale: float) -> PackedFloat64Array:
	var out: PackedFloat64Array = values.duplicate()
	for i: int in out.size():
		out[i] *= scale
	return out


# This is a derived test fixture, not a flyable aircraft-data rewrite. All active dimensional
# geometry is scaled; dimensionless polars, angles and the induced-flow map are unchanged.
func scaled_model(model: Dictionary, scale: float) -> Dictionary:
	var out: Dictionary = model.duplicate(true)
	out.mass_kg *= pow(scale, 3)
	out.inertia = scaled_array(out.inertia, pow(scale, 5))
	out.cg_le = scaled_array(out.cg_le, scale)
	out.cg_inventory_le = scaled_array(out.cg_inventory_le, scale)
	out.reference.S *= scale * scale
	for key: String in ["b", "c", "geometric_chord"]:
		out.reference[key] *= scale
	out.reference.arp_le = scaled_array(out.reference.arp_le, scale)
	out.reference.chords = scaled_array(out.reference.chords, scale)
	out.envelope.station_ys = scaled_array(out.envelope.station_ys, scale)
	for name: String in ["horizontal", "vertical"]:
		out.surfaces[name].position = scaled_array(out.surfaces[name].position, scale)
		out.surfaces[name].area *= scale * scale
	out.surfaces.horizontal.downwash_lag_length *= scale
	out.controls.servo_rate /= sqrt(scale)
	out.start_speed *= sqrt(scale)
	# Stopped engine: lengths/inertia/times are still transformed, but powered similarity is not claimed.
	out.propulsion.diameter *= scale
	out.propulsion.offset = scaled_array(out.propulsion.offset, scale)
	out.propulsion.rotor_inertia *= pow(scale, 5)
	out.propulsion.lag *= sqrt(scale)
	out.propulsion.idle_rpm /= sqrt(scale)
	out.propulsion.max_rpm /= sqrt(scale)
	return out


func fixture(model: Dictionary, initial: PackedFloat64Array, hz: int) -> Node:
	Engine.physics_ticks_per_second = hz
	var session: Node = Session.new()
	session.sim = Simulation.new()
	session.sim.modes = PackedInt64Array([0])
	session.add_child(session.sim)
	# Wire the production callbacks without a powered trim solve or scene/input side effects.
	session._commit_aircraft({data = {ok = true, model = model, warnings = []},
		start = {ok = true, state = initial, mode = "glide", throttle = 0.0, rpm = 0.0},
		trims = {roll = 0.0, pitch = 0.0, yaw = 0.0}})
	session.reset()
	return session


func energy(s: PackedFloat64Array, model: Dictionary) -> float:
	var v: PackedFloat64Array = s.slice(RB.VEL, RB.VEL + 3)
	var w: PackedFloat64Array = s.slice(RB.RATE, RB.RATE + 3)
	return 0.5 * float(model.mass_kg) * M.dot(v, v) - float(model.mass_kg) * 9.80665 * s[RB.POS + 2] \
		+ 0.5 * M.dot(w, RB.inertia_mul(model.inertia, w))


func fly(model: Dictionary, initial: PackedFloat64Array, hz: int, direction: float, neutral: bool = false) -> Array:
	var session: Node = fixture(model, initial, hz)
	var frames: Array = []
	_cases += 1
	for tick: int in range(TICKS + 1):
		var s: PackedFloat64Array = session.sim.state
		var aux: PackedFloat64Array = session.sim.aux
		check("integrity", 0.0 if session.sim.fault_reason.is_empty() and session.sim.tick == tick else 1.0, 0.0, "flight %d tick %d" % [_cases, tick])
		for value: float in s:
			check("integrity", 0.0 if is_finite(value) else 1.0, 0.0, "finite state")
		check("integrity", absf(aux[0]), 0.0, "engine remains stopped")
		var d: Dictionary = session._deflections(aux)
		var air: Dictionary = Air.compute(s, M.v3(0, 0, 0))
		var weight: float = Aero.local_flow_weight(s, air, d, model)
		_coverage["attached" if weight == 0.0 else ("local" if weight == 1.0 else "blended")] += 1
		var lag: int = session.downwash_index()
		if absf(aux[lag] - Aero.wing_lift_coefficient(s, air, d, model)) > 1e-5:
			_coverage.lag_transient += 1
		frames.append({state = s.duplicate(), aux = aux.duplicate(), energy_J = energy(s, model)})
		if tick == TICKS:
			break
		# Matched dimensionless command timing; includes full aileron reversal and servo slew.
		var roll: float = direction * (1.0 if tick < 80 else (-1.0 if tick < 160 else 0.0))
		var pitch: float = 0.15 if tick < 120 else -0.1
		var yaw: float = direction * (0.2 if tick < 100 else -0.1)
		session.sim.inputs = PackedFloat64Array([0.0, 0.0, 0.0, 0.0]) if neutral else PackedFloat64Array([roll, pitch, yaw, 0.0])
		if absf(aux[1] - session.sim.inputs[0]) > 1e-5:
			_coverage.moving_servo += 1
		session.sim.step()
	session.free()
	return frames


func compare_mirror(left: Array, right: Array, label: String) -> void:
	for tick: int in left.size():
		var expected: PackedFloat64Array = mirror(left[tick].state)
		for i: int in RB.SIZE:
			check("mirror", absf(right[tick].state[i] - expected[i]), 1e-12, "%s tick %d state %d" % [label, tick, i])
		for i: int in left[tick].aux.size():
			var sign_: float = -1.0 if i == 1 or i == 3 else 1.0
			check("mirror", absf(right[tick].aux[i] - sign_ * left[tick].aux[i]), 1e-12, "%s tick %d aux %d" % [label, tick, i])


func compare_scale(base: Array, scaled: Array, scale: float, label: String) -> void:
	for tick: int in base.size():
		var restored: PackedFloat64Array = scaled_state(scaled[tick].state, 1.0 / scale)
		for i: int in RB.SIZE:
			check("froude", absf(restored[i] - base[tick].state[i]) / maxf(1.0, absf(base[tick].state[i])), 1e-9,
				"%s N=%.2f tick %d state %d" % [label, scale, tick, i])
		for i: int in base[tick].aux.size():
			check("froude", absf(scaled[tick].aux[i] - base[tick].aux[i]) / maxf(1.0, absf(base[tick].aux[i])), 1e-9,
				"%s N=%.2f tick %d aux %d" % [label, scale, tick, i])


func asymmetric_surface_probes(model: Dictionary) -> void:
	# Differential ailerons alone cannot expose equal-sign Cnda: both contributions cancel.
	# One-sided deflections must also reflect correctly; probe both actual aerodynamic paths.
	for angle: float in [0.0, deg_to_rad(25.0)]:
		var state: PackedFloat64Array = RB.make_state(M.v3(0, 0, -100), M.v3(15*cos(angle), 0.3, 15*sin(angle)),
			M.q_from_euler(0.2, 0.1, -0.3), M.v3(0.1, -0.05, 0.2))
		var reflected: PackedFloat64Array = mirror(state)
		var d: Dictionary = {elevator = 0.0, aileron_right = model.controls.throw_rad.aileron, aileron_left = 0.0, rudder = 0.02}
		var dm: Dictionary = {elevator = 0.0, aileron_right = 0.0, aileron_left = model.controls.throw_rad.aileron, rudder = -0.02}
		var air: Dictionary = Air.compute(state, M.v3(0, 0, 0))
		var air_m: Dictionary = Air.compute(reflected, M.v3(0, 0, 0))
		var branch: float = 0.0 if angle == 0.0 else 1.0
		check("coverage", absf(Aero.local_flow_weight(state, air, d, model) - branch), 0.0, "asymmetric surface branch")
		check("coverage", absf(Aero.local_flow_weight(reflected, air_m, dm, model) - branch), 0.0, "reflected surface branch")
		var f: PackedFloat64Array = Aero.loads(state, air, d, model, Air.RHO_SEA_LEVEL)
		var fm: PackedFloat64Array = Aero.loads(reflected, air_m, dm, model, Air.RHO_SEA_LEVEL)
		var signs: Array = [1, -1, 1, -1, 1, -1]
		for i: int in 6:
			check("mirror", absf(fm[i] - signs[i]*f[i]), 1e-12, "one-sided aileron branch %d load %d" % [int(branch), i])


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 1:
		printerr("VAL-4: expected output.json")
		quit(2)
		return
	var data: Dictionary = AD.load_file("res://data/aircraft/jensen_ugly_stik_60.json")
	if not data.ok:
		printerr("VAL-4: invalid aircraft: ", data.errors)
		quit(2)
		return
	var original: Dictionary = data.model
	var model: Dictionary = original.duplicate(true)
	# Geometric/derivative symmetry is checked by the tests, not manufactured by overwriting coefficients.
	# Remove only declared mass asymmetry and inactive ground/prop-wash features for the symmetric fixture.
	model.inertia[3] = 0.0
	model.inertia[5] = 0.0
	model.landing_gear = {}
	model.propulsion.erase("slipstream")
	asymmetric_surface_probes(model)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = SEED
	var starts: Array = [
		RB.make_state(M.v3(0, 2, -100), M.v3(15, 0, 1), M.q_identity(), M.v3(0, 0, 0)),
		RB.make_state(M.v3(3, -2, -100), M.v3(10, 2, 5), M.q_from_euler(0.3, -0.2, 0.7), M.v3(2, -1, 0.5)),
		RB.make_state(M.v3(-2, 4, -100), M.v3(-12, 1, -4), M.q_from_euler(-0.7, 0.6, -0.2), M.v3(-1, 2, -0.3)),
		RB.make_state(M.v3(0, 0, -100), M.v3(0, 0, 0), M.q_from_euler(1, 0.4, -1), M.v3(3, -2, 1))]
	for index: int in starts.size():
		var initial: PackedFloat64Array = starts[index]
		var base: Array = fly(model, initial, 240, 1.0)
		compare_mirror(base, fly(model, mirror(initial), 240, -1.0), "case %d" % index)
		for scale: float in [0.25, 2.25, 4.0, 9.0]:
			compare_scale(base, fly(scaled_model(model, scale), scaled_state(initial, scale), int(round(240.0 / sqrt(scale))), 1.0), scale, "case %d" % index)
	# Energy uses the original asymmetric inertia, neutral fixed surfaces, no wind, stopped engine, no ground.
	var passive: Dictionary = original.duplicate(true)
	passive.landing_gear = {}
	passive.propulsion.erase("slipstream")
	for index: int in 32:
		var speed: float = rng.randf_range(0, 30) if index != 0 else 0.0
		var alpha: float = rng.randf_range(-PI, PI)
		var beta: float = rng.randf_range(-1.2, 1.2)
		var initial: PackedFloat64Array = RB.make_state(M.v3(0, 0, -100),
			M.v3(speed*cos(alpha)*cos(beta), speed*sin(beta), speed*sin(alpha)*cos(beta)),
			M.q_from_euler(rng.randf_range(-PI, PI), rng.randf_range(-1.4, 1.4), rng.randf_range(-PI, PI)),
			M.v3(rng.randf_range(-8, 8), rng.randf_range(-8, 8), rng.randf_range(-8, 8)))
		var trace: Array = fly(passive, initial, 240, 0.0, true)
		for tick: int in range(1, trace.size()):
			check("energy", maxf(0.0, trace[tick].energy_J - trace[tick-1].energy_J), 1e-9, "seed case %d tick %d" % [index, tick])
	for key: String in _coverage:
		check("coverage", 0.0 if _coverage[key] > 0 else 1.0, 0.0, key)
	var failures: int = 0
	for group: String in _groups:
		failures += _groups[group].failures
	var report: Dictionary = {format = "openrc-metamorphic v1", engine = Engine.get_version_info().string,
		seed = SEED, ticks_per_flight = TICKS, flights = _cases, groups = _groups, coverage = _coverage,
		failures = failures, source_warnings = data.warnings}
	var file: FileAccess = FileAccess.open(args[0], FileAccess.WRITE)
	if file == null:
		printerr("VAL-4: cannot write output")
		quit(2)
		return
	file.store_string(JSON.stringify(report, "\t", true, true) + "\n")
	file.flush()
	var error: Error = file.get_error()
	file.close()
	print("VAL-4: %d flights, %d failures; %s" % [_cases, failures, str(_groups)])
	quit(2 if error != OK else (1 if failures else 0))
