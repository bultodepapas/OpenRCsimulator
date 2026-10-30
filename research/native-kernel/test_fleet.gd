## Fleet qualification policy tests: no native library or full flight is required.
extends SceneTree

const Fleet := preload("fleet.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const NativeStage := preload("res://sim/native_stage.gd")

# Captured typed values from the real FS64V rejecting midpoint (not decimal re-serialization).
const FS64V_TRIAL_HEX := (
	"1c00000003000000210000000d0000002dfb4a651b002e40b2f619ab5f7f47c08db512ad9628cebf8864e81a45a9773f67b2" +
	"57cbd95429bf0beed592e43268bfbabc1d39449fe63f9be668d172d1893f4589738ed0e08ebf7d320ac0bb9fe63fd5ebd948" +
	"fe2a49bf1fddef3e77e694bf780dfe96e6372ebf210000001600000000000000000000007e1e48838021c83f2e19da8cf81f" +
	"784000000000000000003a5cfdb1bb74983f0000000000000000000000000000000000000000000000000000000000000040" +
	"000000000000000000000000000000000000000000000000666666666666f23f00000000000000000000000000000000d9f7" +
	"0afdbfe1ecbf00000000000000000000000000000000000000000000f03fe75cab5af144463f4854f3cb2f714a3f19931f68" +
	"57dd413f030001009999999999d90a40"
)
const FS64V_CONTEXT_HEX := (
	"1c00000008000000210000000e0000000000000000000000d4519a951d5d9b3fa57d00ed5b9db33f8bd52d7239ab983f56f0" +
	"ec88cd5b2e40f81b7414d08e47c0000000000000f03f1248bdca7ba32d404a66cdb6cf8e47c0000000000000f03fc1ce2860" +
	"a4ff2d40f6aa28e1d96147c0000000000000f03f9e9ad56763b0f5bf2100000004000000d4519a951d5d9b3fa57d00ed5b9d" +
	"b33f8bd52d7239ab983f00000000000000002100000005000000f88f96d123639bbf341b2c457e1a83bf341b2c457e1a833f" +
	"72130dac128785bf0000000000000000030001005555555555d50a4003000000000000000300000000000000010000000000" +
	"00000100000000000000"
)
const FS64V_AIRCRAFT_SHA := "c42f72ac9f714e67801466fdd652f7bd214f59cc6577340ace348752f2f9a91a"
const FS64V_CAUSE_BYTES_HEX := "210000000700000000000000000000000000000000000000acf7f5a16f0d90bf442c89836c0a903ffb702e7c620d903fd22f068cdc4b333f85580189a0cd453f"

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


class TerminalRouteFleet:
	extends Fleet
	var terminal_calls := 0
	var normal_calls := 0

	func _fleet_terminal_case(_row: Dictionary, _warmup: int, _samples: int) -> void:
		terminal_calls += 1

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
	var terminal_rows: Array[Dictionary] = []
	for candidate: Dictionary in declared:
		if candidate.get("expected") == "physical-terminal": terminal_rows.append(candidate)
	_check(terminal_rows.size() == 2, "only the two observed X8 physical terminals are declared")
	for row: Dictionary in terminal_rows:
		_check(Fleet._fleet_terminal_tick(row) == 1640, "observed X8 terminal has its exact accepted tick")
		for change: Array in [["aircraft", "other"], ["battery", "ideal"], ["case", "trim"],
				["weather", "crosswind"], ["vehicle", "rotorcraft"], ["soft_hull", 1],
				["default_battery", 1], ["expected_terminal_tick", 1639]]:
			var changed := row.duplicate(true)
			changed[change[0]] = change[1]
			_check(Fleet._fleet_terminal_tick(changed) < 0, "terminal rejects another " + str(change[0]))
	if not terminal_rows.is_empty():
		var terminal_route := TerminalRouteFleet.new()
		terminal_route._report = {fleet = [], components = {}}
		terminal_route._fleet_case(terminal_rows[0], 1, 1)
		_check(terminal_route.normal_calls == 1 and terminal_route.terminal_calls == 0,
			"a shorter horizon remains an ordinary flight")
		terminal_route._fleet_case(terminal_rows[0], 600, 1040)
		_check(terminal_route.normal_calls == 1 and terminal_route.terminal_calls == 1,
			"a horizon ending at the accepted collision requires the physical-terminal proof")
		terminal_route.free()
	var fs64v_runway_rows := 0
	for declared_row: Dictionary in Fleet._fleet_selected_rows(declared, "stik-glow-fs64v-4t", "gusty", ""):
		if declared_row.case != "runway" or declared_row.battery != "ideal":
			continue
		fs64v_runway_rows += 1
		_check(declared_row.get("expected") == "runtime-domain-refusal" \
			and declared_row.get("expected_runtime_tick") == 805,
			"FS64V gusty runway declares its observed rejection: soft=%s" % declared_row.soft_hull)
		var observed_row := declared_row.duplicate(true)
		observed_row.expected = "runtime-domain-refusal"
		observed_row.expected_runtime_tick = 805
		var observed := _runtime_proof_fixture(observed_row, 600, 2400)
		var trial: Array = bytes_to_var(FS64V_TRIAL_HEX.hex_decode())
		var context: Array = bytes_to_var(FS64V_CONTEXT_HEX.hex_decode())
		_replace_runtime_payload(observed, "trial", trial)
		_replace_runtime_payload(observed, "context", context)
		observed.reference_aircraft_sha256 = FS64V_AIRCRAFT_SHA
		observed.native_aircraft_sha256 = FS64V_AIRCRAFT_SHA
		var cause_values: PackedFloat64Array = bytes_to_var(FS64V_CAUSE_BYTES_HEX.hex_decode())
		var cause_fields := ["feed_factor", "rpm", "demand_nm", "friction_nm", "prop_load_torque_nm",
			"axial_acceleration_rad_s2", "rotor_inertia_kg_m2"]
		for index: int in cause_fields.size():
			observed.reference_cause[cause_fields[index]] = cause_values[index]
			observed.native_cause[cause_fields[index]] = cause_values[index]
		observed.rejected_stage_calls = 2
		observed.native_stage_calls = 4 * 805 + 2
		observed.native_diagnostic_stage_call = observed.native_stage_calls
		_check(Fleet._fleet_runtime_proof_error(observed_row, observed, 600, 2400).is_empty(),
			"FS64V midpoint rejection is proven separately: soft=%s" % declared_row.soft_hull)
		for change: Array in [["warmup_completed", 599], ["samples_completed", 206],
				["reference_rollback", false], ["native_rollback", false], ["reference_owner_retained", false],
				["native_owner_retained", false], ["native_covered_every_tick", false],
				["reference_input_reads", 805], ["native_input_reads", 805],
				["rejected_context_calls", 2], ["native_diagnostic_stage_call", 3221],
				["native_diagnostic_context_call", 805], ["native_diagnostic_stage_call", 3222.0],
				["native_diagnostic_context_call", 806.0]]:
			var altered: Dictionary = observed.duplicate(true)
			altered[change[0]] = change[1]
			_check(not Fleet._fleet_runtime_proof_error(observed_row, altered, 600, 2400).is_empty(),
				"FS64V rejects altered " + str(change[0]))
		for ordinal: int in [1, 4]:
			var altered: Dictionary = observed.duplicate(true)
			altered.rejected_stage_calls = ordinal
			altered.native_stage_calls = 4 * 805 + ordinal
			altered.native_diagnostic_stage_call = altered.native_stage_calls
			_check(not Fleet._fleet_runtime_proof_error(observed_row, altered, 600, 2400).is_empty(),
				"FS64V rejects a self-consistent wrong RK call ordinal")
		var short_coverage: Dictionary = observed.duplicate(true)
		short_coverage.native_stage_calls = 4 * 805 + 1
		short_coverage.native_diagnostic_stage_call = short_coverage.native_stage_calls
		_check(not Fleet._fleet_runtime_proof_error(observed_row, short_coverage, 600, 2400).is_empty(),
			"FS64V total native stage coverage includes the two rejecting calls")
		var endpoint: Array = bytes_to_var(FS64V_TRIAL_HEX.hex_decode())
		endpoint[2] = float(805) * (1.0 / 240.0) + (1.0 / 240.0)
		var changed_phase: Dictionary = observed.duplicate(true)
		_replace_runtime_payload(changed_phase, "trial", endpoint)
		_check(not Fleet._fleet_runtime_payload_valid(endpoint, context, 805, 0.5) \
			and not Fleet._fleet_runtime_proof_error(observed_row, changed_phase, 600, 2400).is_empty(),
			"FS64V endpoint is not its observed midpoint")
		for change: String in ["stale time", "forged finite aux", "forged native bytes"]:
			var altered: Dictionary = observed.duplicate(true)
			var forged: Array = bytes_to_var(FS64V_CONTEXT_HEX.hex_decode())
			match change:
				"stale time": forged[3] -= 1.0 / 240.0
				"forged finite aux": forged[0][0] = 0.01
				"forged native bytes": altered.native_context_bytes_hex = "00"
			if change == "forged finite aux":
				_check(Fleet._fleet_runtime_payload_valid(trial, forged, 805, 0.5),
					"finite forged context still satisfies shape and time alone")
			if change != "forged native bytes": _replace_runtime_payload(altered, "context", forged)
			_check(not Fleet._fleet_runtime_proof_error(observed_row, altered, 600, 2400).is_empty(),
				"FS64V rejects " + change + " context")
		var forged_cause: Dictionary = observed.duplicate(true)
		for cause: Dictionary in [forged_cause.reference_cause, forged_cause.native_cause]:
			cause.demand_nm = -0.02
			cause.friction_nm = 0.01
			cause.prop_load_torque_nm = 0.02
			cause.axial_acceleration_rad_s2 = 0.0
			cause.rotor_inertia_kg_m2 = 0.01
		_check(not Fleet._fleet_runtime_proof_error(observed_row, forged_cause, 600, 2400).is_empty(),
			"FS64V rejects an identical, algebraically valid but forged cause tuple")
		var altered_factor: Dictionary = observed.duplicate(true)
		altered_factor.reference_cause.feed_factor = 2.0
		altered_factor.native_cause.feed_factor = 2.0
		_check(not Fleet._fleet_runtime_proof_error(observed_row, altered_factor, 600, 2400).is_empty(),
			"FS64V rejects an unobserved feed endpoint even when both causes agree")
		var altered_aircraft: Dictionary = observed.duplicate(true)
		altered_aircraft.reference_aircraft_sha256 = "d".repeat(64)
		altered_aircraft.native_aircraft_sha256 = "d".repeat(64)
		_check(not Fleet._fleet_runtime_proof_error(observed_row, altered_aircraft, 600, 2400).is_empty(),
			"FS64V rejects another identically reported aircraft")
	_check(fs64v_runway_rows == 2, "both FS64V soft-hull runway rows are selected")
	var runtime_rows: Array[Dictionary] = []
	for row: Dictionary in declared:
		if row.get("expected") == "runtime-domain-refusal": runtime_rows.append(row)
	_check(runtime_rows.size() == 6, "only the six observed reverse-breakaway rows are declared")
	for row: Dictionary in runtime_rows:
		var expected_tick: int = 873 if row.aircraft == "stik-glow-61fx-2t" \
			else 801 if row.aircraft == "stik-glow-55ax-2t" else 805
		_check(Fleet._fleet_runtime_tick(row) == expected_tick,
			"runtime-domain declaration has its exact accepted tick: %s/soft=%s" % [row.aircraft, row.soft_hull])
	var runtime_row := {}
	for candidate: Dictionary in runtime_rows:
		if candidate.aircraft == "stik-glow-61fx-2t" and candidate.soft_hull:
			runtime_row = candidate.duplicate(true)
			break
	_check(not runtime_row.is_empty(), "the two-stroke endpoint control is declared")
	var runtime_proof := _runtime_proof_fixture(runtime_row, 600, 2400)
	_check(Fleet._fleet_runtime_proof_error(runtime_row, runtime_proof, 600, 2400).is_empty(),
		"a complete exact runtime-domain proof is accepted separately")
	var two_stroke_trial: Array = bytes_to_var(runtime_proof.trial_bytes_hex.hex_decode())
	var two_stroke_context: Array = bytes_to_var(runtime_proof.context_bytes_hex.hex_decode())
	two_stroke_trial[2] = float(runtime_row.expected_runtime_tick) * (1.0 / 240.0) + (1.0 / 240.0) / 2.0
	var two_stroke_midpoint: Dictionary = runtime_proof.duplicate(true)
	_replace_runtime_payload(two_stroke_midpoint, "trial", two_stroke_trial)
	_check(not Fleet._fleet_runtime_payload_valid(two_stroke_trial, two_stroke_context,
		runtime_row.expected_runtime_tick, 1.0) \
		and not Fleet._fleet_runtime_proof_error(runtime_row, two_stroke_midpoint, 600, 2400).is_empty(),
		"two-stroke midpoint cannot replace its endpoint")
	var two_stroke_ordinal: Dictionary = runtime_proof.duplicate(true)
	two_stroke_ordinal.rejected_stage_calls = 2
	two_stroke_ordinal.native_stage_calls = 4 * runtime_row.expected_runtime_tick + 2
	two_stroke_ordinal.native_diagnostic_stage_call = two_stroke_ordinal.native_stage_calls
	_check(not Fleet._fleet_runtime_proof_error(runtime_row, two_stroke_ordinal, 600, 2400).is_empty(),
		"two-stroke endpoint requires the fourth stage call")
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
	var fs64v_row := {}
	for candidate: Dictionary in runtime_rows:
		if candidate.aircraft == "stik-glow-fs64v-4t" and candidate.soft_hull:
			fs64v_row = candidate.duplicate(true)
			break
	route._fleet_case(fs64v_row, 600, 205)
	_check(route.normal_calls == 3 and route.runtime_calls == 1,
		"FS64V horizon ending at accepted tick 805 remains an ordinary flight")
	route._fleet_case(fs64v_row, 600, 206)
	_check(route.normal_calls == 3 and route.runtime_calls == 2,
		"FS64V horizon reaching attempted tick 806 requires its specific proof")
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
	var bounded_runway_refusals: Array[Dictionary] = []
	var bounded_trim_refusals: Array[Dictionary] = []
	for row: Dictionary in declared:
		if row.get("expected") == "reference-refusal" and row.get("aircraft") in Fleet.STIK_RUNWAY_REFUSAL_AIRCRAFT:
			stik_refusals.append(row)
		elif row.get("expected") == "reference-refusal" and Fleet._fleet_is_runway_boundary(row):
			bounded_runway_refusals.append(row)
		elif row.get("expected") == "reference-refusal" and Fleet._fleet_is_trim_boundary(row):
			bounded_trim_refusals.append(row)
	_check(stik_refusals.size() == 16, "only the four proven Stik variants and crosswind runway combinations are marked")
	_check(bounded_runway_refusals.size() == 8, "only eight observed crosswind runway rows are marked")
	_check(bounded_trim_refusals.size() == 2, "only two observed X8 half-power hot-high rows are marked")
	for row: Dictionary in declared:
		if row.get("aircraft") in Fleet.RUNWAY_START_BOUNDARIES and row.get("expected") == "reference-refusal":
			_check(Fleet._fleet_is_runway_boundary(row), "other weather, battery or start is not classified")
		if row.get("aircraft") in Fleet.TRIM_START_BOUNDARIES and row.get("expected") == "reference-refusal":
			_check(Fleet._fleet_is_trim_boundary(row), "other X8 weather, battery or start is not classified")
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
	for row: Dictionary in bounded_runway_refusals + bounded_trim_refusals:
		var observed: Dictionary = fleet._build_fleet_session(row, NativeStage.BACKEND_REFERENCE)
		_check(Fleet._fleet_expected_refusal(row, observed) \
			and Fleet._fleet_start_proof_valid(row, observed.get("startup_proof"), NativeStage.BACKEND_REFERENCE),
			"actual bounded reference failure retains the observed typed state: %s/soft=%s" % [row.aircraft, row.soft_hull])
		if observed.get("ok", false):
			observed.session.free()
			continue
		var synthetic_native: Dictionary = observed.duplicate(true)
		var native_proof: Dictionary = synthetic_native.get("startup_proof", {})
		if native_proof.is_empty(): continue
		native_proof.requested = NativeStage.BACKEND_NATIVE
		for key: String in ["before_status", "after_status"]:
			native_proof[key].requested = NativeStage.BACKEND_NATIVE
			native_proof[key].reason = "pending configuration requires reset"
		_check(Fleet._fleet_expected_refusal_pair(row, observed, synthetic_native),
			"paired bounded proof requires both reference-owned reset outcomes")
		var forged_reference: Dictionary = observed.duplicate(true)
		var forged_native: Dictionary = synthetic_native.duplicate(true)
		for forged: Dictionary in [forged_reference, forged_native]:
			forged.startup_proof.before_live_config_bytes_hex = "00"
			forged.startup_proof.live_config_bytes_hex = "00"
			forged.startup_proof.live_config_sha256 = Fleet._fleet_encoded_sha256(PackedByteArray([0]))
		_check(not Fleet._fleet_expected_refusal_pair(row, forged_reference, forged_native),
			"matching rehashed live configurations cannot replace the pinned observation")
		for change: Array in [["before_helper_absent", false], ["after_helper_absent", false],
				["model_retained", false], ["callbacks_retained", false], ["kernel_guard_retained", false],
				["owner_guard_retained", false], ["input_configuration_retained", false],
				["selection_valid_before", false], ["selection_valid_after", false],
				["live_configuration_retained", false], ["live_config_bytes_hex", "00"],
				["reference_callbacks_before", false], ["reference_callbacks_after", false],
				["callbacks_retained", 1], ["outcome_dictionary_empty", 1],
				["outcome_status", "invalid_input"], ["outcome_empty", false],
				["config_sha256", "0".repeat(64)], ["outcome_bytes_hex", "00"],
				["before_frame_bytes_hex", "00"]]:
			var altered: Dictionary = synthetic_native.duplicate(true)
			altered.startup_proof[change[0]] = change[1]
			_check(not Fleet._fleet_expected_refusal_pair(row, observed, altered),
				"bounded proof rejects altered " + str(change[0]))
		for change: Array in [["aircraft", "f4u-corsair-250"], ["weather", "spatial-crosswind-v1"],
				["battery", "invalid-battery"], ["case", "trim"], ["soft_hull", null]]:
			var boundary_changed_row: Dictionary = row.duplicate(true)
			boundary_changed_row[change[0]] = change[1]
			_check(not Fleet._fleet_expected_refusal_pair(boundary_changed_row, observed, synthetic_native),
				"bounded refusal rejects a different " + str(change[0]))
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
		for row: Dictionary in bounded_runway_refusals + bounded_trim_refusals:
			fleet._fleet_case(row, 2, 3)
			var result: Dictionary = fleet._report.fleet.back()
			_check(result.status == "reference-refused" and not result.fingerprint_equal \
				and not result.reference.complete and not result.native.complete \
				and result.reference.phase == "reset" and result.native.phase == "reset" \
				and result.reference.error == result.native.error and result.has("startup_proof"),
				"actual paired bounded reset refuses without native-flight credit: %s/soft=%s" % [row.aircraft, row.soft_hull])
		_check(fleet._failures.is_empty(), "actual paired bounded reset proofs leave no policy errors")
	else:
		print("NK3 fleet policy: native reset checks skipped (verified library unavailable)")
	if OS.get_cmdline_user_args().has("--require-physical-terminal"):
		_check(native_available, "verified native stage is available for physical-terminal pairs")
		if native_available:
			fleet._report = {fleet = [], components = {}}
			fleet._failures = PackedStringArray()
			for row: Dictionary in terminal_rows:
				fleet._fleet_case(row, 2, 3)
				var short_run: Dictionary = fleet._report.fleet.back()
				_check(short_run.status == "pass" and short_run.reference.complete and short_run.native.complete \
					and short_run.native.native_covered_every_tick,
					"shorter X8 horizon remains a healthy native/reference flight: soft=%s" % row.soft_hull)
			fleet._report = {fleet = [], components = {}}
			fleet._failures = PackedStringArray()
			var actual_terminals := 0
			for row: Dictionary in terminal_rows:
				fleet._fleet_terminal_case(row, 600, 2400)
				var result: Dictionary = fleet._report.fleet.back()
				var proof: Dictionary = result.get("physical_terminal", {})
				var accepted: bool = result.status == "physical-terminal" and not result.reference.complete \
					and not result.native.complete and not result.fingerprint_equal \
					and Fleet._fleet_terminal_proof_error(row, proof, 600, 2400).is_empty()
				_check(accepted, "actual paired accepted collision is separate from flights: soft=%s" % row.soft_hull)
				if not accepted: continue
				actual_terminals += 1
				for change: Array in [["terminal_tick", 1639], ["terminal_accepted", false],
						["previous_state_retained", false], ["stopped_unchanged", false],
						["native_covered_every_tick", false], ["native_owner_every_tick", false],
						["model_contract_retained", false], ["physical_configuration_retained", false],
						["live_configuration_retained", false], ["no_holds", false], ["native_context_calls", 1639],
						["native_stage_calls", 6559], ["reference_prefix_sha256", "0".repeat(64)]]:
					var altered: Dictionary = proof.duplicate(true)
					altered[change[0]] = change[1]
					_check(not Fleet._fleet_terminal_proof_error(row, altered, 600, 2400).is_empty(),
						"physical-terminal proof rejects changed " + str(change[0]))
				for field: String in ["terminal_frame", "terminal_view", "impact", "contact_event",
						"physical_configuration", "reference_live_configuration", "native_live_configuration"]:
					var forged: Dictionary = proof.duplicate(true)
					forged[field + "_bytes_hex"] = "00"
					forged[field + "_sha256"] = Fleet._fleet_encoded_sha256("00".hex_decode())
					if field == "terminal_frame": forged.stopped_frame_bytes_hex = "00"
					if field == "terminal_view": forged.stopped_view_bytes_hex = "00"
					_check(not Fleet._fleet_terminal_proof_error(row, forged, 600, 2400).is_empty(),
						"physical-terminal proof rejects rehashed " + field)
				var forged_view: Dictionary = proof.duplicate(true)
				forged_view.terminal_view.crash.impact.obstacle_id = "another-tree"
				forged_view.terminal_view_bytes_hex = var_to_bytes(forged_view.terminal_view).hex_encode()
				forged_view.terminal_view_sha256 = Fleet._fleet_encoded_sha256(forged_view.terminal_view_bytes_hex.hex_decode())
				forged_view.stopped_view_bytes_hex = forged_view.terminal_view_bytes_hex
				_check(not Fleet._fleet_terminal_proof_error(row, forged_view, 600, 2400).is_empty(),
					"physical-terminal proof rejects coherently rehashed collision metadata")
				var forged_configs: Dictionary = proof.duplicate(true)
				for side: String in ["reference", "native"]:
					forged_configs[side + "_live_configuration_bytes_hex"] = "00"
					forged_configs[side + "_live_configuration_sha256"] = Fleet._fleet_encoded_sha256("00".hex_decode())
				_check(not Fleet._fleet_terminal_proof_error(row, forged_configs, 600, 2400).is_empty(),
					"physical-terminal proof rejects paired rehashed live configurations")
				for change: Array in [["binary_sha256", "0".repeat(64)], ["abi_version", 3], ["abi_version", 2.0],
						["backend_version", "other"], ["source_sha256", "0".repeat(64)], ["lock_sha256", "0".repeat(64)]]:
					var forged_owner: Dictionary = proof.duplicate(true)
					forged_owner.native_identity[change[0]] = change[1]
					_check(not Fleet._fleet_terminal_proof_error(row, forged_owner, 600, 2400).is_empty(),
						"physical-terminal proof rejects changed native " + str(change[0]))
			_check(actual_terminals == 2 and fleet._failures.is_empty(), "both physical-terminal pairs are proven")
			if actual_terminals == 2 and fleet._failures.is_empty() and _failures == 0:
				print("NK3_PHYSICAL_TERMINAL_NATIVE verdict=pass")
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
			_check(runtime_rows.size() == 6 and native_proofs == 6,
				"all six native/reference runtime proofs are present and accepted")
			if native_proofs == 6 and fleet._failures.is_empty() and _failures == 0:
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
