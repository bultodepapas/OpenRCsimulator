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
