## Generic packet/transaction tests reuse the independent one-wheel mechanics.
extends "res://tests/test_aircraft_ground_step.gd"
const NewStep := preload(
	"C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-capacity-production/aircraft_ground_step.gd"
)
const Capacity := preload(
	"C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-capacity-production/contact_capacity.gd"
)
const QP := preload("res://physics/ground_traction.gd")
var contact_count := 1
var enforce_compression_domain := false
const OWNER := "analytic-fixed-plane-sourcefree-owner-v1"
const SOLVER := "bounded-eight-KKT-probe-unresolved-descent-certified-fallback-v2"


func _options() -> Dictionary:
	return {operator_law = NewStep.INTEGRATED_CAPACITY_LAW}


func _packet(s: PackedFloat64Array, t: float, point: Dictionary) -> Dictionary:
	var pose := s.slice(0, 3)
	pose.append_array(s.slice(RB.ATT, RB.ATT + 4))
	var p := {
		format = Capacity.FORMAT,
		law = Capacity.LAW,
		binding_identity = OWNER,
		time_s = t,
		pose_state = pose,
		contact_ids = point.contact_ids.duplicate(),
		row_ids = PackedStringArray(),
		group_ids = PackedStringArray(),
		jacobian = PackedFloat64Array(),
		bias = PackedFloat64Array(),
		groups = [],
		row_contact_indices = PackedInt64Array(),
		normal_first = PackedFloat64Array(),
		normal_last = PackedFloat64Array(),
		independent_rates = PackedFloat64Array()
	}
	if contact_count == 1:
		p.row_ids = PackedStringArray(["wheel:long", "wheel:lat", "wheel:roll", "wheel:brake"])
		p.group_ids = PackedStringArray(["wheel:tire", "wheel:rolling", "wheel:internal"])
		p.jacobian = point.jacobian.duplicate()
		p.bias = point.slip_bias.duplicate()
		p.groups = point.groups.duplicate(true)
		p.row_contact_indices = PackedInt64Array([0, 0, 0, -1])
		p.normal_first = _p([_grip, _grip, _rolling, 0.0])
		p.normal_last = _p([1.0, 1.0, RADIUS, 0.0])
		p.independent_rates = _p([0.0, 0.0, 0.0, _brake])
	return p


func _capacity_evaluate(s: PackedFloat64Array, t: float) -> Dictionary:
	if enforce_compression_domain and RADIUS + s[2] > .0201:
		return {
			ok = false,
			status = "capacity_envelope_rejected",
			reason = "outside owner proven compression envelope"
		}
	var point := _evaluate(s, t)
	if not point.ok:
		return point
	if contact_count != 1:
		point.contact_ids = PackedStringArray()
		point.normal_load_n = PackedFloat64Array()
		for i in contact_count:
			point.contact_ids.append("normal_" + str(i))
			point.normal_load_n.append(0.0)
	point.interval_capacity = _packet(s, t, point)
	return point


func _capacity_certificate(
	s: PackedFloat64Array, t: float, h: float, point: Dictionary
) -> Dictionary:
	var result := _certificate(s, t, h, point)
	result.capacity_identity = OWNER
	return result


func _new_advance(
	s: PackedFloat64Array,
	t: float,
	h: float,
	evaluator: Callable = Callable(),
	options: Dictionary = {}
) -> Dictionary:
	return NewStep.advance(
		s,
		t,
		h,
		_derivative,
		PackedFloat64Array(),
		_capacity_evaluate if evaluator.is_null() else evaluator,
		_capacity_certificate,
		_options() if options.is_empty() else options
	)


func _initialize() -> void:
	_fixture()
	_gravity = 0.0
	_grip = 0.0
	_rolling = 0.0
	_brake = 0.0
	_dimensions()
	_malformed()
	_topology()
	_refinement()
	_mixed_failure_precedence()
	_kernel()
	print("Contact capacity packet: ", _checks, " checks, ", _failed, " failed")
	quit(1 if _failed else 0)


func _dimensions() -> void:
	var initial := _initial(-1.0, _zeros(3))
	for count in [0, 1, 2, 4, 16]:
		contact_count = count
		var result := _new_advance(initial, 0.0, 1.0 / 240.0)
		_check("generic contact dimensions accepted " + str(count), result.ok, str(result))
		if result.ok:
			var pieces: Array = result.integration_receipt.interval_capacity.pieces
			_check(
				"all contact integral dimensions retained " + str(count),
				(
					pieces.size() == result.integration_receipt.accepted_substeps
					and pieces[0].predicted_normal_integral_ns.size() == count
					and pieces[0].actual_normal_integral_ns.size() == count
					and pieces[0].predicted_minus_actual_ns.size() == count
					and pieces[0].unreserved_nominal_normal_capacity_area_ns.size() == count
				)
			)
			var work: Dictionary = result.integration_receipt.capacity_computation
			_check(
				"setup/trial/accepted direct counts partition exactly",
				(
					work.setup.actual_snapshot_calls == 1
					and (
						work.total.actual_snapshot_calls
						== (
							work.setup.actual_snapshot_calls
							+ work.discarded.actual_snapshot_calls
							+ work.accepted.actual_snapshot_calls
						)
					)
				)
			)
	contact_count = 1


func _malformed() -> void:
	var initial := _initial(-1.0, _zeros(3))
	var seal := var_to_bytes(initial)
	for key: String in [
		"format", "law", "binding_identity", "pose_state", "normal_first", "groups", "row_ids"
	]:
		for bad: Variant in [null, false, [], {}, 4.0]:
			var evaluator := func(s, t):
				var point := _capacity_evaluate(s, t)
				point.interval_capacity[key] = bad
				return point
			var result := _new_advance(initial, 0.0, .01, evaluator)
			_check(
				"malformed packet refuses without state " + key,
				(
					not result.ok
					and not result.has("state")
					and not result.has("integration_receipt")
					and seal == var_to_bytes(initial)
				)
			)
	for kind: String in [
		"stale_time",
		"stale_pose",
		"negative",
		"nonfinite",
		"duplicate_rows",
		"duplicate_groups",
		"mapping",
		"mixed"
	]:
		var evaluator := func(s, t):
			var point := _capacity_evaluate(s, t)
			var p: Dictionary = point.interval_capacity
			match kind:
				"stale_time":
					p.time_s += .001
				"stale_pose":
					p.pose_state[0] += 1.0
				"negative":
					p.normal_first[0] = -1.0
				"nonfinite":
					p.normal_last[0] = INF
				"duplicate_rows":
					p.row_ids[1] = p.row_ids[0]
				"duplicate_groups":
					p.group_ids[1] = p.group_ids[0]
				"mapping":
					p.row_contact_indices[0] = 1
				"mixed":
					p.row_contact_indices[1] = -1
			return point
		_check(
			"invalid capacity semantics refuses " + kind,
			not _new_advance(initial, 0.0, .01, evaluator).ok
		)
	var mutated := func(s, t):
		s[0] += 1.0
		return _capacity_evaluate(s, t)
	_check(
		"new evaluator mutation is refused atomically",
		not _new_advance(initial, 0.0, .01, mutated).ok and seal == var_to_bytes(initial)
	)
	var exhausted := _options()
	exhausted.predictor_rhs_budget = 0
	var stopped := _new_advance(initial, 0.0, .01, Callable(), exhausted)
	_check(
		"explicit predictor budget exhausts without a physical receipt",
		(
			not stopped.ok
			and stopped.status == "computation_exhausted"
			and not stopped.has("integration_receipt")
			and stopped.capacity_computation.total.predictor_rhs_calls == 0
		)
	)
	var wrong_arity := func(_state): return {}
	_check(
		"new evaluator wrong arity refuses before invocation",
		not _new_advance(initial, 0.0, .01, wrong_arity).ok
	)


func _topology() -> void:
	var initial := _initial(-1.0, _zeros(3))
	var point := _capacity_evaluate(initial, 0.0)
	var pre: Dictionary = point.interval_capacity
	pre.row_ids = PackedStringArray(["first", "second"])
	pre.group_ids = PackedStringArray(["interval1", "interval2"])
	pre.groups = [PackedInt32Array([0]), PackedInt32Array([1])]
	pre.jacobian = pre.jacobian.slice(0, 16)
	pre.bias = _zeros(2)
	pre.normal_first = _p([1, 1])
	pre.normal_last = _p([1, 1])
	pre.independent_rates = _zeros(2)
	pre.row_contact_indices = PackedInt64Array([0, 0])
	var post := pre.duplicate(true)
	post.group_ids = PackedStringArray(["merged"])
	post.groups = [PackedInt32Array([0, 1])]
	_check(
		"each regrouping packet individually validates",
		(
			Capacity.validate(pre, initial, 0.0, 2, point.contact_ids).ok
			and Capacity.validate(post, initial, 0.0, 2, point.contact_ids).ok
		)
	)
	var qp := QP.solve(_p([1, 0, 0, 1]), _p([-.8, -.8]), _p([1, 1]), pre.groups)
	_check("original two interval publication accepted", qp.ok)
	_check(
		"two interval membership cannot transfer to one disk",
		not Capacity.reserve(qp, pre, _p([1, 1]), post, _p([1, 1])).ok
	)
	var evaluator := func(s, t):
		var p := _capacity_evaluate(s, t)
		if t > 0.0:
			p.interval_capacity.group_ids[0] = "changed"
		return p
	_check(
		"interval group identity mutation refuses",
		not _new_advance(initial, 0.0, .01, evaluator).ok
	)


func _refinement() -> void:
	contact_count = 1
	_gravity = 0.0
	_grip = 0.0
	_rolling = 0.0
	var x := .02 / sqrt(2.0)
	var vertical := sqrt(STIFFNESS / MASS) * x
	var initial := _initial(-RADIUS + x, _p([0, 0, vertical]))
	enforce_compression_domain = true
	var result := _new_advance(initial, 0.0, .08)
	_check("larger bounded predictor refusal refines to valid full tick", result.ok, str(result))
	if result.ok:
		_check(
			"predictor domain rejection is explicit and bounded",
			(
				result.integration_receipt.capacity_computation.total.predictor_domain_refusals > 0
				and result.integration_receipt.capacity_computation.total.predictor_rhs_calls <= 124
			)
		)
	enforce_compression_domain = false


func _kernel() -> void:
	contact_count = 1
	_gravity = 9.80665
	_grip = .6
	_rolling = .02
	_brake = 0.0
	var initial := _initial(-.08, _p([1, 0, .1]))
	var sim := _simulation(initial)
	sim.model.state_layout_identity = (
		"capacity-test:"
		+ (
			JSON
			. stringify([NewStep.INTEGRATED_CAPACITY_LAW, Capacity.LAW, OWNER, SOLVER])
			. sha256_text()
		)
	)
	sim.model.step_policy = func(s, t, h, f, k1):
		return NewStep.advance(
			s, t, h, f, k1, _capacity_evaluate, _capacity_certificate, _options()
		)
	_check("new owner identity/reset committed before use", sim.reset(initial.slice(0, RB.SIZE)))
	for i in 5:
		sim.step()
	_check(
		"actual Simulation accepts shared capacity operator",
		sim.tick == 5 and sim.fault_reason.is_empty(),
		sim.fault_reason
	)
	var cp: Dictionary = sim.checkpoint()
	var selected_identity: String = sim.model.state_layout_identity
	sim.model.state_layout_identity = "wrong-capacity-source-and-solver"
	_check("checkpoint refuses another source/solver identity", not sim.can_restore_checkpoint(cp))
	sim.model.state_layout_identity = selected_identity
	for i in 3:
		sim.step()
	var expected := var_to_bytes(sim.checkpoint())
	_check("new checkpoint restores", sim.restore_checkpoint(cp))
	for i in 3:
		sim.step()
	_check("new checkpoint continues byte exactly", var_to_bytes(sim.checkpoint()) == expected)
	var before := var_to_bytes([sim.state, sim.previous, sim.continuous, sim.aux, sim.modes])
	var published := [0]
	sim.stepped.connect(func(_a, _b, _c, _d, _e, _f): published[0] += 1)
	var bad := func(s, t):
		var point := _capacity_evaluate(s, t)
		point.interval_capacity.row_ids[1] = point.interval_capacity.row_ids[0]
		return point
	sim.model.step_policy = func(s, t, h, f, k1):
		return NewStep.advance(s, t, h, f, k1, bad, _capacity_certificate, _options())
	sim.step()
	_check(
		"bad packet rolls back all frame channels and events",
		(
			not sim.fault_reason.is_empty()
			and published[0] == 0
			and (
				before
				== var_to_bytes([sim.state, sim.previous, sim.continuous, sim.aux, sim.modes])
			)
		)
	)
	sim.free()


func _mixed_failure_precedence() -> void:
	contact_count = 1
	_gravity = 0.0
	_grip = 0.0
	_rolling = 0.0
	var initial := _initial(-1.0, _zeros(3))
	var options := _options()
	options.max_substeps = 1
	var half_calls := [0]
	var domain_then_bad := func(state, at):
		var point := _capacity_evaluate(state, at)
		if at == .0025:
			half_calls[0] += 1
			if half_calls[0] == 3:
				return {
					ok = false,
					status = "capacity_envelope_rejected",
					reason = "actual stage domain"
				}
			if half_calls[0] > 3:
				point.interval_capacity.groups = []
		return point
	var domain_result := _new_advance(initial, 0.0, .005, domain_then_bad, options)
	_check(
		"actual domain stage stops before later malformed callback",
		(
			not domain_result.ok
			and domain_result.status == "admission_exhausted"
			and half_calls[0] == 3
		)
	)
	var derivative_half := [0]
	var evaluate_half := [0]
	var mutation_then_domain := func(state, at):
		if at == .0025:
			derivative_half[0] += 1
			if derivative_half[0] == 3:
				state[0] += 1.0
		return _derivative(state, at)
	var later_domain := func(state, at):
		if at == .0025:
			evaluate_half[0] += 1
			if evaluate_half[0] > 3:
				return {ok = false, status = "capacity_envelope_rejected", reason = "later domain"}
		return _capacity_evaluate(state, at)
	var mutation_result := NewStep.advance(
		initial,
		0.0,
		.005,
		mutation_then_domain,
		PackedFloat64Array(),
		later_domain,
		_capacity_certificate,
		options
	)
	_check(
		"actual RHS mutation is fatal before later domain",
		(
			not mutation_result.ok
			and mutation_result.status == "invalid_capacity_callback"
			and derivative_half[0] == 3
			and evaluate_half[0] == 3
			and mutation_result.capacity_computation.total.attempts == 1
		)
	)
