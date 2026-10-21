extends SceneTree

## Migration parity gate for the reachable pilot wrapper and immutable circuit base.
## Run only after pilot.gd and reachable_pilot_r2.gd both extend circuit_controller.gd.
const ProductionPath := "res://ai/companions/pilot.gd"
const CandidatePath := "res://../research/ai-companions/avoidance/reachable_pilot_r2.gd"
const CircuitBasePath := "res://ai/companions/circuit_controller.gd"
const FieldLoader := preload("res://data/field_loader.gd")
const Math3D := preload("res://physics/math3d.gd")
const RigidBody := preload("res://physics/rigid_body.gd")

const SEED := 20261020
const TRIM := {"V": 15.0, "throttle": 0.45}
const EMPTY_REACHABLE_STATE := {
	"version": "reachable-pilot-state-v1",
	"planning_tick": 0,
	"has_held_maneuver": false,
	"held_bank_rad": 0.0,
	"hold_until_tick": -1,
	"clear_since_tick": -1,
}

var _checks := 0
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var production_script := _load_script(ProductionPath)
	var candidate_script := _load_script(CandidatePath)
	var base_script := _load_script(CircuitBasePath)
	_check("production wrapper script loads", production_script != null)
	_check("research R2 wrapper script loads", candidate_script != null)
	_check("immutable circuit base script loads", base_script != null)
	if production_script == null or candidate_script == null or base_script == null:
		_finish()
		return

	_check("production wrapper extends the immutable circuit base",
		_base_path(production_script) == CircuitBasePath,
		"actual=%s" % _base_path(production_script))
	_check("research R2 wrapper extends the immutable circuit base",
		_base_path(candidate_script) == CircuitBasePath,
		"actual=%s" % _base_path(candidate_script))

	var field_result: Dictionary = FieldLoader.load_from()
	_check("accepted Club field loads", bool(field_result.get("ok", false)),
		str(field_result.get("errors", [])))
	if not field_result.get("ok", false):
		_finish()
		return
	var field: Dictionary = field_result.field

	var production = production_script.new()
	var candidate = candidate_script.new()
	var circuit = base_script.new()
	_check("production diagnostics default off", _diagnostics_default_off(production))
	_check("research R2 initializes without a held maneuver",
		_latch_is_clear(candidate.call("snapshot_state")))
	_check("production wrapper configures", _configure(production, field))
	_check("research R2 wrapper configures", _configure(candidate, field))
	_check("immutable circuit base configures", _configure(circuit, field))
	if not _configured(production) or not _configured(candidate) or not _configured(circuit):
		_finish()
		return
	var pose: Dictionary = circuit.call("initial_pose")
	_check("all three wrappers preserve the same initial pose",
		pose == production.call("initial_pose") and pose == candidate.call("initial_pose"))

	for environment: Dictionary in _environments():
		var snapshot: Dictionary = _snapshot(pose, environment)
		_check("%s no-traffic production packet equals immutable base" % environment.name,
			_no_traffic_trace_matches(production_script, base_script, field, snapshot),
			str(environment))
		_check("%s no-traffic R2 packet equals immutable base" % environment.name,
			_no_traffic_trace_matches(candidate_script, base_script, field, snapshot),
			str(environment))
		_check("%s diagnostics off preserves exact R2 packets and latch state" % environment.name,
			_diagnostic_pair_parity(production_script, candidate_script, field, pose, environment, false),
			str(environment))
		_check("%s traffic conflict latches, clears, and reacquires" % environment.name,
			_traffic_clear_reacquire(production_script, candidate_script, field, pose, environment),
			str(environment))
		_check("%s diagnostics on preserves exact R2 packets and latch state" % environment.name,
			_diagnostic_pair_parity(production_script, candidate_script, field, pose, environment, true),
			str(environment))
		_check("%s diagnostics toggle is control-state neutral" % environment.name,
			_diagnostics_toggle_parity(production_script, candidate_script, field, pose, environment),
			str(environment))
		_check("%s held-latch checkpoint continuation is exact" % environment.name,
			_checkpoint_continuation(production_script, candidate_script, field, pose, environment),
			str(environment))
		_check("%s reconfiguration clears the held maneuver" % environment.name,
			_reconfigure_clears_latch(production_script, candidate_script, field, pose, environment),
			str(environment))

	print("pilot promotion parity: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _load_script(path: String) -> Script:
	var resource: Resource = ResourceLoader.load(path)
	if not resource is Script:
		return null
	var script: Script = resource as Script
	return script if script.can_instantiate() else null


func _base_path(script: Script) -> String:
	var base: Script = script.get_base_script()
	return base.resource_path if base != null else ""


func _has_property(target: Object, property_name: String) -> bool:
	for property: Dictionary in target.get_property_list():
		if str(property.get("name", "")) == property_name:
			return true
	return false


func _diagnostics_default_off(target: Object) -> bool:
	return _has_property(target, "diagnostics_enabled") \
		and not bool(target.get("diagnostics_enabled"))


func _set_diagnostics(target: Object, enabled: bool) -> bool:
	if not _has_property(target, "diagnostics_enabled"):
		return false
	target.set("diagnostics_enabled", enabled)
	return bool(target.get("diagnostics_enabled")) == enabled


func _set_optional_diagnostics(target: Object, enabled: bool) -> bool:
	if not _has_property(target, "diagnostics_enabled"):
		return true
	target.set("diagnostics_enabled", enabled)
	return bool(target.get("diagnostics_enabled")) == enabled


func _configure(target: Object, field: Dictionary) -> bool:
	return bool(target.call("configure", 0, 1, SEED, TRIM, field))


func _configured(target: Object) -> bool:
	return bool(target.get("_configured"))


func _environments() -> Array[Dictionary]:
	return [
		{"name": "calm", "wind_ned": PackedFloat64Array([0.0, 0.0, 0.0]),
			"turbulence_rms_m_s": PackedFloat64Array([0.0, 0.0, 0.0])},
		{"name": "gentle", "wind_ned": PackedFloat64Array([1.5, 2.0, 0.0]),
			"turbulence_rms_m_s": PackedFloat64Array([0.05, 0.04, 0.02])},
	]


func _snapshot(pose: Dictionary, environment: Dictionary) -> Dictionary:
	var attitude: PackedFloat64Array = Math3D.q_from_euler(float(pose.heading_rad), 0.0, 0.0)
	var state: PackedFloat64Array = RigidBody.make_state(
		PackedFloat64Array([float(pose.north), float(pose.east), -float(pose.height_m)]),
		PackedFloat64Array([float(TRIM.V), 0.0, 0.0]), attitude,
		PackedFloat64Array([0.0, 0.0, 0.0]))
	return {
		"state": state,
		"airspeed_m_s": float(TRIM.V),
		"wind_ned": environment.wind_ned,
		"ground_clearance_m": float(pose.height_agl_m),
		"trim": TRIM,
		"turbulence_rms_m_s": environment.turbulence_rms_m_s,
	}


func _traffic_state(north: float, east: float, down: float, heading: float,
		speed_m_s: float) -> PackedFloat64Array:
	return RigidBody.make_state(PackedFloat64Array([north, east, down]),
		PackedFloat64Array([speed_m_s, 0.0, 0.0]), Math3D.q_from_euler(heading, 0.0, 0.0),
		PackedFloat64Array([0.0, 0.0, 0.0]))


func _traffic_cases(snapshot: Dictionary) -> Array[Dictionary]:
	var own_state: PackedFloat64Array = snapshot.state
	var attitude: PackedFloat64Array = Math3D.quat(own_state[RigidBody.ATT],
		own_state[RigidBody.ATT + 1], own_state[RigidBody.ATT + 2], own_state[RigidBody.ATT + 3])
	var forward: PackedFloat64Array = Math3D.q_rotate(attitude, PackedFloat64Array([1.0, 0.0, 0.0]))
	var heading: float = float(Math3D.q_to_euler(attitude)[0])
	var north: float = float(own_state[RigidBody.POS])
	var east: float = float(own_state[RigidBody.POS + 1])
	var down: float = float(own_state[RigidBody.POS + 2])
	var head_on := {"id": "promotion-player-head-on", "is_player": true, "wingspan_m": 1.7,
		"state": _traffic_state(north + 45.0 * forward[0], east + 45.0 * forward[1],
			down, wrapf(heading + PI, -PI, PI), 15.0)}
	var crossing := {"id": "promotion-player-crossing", "is_player": true, "wingspan_m": 1.7,
		"state": _traffic_state(north + 28.0 * forward[0] - 12.0 * forward[1],
			east + 28.0 * forward[1] + 12.0 * forward[0], down,
			wrapf(heading - PI / 2.0, -PI, PI), 15.0)}
	var far := {"id": "promotion-player-clear", "is_player": true, "wingspan_m": 1.7,
		"state": _traffic_state(north + 500.0, east + 500.0, down, heading, 15.0)}
	return [head_on, crossing, far]


func _trace(controller: Object, snapshot: Dictionary) -> Array[Dictionary]:
	var traffic: Array[Dictionary] = _traffic_cases(snapshot)
	var stages: Array[Dictionary] = [
		{"tick": 0, "traffic": []},
		{"tick": 4, "traffic": [traffic[0]]},
		{"tick": 8, "traffic": [traffic[1]]},
		{"tick": 484, "traffic": [traffic[2]]},
		{"tick": 724, "traffic": []},
		{"tick": 728, "traffic": [traffic[0]]},
	]
	var results: Array[Dictionary] = []
	for stage: Dictionary in stages:
		var packet: Dictionary = controller.call("command", snapshot, int(stage.tick), stage.traffic)
		results.append({"tick": stage.tick, "packet": packet.duplicate(true),
			"latch": controller.call("snapshot_state").duplicate(true)})
	return results


func _trace_contract_ok(trace: Array[Dictionary]) -> bool:
	if trace.size() != 6:
		return false
	var initial: Dictionary = trace[0].latch
	var acquired: Dictionary = trace[1].latch
	var retained: Dictionary = trace[3].latch
	var released: Dictionary = trace[4].latch
	var reacquired: Dictionary = trace[5].latch
	return not bool(initial.get("has_held_maneuver", true)) \
		and bool(acquired.get("has_held_maneuver", false)) \
		and bool(retained.get("has_held_maneuver", false)) \
		and not bool(released.get("has_held_maneuver", true)) \
		and bool(reacquired.get("has_held_maneuver", false))


func _latch_is_clear(state: Dictionary) -> bool:
	return state.size() == EMPTY_REACHABLE_STATE.size() \
		and typeof(state.get("planning_tick")) == TYPE_INT \
		and int(state.get("planning_tick", -1)) >= 0 \
		and not bool(state.get("has_held_maneuver", true)) \
		and float(state.get("held_bank_rad", NAN)) == 0.0 \
		and int(state.get("hold_until_tick", 0)) == -1 \
		and int(state.get("clear_since_tick", 0)) == -1


func _no_traffic_trace_matches(wrapper_script: Script, base_script: Script,
		field: Dictionary, snapshot: Dictionary) -> bool:
	var wrapper = wrapper_script.new()
	var base = base_script.new()
	if not _set_optional_diagnostics(wrapper, false) \
			or not _configure(wrapper, field) or not _configure(base, field):
		return false
	for tick: int in [0, 4, 8, 240, 720]:
		var wrapper_packet: Dictionary = wrapper.call("command", snapshot, tick, [])
		var base_packet: Dictionary = base.call("command", snapshot, tick, [])
		if wrapper_packet != base_packet \
				or not _latch_is_clear(wrapper.call("snapshot_state")):
			return false
	return true


func _diagnostic_pair_parity(production_script: Script, candidate_script: Script,
		field: Dictionary, pose: Dictionary, environment: Dictionary, diagnostics: bool) -> bool:
	var production = production_script.new()
	var candidate = candidate_script.new()
	if not _set_diagnostics(production, diagnostics) \
			or not _set_optional_diagnostics(candidate, diagnostics):
		return false
	if not _configure(production, field) or not _configure(candidate, field):
		return false
	var snapshot: Dictionary = _snapshot(pose, environment)
	var production_trace: Array[Dictionary] = _trace(production, snapshot)
	var candidate_trace: Array[Dictionary] = _trace(candidate, snapshot)
	if production_trace != candidate_trace \
			or not _trace_contract_ok(production_trace) \
			or not _trace_contract_ok(candidate_trace):
		return false
	return _configure(production, field) and _configure(candidate, field) \
		and production.call("snapshot_state") == EMPTY_REACHABLE_STATE \
		and candidate.call("snapshot_state") == EMPTY_REACHABLE_STATE \
		and production.call("snapshot_state") == candidate.call("snapshot_state")


func _traffic_clear_reacquire(production_script: Script, candidate_script: Script,
		field: Dictionary, pose: Dictionary, environment: Dictionary) -> bool:
	var production = production_script.new()
	var candidate = candidate_script.new()
	if not _set_diagnostics(production, false) or not _set_optional_diagnostics(candidate, false):
		return false
	if not _configure(production, field) or not _configure(candidate, field):
		return false
	var snapshot: Dictionary = _snapshot(pose, environment)
	var production_trace: Array[Dictionary] = _trace(production, snapshot)
	var candidate_trace: Array[Dictionary] = _trace(candidate, snapshot)
	return _trace_contract_ok(production_trace) and _trace_contract_ok(candidate_trace) \
		and production_trace == candidate_trace


func _diagnostics_toggle_parity(production_script: Script, candidate_script: Script,
		field: Dictionary, pose: Dictionary, environment: Dictionary) -> bool:
	var production_off = production_script.new()
	var production_on = production_script.new()
	var candidate_off = candidate_script.new()
	var candidate_on = candidate_script.new()
	for pair: Array in [[production_off, false], [production_on, true]]:
		if not _set_diagnostics(pair[0], bool(pair[1])) or not _configure(pair[0], field):
			return false
	for pair: Array in [[candidate_off, false], [candidate_on, true]]:
		if not _set_optional_diagnostics(pair[0], bool(pair[1])) \
				or not _configure(pair[0], field):
			return false
	var snapshot: Dictionary = _snapshot(pose, environment)
	var traces := [
		_trace(production_off, snapshot), _trace(production_on, snapshot),
		_trace(candidate_off, snapshot), _trace(candidate_on, snapshot),
	]
	return _trace_contract_ok(traces[0]) and _trace_contract_ok(traces[1]) \
		and _trace_contract_ok(traces[2]) and _trace_contract_ok(traces[3]) \
		and traces[0] == traces[1] and traces[0] == traces[2] and traces[0] == traces[3]


func _checkpoint_continuation(production_script: Script, candidate_script: Script,
		field: Dictionary, pose: Dictionary, environment: Dictionary) -> bool:
	var production = production_script.new()
	var candidate = candidate_script.new()
	if not _set_diagnostics(production, false) or not _set_optional_diagnostics(candidate, false):
		return false
	if not _configure(production, field) or not _configure(candidate, field):
		return false
	var snapshot: Dictionary = _snapshot(pose, environment)
	var head_on: Dictionary = _traffic_cases(snapshot)[0]
	var production_packet: Dictionary = production.call("command", snapshot, 4, [head_on])
	var candidate_packet: Dictionary = candidate.call("command", snapshot, 4, [head_on])
	var production_state: Dictionary = production.call("snapshot_state")
	var candidate_state: Dictionary = candidate.call("snapshot_state")
	if production_packet != candidate_packet or production_state != candidate_state:
		return false
	var production_restored = production_script.new()
	var candidate_restored = candidate_script.new()
	if not _set_diagnostics(production_restored, false) \
			or not _set_optional_diagnostics(candidate_restored, false):
		return false
	if not _configure(production_restored, field) or not _configure(candidate_restored, field):
		return false
	var production_restore: Dictionary = production_restored.call("restore_state", production_state)
	var candidate_restore: Dictionary = candidate_restored.call("restore_state", candidate_state)
	if not bool(production_restore.get("ok", false)) or not bool(candidate_restore.get("ok", false)):
		return false
	if production_restored.call("snapshot_state") != candidate_restored.call("snapshot_state"):
		return false
	var continuation_traffic: Dictionary = _traffic_cases(snapshot)[1]
	var production_next: Dictionary = production.call("command", snapshot, 8, [continuation_traffic])
	var candidate_next: Dictionary = candidate.call("command", snapshot, 8, [continuation_traffic])
	var production_restored_next: Dictionary = production_restored.call("command", snapshot, 8, [continuation_traffic])
	var candidate_restored_next: Dictionary = candidate_restored.call("command", snapshot, 8, [continuation_traffic])
	return production_next == candidate_next \
		and production_restored_next == candidate_restored_next \
		and production_next == production_restored_next \
		and candidate_next == candidate_restored_next \
		and production.call("snapshot_state") == candidate.call("snapshot_state") \
		and production.call("snapshot_state") == production_restored.call("snapshot_state") \
		and candidate.call("snapshot_state") == candidate_restored.call("snapshot_state")


func _reconfigure_clears_latch(production_script: Script, candidate_script: Script,
		field: Dictionary, pose: Dictionary, environment: Dictionary) -> bool:
	var production = production_script.new()
	var candidate = candidate_script.new()
	if not _set_diagnostics(production, false) or not _set_optional_diagnostics(candidate, false):
		return false
	if not _configure(production, field) or not _configure(candidate, field):
		return false
	var snapshot: Dictionary = _snapshot(pose, environment)
	var head_on: Dictionary = _traffic_cases(snapshot)[0]
	production.call("command", snapshot, 4, [head_on])
	candidate.call("command", snapshot, 4, [head_on])
	if not bool(production.call("snapshot_state").get("has_held_maneuver", false)) \
			or not bool(candidate.call("snapshot_state").get("has_held_maneuver", false)):
		return false
	return _configure(production, field) and _configure(candidate, field) \
		and production.call("snapshot_state") == EMPTY_REACHABLE_STATE \
		and candidate.call("snapshot_state") == EMPTY_REACHABLE_STATE \
		and production.call("snapshot_state") == candidate.call("snapshot_state")


func _check(label: String, passed: bool, detail: String = "") -> void:
	_checks += 1
	print(("ok   " if passed else "FAIL ") + label + ("  " + detail if not detail.is_empty() else ""))
	if not passed:
		_failures += 1


func _finish() -> void:
	print("pilot promotion parity: %d checks, %d failed" % [_checks, _failures])
	quit(1)
