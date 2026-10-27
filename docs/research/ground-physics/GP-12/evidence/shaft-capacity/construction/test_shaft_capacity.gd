## Detached opt-in stable finite-bearing packet integration. Synthetic fixed
## supports, existing fixed-voltage motor/propeller and common RotorSystem.
extends "res://tests/test_aircraft_ground_electric.gd"
const NewElectric := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-shaft-capacity/candidate/aircraft_ground_electric.gd")
const NewStep := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-shaft-capacity/candidate/aircraft_ground_step.gd")
const NewCapacity := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-shaft-capacity/candidate/contact_capacity.gd")
const LEGACY_ORACLE := "res://tests/fixtures/ground_contact_shaft_legacy.bin"
const LEGACY_ORACLE_SHA256 := "bbb1d11179dfc89ba23285f1d9c9f5f46fe6f9652ce31990f4ea0f2f7f10ac6d"
var shaft_context: Dictionary
var saved_results: Array = []

func _initialize() -> void:
	_fixture()
	_electric_fixture()
	shaft_context = NewElectric.prepare_capacity(electric, provider, "fixed-voltage-synthetic-owner-no-events-v1")
	check("explicit closed-source capacity context", shaft_context.get("ok", false), str(shaft_context))
	if failed == 0:
		_rows_and_legacy()
		_bad_mappings()
		if not OS.get_cmdline_user_args().has("--rows-only"):
			_actual_runtime()
			_runtime_failures()
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--shaft-evidence="):
			var file := FileAccess.open(arg.trim_prefix("--shaft-evidence="), FileAccess.WRITE)
			file.store_var(saved_results)
	print("Shaft capacity draft: %d checks, %d failed" % [checks, failed])
	quit(1 if failed else 0)

func _wrapped(body: PackedFloat64Array, values: PackedFloat64Array, at := 0.0, enabled := true) -> Dictionary:
	return NewElectric.evaluate_capacity(electric, shaft_context, body, values, at,
		Air.compute(body, M.v3(0, 0, 0), 1.18), 1.18, defs, .02, enabled, provider, 0.0,
		PackedFloat64Array([0.0, 0.0, 0.0]), NAN, 0.0, true)

func _rows_and_legacy() -> void:
	var bytes := FileAccess.get_file_as_bytes(LEGACY_ORACLE)
	var hash := HashingContext.new(); hash.start(HashingContext.HASH_SHA256); hash.update(bytes)
	check("exact original prechange oracle bytes", hash.finish().hex_encode() == LEGACY_ORACLE_SHA256)
	if bytes.is_empty(): return
	var oracle: Variant = bytes_to_var(bytes)
	check("original oracle closed shape", _oracle_shape(oracle))
	if not _oracle_shape(oracle): return
	var malformed: Dictionary = oracle.duplicate(true); malformed.evaluations[0].erase("expected")
	check("missing original result refuses", not _oracle_shape(malformed))
	malformed = oracle.duplicate(true); malformed.steps[0].expected = []
	check("mistyped original result refuses", not _oracle_shape(malformed))
	var case_index := 0
	var row_id := ""
	var packet_ordinal := -1
	var old_ordinals := PackedInt64Array()
	for down: float in [-20.0, -0.19, -0.2, -0.20001]:
		for enabled: bool in [false, true]:
			var body := RB.make_state(M.v3(0, 0, down), M.v3(0, 0, 0), M.q_identity(), M.v3(0, 0, 0))
			var values := _values(0.0)
			var snapshot := var_to_bytes([electric, shaft_context, body, values, provider])
			var frozen: Dictionary = oracle.evaluations[case_index]
			case_index += 1
			check("original evaluation inputs pinned", frozen.down == down and frozen.enabled == enabled)
			var original: Dictionary = bytes_to_var(frozen.expected)
			var unchanged := NewElectric.evaluate(electric, body, values, 0.0, Air.compute(body, M.v3(0, 0, 0), 1.18), 1.18,
				defs, .02, enabled, provider, 0.0, PackedFloat64Array([0, 0, 0]), NAN, 0.0, true)
			check("unselected Electric complete result bytes unchanged", var_to_bytes(original) == var_to_bytes(unchanged))
			var result := _wrapped(body, values, 0.0, enabled)
			check("airborne/loaded/unloading packet source evaluates", original.ok and result.ok, str(result.get("reason")))
			if not result.ok: continue
			var detached := result.duplicate(true)
			detached.sample.erase("interval_capacity")
			detached.sample.erase("interval_capture")
			check("wrapper preserves COMPLETE original force/derivative/legacy rows", var_to_bytes(original) == var_to_bytes(detached))
			check("new source wrapper never mutates inputs", snapshot == var_to_bytes([electric, shaft_context, body, values, provider]))
			var packet: Dictionary = result.sample.interval_capacity
			var mapping := NewCapacity.capture_mapping(result.sample, packet, electric.rotor_state_indices.size())
			check("exact stable independent shaft row validates", mapping.ok, str(mapping))
			if row_id.is_empty():
				row_id = mapping.binding.row_id
				packet_ordinal = mapping.capture.impulse_row
			check("stable semantic identity and packet ordinal survive load transition", row_id == mapping.binding.row_id and packet_ordinal == mapping.capture.impulse_row)
			check("bearing capacity exists airborne and disabled", packet.independent_rates[mapping.capture.impulse_row] > 0.0
				and packet.independent_rates[mapping.capture.impulse_row] == result.source.shaft_friction_capacity_nm)
			old_ordinals.append(result.sample.capture.impulse_row)
			saved_results.append({kind = "complete_evaluation", down = down, enabled = enabled, original = original, wrapped = result})
	old_ordinals.sort()
	check("legacy ordinal ACTUALLY changes with loaded wheel rows", old_ordinals.has(0) and old_ordinals[-1] > 0)
	var finite := electric.duplicate(true)
	finite.law = Electric.DYNAMIC_LAW
	check("finite source cannot opt into event-free wrapper", not NewElectric.prepare_capacity(finite, provider, "finite-refusal").ok)
	var modified := electric.duplicate(true)
	modified.model.propulsion.motor.no_load_current_a *= 2.0
	var body := _runtime_initial().slice(0,RB.SIZE)
	check("changed captured source cannot reuse unchanged context label", not NewElectric.evaluate_capacity(modified,shaft_context,body,
		_values(),0.0,Air.compute(body,M.v3(0,0,0),1.18),1.18,defs,.02,true,provider,0.0,PackedFloat64Array([0,0,0]),NAN,0.0,true).ok)
	var state := _runtime_initial()
	case_index = 0
	for law: String in [Step.LAW, Step.TWO_SIDED_LAW]:
		var frozen: Dictionary = oracle.steps[case_index]
		case_index += 1
		check("original old operator identity pinned", frozen.law == law)
		var original: Dictionary = bytes_to_var(frozen.expected)
		var candidate := NewStep.advance(state, 0.0, 1.0 / 240.0, _airborne_derivative, PackedFloat64Array(), _airborne_point, _airborne_certificate,
			{operator_law = law}, _runtime_error_gate)
		check("unselected old Step COMPLETE result bytes unchanged " + law, var_to_bytes(original) == var_to_bytes(candidate))
		saved_results.append({kind = "legacy_step", law = law, original = original, candidate = candidate})

static func _oracle_shape(value: Variant) -> bool:
	if typeof(value) != TYPE_DICTIONARY or value.size() != 3 or not value.has_all(["format","evaluations","steps"]): return false
	if typeof(value.format) != TYPE_STRING or value.format != "openrc-electric-shaft-original-oracle v1" \
		or typeof(value.evaluations) != TYPE_ARRAY or value.evaluations.size() != 8 \
		or typeof(value.steps) != TYPE_ARRAY or value.steps.size() != 2: return false
	for row: Variant in value.evaluations:
		if typeof(row) != TYPE_DICTIONARY or row.size() != 3 or not row.has_all(["down","enabled","expected"]) \
			or typeof(row.down) != TYPE_FLOAT or not is_finite(row.down) or typeof(row.enabled) != TYPE_BOOL \
			or typeof(row.expected) != TYPE_PACKED_BYTE_ARRAY or row.expected.is_empty(): return false
	for row: Variant in value.steps:
		if typeof(row) != TYPE_DICTIONARY or row.size() != 2 or not row.has_all(["law","expected"]) \
			or typeof(row.law) != TYPE_STRING or row.law not in [Step.LAW,Step.TWO_SIDED_LAW] \
			or typeof(row.expected) != TYPE_PACKED_BYTE_ARRAY or row.expected.is_empty(): return false
	return true

func _bad_mappings() -> void:
	var state := _runtime_initial()
	var point := _airborne_point(state, 0.0)
	check("mapping fixture valid", point.ok)
	if not point.ok: return
	for kind: String in ["orphan_stable", "orphan_legacy", "extra_key", "missing_id", "wrong_rotor", "contact_owned", "normal_owned", "rate_changed", "biased", "wrong_row", "two_group", "duplicate_id"]:
		var sample := point.duplicate(true)
		var p: Dictionary = sample.interval_capacity
		var row: int = p.row_ids.size() - 1
		match kind:
			"orphan_stable": sample.capture = {}
			"orphan_legacy": sample.interval_capture = {}
			"extra_key": sample.interval_capture.extra = 0
			"missing_id": sample.interval_capture.row_id = "absent"
			"wrong_rotor": sample.interval_capture.rotor_index = 1
			"contact_owned": p.row_contact_indices[row] = 0
			"normal_owned": p.normal_first[row] = 1.0
			"rate_changed": p.independent_rates[row] *= 2.0
			"biased": p.bias[row] = .01
			"wrong_row": p.jacobian[row * (6 + electric.rotor_state_indices.size())] = 1.0
			"two_group": p.groups[-1] = PackedInt32Array([row - 1, row])
			"duplicate_id": p.row_ids[0] = sample.interval_capture.row_id
		check("invalid mapping refuses " + kind, not NewCapacity.capture_mapping(sample, p, electric.rotor_state_indices.size()).ok)
	for bad: Variant in [null, false, [], {}, 0, 1.0, StringName("shaft")]:
		for key: String in ["row_id", "rotor_index"]:
			var sample := point.duplicate(true)
			sample.interval_capture[key] = bad
			# Integer0 is the only valid rotor selector in this negative matrix.
			if key == "rotor_index" and typeof(bad) == TYPE_INT: continue
			check("typed stable selectors refuse quietly", not NewCapacity.capture_mapping(sample, sample.interval_capacity, electric.rotor_state_indices.size()).ok)
	for bad: Variant in [null, false, [], 1, 1.0, "bad"]:
		var sample := point.duplicate(true)
		sample.interval_capture = bad
		check("non-dictionary mapping refuses quietly", not NewCapacity.capture_mapping(sample, sample.interval_capacity, electric.rotor_state_indices.size()).ok)
	var absent := point.duplicate(true)
	absent.capture = {}; absent.erase("interval_capture")
	check("absent mapping remains exact no-op", var_to_bytes(NewCapacity.capture_mapping(absent, absent.interval_capacity, electric.rotor_state_indices.size())) == var_to_bytes({ok = true, capture = {}, binding = {}}))

func _airborne_point(state: PackedFloat64Array, at: float, controls := PackedFloat64Array()) -> Dictionary:
	if state.size() != RB.SIZE + electric.continuous_size or M.norm(state.slice(RB.VEL, RB.VEL + 3)) > 5.0 \
		or M.norm(state.slice(RB.RATE, RB.RATE + 3)) > 5.0 or absf(state[RB.SIZE + electric.rotor_index] * TAU / 60.0) > 600:
		return {ok = false}
	var body := state.slice(0, RB.SIZE)
	var duty: float = controls[0] if not controls.is_empty() else runtime_duty
	var enabled: bool = controls[1] == 1.0 if not controls.is_empty() else runtime_enabled
	var result := NewElectric.evaluate_capacity(electric, shaft_context, body, state.slice(RB.SIZE), at,
		Air.compute(body, M.v3(0, 0, 0), 1.18), 1.18, {elevator = 0.0, aileron_left = 0.0, aileron_right = 0.0, rudder = 0.0},
		duty, enabled, provider, 0.0, PackedFloat64Array([0, 0, 0]), NAN, 0.0, true)
	if not result.ok: return result
	var sample: Dictionary = result.sample
	sample.rate = result.body_derivative.duplicate(); sample.rate.append_array(result.derivative)
	sample.loads = result.loads; sample.source = result.source
	return sample

func _shaft_certificate(state: PackedFloat64Array, at: float, h: float, point: Dictionary) -> Dictionary:
	var result := _airborne_certificate(state, at, h, point)
	result.capacity_identity = shaft_context.identity
	return result

func _runtime_sim(initial: PackedFloat64Array, quality_profile := false) -> Node:
	var sim := Sim.new()
	sim.mass = electric.properties.mass_kg
	sim.inertia = electric.properties.inertia.duplicate()
	sim.gravity = 0.0
	sim.inputs = PackedFloat64Array([0, 0, 0, runtime_duty, 1])
	sim.aux = PackedFloat64Array([runtime_duty, 1, 0, 0, 0, 0, 0, 0])
	sim.continuous = initial.slice(RB.SIZE)
	var vehicle := Model.new()
	vehicle.input_size = 5 # neutral surfaces, duty, explicit sampled motor enable
	vehicle.aux_size = 8
	vehicle.modes_size = 0
	vehicle.continuous_size = electric.continuous_size
	vehicle.state_layout_identity = "synthetic-electric-airborne-capture-checked-SI-v1:" + NewCapacity.CAPTURE_LAW + ":" + NewStep.INTEGRATED_CAPACITY_LAW
	if quality_profile: vehicle.state_layout_identity += ":work-throughput-r0.005-v1"
	vehicle.pre_tick = func(aux, inputs, _dt):
		var next: PackedFloat64Array = aux.duplicate()
		next[0] = inputs[3]
		next[1] = inputs[4]
		return next
	var sample := func(state, at): return _airborne_point(state, at, sim.aux)
	vehicle.stage = func(body, values, at):
		var state: PackedFloat64Array = body.duplicate()
		state.append_array(values)
		var point: Dictionary = sample.call(state, at)
		if not point.ok: return {}
		return {loads = point.loads, body_derivative = point.rate.slice(0, RB.SIZE), derivative = point.rate.slice(RB.SIZE), rotor_momentum = M.v3(0, 0, 0)}
	var gate: Callable = _runtime_quality_gate if quality_profile else _runtime_error_gate
	vehicle.step_policy = func(state, at, dt, f, first): return NewStep.advance(state, at, dt, f, first, sample, _shaft_certificate, {operator_law = NewStep.INTEGRATED_CAPACITY_LAW}, gate)
	vehicle.state_validator = func(frame, _context): return frame.continuous[electric.rotor_index] >= 0.0
	vehicle.endpoint_transition = func(_previous, candidate, context):
		if context.body_filtered or not context.has("integration_receipt"): return {}
		var receipt: Dictionary = context.integration_receipt
		if not receipt.has("error_control"): return {}
		candidate.aux[2] += receipt.external_work_j
		candidate.aux[3] += receipt.tangent_dissipation_j + receipt.normal_dissipation_j
		candidate.aux[4] = receipt.error_control.normalized_error
		candidate.aux[5] = receipt.accepted_substeps
		for load: float in receipt.sampled_peak_normal_n: candidate.aux[6] = maxf(candidate.aux[6], load)
		candidate.aux[7] = receipt.energy_balance_residual_j
		candidate.events = []
		return candidate
	check("actual electric VehicleModel installs", sim.set_model(vehicle))
	check("airborne actual electric kernel resets", sim.reset(initial.slice(0, RB.SIZE)), sim.fault_reason)
	return sim


func _actual_runtime() -> void:
	var initial := _runtime_initial()
	var index: int = RB.SIZE + electric.rotor_index
	# No gate relaxation: known half-kick-from-rest startup is intentionally a
	# refused transaction at240Hz; the new mapping cannot fix that operator.
	for command: float in [.02, 1.0]:
		runtime_duty = command; runtime_enabled = true
		var before := var_to_bytes(initial)
		var sample := func(s,t): return _airborne_point(s,t)
		var scores: Array = []
		var gate := func(a,b,ar,br,dt):
			var r := _runtime_error_gate(a,b,ar,br,dt)
			scores.append(r.normalized_error)
			return r
		var result := NewStep.advance(initial, 0.0, 1.0/240.0, _airborne_derivative, PackedFloat64Array(), sample,
			_shaft_certificate, {operator_law = NewStep.INTEGRATED_CAPACITY_LAW}, gate)
		check("unchanged strict startup gate refuses unaffordable half-kick transient", not result.ok and result.status == "error_control_exhausted")
		check("startup refusal leaves state unchanged", before == var_to_bytes(initial) and not result.has("state"))
		var sim := _runtime_sim(initial)
		var publications := [0]
		sim.stepped.connect(func(_a,_b,_c,_d,_e,_f): publications[0] += 1)
		var frame := var_to_bytes([sim.state, sim.continuous, sim.aux])
		sim.step()
		check("actual kernel rejected startup is atomic with no publication", sim.tick == 0 and not sim.fault_reason.is_empty()
			and publications[0] == 0 and frame == var_to_bytes([sim.state, sim.continuous, sim.aux]))
		saved_results.append({kind = "strict_startup_refusal", command = command, result = result, scores = scores})
		sim.free()
	# Genuine finite-capacity capture from a small already-positive shaft state.
	# Seed is explicitly synthetic, not a claimed accepted powered startup.
	runtime_duty = 0.0; runtime_enabled = false
	var seeded := initial.duplicate(); seeded[index] = .01
	var sim := _runtime_sim(seeded)
	var first := _airborne_point(seeded,0.0)
	var e0 := NewStep._energy(seeded, first)
	sim.inputs[3] = 0.0; sim.inputs[4] = 0.0
	sim.step()
	check("actual fixed-voltage motor-off common kernel captures positive RPM exactly", sim.tick == 1 and sim.fault_reason.is_empty()
		and sim.continuous[electric.rotor_index] == 0.0, sim.fault_reason)
	if sim.tick == 1:
		var end: PackedFloat64Array = sim.state.duplicate(); end.append_array(sim.continuous)
		var e1 := NewStep._energy(end,_airborne_point(end,sim.time(),sim.aux))
		check("source-free airborne bearing capture closes full mechanical ledger", sim.aux[3] > 0.0 and sim.aux[6] == 0.0
			and absf(e1-e0+sim.aux[3]-sim.aux[2]) < 1e-7)
		var cp: Dictionary = sim.checkpoint()
		for i in 3: sim.step()
		var expected := var_to_bytes(sim.checkpoint())
		check("captured common-kernel checkpoint restores", sim.restore_checkpoint(cp))
		for i in 3: sim.step()
		check("captured motor-off continuation exact", sim.fault_reason.is_empty() and expected == var_to_bytes(sim.checkpoint()))
		saved_results.append({kind = "actual_capture", initial = seeded, initial_energy_j = e0, checkpoint = cp,
			continuation = sim.checkpoint(), final_energy_j = e1})
	sim.free()
	runtime_duty = .02; runtime_enabled = true

func _runtime_failures() -> void:
	var initial := _runtime_initial()
	for kind: String in ["orphan", "stable_change", "legacy_rate_change"]:
		var callback := func(state, at):
			var point := _airborne_point(state, at)
			if point.ok and at > 0.0:
				match kind:
					"orphan": point.erase("interval_capture")
					"stable_change": point.interval_capture.row_id = "changed"
					"legacy_rate_change": point.limit_rates[-1] *= 2.0
			return point
		var bytes := var_to_bytes(initial)
		var result := NewStep.advance(initial, 0.0, 1.0 / 240.0, _airborne_derivative, PackedFloat64Array(), callback,
			_shaft_certificate, {operator_law = NewStep.INTEGRATED_CAPACITY_LAW}, _runtime_error_gate)
		check("changed stable mapping is fatal not refinement " + kind, not result.ok and result.status == "invalid_capacity_callback", str(result))
		check("refused complete advance leaves accepted state unchanged", bytes == var_to_bytes(initial) and not result.has("state"))
		saved_results.append({kind = "mutation_refusal", mutation = kind, result = result})
