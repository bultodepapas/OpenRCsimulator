## Fleet qualification policy tests: no native library or full flight is required.
extends SceneTree

const Fleet := preload("fleet.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const NativeStage := preload("res://sim/native_stage.gd")

var _checks := 0
var _failures := 0


class FakeNative:
	extends RefCounted
	var stage_calls := 0
	var context_calls := 0

	func stage(_body: Variant, _continuous: Variant, _time: Variant) -> void:
		stage_calls += 1

	func body_loads(_body: Variant, _time: Variant) -> void:
		stage_calls += 1

	func body_rotor(_aux: Variant) -> void:
		pass

	func reset_stage_stats(_timing: bool) -> void:
		stage_calls = 0
		context_calls = 0

	func stage_stats() -> Dictionary:
		return {stage_calls = stage_calls, context_calls = context_calls}


class FakeHelper:
	extends RefCounted
	var _native: FakeNative

	func owns_stage(session: Node) -> bool:
		return session.sim.model.stage == Callable(_native, "stage") \
			or (not session.sim.model.stage.is_valid() and session.sim.model.loads == Callable(_native, "body_loads") \
			and session.sim.model.rotor_momentum == Callable(_native, "body_rotor"))

	func stage_stats() -> Dictionary:
		return _native.stage_stats()


class RefusalFleet:
	extends Fleet
	var reference_result: Dictionary
	var native_result: Dictionary

	func _build_fleet_session(_row: Dictionary, requested_backend: String) -> Dictionary:
		return (reference_result if requested_backend == "gdscript_reference" else native_result).duplicate(true)


class RuntimeRouteFleet:
	extends Fleet
	var runtime_calls := 0
	var normal_calls := 0

	func _fleet_runtime_case(_row: Dictionary, _warmup: int, _samples: int) -> void:
		runtime_calls += 1

	func _fleet_execute(_row: Dictionary, requested: String, _warmup: int, _samples: int) -> Dictionary:
		normal_calls += 1
		return {complete = false, requested = requested, error = "synthetic incomplete run"}


class FakeSimulation:
	extends Node
	var tick := 0
	var paused := false
	var fault_reason := ""
	var state := PackedFloat64Array([0.0])
	var previous := PackedFloat64Array([0.0])
	var aux := PackedFloat64Array([0.0])
	var continuous := PackedFloat64Array([0.0])
	var inputs := PackedFloat64Array([0.0])
	var last_loads := PackedFloat64Array([0.0])
	var modes := PackedInt64Array([0])
	var last_events := []
	var model := {stage = Callable(), loads = Callable(), rotor_momentum = Callable(),
		block_loads = Callable(), block_derivative = Callable(), stage_rotor_momentum = Callable()}
	var native: FakeNative
	var session: Node
	var failure := ""
	var fail_at := -1

	func dt() -> float:
		return 1.0 / 240.0

	func set_paused(value: bool) -> void:
		paused = value

	func reference_stage(_body: Variant, _continuous: Variant, _time: Variant) -> void:
		pass

	func _physics_process(_delta: float) -> void:
		if paused or (failure == "stopped" and tick == fail_at):
			return
		previous = state.duplicate()
		tick += 1
		state[0] = 0.0
		aux[0] = float(tick)
		if not continuous.is_empty(): continuous[0] = float(tick)
		inputs[0] = float(tick)
		last_loads[0] = float(tick)
		modes[0] = tick
		if tick == fail_at and failure == "diverge_warmup":
			state[0] = 1.0
		if tick == fail_at and failure == "diverge_previous":
			previous[0] = 2.0
		if tick == fail_at and failure == "diverge_events":
			last_events = [{kind = "changed"}]
		if native != null:
			if failure != "missing_context" or tick != fail_at:
				native.context_calls += 1
			var count := 3 if failure == "missing_stage" and tick == fail_at else 4
			for _index in count:
				if model.stage.is_valid(): model.stage.call(0, 0, 0)
				else: model.loads.call(0, 0)
		if tick == fail_at:
			match failure:
				"uninstall":
					if model.stage.is_valid(): model.stage = Callable(self, "reference_stage")
					else: model.loads = Callable(self, "reference_stage")
				"remove_rotor": model.rotor_momentum = Callable()
				"change_block": model.block_loads = Callable(self, "reference_stage")
				"fault": fault_reason = "rejected"
				"pause": paused = true
				"crash": session.crash = {reason = "crashed"}


class FakeSession:
	extends Node
	var sim := FakeSimulation.new()
	var crash := {}
	var holds := {}
	var pause_reason := ""
	var read_raw := Callable()
	var requested := "gdscript_reference"
	var actual := "gdscript_reference"
	var _native_stage: FakeHelper
	var aircraft := {input_identity = {sha256 = "a".repeat(64)}}
	var restore_failure := ""

	func _init() -> void:
		add_child(sim)
		sim.session = self
		sim.model.stage = Callable(sim, "reference_stage")

	func _physics_process(_delta: float) -> void:
		if read_raw.is_valid():
			read_raw.call()

	func stage_backend_status() -> Dictionary:
		return {requested = requested, identity = {backend = actual}, reason = "fixture fallback" if actual != requested else ""}

	func checkpoint() -> Dictionary:
		return {tick = sim.tick, state = sim.state.duplicate(), previous = sim.previous.duplicate(),
			aux = sim.aux.duplicate(), continuous = sim.continuous.duplicate(), inputs = sim.inputs.duplicate(),
			last_loads = sim.last_loads.duplicate(), modes = sim.modes.duplicate(), last_events = sim.last_events.duplicate(true)}

	func restore_checkpoint(saved: Dictionary) -> Dictionary:
		if restore_failure == "replay_reject": return {ok = false}
		for name: String in ["tick", "state", "previous", "aux", "continuous", "inputs", "last_loads", "modes", "last_events"]:
			sim.set(name, saved[name])
		sim.paused = true
		if restore_failure == "replay_initial": sim.state = PackedFloat64Array([999.0])
		if restore_failure == "replay_diverge":
			sim.failure = "diverge_warmup"
			sim.fail_at = 1
		if restore_failure == "replay_missing_stage":
			sim.failure = "missing_stage"
			sim.fail_at = 1
		return {ok = true}


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL: " + label)


func _run_fake(fleet: Object, requested: String, failure := "", fail_at := -1,
		warmup := 2, samples := 3, replay := false, body := false) -> Dictionary:
	var session := FakeSession.new()
	session.requested = requested
	session.actual = requested
	session.sim.failure = failure
	session.sim.fail_at = fail_at
	session.restore_failure = failure
	if body:
		session.sim.continuous = PackedFloat64Array()
		session.sim.model.stage = Callable()
		session.sim.model.loads = Callable(session.sim, "reference_stage")
	if requested == "native" and failure != "fallback":
		var helper := FakeHelper.new()
		helper._native = FakeNative.new()
		session._native_stage = helper
		session.sim.native = helper._native
		if body:
			session.sim.model.loads = Callable(helper._native, "body_loads")
			session.sim.model.rotor_momentum = Callable(helper._native, "body_rotor")
		else:
			session.sim.model.stage = Callable(helper._native, "stage")
	elif failure == "fallback":
		session.actual = "gdscript_reference"
	session.read_raw = func() -> Dictionary:
		fleet._input_reads += 1
		return {}
	var result: Dictionary = fleet._fleet_run_session(session, requested, warmup, samples, replay)
	session.free()
	return result


func _runtime_proof_fixture(row: Dictionary, warmup: int, samples: int) -> Dictionary:
	var tick: int = row.expected_runtime_tick
	var body := PackedFloat64Array()
	body.resize(13)
	body[6] = 1.0
	var continuous := PackedFloat64Array()
	continuous.resize(22)
	continuous[8] = 2.0
	continuous[18] = 1.0
	var aux := PackedFloat64Array()
	aux.resize(14)
	var inputs := PackedFloat64Array()
	inputs.resize(4)
	var deflections := PackedFloat64Array()
	deflections.resize(5)
	var tick_time: float = float(tick) * (1.0 / 240.0)
	var trial := [body, continuous, tick_time + (1.0 / 240.0)]
	var context := [aux, inputs, deflections, tick_time, 0.0, 0.0, false, false]
	var end := {tick = tick, fault = Fleet.GLOW_REVERSE_FAULT, crashed = false, paused = true,
		held = false, pause_reason = "simulation fault: " + Fleet.GLOW_REVERSE_FAULT}
	var cause := {code = Fleet.GLOW_REVERSE_CODE, origin = "feed_endpoint", feed_factor = 0.0, rpm = 0.0,
		demand_nm = -0.02, friction_nm = 0.01, prop_load_torque_nm = 0.02,
		axial_acceleration_rad_s2 = 0.0, rotor_inertia_kg_m2 = 0.01}
	var native_cause := cause.duplicate(true)
	return {code = Fleet.GLOW_REVERSE_CODE, origin = "feed_endpoint", accepted_ticks = tick,
		attempted_tick = tick + 1, requested_ticks = warmup + samples,
		warmup_completed = mini(warmup, tick), samples_completed = maxi(0, tick - warmup),
		prefix_boundaries = tick + 1, reference_prefix_sha256 = "a".repeat(64),
		native_prefix_sha256 = "a".repeat(64), prefix_equal_every_tick = true,
		terminal_equal = true, reference_rollback = true, native_rollback = true,
		reference_end = end.duplicate(true), native_end = end.duplicate(true),
		reference_identity = {backend = "gdscript_reference"}, reference_owner_retained = true,
		reference_aircraft_sha256 = "c".repeat(64), native_aircraft_sha256 = "c".repeat(64),
		native_identity = {backend = "native", abi_version = 2}, native_owner_retained = true,
		native_covered_every_tick = true, reference_input_reads = tick + 1, native_input_reads = tick + 1,
		native_stage_calls = 4 * tick + 4, native_context_calls = tick + 1,
		rejected_stage_calls = 4, rejected_context_calls = 1,
		native_diagnostic_stage_call = 4 * tick + 4, native_diagnostic_context_call = tick + 1,
		trial_equal = true, context_equal = true, reference_result_empty = true,
		trial_bytes_hex = var_to_bytes(trial).hex_encode(), trial_sha256 = Fleet._fleet_bytes_sha(trial),
		native_trial_bytes_hex = var_to_bytes(trial).hex_encode(), native_trial_sha256 = Fleet._fleet_bytes_sha(trial),
		context_bytes_hex = var_to_bytes(context).hex_encode(), context_sha256 = Fleet._fleet_bytes_sha(context),
		native_context_bytes_hex = var_to_bytes(context).hex_encode(), native_context_sha256 = Fleet._fleet_bytes_sha(context),
		reference_cause = cause.duplicate(true), native_cause = native_cause}


func _replace_runtime_payload(proof: Dictionary, field: String, payload: Variant) -> void:
	var bytes: PackedByteArray = var_to_bytes(payload)
	var digest: String = Fleet._fleet_bytes_sha(payload)
	proof[field + "_bytes_hex"] = bytes.hex_encode()
	proof[field + "_sha256"] = digest
	proof["native_" + field + "_bytes_hex"] = bytes.hex_encode()
	proof["native_" + field + "_sha256"] = digest


func _initialize() -> void:
	var fleet := Fleet.new()
	var reference := _run_fake(fleet, "gdscript_reference")
	var native := _run_fake(fleet, "native")
	_check(reference.complete and native.complete and Fleet._fleet_pair_error(reference, native, 2, 3).is_empty(),
		"healthy production-shaped native/reference pair succeeds")
	_check(reference.fingerprint_boundaries == 6 and native.fingerprint_boundaries == 6 \
		and reference.fingerprint == native.fingerprint, "initial, warmup and sample state boundaries are hashed")
	var zero := _run_fake(fleet, "gdscript_reference", "", -1, 2, 0)
	_check(not zero.complete and "positive" in zero.error and zero.fingerprint.is_empty(), "zero samples fail closed")
	zero = _run_fake(fleet, "native", "", -1, 0, 3)
	_check(not zero.complete and "positive" in zero.error, "zero warmup fails closed")
	var stopped := _run_fake(fleet, "native", "stopped", 1)
	_check(not stopped.complete and stopped.warmup_completed == 1 and stopped.samples_completed == 0 \
		and "warmup tick 2" in stopped.error and stopped.fingerprint.is_empty(), "stopped warmup cannot pass")
	var fallback := _run_fake(fleet, "native", "fallback")
	_check(not fallback.complete and fallback.actual == "gdscript_reference", "reference fallback is refused")
	var false_native := reference.duplicate(true)
	false_native.requested = "native"
	_check(not Fleet._fleet_pair_error(reference, false_native, 2, 3).is_empty(),
		"matching reference fingerprints cannot pass as native")
	for failure: String in ["missing_context", "missing_stage", "uninstall", "change_block", "fault", "pause", "crash"]:
		var rejected := _run_fake(fleet, "native", failure, 3)
		_check(not rejected.complete and not Fleet._fleet_pair_error(reference, rejected, 2, 3).is_empty(),
			"native %s fails per-tick qualification" % failure)
	for failure: String in ["diverge_warmup", "diverge_previous", "diverge_events"]:
		var divergent := _run_fake(fleet, "native", failure, 1)
		_check(divergent.complete and divergent.fingerprint != reference.fingerprint \
			and "fingerprints differ" in Fleet._fleet_pair_error(reference, divergent, 2, 3),
			"%s is retained in the complete fingerprint" % failure)
	var replay_reference := _run_fake(fleet, "gdscript_reference", "", -1, 2, 3, true)
	var replay_native := _run_fake(fleet, "native", "", -1, 2, 3, true)
	_check(replay_reference.replay_ok and replay_native.replay_ok and replay_native.replay_native_covered \
		and Fleet._fleet_pair_error(replay_reference, replay_native, 2, 3).is_empty(),
		"checkpoint replay requires matching continuation and native coverage")
	for failure: String in ["replay_reject", "replay_initial", "replay_diverge", "replay_missing_stage"]:
		var rejected := _run_fake(fleet, "native", failure, -1, 2, 3, true)
		_check(not rejected.complete and not rejected.error.is_empty(), failure + " cannot qualify")
	var incomplete_replay := replay_native.duplicate(true)
	incomplete_replay.replay_completed -= 1
	_check(not Fleet._fleet_pair_error(replay_reference, incomplete_replay, 2, 3).is_empty(),
		"an incomplete replay cannot qualify")
	var body_reference := _run_fake(fleet, "gdscript_reference", "", -1, 2, 3, false, true)
	var body_native := _run_fake(fleet, "native", "", -1, 2, 3, false, true)
	_check(body_reference.complete and body_native.complete and body_native.stage_in_use == "body_loads" \
		and Fleet._fleet_pair_error(body_reference, body_native, 2, 3).is_empty(),
		"empty-continuous body callbacks qualify with native coverage")
	for failure: String in ["uninstall", "remove_rotor", "missing_stage", "missing_context"]:
		var rejected := _run_fake(fleet, "native", failure, 3, 2, 3, false, true)
		_check(not rejected.complete and not Fleet._fleet_pair_error(body_reference, rejected, 2, 3).is_empty(),
			"body callback %s fails qualification" % failure)
	var declared := Fleet._fleet_declared_rows()
	var runtime_rows: Array[Dictionary] = []
	for row: Dictionary in declared:
		if row.get("expected") == "runtime-domain-refusal": runtime_rows.append(row)
	_check(runtime_rows.size() == 4, "only the four observed reverse-breakaway rows are declared")
	for row: Dictionary in runtime_rows:
		var expected_tick: int = 873 if row.aircraft == "stik-glow-61fx-2t" else 801
		_check(Fleet._fleet_runtime_tick(row) == expected_tick,
			"runtime-domain declaration has its exact accepted tick: %s/soft=%s" % [row.aircraft, row.soft_hull])
	var runtime_row := runtime_rows[0].duplicate(true)
	var runtime_proof := _runtime_proof_fixture(runtime_row, 600, 2400)
	_check(Fleet._fleet_runtime_proof_error(runtime_row, runtime_proof, 600, 2400).is_empty(),
		"a complete exact runtime-domain proof is accepted separately")
	var warmup_proof := _runtime_proof_fixture(runtime_row, 900, 1)
	_check(Fleet._fleet_runtime_proof_error(runtime_row, warmup_proof, 900, 1).is_empty() \
		and warmup_proof.warmup_completed == runtime_row.expected_runtime_tick and warmup_proof.samples_completed == 0,
		"a refusal during warmup records its actual phase counts")
	var wrong_runtime_row := runtime_row.duplicate(true)
	wrong_runtime_row.aircraft = "gp-extra-300s-60"
	_check(not Fleet._fleet_runtime_proof_error(wrong_runtime_row, runtime_proof, 600, 2400).is_empty(),
		"another aircraft cannot use the runtime-domain declaration")
	for change: Array in [["accepted_ticks", runtime_row.expected_runtime_tick - 1],
			["attempted_tick", runtime_row.expected_runtime_tick], ["prefix_equal_every_tick", false],
			["terminal_equal", false], ["reference_rollback", false], ["native_rollback", false],
			["reference_owner_retained", false], ["native_aircraft_sha256", "d".repeat(64)],
			["native_owner_retained", false], ["native_covered_every_tick", false],
			["native_input_reads", 0], ["rejected_stage_calls", 0], ["rejected_context_calls", 0],
			["native_diagnostic_stage_call", 0], ["native_diagnostic_context_call", 0],
			["trial_equal", false], ["context_equal", false], ["reference_result_empty", false],
			["trial_sha256", "b".repeat(64)], ["context_bytes_hex", "not-hex"]]:
		var altered: Dictionary = runtime_proof.duplicate(true)
		altered[change[0]] = change[1]
		_check(not Fleet._fleet_runtime_proof_error(runtime_row, altered, 600, 2400).is_empty(),
			"runtime-domain proof rejects altered " + str(change[0]))
	for change: Array in [["code", "unknown"], ["origin", "direct"], ["feed_factor", 1.0], ["rpm", 1.0],
			["demand_nm", NAN], ["friction_nm", -1.0], ["prop_load_torque_nm", 2.0]]:
		var altered: Dictionary = runtime_proof.duplicate(true)
		altered.native_cause[change[0]] = change[1]
		_check(not Fleet._fleet_runtime_proof_error(runtime_row, altered, 600, 2400).is_empty(),
			"runtime-domain proof rejects invalid native branch field " + str(change[0]))
	var wrong_reference: Dictionary = runtime_proof.duplicate(true)
	wrong_reference.reference_identity.backend = "native"
	_check(not Fleet._fleet_runtime_proof_error(runtime_row, wrong_reference, 600, 2400).is_empty(),
		"runtime-domain proof rejects a native evaluator masquerading as reference")
	var owner_fixture := FakeSession.new()
	var original_owner: Callable = owner_fixture.sim.model.stage
	var wrapper := func(body: Variant, continuous: Variant, at: Variant) -> Variant:
		return original_owner.call(body, continuous, at)
	owner_fixture.sim.model.stage = wrapper
	var owner_expected := {stage = wrapper, loads = Callable(), rotor_momentum = Callable(),
		block_loads = Callable(), block_derivative = Callable(), stage_rotor_momentum = Callable()}
	_check(Fleet._fleet_backend_owner_error(owner_fixture, "gdscript_reference", {backend = "gdscript_reference"},
		owner_expected, null, null).is_empty(), "reference wrapper retains its verified owner")
	owner_fixture.sim.model.stage = original_owner
	_check(not Fleet._fleet_backend_owner_error(owner_fixture, "gdscript_reference", {backend = "gdscript_reference"},
		owner_expected, null, null).is_empty(), "replacing the reference wrapper fails ownership")
	owner_fixture.sim.model.stage = wrapper
	owner_fixture.actual = "native"
	_check(not Fleet._fleet_backend_owner_error(owner_fixture, "gdscript_reference", {backend = "gdscript_reference"},
		owner_expected, null, null).is_empty(), "reference identity changing after rejection fails ownership")
	owner_fixture.free()
	for change: Array in [["demand_nm", -0.01], ["demand_nm", -0.009], ["demand_nm", NAN],
			["rotor_inertia_kg_m2", 0.0], ["rotor_inertia_kg_m2", -1.0], ["prop_load_torque_nm", 0.03]]:
		var altered: Dictionary = runtime_proof.duplicate(true)
		altered.reference_cause[change[0]] = change[1]
		altered.native_cause[change[0]] = change[1]
		if change[0] == "demand_nm" and is_finite(change[1]):
			altered.reference_cause.prop_load_torque_nm = -change[1]
			altered.native_cause.prop_load_torque_nm = -change[1]
		_check(not Fleet._fleet_runtime_proof_error(runtime_row, altered, 600, 2400).is_empty(),
			"runtime-domain proof rejects identical but invalid boundary value " + str(change[0]))
	for problem: String in ["body shape", "continuous shape", "nonfinite body", "degenerate attitude", "wrong mode", "wrong stage time", "context shape", "nonfinite input", "wrong tick time", "wrong flags"]:
		var altered: Dictionary = runtime_proof.duplicate(true)
		var trial: Array = bytes_to_var(runtime_proof.trial_bytes_hex.hex_decode())
		var context: Array = bytes_to_var(runtime_proof.context_bytes_hex.hex_decode())
		match problem:
			"body shape": trial[0].resize(12)
			"continuous shape": trial[1].resize(21)
			"nonfinite body": trial[0][0] = NAN
			"degenerate attitude": trial[0][6] = 0.0
			"wrong mode": trial[1][18] = 0.0
			"wrong stage time": trial[2] += 1.0
			"context shape": context[0].resize(13)
			"nonfinite input": context[1][0] = INF
			"wrong tick time": context[3] += 1.0
			"wrong flags": context[6] = true
		_replace_runtime_payload(altered, "trial", trial)
		_replace_runtime_payload(altered, "context", context)
		_check(not Fleet._fleet_runtime_proof_error(runtime_row, altered, 600, 2400).is_empty(),
			"runtime-domain proof rejects identically rehashed " + problem)
	var route := RuntimeRouteFleet.new()
	route._report = {fleet = [], components = {}}
	route._fleet_case(runtime_row, 1, 1)
	_check(route.normal_calls == 1 and route.runtime_calls == 0,
		"a horizon ending before the known boundary remains an ordinary flight")
	route._fleet_case(runtime_row, runtime_row.expected_runtime_tick - 1, 1)
	_check(route.normal_calls == 2 and route.runtime_calls == 0,
		"a horizon ending exactly at the last accepted tick remains an ordinary flight")
	route._fleet_case(runtime_row, 600, 2400)
	_check(route.normal_calls == 2 and route.runtime_calls == 1,
		"a horizon beyond the known boundary requires the specific runtime-domain proof")
	route.free()
	for id: String in Catalog.flyable_ids():
		_check(not Fleet._fleet_selected_rows(declared, id, "", "").is_empty(), "catalog aircraft is declared: " + id)
	for id: String in Catalog.airplane_flyable_ids():
		if not Catalog.has_battery_mode(id, "pack"):
			continue
		var found := {}
		for row: Dictionary in Fleet._fleet_selected_rows(declared, id, "calm", "on"):
			found[row.battery] = true
		_check(found.has("pack") and found.has("ideal"), "both battery modes declared: " + id)
	var rotor_rows := Fleet._fleet_selected_rows(declared, "xcell-60-research", "calm", "")
	_check(rotor_rows.size() == 2 and rotor_rows[0].vehicle == "rotorcraft",
		"helicopter airborne and ground routes are declared")
	var rotor_all := Fleet._fleet_selected_rows(declared, "xcell-60-research", "", "")
	var rotor_refusals := Fleet._fleet_selected_rows(declared, "xcell-60-research", "hot-high", "")
	_check(rotor_all.size() == 14 and rotor_refusals.size() == 2,
		"six supported helicopter conditions and the hot-high reference refusal are declared for both starts")
	var expected_failure := {ok = false, phase = "reset",
		reason = "reset failed: Helicopter start refused: " + Fleet.HELICOPTER_TRIM_REFUSAL}
	_check(Fleet._fleet_expected_refusal(rotor_refusals[0], expected_failure), "the known trim refusal is explicit")
	_check(not Fleet._fleet_expected_refusal(rotor_rows[0], expected_failure) \
		and not Fleet._fleet_expected_refusal(rotor_refusals[0], {ok = false, phase = "weather", reason = Fleet.HELICOPTER_TRIM_REFUSAL}) \
		and not Fleet._fleet_expected_refusal(rotor_refusals[0], {ok = false, phase = "reset", reason = "different failure"}) \
		and not Fleet._fleet_expected_refusal(rotor_refusals[0], {ok = true}) \
		and not Fleet._fleet_expected_refusal(rotor_refusals[1], expected_failure),
		"setup failure, wrong condition, different reset failure and successful start do not masquerade as trim refusal")
	var stik_refusals: Array[Dictionary] = []
	for row: Dictionary in declared:
		if row.vehicle == "fixed-wing" and row.get("expected") == "reference-refusal":
			stik_refusals.append(row)
	_check(stik_refusals.size() == 16, "only the four proven Stik variants and crosswind runway combinations are marked")
	var stik_failure := {ok = false, phase = "reset", reason = Fleet.STIK_RUNWAY_REFUSAL}
	for row: Dictionary in stik_refusals:
		_check(Fleet._fleet_expected_refusal_pair(row, stik_failure, stik_failure),
			"the exact matching Stik reset refusal is declared: %s/%s/soft=%s" % [row.aircraft, row.weather, row.soft_hull])
	var stik_row := stik_refusals[0].duplicate(true)
	var altered_row := stik_row.duplicate(true)
	altered_row.aircraft = "gp-extra-300s-60"
	_check(not Fleet._fleet_expected_refusal(altered_row, stik_failure), "another aircraft cannot match the Stik refusal")
	altered_row = stik_row.duplicate(true)
	altered_row.weather = "calm"
	_check(not Fleet._fleet_expected_refusal(altered_row, stik_failure), "another weather cannot match the Stik refusal")
	altered_row = stik_row.duplicate(true)
	altered_row.case = "trim"
	_check(not Fleet._fleet_expected_refusal(altered_row, stik_failure), "another start cannot match the Stik refusal")
	altered_row = stik_row.duplicate(true)
	altered_row.battery = "pack"
	_check(not Fleet._fleet_expected_refusal(altered_row, stik_failure), "another battery cannot match the Stik refusal")
	altered_row = stik_row.duplicate(true)
	altered_row.soft_hull = null
	_check(not Fleet._fleet_expected_refusal(altered_row, stik_failure), "missing contact selection cannot match the Stik refusal")
	_check(not Fleet._fleet_expected_refusal_pair(stik_row, stik_failure,
		{ok = false, phase = "weather", reason = Fleet.STIK_RUNWAY_REFUSAL}) \
		and not Fleet._fleet_expected_refusal_pair(stik_row, stik_failure,
			{ok = false, phase = "reset", reason = Fleet.STIK_RUNWAY_REFUSAL + " different"}) \
		and not Fleet._fleet_expected_refusal_pair(stik_row, stik_failure, {ok = true}) \
		and not Fleet._fleet_expected_refusal_pair(stik_row, {ok = false, phase = "backend"}, stik_failure),
		"a mismatch from either requested backend fails the paired refusal")
	var refusal_fixture := RefusalFleet.new()
	refusal_fixture._report = {fleet = [], components = {}}
	refusal_fixture.reference_result = stik_failure
	refusal_fixture.native_result = stik_failure
	refusal_fixture._fleet_case(stik_row, 2, 3)
	var refusal_result: Dictionary = refusal_fixture._report.fleet.back()
	_check(refusal_result.status == "reference-refused" and not refusal_result.fingerprint_equal \
		and not refusal_result.reference.complete and not refusal_result.native.complete \
		and refusal_result.reference.phase == "reset" and refusal_result.native.phase == "reset" \
		and refusal_result.reference.error == Fleet.STIK_RUNWAY_REFUSAL \
		and refusal_result.native.error == Fleet.STIK_RUNWAY_REFUSAL and refusal_fixture._failures.is_empty(),
		"matching refusals record both attempts without qualifying a native flight")
	for mismatch: Dictionary in [{ok = false, phase = "weather", reason = Fleet.STIK_RUNWAY_REFUSAL},
			{ok = false, phase = "reset", reason = "different failure"}]:
		refusal_fixture._report = {fleet = [], components = {}}
		refusal_fixture._failures = PackedStringArray()
		refusal_fixture.native_result = mismatch
		refusal_fixture._fleet_case(stik_row, 2, 3)
		_check(refusal_fixture._report.fleet.back().status == "fail" and not refusal_fixture._failures.is_empty(),
			"a mismatched native attempt is reported as a failure")
	refusal_fixture.free()
	for row: Dictionary in stik_refusals:
		var built: Dictionary = fleet._build_fleet_session(row, NativeStage.BACKEND_REFERENCE)
		_check(Fleet._fleet_expected_refusal(row, built), "actual Stik reference reset refuses: %s/%s/soft=%s %s" \
			% [row.aircraft, row.weather, row.soft_hull, built.get("reason", "started")])
		if built.get("ok", false): built.session.free()
	# Exercise the real policy when the verified native library is installed. A library-free
	# policy test still checks the refusal predicate and the reference starts below.
	var native_available: bool = NativeStage.library_status().get("ok", false)
	if native_available:
		fleet._report = {fleet = [], components = {}}
		for row: Dictionary in stik_refusals + rotor_refusals:
			fleet._fleet_case(row, 2, 3)
			var result: Dictionary = fleet._report.fleet.back()
			_check(result.status == "reference-refused" and not result.fingerprint_equal \
				and not result.reference.complete and not result.native.complete \
				and result.reference.phase == "reset" and result.native.phase == "reset" \
				and result.reference.error == result.native.error and Fleet._fleet_expected_refusal(row,
					{ok = false, phase = result.reference.phase, reason = result.reference.error}),
				"actual paired reset refusal is recorded without a flight pass: %s/%s/%s/soft=%s" \
				% [row.aircraft, row.case, row.weather, row.soft_hull])
		_check(fleet._failures.is_empty(), "actual paired reset refusals leave no policy errors")
	else:
		print("NK3 fleet policy: native reset checks skipped (verified library unavailable)")
	if OS.get_cmdline_user_args().has("--require-runtime-domain"):
		var can_probe := native_available and ClassDB.class_has_method("OpenRCNativeKernel", "set_stage_rejection_diagnostics") \
			and ClassDB.class_has_method("OpenRCNativeKernel", "stage_rejection_diagnostic")
		_check(can_probe, "verified native rejection diagnostic is available")
		if can_probe:
			fleet._report = {fleet = [], components = {}}
			fleet._failures = PackedStringArray()
			var native_proofs := 0
			for row: Dictionary in runtime_rows:
				fleet._fleet_runtime_case(row, 600, 2400)
				var result: Dictionary = fleet._report.fleet.back()
				var accepted: bool = result.status == "runtime-domain-refused" and not result.reference.complete \
					and not result.native.complete and Fleet._fleet_runtime_proof_error(row, result.runtime_domain, 600, 2400).is_empty()
				_check(accepted, "actual native/reference reverse-domain proof: %s/soft=%s (%s)" \
					% [row.aircraft, row.soft_hull, result.reason])
				if accepted: native_proofs += 1
			if native_proofs == 4 and fleet._failures.is_empty() and _failures == 0:
				print("NK3_RUNTIME_DOMAIN_NATIVE verdict=pass")
	var filtered := Fleet._fleet_selected_rows(declared, Catalog.DEFAULT_ID, "calm", "on")
	_check(not filtered.is_empty() and filtered.size() < declared.size(), "filters select a scoped matrix")
	for row: Dictionary in filtered:
		_check(row.aircraft == Catalog.DEFAULT_ID and row.weather == "calm" and row.soft_hull == true,
			"scoped row respects all filters")
	for row: Dictionary in rotor_all:
		var built: Dictionary = fleet._build_fleet_session(row, "gdscript_reference")
		var label := "%s/%s" % [row.case, row.weather]
		if row.expected == "reference-refusal":
			_check(Fleet._fleet_expected_refusal(row, built),
				"actual hot-high reference reset refuses: " + label + " " + str(built.get("reason", "started")))
			if built.get("ok", false): built.session.free()
			continue
		_check(built.ok, "actual helicopter reference start: " + label + " " + str(built.get("reason", "")))
		if built.ok:
			var real_session: Node = built.session
			var real_run: Dictionary = fleet._fleet_run_session(real_session, "gdscript_reference", 2, 3, true)
			_check(real_run.complete and real_run.replay_ok and real_run.replay_completed == 5,
				"actual helicopter reference and checkpoint continuation: " + label + " " + str(real_run.error))
			real_session.free()
	fleet.free()
	print("NK3 fleet policy: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
