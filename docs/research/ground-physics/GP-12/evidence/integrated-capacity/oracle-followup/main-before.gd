## Installed P51 hardware with the existing explicitly synthetic contact fixture.
extends "res://tests/test_aircraft_ground_unloaded.gd"
const DraftTraction := preload(
	"res://physics/aircraft_ground_traction.gd"
)
const DraftStep := preload(
	"res://physics/aircraft_ground_step.gd"
)
const Capacity := preload(
	"res://physics/contact_capacity.gd"
)
var capacity_context: Dictionary
var evidence_dir := ""
const OWNER := "installed-P51-synthetic-fixed-plane-no-source-capacity-owner-v1"


func _capacity_sample(state: PackedFloat64Array, at: float) -> Dictionary:
	var point := _sample_policy(state, at)
	if not point.ok:
		return point
	var brake := .7 if at >= brake_start else 0.0
	var built := DraftTraction.capacity_packet(
		capacity_context,
		state.slice(0, RB.SIZE),
		live.cg_body_m,
		at,
		PackedFloat64Array([brake, brake, 0.0])
	)
	if not built.ok:
		return built
	point.interval_capacity = built.packet
	return point


func _capacity_certificate(
	state: PackedFloat64Array, at: float, h: float, point: Dictionary
) -> Dictionary:
	var result := _certificate(state, at, h, point)
	result.capacity_identity = capacity_context.identity
	if (at < brake_start and at + h >= brake_start) or lift_ratio != 0.0:
		result.ok = false
	return result


func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--evidence-dir="):
			evidence_dir = argument.trim_prefix("--evidence-dir=")
	_fixture()
	_prepare_composition()
	_prepare_quality()
	_bind()
	_context()
	_legacy_rows()
	_legacy_steps()
	_real_steps()
	print("Traction capacity producer: ", checks, " checks, ", failed, " failed")
	quit(1 if failed else 0)


func _context() -> void:
	capacity_context = DraftTraction.prepare_capacity(
		traction, prepared.normal, provider, motion, OWNER
	)
	check(
		"installed fixed plane capacity context prepares",
		capacity_context.ok,
		str(capacity_context)
	)
	if not capacity_context.ok:
		return
	var body := _initial(-.1, 3.0, .2, 0.0).slice(0, RB.SIZE)
	var pin := var_to_bytes([body, live, capacity_context])
	var result := DraftTraction.capacity_packet(
		capacity_context, body, live.cg_body_m, 0.0, PackedFloat64Array([0.0, 0.0, 0.0])
	)
	check("current zero-demand full capacity packet builds", result.ok, str(result))
	check(
		"capacity builder leaves physical/source data unchanged",
		pin == var_to_bytes([body, live, capacity_context])
	)
	if result.ok:
		check(
			"normal and independent rows have fixed full topology",
			(
				result.packet.row_ids.size() == 11
				and result.packet.groups.size() == 8
				and result.packet.normal_first.size() == 11
			)
		)
		var detached: Dictionary = result.packet.duplicate(true)
		detached.jacobian[0] += 2.0
		var again := DraftTraction.capacity_packet(
			capacity_context, body, live.cg_body_m, 0.0, PackedFloat64Array([0.0, 0.0, 0.0])
		)
		check(
			"mutating returned packet cannot change prepared source",
			again.ok and var_to_bytes(again.packet) == var_to_bytes(result.packet)
		)
	for kind: String in ["motion", "material", "provider", "owner"]:
		var bad := capacity_context.duplicate(true)
		match kind:
			"motion":
				bad.motion[0].hub_body[0] += 1.0
			"material":
				bad.traction.materials.dry_pavement.values.longitudinal_friction = .123
			"provider":
				bad.provider.geometry_law = []
			"owner":
				bad.owner_identity = []
		check(
			"captured lifetime mutation refuses " + kind,
			not (
				DraftTraction
				. capacity_packet(
					bad, body, live.cg_body_m, 0.0, PackedFloat64Array([0.0, 0.0, 0.0])
				)
				. ok
			)
		)
	var forged := capacity_context.duplicate(true)
	forged.motion[0].hub_body[0] += 1.0
	var copy := forged.duplicate(true)
	copy.erase("seal")
	forged.seal = JSON.stringify(copy, "", true, true).sha256_text()
	check(
		"re-sealing invalid source cannot forge original fixed mechanics",
		not (
			DraftTraction
			. capacity_packet(
				forged, body, live.cg_body_m, 0.0, PackedFloat64Array([0.0, 0.0, 0.0])
			)
			. ok
		)
	)


func _legacy_rows() -> void:
	for down: float in [-1.0, -.2, -.15, -.1]:
		for bank: float in [0.0, .15]:
			var state := _initial(down, 3.0, .2, 0.0)
			var q := M.q_from_euler(bank, .02, .1)
			for i in 4:
				state[RB.ATT + i] = q[i]
			var point := _snapshot(state, 0.0)
			check("legacy row comparison sample valid", point.ok, str(point))
			if not point.ok:
				continue
			for brake: PackedFloat64Array in [
				PackedFloat64Array([0.0, 0.0, 0.0]), PackedFloat64Array([.7, .2, 0.0])
			]:
				var before := var_to_bytes(point.physical.ground)
				var a := Traction.evaluate(
					traction, state.slice(0, RB.SIZE), live.cg_body_m, point.physical.ground, brake
				)
				var b := DraftTraction.evaluate(
					traction, state.slice(0, RB.SIZE), live.cg_body_m, point.physical.ground, brake
				)
				check(
					"extracted old row builder preserves complete bytes",
					var_to_bytes(a) == var_to_bytes(b)
				)
				check(
					"old row comparison leaves physical contact unchanged",
					before == var_to_bytes(point.physical.ground)
				)


func _legacy_steps() -> void:
	var pinned: Array = []
	for law: String in [Candidate.LAW, Candidate.TWO_SIDED_LAW]:
		selected_law = law
		_prepare_quality()
		for name: String in ["ground_unloaded_gentle.bin", "ground_unloaded_hard.bin"]:
			var raw := _read(name)
			var options: Dictionary = raw.options.duplicate(true)
			options.operator_law = law
			var old := Candidate.advance(
				raw.state,
				raw.time_s,
				raw.dt,
				_derivative,
				PackedFloat64Array(),
				_sample_policy,
				_certificate,
				options,
				_gate,
				_policy
			)
			var current := DraftStep.advance(
				raw.state,
				raw.time_s,
				raw.dt,
				_derivative,
				PackedFloat64Array(),
				_sample_policy,
				_certificate,
				options,
				_gate,
				_policy
			)
			check(
				"old selected law full result bytes unchanged " + law + name,
				var_to_bytes(old) == var_to_bytes(current)
			)
			pinned.append(
				{
					fixture = name,
					law = law,
					original_result = old,
					draft_result = current,
					equal = var_to_bytes(old) == var_to_bytes(current)
				}
			)
	_retain("legacy-step-parity.bin", pinned)


func _real_steps() -> void:
	selected_law = DraftStep.INTEGRATED_CAPACITY_LAW
	_prepare_quality()
	for name: String in ["ground_unloaded_gentle.bin", "ground_unloaded_hard.bin"]:
		var raw := _read(name)
		var options: Dictionary = raw.options.duplicate(true)
		options.operator_law = selected_law
		var result := DraftStep.advance(
			raw.state,
			raw.time_s,
			raw.dt,
			_derivative,
			PackedFloat64Array(),
			_capacity_sample,
			_capacity_certificate,
			options,
			_gate,
			_policy
		)
		check("real producer feeds actual coupled raw gate " + name, result.ok, str(result))
		if result.ok:
			check(
				"same physical quality admits explicit new operator",
				result.integration_receipt.error_control.normalized_error <= 1.0
			)
			check(
				"predictor direct cost is bounded and includes rejected trials",
				(
					result.integration_receipt.capacity_computation.total.predictor_rhs_calls <= 124
					and result.integration_receipt.capacity_computation.discarded.attempts > 0
				)
			)
		_retain("new-" + name, result)


func _retain(name: String, value: Variant) -> void:
	if evidence_dir.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(evidence_dir)
	var output := FileAccess.open(evidence_dir.path_join(name), FileAccess.WRITE)
	if output == null:
		check("explicit evidence output opens", false)
		return
	output.store_buffer(var_to_bytes(value))
	output.close()
