extends "res://tests/test_aircraft_ground_electric.gd"
const Accuracy := preload("res://physics/aircraft_ground_accuracy.gd")
var quality: Dictionary
var layout: Dictionary
var policy: Dictionary


func _initialize() -> void:
	_fixture()
	_electric_fixture()
	if not failed:
		_accuracy_fixture()
	if not failed:
		_actual_electric_oracle()
		_kinematics_and_units()
		_complete_layout_rejections()
		_receipt_rejections()
		_prepared_integrity()
	print("Aircraft ground accuracy: %d checks, %d failed" % [checks, failed])
	quit(1 if failed else 0)


func _nq(value: float, unit: String) -> Dictionary:
	return {value = value, unit = unit, kind = "estimated", source = "Explicit test numerical acceptance choice, not a hardware measurement/default"}


func _tol(absolute: float, relative: float, floor_value: float, unit: String, sources: Array = []) -> Dictionary:
	var result := {absolute = _nq(absolute, unit), relative = _nq(relative, "1"), floor = _nq(floor_value, unit)}
	if not sources.is_empty(): result.scale_sources = sources.duplicate()
	return result


func _accuracy_fixture() -> void:
	var blocks: Array = []
	var tolerances := {}
	if electric.wash_count > 0:
		var indices := PackedInt64Array()
		for i in electric.wash_count: indices.append(RB.SIZE + i)
		blocks.append({id = "wash", indices = indices, unit = "m/s"})
		tolerances.wash = _tol(1e-5, 1e-5, 1e-12, "m/s")
	blocks.append({id = "shaft", indices = PackedInt64Array([electric.rotor_state_indices[0]]), unit = "rpm"})
	tolerances.shaft = _tol(1e-4, 1e-5, 1e-12, "rad/s")
	var ids := PackedStringArray()
	for i in electric.ground.radii_m.size():
		var id: String = electric.ground.normal.supports[i].contact_id
		ids.append(id)
		blocks.append({id = "rim:" + id, indices = PackedInt64Array([electric.rotor_state_indices[i + 1]]), unit = "m/s"})
		# Radius stays with selected hardware. Only a derived NUMERICAL rim-speed
		# target is provided to quality; no second physical radius is authored.
		var radius: float = electric.ground.radii_m[i]
		tolerances["rim:" + id] = _tol(1e-4 * radius, 1e-5, 1e-12 * radius, "m/s")
	layout = {format = Accuracy.LAYOUT_FORMAT, identity = electric.identity, state_layout_id = "electric-test-wash-rpm-rims-v1",
		state_size = RB.SIZE + electric.continuous_size, continuous_start = RB.SIZE,
		cg_body_m = electric.properties.cg_body_m.duplicate(), blocks = blocks, contact_ids = ids, step_law = Step.LAW, operator_order = 1}
	quality = {format = Accuracy.FORMAT, quality_name = "explicit-electric-throughput-quality-test-v1",
		source = "Numerical candidate profile only; no physical calibration or automatic runtime selection",
		body = {position = _tol(1e-6, 1e-5, .1, "m"), velocity_cm = _tol(1e-5, 1e-5, 1e-12, "m/s"),
			attitude = _tol(1e-6, 0, 1, "rad"), angular_rate = _tol(1e-5, 1e-5, 1e-12, "rad/s")},
		continuous = tolerances, normal_peak = _tol(.01, .02, .1, "N"), time_tolerance = _nq(1e-9, "s"),
		work = {external_work_j = _tol(1e-6, .005, 1e-12, "J", ["external_work_j"]),
			tangent_dissipation_j = _tol(1e-6, .005, 1e-12, "J", ["external_work_j", "tangent_dissipation_j"]),
			normal_dissipation_j = _tol(1e-6, 1e-5, 1e-12, "J", ["normal_dissipation_j"]),
			prescribed_contact_work_j = _tol(1e-6, 1e-5, 1e-12, "J", ["prescribed_contact_work_j"])}}
	var before := var_to_bytes([quality, layout])
	policy = Accuracy.prepare(quality, layout)
	check("explicit physical-owner layout and numerical profile prepare", policy.ok, str(policy))
	check("preparation is deterministic and leaves owners unchanged", before == var_to_bytes([quality, layout])
		and var_to_bytes(policy) == var_to_bytes(Accuracy.prepare(quality, layout)))
	var reordered := {}
	var keys: Array = layout.keys()
	keys.reverse()
	for key: Variant in keys: reordered[key] = layout[key]
	check("owner descriptor key insertion order does not change semantic pins", Accuracy.prepare(quality, reordered).identity == policy.identity)


func _receipt(n: int, start := 2.0, work := .02, loss := .01) -> Dictionary:
	var times := PackedFloat64Array()
	var samples: Array = []
	var zeros := PackedFloat64Array()
	zeros.resize(layout.contact_ids.size())
	for i in n + 1:
		times.append(start + .004 * i / n)
		samples.append(zeros.duplicate())
	var peak_times := zeros.duplicate()
	peak_times.fill(start)
	return {format = Step.RECEIPT_FORMAT, law = Step.LAW, contact_operator_order = 1, accepted_substeps = n,
		contact_ids = layout.contact_ids.duplicate(), normal_sample_times_s = times, normal_samples_n = samples,
		normal_sampling_method = "accepted_substep_start_and_end_states_not_interval_maximum",
		sampled_peak_normal_n = zeros, sampled_peak_times_s = peak_times,
		quadrature_method = "RK4_algebraic_stage_weights_not_damage_samples", certificate_identities = PackedStringArray(["explicit-test-certificate"]),
		normal_dissipation_j = 0.0, external_work_j = work, tangent_dissipation_j = loss, prescribed_contact_work_j = 0.0,
		absolute_impulse_sum = .01, initial_mechanical_energy_j = .1, final_mechanical_energy_j = .1 + work - loss,
		energy_balance_residual_j = 0.0, maximum_piece_energy_residual_j = 0.0}


func _state_pair() -> Array:
	var a := _runtime_initial()
	a[RB.VEL] = 2.0
	a[RB.VEL + 1] = 3.0
	a[RB.VEL + 2] = 4.0
	a[RB.RATE] = .1
	a[RB.RATE + 1] = .2
	a[RB.RATE + 2] = .3
	a[electric.rotor_state_indices[0]] = 3000.0
	for i in electric.ground.radii_m.size(): a[electric.rotor_state_indices[i + 1]] = 1.0 + i
	return [a, a.duplicate()]


func _actual_electric_oracle() -> void:
	var initial := _runtime_initial()
	for command: float in [.02, .15, 1.0]:
		runtime_duty = command
		var paths: Array = []
		for n in [8, 16]:
			var certificate := func(s, t, h, point):
				var c := _airborne_certificate(s, t, h, point)
				c.admitted = c.admitted and h <= (1.0 / 240.0) / n + 1e-15
				return c
			paths.append(Step.advance(initial, 0, 1.0 / 240.0, _airborne_derivative, PackedFloat64Array(), _airborne_point, certificate))
		check("actual fixed-voltage complete paths exist", paths[0].ok and paths[1].ok)
		if not paths[0].ok or not paths[1].ok: continue
		var a: Dictionary = paths[0]
		var b: Dictionary = paths[1]
		var before := var_to_bytes([policy, a, b])
		var actual := Accuracy.compare(policy, a.state, b.state, a.integration_receipt, b.integration_receipt, 1.0 / 240.0)
		var expected := _runtime_quality_gate(a.state, b.state, a.integration_receipt, b.integration_receipt, 1.0 / 240.0)
		check("shared SI gate agrees with independent existing electric oracle", actual.ok and actual.admitted == expected.admitted
			and absf(actual.normalized_error - expected.normalized_error) < 1e-10, str([actual, expected]))
		check("Step-compatible gate returns EXACT four primitive keys", actual.size() == 4 and actual.has_all(["ok", "admitted", "identity", "normalized_error"]))
		check("comparison never mutates physical layout, states or receipts", before == var_to_bytes([policy, a, b]))
		var gate := func(c, f, cr, fr, dt): return Accuracy.compare(policy, c, f, cr, fr, dt)
		var integrated := Step.advance(initial, 0, 1.0 / 240.0, _airborne_derivative, PackedFloat64Array(), _airborne_point, _airborne_certificate, {}, gate)
		check("prepared shared accuracy policy binds directly into canonical Step", integrated.ok
			and integrated.integration_receipt.error_control.identity == policy.identity, str(integrated.get("reason", "")))
	runtime_duty = .02


func _kinematics_and_units() -> void:
	var states := _state_pair()
	var a: PackedFloat64Array = states[0]
	var b: PackedFloat64Array = states[1]
	var ar := _receipt(1)
	var br := _receipt(2)
	check("identical complete states/receipts have zero normalized difference", Accuracy.compare(policy, a, b, ar, br, .004).normalized_error == 0.0)
	for i in 4: b[RB.ATT + i] = -a[RB.ATT + i]
	check("quaternion sign does not change physical attitude accuracy", Accuracy.compare(policy, a, b, ar, br, .004).normalized_error == 0.0)
	b = a.duplicate()
	b[electric.rotor_state_indices[0]] += .001
	var d := Accuracy.diagnose(policy, a, b, ar, br, .004)
	var key := "continuous:shaft:" + str(electric.rotor_state_indices[0])
	check("shaft RPM error is converted to rad/s exactly once", d.ok and d.channels[key].unit == "rad/s" and absf(d.channels[key].absolute_difference - .001 * TAU / 60.0) < 1e-13)
	var offset_layout := layout.duplicate(true)
	offset_layout.cg_body_m = M.v3(.2, -.1, .3)
	var offset_policy := Accuracy.prepare(quality, offset_layout)
	b = a.duplicate()
	b[RB.RATE + 1] += 1e-4
	b[RB.VEL + 0] -= 1e-4 * .3
	b[RB.VEL + 2] += 1e-4 * .2
	d = Accuracy.diagnose(offset_policy, a, b, ar, br, .004)
	check("fixed-CG CM velocity uses the changed angular rate", d.ok and d.channels["velocity_cm:0"].absolute_difference < 1e-14
		and d.channels["velocity_cm:2"].absolute_difference < 1e-14)
	check("physical CG change alters owner layout and prepared identity", offset_policy.layout_identity != policy.layout_identity and offset_policy.identity != policy.identity)
	b = a.duplicate()
	b[0] += 2e-5
	d = Accuracy.diagnose(policy, a, b, ar, br, .004)
	check("split differences are raw and never divided by Richardson15", d.ok and not d.admitted and d.channels["position:0"].normalized_error > 9.9)
	b = a.duplicate()
	b[0] += .001
	check("meaningful position error rejects", not Accuracy.compare(policy, a, b, ar, br, .004).admitted)
	a[0] += 1e9
	b[0] += 1e9
	check("large absolute NED does not inflate a local position scale", not Accuracy.compare(policy, a, b, ar, br, .004).admitted)
	b = a.duplicate()
	b[RB.ATT + 1] = 1e-3
	check("shortest attitude difference has an explicit radian bound", not Accuracy.compare(policy, a, b, ar, br, .004).admitted)
	b = a.duplicate()
	br = _receipt(2, 2.0, .021, .011)
	d = Accuracy.diagnose(policy, a, b, ar, br, .004)
	check("work partition rejects even when work and heat errors cancel energy", d.ok and not d.admitted and d.channels["work:external_work_j"].absolute_difference > .0009)
	ar.initial_mechanical_energy_j += 1e12
	ar.final_mechanical_energy_j += 1e12
	br.initial_mechanical_energy_j += 1e12
	br.final_mechanical_energy_j += 1e12
	d = Accuracy.diagnose(policy, a, b, ar, br, .004)
	check("large stored shaft/body energy cannot hide local work partition error", d.ok and not d.admitted
		and d.channels["work:external_work_j"].bound < .001)
	ar = _receipt(1)
	br = _receipt(2)
	ar.normal_samples_n[1][0] = 10.0
	ar.sampled_peak_normal_n[0] = 10.0
	ar.sampled_peak_times_s[0] = ar.normal_sample_times_s[-1]
	br.normal_samples_n[1][0] = 20.0
	br.sampled_peak_normal_n[0] = 20.0
	br.sampled_peak_times_s[0] = br.normal_sample_times_s[1]
	d = Accuracy.diagnose(policy, a, a, ar, br, .004)
	check("accepted sampled normal-load refinement has its own N tolerance", d.ok and not d.admitted)
	ar = _receipt(1)
	br = _receipt(2)
	ar.energy_balance_residual_j = 1.0
	ar.final_mechanical_energy_j += 1.0
	br.energy_balance_residual_j = 1.0
	br.final_mechanical_energy_j += 1.0
	d = Accuracy.diagnose(policy, a, b, ar, br, .004)
	check("accuracy comparison does not masquerade as a conservation certificate", d.ok and d.admitted and not d.conservation_certificate
		and d.conservation_residuals_j[0] == 1.0)


func _complete_layout_rejections() -> void:
	for kind: String in ["missing", "duplicate", "unknown", "prefix", "unit", "size", "contact", "cg"]:
		var changed := layout.duplicate(true)
		match kind:
			"missing": changed.blocks.pop_back()
			"duplicate": changed.blocks[1].indices = changed.blocks[0].indices.duplicate()
			"unknown": changed.blocks[0].id = "unowned"
			"prefix": changed.blocks[0].indices[0] = 12
			"unit": changed.blocks[0].unit = "furlong"
			"size": changed.state_size += 1
			"contact": changed.contact_ids[1] = changed.contact_ids[0]
			"cg": changed.cg_body_m[0] = NAN
		check("bad/incomplete physical layout refuses: " + kind, not Accuracy.prepare(quality, changed).ok)
	for kind: String in ["missing", "unknown", "unit", "floor", "nan", "relative", "source", "callback", "energy_scale"]:
		var changed := quality.duplicate(true)
		match kind:
			"missing": changed.body.erase("attitude")
			"unknown": changed.continuous.unowned = changed.continuous.shaft
			"unit": changed.continuous.shaft.absolute.unit = "rpm"
			"floor": changed.body.position.floor.value = 0.0
			"nan": changed.body.velocity_cm.absolute.value = INF
			"relative": changed.body.position.relative.value = 1.0
			"source": changed.normal_peak.absolute.source = ""
			"callback": changed.extra = func(): return 1
			"energy_scale": changed.work.external_work_j.scale_sources = ["final_mechanical_energy_j"]
		check("missing/invalid numerical quality refuses: " + kind, not Accuracy.prepare(changed, layout).ok)
	# A declared extra wash state must be covered and uses its own m/s quality.
	var wash_layout := layout.duplicate(true)
	var wash_quality := quality.duplicate(true)
	wash_layout.blocks.append({id = "wash", indices = PackedInt64Array([wash_layout.state_size]), unit = "m/s"})
	wash_layout.state_size += 1
	check("new physical wash state cannot be silently ignored", not Accuracy.prepare(wash_quality, wash_layout).ok)
	wash_quality.continuous.wash = _tol(1e-5, 1e-5, .01, "m/s")
	check("explicitly covered wash state is admissible", Accuracy.prepare(wash_quality, wash_layout).ok)


func _receipt_rejections() -> void:
	var states := _state_pair()
	for kind: String in ["stale", "wrong_pair", "law", "layout", "negative_heat", "negative_load", "peak", "algebra", "nan", "sample_size", "clock", "object"]:
		var ar := _receipt(1)
		var br := _receipt(2)
		match kind:
			"stale": br = _receipt(2, 3.0)
			"wrong_pair": br = _receipt(4)
			"law": br.law = "different-split"
			"layout": br.accuracy_layout_identity = "stale-owner-pin"
			"negative_heat": br.tangent_dissipation_j = -.01
			"negative_load": br.normal_samples_n[1][0] = -1
			"peak": br.sampled_peak_normal_n[0] = 10
			"algebra": br.external_work_j += .001
			"nan": br.energy_balance_residual_j = NAN
			"sample_size": br.normal_samples_n[1] = PackedFloat64Array()
			"clock": br.normal_sample_times_s[1] += .001
			"object": br.extra = self
		var rejected := Accuracy.compare(policy, states[0], states[1], ar, br, .004)
		check("stale/malformed/altered receipt rejects atomically: " + kind, not rejected.ok and not rejected.admitted and rejected.size() == 4)
	var bad: PackedFloat64Array = states[1].duplicate()
	bad.append(0.0)
	check("uncovered runtime tail cannot pass via prefix comparison", not Accuracy.compare(policy, states[0], bad, _receipt(1), _receipt(2), .004).ok)
	bad = states[1].duplicate()
	bad[RB.ATT] = 0.0
	check("degenerate quaternion refuses", not Accuracy.compare(policy, states[0], bad, _receipt(1), _receipt(2), .004).ok)


func _prepared_integrity() -> void:
	var states := _state_pair()
	for key: String in ["cg", "tolerance", "layout", "source", "seal"]:
		var changed := policy.duplicate(true)
		match key:
			"cg": changed.cg_body_m[0] += .1
			"tolerance": changed.body.position.absolute *= 1000
			"layout": changed.layout.state_layout_id = "different-model"
			"source": changed.provenance.source = "changed source"
			"seal": changed.seal = "forged"
		check("mutated prepared numerical/physical binding refuses: " + key, not Accuracy.compare(changed, states[0], states[1], _receipt(1), _receipt(2), .004).ok)
	var changed := quality.duplicate(true)
	changed.body.position.absolute.value *= 2
	check("explicit different quality gets a different identity without changing physical layout", Accuracy.prepare(changed, layout).identity != policy.identity
		and Accuracy.prepare(changed, layout).layout_identity == policy.layout_identity)
	var malformed := policy.duplicate(true)
	malformed.erase("body")
	malformed.seal = Accuracy._seal(malformed)
	check("malformed prepared envelope cannot trigger unchecked arithmetic", not Accuracy.compare(malformed, states[0], states[1], _receipt(1), _receipt(2), .004).ok)
	malformed = policy.duplicate(true)
	malformed.layout = {}
	malformed.seal = Accuracy._seal(malformed)
	check("malformed prepared owner descriptor is refused before receipt access", not Accuracy.compare(malformed, states[0], states[1], _receipt(1), _receipt(2), .004).ok)
	malformed = policy.duplicate(true)
	malformed.body.position.absolute *= 1000
	malformed.seal = Accuracy._seal(malformed)
	check("compiled tolerances cannot silently diverge from pinned numerical provenance", not Accuracy.compare(malformed, states[0], states[1], _receipt(1), _receipt(2), .004).ok)
	malformed = policy.duplicate(true)
	malformed.layout.identity = "different-owner"
	malformed.seal = Accuracy._seal(malformed)
	check("owner layout changes cannot reuse a stale derived layout pin", not Accuracy.compare(malformed, states[0], states[1], _receipt(1), _receipt(2), .004).ok)
