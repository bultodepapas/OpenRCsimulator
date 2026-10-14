# RCV-04b: coupled four-corner verification. This constrained rig is not a 6DoF truck.
extends SceneTree

const Rig := preload("res://physics/ground_vehicle/four_corner.gd")
const Data := preload("res://physics/ground_vehicle/support_bench_data.gd")
const Quarter := preload("res://physics/ground_vehicle/quarter_car.gd")
var _count := 0
var _failures := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	print("%s %s %s" % ["ok  " if ok else "FAIL", label, detail])
	if not ok:
		_failures += 1


func _path(name: String) -> String:
	return ProjectSettings.globalize_path("res://").path_join("../research/rc-monster-truck/" + name)


func _flat(_t: float) -> PackedFloat64Array:
	return PackedFloat64Array([0, 0, 0, 0])


func _error(a: PackedFloat64Array, b: PackedFloat64Array) -> float:
	var result := 0.0
	for i in a.size():
		result = maxf(result, absf(a[i] - b[i]))
	return result


func _run(s: PackedFloat64Array, p: Dictionary, hz: int, seconds: float, road: Callable) -> PackedFloat64Array:
	for i in roundi(seconds * hz):
		s = Rig.step(s, p, float(i) / hz, 1.0 / hz, road)
	return s


func _reject(label: String, raw: Variant) -> void:
	var loaded := Data.validate(raw)
	_check(label, not loaded.ok and not loaded.errors.is_empty() and loaded.parameters.is_empty() and loaded.id.is_empty())


func _contract(raw: Dictionary, p: Dictionary) -> void:
	var original := JSON.stringify(raw)
	Data.validate(raw)
	_check("data validation preserves source", JSON.stringify(raw) == original)
	var named := raw.duplicate(true)
	named.id = "rcv-forward-cg-experiment"
	_check("custom experiment identity survives validation", Data.validate(named).id == named.id)
	named.id = " "
	_reject("reject empty identity", named)
	_reject("reject non-object profile", [])
	for key in raw:
		var missing := raw.duplicate(true)
		missing.erase(key)
		_reject("reject missing " + key, missing)
	var bad := raw.duplicate(true)
	bad.version = 2
	_reject("reject future version", bad)
	bad = raw.duplicate(true)
	bad.unrecognized = true
	_reject("reject unknown top-level field", bad)
	bad = raw.duplicate(true)
	bad.parameters.unrecognized = {"value": 1, "unit": "kg", "kind": "estimated", "source": "test"}
	_reject("reject unknown parameter", bad)
	for key in raw.parameters:
		bad = raw.duplicate(true)
		bad.parameters.erase(key)
		_reject("reject missing parameter " + key, bad)
		bad = raw.duplicate(true)
		bad.parameters[key].value = NAN
		_reject("reject nonfinite " + key, bad)
	for invalid in [true, "4.8", null, INF, 0.0, -1.0]:
		bad = raw.duplicate(true)
		bad.parameters.sprung_mass_kg.value = invalid
		_reject("reject malformed mass " + str(invalid), bad)
	for edit in [{"unit": "g"}, {"kind": "proven"}, {"source": " "}, {"extra": 1}]:
		bad = raw.duplicate(true)
		bad.parameters.sprung_mass_kg.merge(edit, true)
		_reject("reject malformed quantity " + str(edit), bad)
	for key in ["roll_inertia_kg_m2", "pitch_inertia_kg_m2", "half_track_m", "front_axle_x_m", "rear_axle_x_m"]:
		bad = raw.duplicate(true)
		bad.parameters[key].value = 0.0
		_reject("reject degenerate support " + key, bad)
	bad = raw.duplicate(true)
	bad.parameters.rear_axle_x_m.value = 0.18
	_reject("reject CG outside axle interval", bad)
	for key in ["tire_stiffness_n_per_m", "suspension_stiffness_n_per_m"]:
		bad = raw.duplicate(true)
		bad.parameters[key].value = 1.0
		_reject("reject static collapse " + key, bad)
	bad = raw.duplicate(true)
	bad.parameters.gravity_m_per_s2.value = 0.0
	bad.parameters.suspension_damping_n_s_per_m.value = 0.0
	_check("zero gravity and damping accepted explicitly", Data.validate(bad).ok)
	_check("corner ordering and handedness", p.corner_x_m == PackedFloat64Array([0.18, 0.18, -0.18, -0.18]) and p.corner_y_m == PackedFloat64Array([0.2, -0.2, 0.2, -0.2]))
	_check("malformed JSON is refused", not Data.parse_text("{").ok)
	_check("missing profile is refused", not Data.load_file(_path("missing-support.json")).ok)


func _statics(raw: Dictionary, p: Dictionary) -> void:
	var solved := Rig.equilibrium(p)
	_check("four-contact equilibrium exists", solved.ok, str(solved.errors))
	if not solved.ok:
		return
	var s: PackedFloat64Array = solved.state
	var f := Rig.loads(s, p)
	var residual := Rig.derivative(s, p)
	var residual_max := 0.0
	for value in residual:
		residual_max = maxf(residual_max, absf(value))
	_check("static force and moment balance", residual_max < 1e-10, str(residual_max))
	var equal := true
	for i in 4:
		equal = equal and absf(f.tire_force_n[i] - (p.sprung_mass_kg / 4.0 + p.unsprung_mass_kg) * p.gravity_m_per_s2) < 1e-10
	_check("four tires support disjoint body and hub masses once", equal)
	_check("equilibrium remains at rest for two seconds", _error(_run(s, p, 240, 2.0, _flat), s) < 1e-11)
	var shifted := raw.duplicate(true)
	shifted.parameters.front_axle_x_m.value = 0.14
	shifted.parameters.rear_axle_x_m.value = -0.22
	var cp: Dictionary = Data.validate(shifted).parameters
	var cs: PackedFloat64Array = Rig.equilibrium(cp).state
	var cf := Rig.loads(cs, cp)
	var expected_front: float = cp.sprung_mass_kg * cp.gravity_m_per_s2 * 0.22 / 0.36
	_check("forward CG changes front axle load by lever-arm law", absf(cf.suspension_force_n[0] + cf.suspension_force_n[1] - expected_front) < 1e-10)
	_check("forward CG gives symmetric left/right loading", absf(cf.tire_force_n[0] - cf.tire_force_n[1]) < 1e-10 and absf(cf.tire_force_n[2] - cf.tire_force_n[3]) < 1e-10)
	var road := PackedFloat64Array()
	for i in 4:
		road.append(0.02 + 0.015 * p.corner_y_m[i] - 0.012 * p.corner_x_m[i])
	var plane := Rig.equilibrium(p, road)
	_check("inclined support equilibrium", plane.ok and absf(plane.state[0] - s[0] - 0.02) < 1e-11 and absf(plane.state[1] - 0.015) < 1e-11 and absf(plane.state[2] - 0.012) < 1e-11)
	var impossible := Rig.equilibrium(p, PackedFloat64Array([1.0, -1.0, -1.0, 1.0]))
	_check("refuse all-contact equilibrium that needs tensile ground", not impossible.ok and impossible.state.is_empty())
	var zero_g := p.duplicate()
	zero_g.gravity_m_per_s2 = 0.0
	var neutral := Rig.equilibrium(zero_g, road)
	_check("zero-g planar equilibrium exists without preload", neutral.ok)
	if neutral.ok:
		var nf := Rig.loads(neutral.state, zero_g, road)
		var nd := Rig.derivative(neutral.state, zero_g, road)
		var neutral_error := 0.0
		for value in nd:
			neutral_error = maxf(neutral_error, absf(value))
		for value in nf.tire_force_n:
			neutral_error = maxf(neutral_error, absf(value))
		_check("zero-g neutral load and acceleration vanish", neutral_error < 1e-10)
	_check("zero-g saddle cannot be an unstrained neutral pose", not Rig.equilibrium(zero_g, PackedFloat64Array([0.01, 0, 0, 0.01])).ok)
	_check("equilibrium rejects invalid road shape", not Rig.equilibrium(p, PackedFloat64Array([0, 0, 0])).ok)


func _quarter_reduction(p: Dictionary) -> void:
	var qp := p.duplicate()
	qp.sprung_mass_kg /= 4.0
	var q := Quarter.equilibrium(qp)
	q[0] += 0.001
	q[1] += 0.0002
	var s: PackedFloat64Array = Rig.equilibrium(p).state
	s[0] = q[0]
	for i in 4:
		s[3 + i] = q[1]
	var worst := 0.0
	var angles := 0.0
	var flat_scalar := func(_t: float) -> float: return 0.0
	for tick in 240:
		s = Rig.step(s, p, float(tick) / 240, 1.0 / 240, _flat)
		q = Quarter.step(q, qp, float(tick) / 240, 1.0 / 240, flat_scalar)
		worst = maxf(worst, absf(s[0] - q[0]))
		worst = maxf(worst, absf(s[7] - q[2]))
		for i in 4:
			worst = maxf(worst, absf(s[3 + i] - q[1]))
			worst = maxf(worst, absf(s[10 + i] - q[3]))
		angles = maxf(angles, maxf(absf(s[1]), absf(s[2])))
	_check("symmetric four-corner motion reduces to the verified quarter car", worst < 1e-11, str(worst))
	_check("symmetric heave creates no roll or pitch", angles < 1e-13)


func _oracle(p: Dictionary) -> void:
	var fixture: Variant = JSON.parse_string(FileAccess.get_file_as_string(_path("fixtures/support_reference.json")))
	_check("independent 14-state reference exists", fixture is Dictionary)
	if not fixture is Dictionary:
		return
	var matches := true
	for key in fixture.parameters:
		matches = matches and p.has(key) and float(p[key]) == float(fixture.parameters[key])
	_check("independent reference agrees with input parameters", matches)
	for name in ["damped", "undamped"]:
		var case: Dictionary = fixture.cases[name]
		var cp := p.duplicate()
		cp.suspension_damping_n_s_per_m = case.suspension_damping_n_s_per_m
		var errors := PackedFloat64Array()
		var position_errors := PackedFloat64Array()
		for hz in [240, 480, 960, 1920]:
			var s := PackedFloat64Array(fixture.initial_state)
			var worst := 0.0
			var position_worst := 0.0
			var sample_index := 0
			for tick in hz:
				s = Rig.step(s, cp, float(tick) / hz, 1.0 / hz, _flat)
				if sample_index < case.samples.size() and tick + 1 == roundi(float(case.samples[sample_index].time_s) * hz):
					var reference := PackedFloat64Array(case.samples[sample_index].state)
					worst = maxf(worst, _error(s, reference))
					for j in 7:
						position_worst = maxf(position_worst, absf(s[j] - reference[j]))
					sample_index += 1
			_check(name + " all reference times sampled at %d Hz" % hz, sample_index == case.samples.size())
			errors.append(worst)
			position_errors.append(position_worst)
		# Predeclared, before execution: normalized m/rad/m/s/rad/s maxima.
		_check(name + " independent response accuracy", errors[0] < 2e-3 and errors[3] < 2e-6, str(errors))
		_check(name + " displacement/angle accuracy", position_errors[0] < 2e-5 and position_errors[3] < 2e-8, str(position_errors))
		var r := PackedFloat64Array([errors[0] / errors[1], errors[1] / errors[2], errors[2] / errors[3]])
		_check(name + " smooth fourth-order refinement", r[0] > 10 and r[0] < 24 and r[1] > 12 and r[1] < 22 and r[2] > 12 and r[2] < 20, str(r))


func _power_and_road(p: Dictionary) -> void:
	var s: PackedFloat64Array = Rig.equilibrium(p).state
	s[0] += 0.001
	s[1] = 0.004
	s[2] = -0.003
	for i in 7:
		s[7 + i] = 0.03 * (i - 2)
	var f := Rig.loads(s, p)
	var ds := Rig.derivative(s, p)
	var vertical: float = p.sprung_mass_kg * ds[7]
	var expected: float = -(p.sprung_mass_kg + 4.0 * p.unsprung_mass_kg) * float(p.gravity_m_per_s2)
	for i in 4:
		vertical += p.unsprung_mass_kg * ds[10 + i]
		expected += f.tire_force_n[i]
	_check("internal forces cancel in total vertical momentum", absf(vertical - expected) < 1e-11)
	var eps := 1e-7
	var plus := s.duplicate()
	var minus := s.duplicate()
	for j in 14:
		plus[j] += eps * ds[j]
		minus[j] -= eps * ds[j]
	var rv := PackedFloat64Array([0.01, -0.02, 0.03, -0.01])
	var hp := rv.duplicate()
	var hm := rv.duplicate()
	var power := 0.0
	for i in 4:
		hp[i] *= eps
		hm[i] *= -eps
		power += f.tire_force_n[i] * rv[i] - f.damper_loss_w[i]
	var de := (Rig.energy(plus, p, hp) - Rig.energy(minus, p, hm)) / (2 * eps)
	_check("four moving supports close energy/work balance", absf(de - power) < 2e-7, str(de - power))
	var shifted := s.duplicate()
	shifted[0] += 0.2
	shifted[7] += 0.03
	for i in 4:
		shifted[3 + i] += 0.2
		shifted[10 + i] += 0.03
	var moving_road := func(t: float) -> PackedFloat64Array:
		var h := 0.2 + 0.03 * t
		return PackedFloat64Array([h, h, h, h])
	shifted = _run(shifted, p, 240, 0.25, moving_road)
	shifted[0] -= 0.2075
	shifted[7] -= 0.03
	for i in 4:
		shifted[3 + i] -= 0.2075
		shifted[10 + i] -= 0.03
	_check("moving road trajectory respects a constant-velocity change of frame", _error(shifted, _run(s, p, 240, 0.25, _flat)) < 1e-11)
	var original := s.to_byte_array()
	var a := _run(s, p, 240, 0.1, _flat)
	var b := _run(s, p, 240, 0.1, _flat)
	_check("input state immutable and same-build replay exact", s.to_byte_array() == original and a.to_byte_array() == b.to_byte_array())
	var front_lift := func(_t: float) -> PackedFloat64Array: return PackedFloat64Array([0.005, 0.0, 0.0, 0.0])
	var response := _run(Rig.equilibrium(p).state, p, 240, 0.05, front_lift)
	_check("front-left lift raises left side and nose", response[1] > 0 and response[2] < 0)
	var right_lift := func(_t: float) -> PackedFloat64Array: return PackedFloat64Array([0, 0.005, 0, 0])
	var reflected := _run(Rig.equilibrium(p).state, p, 240, 0.05, right_lift)
	reflected[1] *= -1.0
	reflected[8] *= -1.0
	for pair in [[3, 4], [5, 6], [10, 11], [12, 13]]:
		var swap := reflected[pair[0]]
		reflected[pair[0]] = reflected[pair[1]]
		reflected[pair[1]] = swap
	_check("left/right wheel excitation is a mirror image", _error(response, reflected) < 1e-11)


func _energy_and_events(p: Dictionary) -> void:
	var cp := p.duplicate()
	cp.suspension_damping_n_s_per_m = 0.0
	var s: PackedFloat64Array = Rig.equilibrium(cp).state
	var eq_energy := Rig.energy(s, cp)
	s[0] += 0.0005
	s[1] = 0.0007
	s[2] = -0.0009
	var initial_energy := Rig.energy(s, cp)
	var peak := 0.0
	for i in 1920:
		s = Rig.step(s, cp, float(i) / 1920, 1.0 / 1920, _flat)
		peak = maxf(peak, absf(Rig.energy(s, cp) - initial_energy))
	_check("coupled undamped perturbation energy conserved", peak / (initial_energy - eq_energy) < 1e-4, String.num_scientific(peak / (initial_energy - eq_energy)))
	var start: PackedFloat64Array = Rig.equilibrium(p).state
	start[0] += 0.03
	for j in 4:
		start[3 + j] += 0.03
	var ends: Array[PackedFloat64Array] = []
	for hz in [240, 480, 960, 1920]:
		s = start.duplicate()
		var air := false
		var contact := false
		var finite := true
		var max_gain := 0.0
		var dissipated := 0.0
		var start_energy := Rig.energy(s, p)
		for i in hz:
			var loads := Rig.loads(s, p)
			air = air or loads.in_contact[0] == 0
			contact = contact or loads.in_contact[0] == 1
			var prev := Rig.energy(s, p)
			s = Rig.step(s, p, float(i) / hz, 1.0 / hz, _flat)
			var after := Rig.loads(s, p)
			for corner in 4:
				dissipated += 0.5 / hz * (loads.damper_loss_w[corner] + after.damper_loss_w[corner])
			for value in s:
				finite = finite and is_finite(value)
			max_gain = maxf(max_gain, Rig.energy(s, p) - prev)
		ends.append(s)
		_check("drop separates/recontacts and stays finite at %d Hz" % hz, air and contact and finite)
		_check("drop per-tick energy gain <= 4 mJ at %d Hz" % hz, max_gain < 4e-3, String.num_scientific(max_gain))
		# Independent trapezoidal dissipation quadrature; includes contact crossings.
		var balance := absf(Rig.energy(s, p) + dissipated - start_energy)
		var available := start_energy - Rig.energy(Rig.equilibrium(p).state, p)
		_check("drop accumulated energy/work residual <= 0.5 percent at %d Hz" % hz, balance / available < 0.005, String.num_scientific(balance / available))
	var coarse := _error(ends[0], ends[3])
	var fine := _error(ends[2], ends[3])
	_check("drop endpoint refines, without smooth-order claim", coarse < 0.02 and fine < 0.002 and fine < coarse, "%s %s" % [coarse, fine])


func _initialize() -> void:
	var loaded := Data.load_file(_path("support_bench.json"))
	_check("load strict support profile", loaded.ok, str(loaded.errors))
	if loaded.ok:
		var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_path("support_bench.json")))
		_contract(raw, loaded.parameters)
		_statics(raw, loaded.parameters)
		_quarter_reduction(loaded.parameters)
		_oracle(loaded.parameters)
		_power_and_road(loaded.parameters)
		_energy_and_events(loaded.parameters)
	print("RCV-04b: %d checks, %d failed" % [_count, _failures])
	quit(1 if _failures else 0)
