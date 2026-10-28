## Fleet qualification policy tests: no native library or full flight is required.
extends SceneTree

const Fleet := preload("fleet.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")

var _checks := 0
var _failures := 0


class FakeNative:
	extends RefCounted
	var stage_calls := 0
	var context_calls := 0

	func stage(_body: Variant, _continuous: Variant, _time: Variant) -> void:
		stage_calls += 1

	func reset_stage_stats(_timing: bool) -> void:
		stage_calls = 0
		context_calls = 0

	func stage_stats() -> Dictionary:
		return {stage_calls = stage_calls, context_calls = context_calls}


class FakeHelper:
	extends RefCounted
	var _native: FakeNative

	func owns_stage(session: Node) -> bool:
		return session.sim.model.stage == Callable(_native, "stage")


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
	var model := {stage = Callable()}
	var native: FakeNative
	var session: Node
	var failure := ""
	var fail_at := -1

	func dt() -> float:
		return 1.0 / 240.0

	func reference_stage(_body: Variant, _continuous: Variant, _time: Variant) -> void:
		pass

	func _physics_process(_delta: float) -> void:
		if paused or (failure == "stopped" and tick == fail_at):
			return
		previous = state.duplicate()
		tick += 1
		state[0] = 0.0
		aux[0] = float(tick)
		continuous[0] = float(tick)
		inputs[0] = float(tick)
		last_loads[0] = float(tick)
		modes[0] = tick
		if tick == fail_at and failure == "diverge_warmup":
			state[0] = 1.0
		if tick == fail_at and failure == "diverge_previous":
			previous[0] = 2.0
		if native != null:
			if failure != "missing_context" or tick != fail_at:
				native.context_calls += 1
			var count := 3 if failure == "missing_stage" and tick == fail_at else 4
			for _index in count:
				model.stage.call(0, 0, 0)
		if tick == fail_at:
			match failure:
				"uninstall": model.stage = Callable(self, "reference_stage")
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

	func _init() -> void:
		add_child(sim)
		sim.session = self
		sim.model.stage = Callable(sim, "reference_stage")

	func _physics_process(_delta: float) -> void:
		if read_raw.is_valid():
			read_raw.call()

	func stage_backend_status() -> Dictionary:
		return {requested = requested, identity = {backend = actual}, reason = "fixture fallback" if actual != requested else ""}


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL: " + label)


func _run_fake(fleet: Object, requested: String, failure := "", fail_at := -1,
		warmup := 2, samples := 3) -> Dictionary:
	var session := FakeSession.new()
	session.requested = requested
	session.actual = requested
	session.sim.failure = failure
	session.sim.fail_at = fail_at
	if requested == "native" and failure != "fallback":
		var helper := FakeHelper.new()
		helper._native = FakeNative.new()
		session._native_stage = helper
		session.sim.native = helper._native
		session.sim.model.stage = Callable(helper._native, "stage")
	elif failure == "fallback":
		session.actual = "gdscript_reference"
	session.read_raw = func() -> Dictionary:
		fleet._input_reads += 1
		return {}
	var result: Dictionary = fleet._fleet_run_session(session, requested, warmup, samples)
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
	for failure: String in ["missing_context", "missing_stage", "uninstall", "fault", "pause", "crash"]:
		var rejected := _run_fake(fleet, "native", failure, 3)
		_check(not rejected.complete and not Fleet._fleet_pair_error(reference, rejected, 2, 3).is_empty(),
			"native %s fails per-tick qualification" % failure)
	for failure: String in ["diverge_warmup", "diverge_previous"]:
		var divergent := _run_fake(fleet, "native", failure, 1)
		_check(divergent.complete and divergent.fingerprint != reference.fingerprint \
			and "fingerprints differ" in Fleet._fleet_pair_error(reference, divergent, 2, 3),
			"%s is retained in the complete fingerprint" % failure)
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
	var filtered := Fleet._fleet_selected_rows(declared, Catalog.DEFAULT_ID, "calm", "on")
	_check(not filtered.is_empty() and filtered.size() < declared.size(), "filters select a scoped matrix")
	for row: Dictionary in filtered:
		_check(row.aircraft == Catalog.DEFAULT_ID and row.weather == "calm" and row.soft_hull == true,
			"scoped row respects all filters")
	fleet.free()
	print("NK3 fleet policy: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
