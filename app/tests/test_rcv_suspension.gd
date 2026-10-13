# RCV-04a: independent suspension oracle, contact, passivity and strict data validation.
extends SceneTree

const BenchData := preload("res://physics/ground_vehicle/suspension_bench_data.gd")
const Car := preload("res://physics/ground_vehicle/quarter_car.gd")
const M := preload("res://physics/math3d.gd")
const STATE_KEYS := ["z_s_m", "z_u_m", "v_s_m_per_s", "v_u_m_per_s"]

var _failures := 0
var _count := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	print("%s %s %s" % ["ok  " if ok else "FAIL", label, detail])
	if not ok:
		_failures += 1


func _research_path(name: String) -> String:
	return ProjectSettings.globalize_path("res://").path_join("../research/rc-monster-truck/" + name)


func _flat(_t: float) -> float:
	return 0.0


func _run(s: PackedFloat64Array, p: Dictionary, hz: int, seconds: float, road: Callable) -> PackedFloat64Array:
	for i in roundi(seconds * hz):
		s = Car.step(s, p, float(i) / hz, 1.0 / hz, road)
	return s


func _state(raw: Dictionary) -> PackedFloat64Array:
	var s := PackedFloat64Array()
	for key in STATE_KEYS:
		s.append(raw[key])
	return s


func _max_error(a: PackedFloat64Array, b: PackedFloat64Array) -> float:
	var error := 0.0
	# Explicit normalization: positions / 1 m, velocities / 1 m/s.
	for i in 4:
		error = maxf(error, absf(a[i] - b[i]))
	return error


func _reject(label: String, raw: Variant) -> void:
	var r := BenchData.validate(raw)
	_check(label, not r.ok and not r.errors.is_empty() and r.parameters.is_empty() and r.id.is_empty())


func _data_tests(raw: Dictionary) -> void:
	var before := JSON.stringify(raw)
	_check("profile accepts synthetic quantities", BenchData.validate(raw).ok)
	_check("validation leaves source untouched", before == JSON.stringify(raw))
	_reject("reject non-object", [])
	for key in raw:
		var missing := raw.duplicate(true)
		missing.erase(key)
		_reject("reject missing " + key, missing)
	var extra := raw.duplicate(true)
	extra["typo"] = 1
	_reject("reject unknown top-level field", extra)
	var wrong_version := raw.duplicate(true)
	wrong_version.version = 2
	_reject("reject future version", wrong_version)
	wrong_version.version = true
	_reject("reject boolean version", wrong_version)
	var bad := raw.duplicate(true)
	bad.parameters.typo = bad.parameters.sprung_mass_kg
	_reject("reject unknown parameter", bad)
	bad = raw.duplicate(true)
	bad.parameters.erase("sprung_mass_kg")
	_reject("reject missing parameter", bad)
	for invalid in [true, "1.2", null, NAN, INF, -INF, 0.0, -1.0]:
		bad = raw.duplicate(true)
		bad.parameters.sprung_mass_kg.value = invalid
		_reject("reject invalid mass %s" % str(invalid), bad)
	for field in ["value", "unit", "kind", "source"]:
		bad = raw.duplicate(true)
		bad.parameters.sprung_mass_kg.erase(field)
		_reject("reject missing quantity " + field, bad)
	for change in [{"unit": "g"}, {"kind": "verified"}, {"source": "  "}, {"extra": "ignored?"}]:
		bad = raw.duplicate(true)
		bad.parameters.sprung_mass_kg.merge(change, true)
		_reject("reject malformed quantity " + str(change), bad)
	for key in BenchData.UNITS:
		bad = raw.duplicate(true)
		bad.parameters[key].value = -1.0
		_reject("reject negative " + key, bad)
	bad = raw.duplicate(true)
	bad.parameters.suspension_damping_n_s_per_m.value = 0.0
	bad.parameters.gravity_m_per_s2.value = 0.0
	_check("zero damping and zero gravity are explicit supported cases", BenchData.validate(bad).ok)
	bad = raw.duplicate(true)
	bad.parameters.tire_stiffness_n_per_m.value = 1.0
	_reject("reject statically collapsed tire", bad)
	bad = raw.duplicate(true)
	bad.parameters.suspension_stiffness_n_per_m.value = 1.0
	_reject("reject statically inverted suspension", bad)
	_check("missing file fails closed", not BenchData.load_file(_research_path("no-such-profile.json")).ok)


func _statics_and_signs(p: Dictionary) -> void:
	var s := Car.equilibrium(p)
	var f := Car.loads(s, p)
	var g: float = p.gravity_m_per_s2
	_check("static tire supports both masses", absf(f.tire_force_n - (p.sprung_mass_kg + p.unsprung_mass_kg) * g) < 1e-12)
	_check("static suspension supports sprung mass", absf(f.suspension_force_n - p.sprung_mass_kg * g) < 1e-12)
	_check("equilibrium accelerations vanish", _max_error(Car.derivative(s, p), PackedFloat64Array([0, 0, 0, 0])) < 1e-11)
	var final := _run(s, p, 240, 2.0, _flat)
	_check("equilibrium remains at rest", _max_error(final, s) < 1e-12)
	var translated := Car.equilibrium(p, 12.0)
	translated[0] -= 12.0
	translated[1] -= 12.0
	_check("road translation preserves static geometry", _max_error(translated, s) < 1e-13)
	var moving := s.duplicate()
	moving[2] = 0.7
	moving[3] = -0.2
	var no_damping := p.duplicate()
	no_damping.suspension_damping_n_s_per_m = 0.0
	var damped := Car.derivative(moving, p)
	var undamped := Car.derivative(moving, no_damping)
	var work: float = p.sprung_mass_kg * moving[2] * (damped[2] - undamped[2]) + p.unsprung_mass_kg * moving[3] * (damped[3] - undamped[3])
	_check("damper removes relative-motion energy", absf(work + p.suspension_damping_n_s_per_m * 0.9 * 0.9) < 1e-12)
	var airborne := PackedFloat64Array([1.1, 1.0, 0.0, 0.0])
	var af := Car.loads(airborne, p)
	var ad := Car.derivative(airborne, p)
	_check("separated tire cannot pull on road", af.tire_force_n == 0.0 and not af.in_contact)
	_check("unstrained airborne masses fall together", absf(ad[2] + g) < 1e-11 and absf(ad[3] + g) < 1e-11)
	var falling := _run(airborne, p, 240, 0.1, _flat)
	_check("airborne free fall matches analytic polynomial", absf(falling[0] - (airborne[0] - 0.5 * g * 0.01)) < 1e-12 and absf(falling[3] + g * 0.1) < 1e-12)
	var original := moving.to_byte_array()
	Car.step(moving, p, 0.0, 1.0 / 240.0, _flat)
	Car.energy(moving, p)
	Car.loads(moving, p)
	_check("kernel never mutates input state", moving.to_byte_array() == original)
	var stage_times := PackedFloat64Array()
	var road := func(t: float) -> float:
		stage_times.append(t)
		return 0.0
	Car.step(s, p, 1.0, 0.02, road)
	_check("road sampled at both substeps' RK stage times", stage_times.size() == 8)
	var expected := PackedFloat64Array([1.0, 1.005, 1.005, 1.01, 1.01, 1.015, 1.015, 1.02])
	var stage_error := 0.0
	if stage_times.size() == expected.size():
		for i in expected.size():
			stage_error = maxf(stage_error, absf(stage_times[i] - expected[i]))
	_check("substeps preserve nonautonomous stage time", stage_times.size() == expected.size() and stage_error < 1e-14)
	_check("same-build repeated trajectory is byte-identical", _run(moving, p, 240, 0.25, _flat).to_byte_array() == _run(moving, p, 240, 0.25, _flat).to_byte_array())
	# A road and both masses translating at constant speed is a Galilean change
	# of frame. This independently exercises road values AND their stage times.
	var road_motion := func(t: float) -> float: return 0.2 + 0.03 * t
	var lifted := moving.duplicate()
	for i in 2:
		lifted[i] += 0.2
		lifted[i + 2] += 0.03
	lifted = _run(lifted, p, 240, 0.25, road_motion)
	for i in 2:
		lifted[i] -= 0.2 + 0.03 * 0.25
		lifted[i + 2] -= 0.03
	_check("moving road preserves equivalent trajectory", _max_error(lifted, _run(moving, p, 240, 0.25, _flat)) < 1e-11)


func _oracle_tests(p: Dictionary) -> void:
	var fixture: Variant = JSON.parse_string(FileAccess.get_file_as_string(_research_path("fixtures/suspension_reference.json")))
	_check("independent matrix-exponential fixture exists", fixture is Dictionary)
	if not fixture is Dictionary:
		return
	for key in p:
		_check("fixture/profile agree: " + key, float(fixture.parameters[key]) == float(p[key]))
	for case_name in ["damped", "undamped"]:
		var case: Dictionary = fixture.cases[case_name]
		var cp := p.duplicate()
		cp.suspension_damping_n_s_per_m = case.suspension_damping_n_s_per_m
		var initial := _state(fixture.initial_state)
		var errors := PackedFloat64Array()
		var position_errors := PackedFloat64Array()
		for hz in [240, 480, 960, 1920]:
			var worst := 0.0
			var position_worst := 0.0
			for sample in case.samples:
				var s := _run(initial, cp, hz, sample.time_s, _flat)
				var expected_state := _state(sample.state)
				worst = maxf(worst, _max_error(s, expected_state))
				for j in 2:
					position_worst = maxf(position_worst, absf(s[j] - expected_state[j]))
			errors.append(worst)
			position_errors.append(position_worst)
		# Freeze before first run: 240 Hz velocity error <= 2 mm/s; fine <= 2 um/s.
		_check(case_name + " matches independent oracle", errors[0] < 2e-3 and errors[3] < 2e-6, str(errors))
		_check(case_name + " position accuracy", position_errors[0] < 2e-5 and position_errors[3] < 2e-8, str(position_errors))
		var ratios := PackedFloat64Array([errors[0] / errors[1], errors[1] / errors[2], errors[2] / errors[3]])
		_check(case_name + " smooth fourth-order convergence", ratios[0] > 10 and ratios[0] < 24 and ratios[1] > 12 and ratios[1] < 20 and ratios[2] > 12 and ratios[2] < 20, str(ratios))


func _energy_tests(p: Dictionary) -> void:
	var cp := p.duplicate()
	cp.suspension_damping_n_s_per_m = 0.0
	var s := Car.equilibrium(cp)
	s[0] += 0.001
	s[1] += 0.0002
	var e0 := Car.energy(s, cp)
	var e_eq := Car.energy(Car.equilibrium(cp), cp)
	var peak_error := 0.0
	for i in 1920:
		s = Car.step(s, cp, float(i) / 1920, 1.0 / 1920, _flat)
		peak_error = maxf(peak_error, absf(Car.energy(s, cp) - e0))
	_check("undamped contact conserves perturbation energy at 1920 Hz", peak_error / (e0 - e_eq) < 1e-4, "relative=" + String.num_scientific(peak_error / (e0 - e_eq)))
	s = Car.equilibrium(p)
	s[0] += 0.01
	var max_gain := 0.0
	for i in 960:
		var prev := Car.energy(s, p)
		s = Car.step(s, p, float(i) / 960, 1.0 / 960, _flat)
		max_gain = maxf(max_gain, Car.energy(s, p) - prev)
	_check("damped release does not gain energy", max_gain < 1e-10, "max gain=" + String.num_scientific(max_gain))
	# Moving support: dE/dt = tire_force * road_velocity - damper_loss.
	s = Car.equilibrium(p)
	s[2] = 0.1
	s[3] = -0.2
	var d := Car.derivative(s, p)
	var eps := 1e-7
	var plus := s.duplicate()
	var minus := s.duplicate()
	for j in 4:
		plus[j] += eps * d[j]
		minus[j] -= eps * d[j]
	var numerical := (Car.energy(plus, p, eps * 0.03) - Car.energy(minus, p, -eps * 0.03)) / (2.0 * eps)
	var f := Car.loads(s, p)
	_check("moving road work closes local energy balance", absf(numerical - (f.tire_force_n * 0.03 - f.dissipation_w)) < 1e-7)


func _event_tests(p: Dictionary) -> void:
	var initial := Car.equilibrium(p)
	initial[0] += 0.05
	initial[1] += 0.05
	var ends: Array[PackedFloat64Array] = []
	for hz in [240, 480, 960, 1920]:
		var s := initial.duplicate()
		var had_air := false
		var had_contact := false
		var finite := true
		var max_energy_gain := 0.0
		for i in hz:
			var f := Car.loads(s, p)
			had_air = had_air or not f.in_contact
			had_contact = had_contact or f.in_contact
			var prev := Car.energy(s, p)
			s = Car.step(s, p, float(i) / hz, 1.0 / hz, _flat)
			max_energy_gain = maxf(max_energy_gain, Car.energy(s, p) - prev)
			for value in s:
				finite = finite and is_finite(value)
		ends.append(s)
		_check("drop separates and reacquires contact at %d Hz" % hz, had_air and had_contact and finite)
		# Event convergence has a separate, looser passivity budget than smooth motion.
		_check("drop event energy gain <= 1 mJ at %d Hz" % hz, max_energy_gain < 1e-3, String.num_scientific(max_energy_gain))
	var coarse := _max_error(ends[0], ends[3])
	var medium := _max_error(ends[1], ends[3])
	var fine := _max_error(ends[2], ends[3])
	_check("drop endpoint refines without claiming fourth order at contact", coarse < 0.02 and fine < 0.002 and fine < coarse and medium < coarse, "%s %s %s" % [coarse, medium, fine])


func _initialize() -> void:
	var loaded := BenchData.load_file(_research_path("suspension_bench.json"))
	_check("load bench profile", loaded.ok, str(loaded.errors))
	if loaded.ok:
		var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_research_path("suspension_bench.json")))
		_data_tests(raw)
		_statics_and_signs(loaded.parameters)
		_oracle_tests(loaded.parameters)
		_energy_tests(loaded.parameters)
		_event_tests(loaded.parameters)
	print("RCV-04a: %d checks, %d failed" % [_count, _failures])
	quit(1 if _failures else 0)
