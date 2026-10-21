extends SceneTree

const BasePilot := preload("res://ai/companions/circuit_controller.gd")
const CandidatePilot := preload("res://../research/ai-companions/avoidance/reachable_pilot.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const Math3D := preload("res://physics/math3d.gd")
const RigidBody := preload("res://physics/rigid_body.gd")

const SEED := 20261020
const TRIM := {"V": 15.0, "throttle": 0.45}
const NO_WIND := [0.0, 0.0, 0.0]
const NO_TURBULENCE := [0.0, 0.0, 0.0]

var _checks := 0
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var loaded: Dictionary = FieldLoader.load_from()
	_check("accepted Club field loads", bool(loaded.get("ok", false)), str(loaded.get("errors", [])))
	if not loaded.get("ok", false):
		quit(1)
		return
	var field: Dictionary = loaded.field
	var base = BasePilot.new()
	var candidate = CandidatePilot.new()
	_check("base pilot configures", base.configure(0, 1, SEED, TRIM, field), base.configure_error)
	_check("candidate configures", candidate.configure(0, 1, SEED, TRIM, field), candidate.configure_error)
	if not base.initial_pose().get("ok", false) or not candidate.initial_pose().get("ok", false):
		quit(1)
		return

	var pose: Dictionary = base.initial_pose()
	var snapshot: Dictionary = _snapshot(pose)
	var base_packet: Dictionary = base.command(snapshot, 0)
	var candidate_packet: Dictionary = candidate.command(snapshot, 0)
	_check("no-traffic command exactly preserves production controls",
		_packet_axes(base_packet) == _packet_axes(candidate_packet),
		"base=%s candidate=%s" % [_packet_axes(base_packet), _packet_axes(candidate_packet)])
	_check_state_contract(base, candidate, snapshot)

	var own_state: PackedFloat64Array = snapshot.state
	var attitude: PackedFloat64Array = Math3D.quat(own_state[RigidBody.ATT], own_state[RigidBody.ATT + 1],
		own_state[RigidBody.ATT + 2], own_state[RigidBody.ATT + 3])
	var forward: PackedFloat64Array = Math3D.q_rotate(attitude, PackedFloat64Array([1.0, 0.0, 0.0]))
	var heading: float = float(pose.heading_rad)
	var head_on_state: PackedFloat64Array = _traffic_state(
		float(own_state[RigidBody.POS]) + 45.0 * forward[0],
		float(own_state[RigidBody.POS + 1]) + 45.0 * forward[1],
		float(own_state[RigidBody.POS + 2]), wrapf(heading + PI, -PI, PI), 15.0)
	var traffic := [{"id": "player", "is_player": true, "wingspan_m": 1.7, "state": head_on_state}]
	var avoidance_packet: Dictionary = candidate.command(snapshot, 0, traffic)
	var expected_roll: float = clampf(1.8 * (float(candidate._selected_bank_target_rad) - float(Math3D.q_to_euler(attitude)[2]))
		- 0.35 * own_state[RigidBody.RATE], -1.0, 1.0)
	_check("traffic response sends selected-bank feedback directly",
		bool(candidate._override_roll_demand) and _near(float(avoidance_packet.get("roll", NAN)), expected_roll),
		"selected bank %.2f deg; packet roll %.6f; expected %.6f" % [rad_to_deg(float(candidate._selected_bank_target_rad)),
		float(avoidance_packet.get("roll", NAN)), expected_roll])
	_check("traffic command remains finite and bounded", _packet_bounded(avoidance_packet), str(avoidance_packet))
	_check("reachable bank stays within the qualified 25-degree limit",
		absf(float(candidate._selected_bank_target_rad)) <= deg_to_rad(25.0) + 1e-12)
	_check("threat starts a held maneuver", bool(candidate._has_held_maneuver))
	var logged_decision: Dictionary = candidate._last_decision
	var world_velocity := PackedFloat64Array([15.0 * forward[0], 15.0 * forward[1], 0.0])
	var nominal_bank: float = clampf(float(candidate._direction) * atan2(
		float(candidate._target_speed_mps) * float(candidate._target_speed_mps),
		float(candidate.G) * float(candidate._radius_m)), -deg_to_rad(25.0), deg_to_rad(25.0))
	var selected_prediction: Dictionary = candidate._score_bank(own_state, world_velocity, 15.0,
		float(Math3D.q_to_euler(attitude)[2]), nominal_bank,
		float(candidate._held_bank_rad), float(snapshot.ground_clearance_m),
		candidate._prepare_threats(traffic, world_velocity))
	_check("logged selected clearance is scored for the held bank actually commanded",
		bool(logged_decision.get("selected_bank_is_held", false))
			and _near(float(logged_decision.get("selected_bank_deg", NAN)), rad_to_deg(float(candidate._held_bank_rad)))
			and _near(float(logged_decision.get("selected_score_m", NAN)), float(selected_prediction.score))
			and _near(float(logged_decision.get("selected_player_min_m", NAN)),
				float(selected_prediction.minimum_player_distance_m)),
		str(logged_decision))

	var held_until: int = int(candidate._hold_until_tick)
	var quiet_before_release: Dictionary = candidate.command(snapshot, 4, [])
	var base_quiet_before_release: Dictionary = base.command(snapshot, 4, [])
	_check("empty traffic preserves production output during the hold",
		_packet_axes(quiet_before_release) == _packet_axes(base_quiet_before_release)
			and bool(candidate._has_held_maneuver))
	var release_tick: int = held_until + 400 # more than the 1 s clear window after the 2 s hold
	var quiet_after_release: Dictionary = candidate.command(snapshot, release_tick, [])
	var base_quiet_after_release: Dictionary = base.command(snapshot, release_tick, [])
	_check("sustained empty traffic releases the maneuver after hold and clear windows",
		_packet_axes(quiet_after_release) == _packet_axes(base_quiet_after_release)
			and not bool(candidate._has_held_maneuver))
	var renewed_threat: Dictionary = candidate.command(snapshot, release_tick + 4, traffic)
	_check("a later threat starts a fresh maneuver hold",
		bool(renewed_threat.get("ok", false)) and bool(candidate._has_held_maneuver)
			and int(candidate._hold_until_tick) > release_tick)
	var checkpoint: Dictionary = candidate.snapshot_state()
	var restored = CandidatePilot.new()
	_check("candidate reconfigures for latch checkpoint continuation",
		restored.configure(0, 1, SEED, TRIM, field), restored.configure_error)
	var restore_result: Dictionary = restored.restore_state(checkpoint)
	_check("held maneuver snapshot restores exactly", bool(restore_result.get("ok", false))
		and restored.snapshot_state() == checkpoint, str(restore_result))
	var checkpoint_tick: int = int(checkpoint.planning_tick) + 60
	var original_continuation: Dictionary = candidate.command(snapshot, checkpoint_tick, traffic)
	var restored_continuation: Dictionary = restored.command(snapshot, checkpoint_tick, traffic)
	_check("restored held maneuver produces exact next command and state",
		_packet_axes(original_continuation) == _packet_axes(restored_continuation)
			and candidate.snapshot_state() == restored.snapshot_state(),
		"original=%s restored=%s" % [_packet_axes(original_continuation), _packet_axes(restored_continuation)])
	var safe_traffic := [{"id": "far-player", "is_player": true, "wingspan_m": 1.7,
		"state": _traffic_state(float(own_state[RigidBody.POS]) + 500.0,
			float(own_state[RigidBody.POS + 1]) + 500.0,
			float(own_state[RigidBody.POS + 2]), heading, 15.0)}]
	var safe_tick: int = maxi(int(candidate._hold_until_tick) + 1, checkpoint_tick + 1)
	candidate.command(snapshot, safe_tick, safe_traffic)
	var clearing_checkpoint: Dictionary = candidate.snapshot_state()
	var clearing_restore: Dictionary = restored.restore_state(clearing_checkpoint)
	_check("checkpoint retains the clear-window start tick", bool(clearing_restore.get("ok", false))
		and int(clearing_checkpoint.clear_since_tick) == safe_tick
		and restored.snapshot_state() == clearing_checkpoint, str(clearing_checkpoint))
	var clear_release_tick: int = safe_tick + 240
	var continued_clear: Dictionary = candidate.command(snapshot, clear_release_tick, [])
	var restored_clear: Dictionary = restored.command(snapshot, clear_release_tick, [])
	var base_after_clear: Dictionary = base.command(snapshot, clear_release_tick, [])
	_check("restored clear-window timer releases at the same tick and preserves baseline output",
		_packet_axes(continued_clear) == _packet_axes(restored_clear)
			and _packet_axes(continued_clear) == _packet_axes(base_after_clear)
			and candidate.snapshot_state() == restored.snapshot_state()
			and not bool(candidate._has_held_maneuver),
		"candidate=%s restored=%s baseline=%s" % [_packet_axes(continued_clear),
			_packet_axes(restored_clear), _packet_axes(base_after_clear)])
	var before_rejected_restore: Dictionary = restored.snapshot_state()
	var malformed: Dictionary = before_rejected_restore.duplicate(true)
	malformed.held_bank_rad = deg_to_rad(30.0)
	var rejected: Dictionary = restored.restore_state(malformed)
	_check("out-of-range checkpoint is rejected atomically",
		not bool(rejected.get("ok", false)) and restored.snapshot_state() == before_rejected_restore,
		str(rejected))
	malformed = before_rejected_restore.duplicate(true)
	malformed.unexpected = true
	_check("checkpoint schema rejects unknown fields",
		not bool(restored.restore_state(malformed).get("ok", false))
			and restored.snapshot_state() == before_rejected_restore)

	print("reachable pilot: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _check(label: String, passed: bool, detail: String = "") -> void:
	_checks += 1
	print(("ok   " if passed else "FAIL ") + label + ("  " + detail if not detail.is_empty() else ""))
	if not passed:
		_failures += 1


func _snapshot(pose: Dictionary) -> Dictionary:
	var attitude: PackedFloat64Array = Math3D.q_from_euler(float(pose.heading_rad), 0.0, 0.0)
	var state: PackedFloat64Array = RigidBody.make_state(
		PackedFloat64Array([float(pose.north), float(pose.east), -float(pose.height_m)]),
		PackedFloat64Array([float(TRIM.V), 0.0, 0.0]), attitude, PackedFloat64Array([0.0, 0.0, 0.0]))
	return {"state": state, "airspeed_m_s": float(TRIM.V), "wind_ned": NO_WIND,
		"ground_clearance_m": float(pose.height_agl_m), "trim": TRIM,
		"turbulence_rms_m_s": NO_TURBULENCE}


func _check_state_contract(base, candidate, snapshot: Dictionary) -> void:
	var own_state: PackedFloat64Array = snapshot.state
	var shortened: PackedFloat64Array = own_state.duplicate()
	shortened.resize(RigidBody.SIZE - 1)
	var short_snapshot: Dictionary = snapshot.duplicate(true)
	short_snapshot.state = shortened
	var short_packet: Dictionary = candidate.command(short_snapshot, 1)
	_check("pilot snapshot rejects a 12-value rigid-body state",
		not bool(short_packet.get("ok", false))
			and str(short_packet.get("reason", "")).contains("13-value"), str(short_packet))
	var extended: PackedFloat64Array = own_state.duplicate()
	extended.append(123.0)
	var extended_snapshot: Dictionary = snapshot.duplicate(true)
	extended_snapshot.state = extended
	var extended_packet: Dictionary = candidate.command(extended_snapshot, 1)
	_check("pilot snapshot rejects a 14-value rigid-body state",
		not bool(extended_packet.get("ok", false))
			and str(extended_packet.get("reason", "")).contains("13-value"), str(extended_packet))
	var nonfinite: PackedFloat64Array = own_state.duplicate()
	nonfinite[RigidBody.POS] = NAN
	var nonfinite_snapshot: Dictionary = snapshot.duplicate(true)
	nonfinite_snapshot.state = nonfinite
	var nonfinite_packet: Dictionary = candidate.command(nonfinite_snapshot, 1)
	_check("pilot snapshot rejects a nonfinite rigid-body state",
		not bool(nonfinite_packet.get("ok", false))
			and str(nonfinite_packet.get("reason", "")).contains("nonfinite"), str(nonfinite_packet))
	var velocity := PackedFloat64Array([15.0, 0.0, 0.0])
	_check("traffic parsing rejects an extended state instead of misreading its layout",
		candidate._prepare_threats([{"id": "extended", "state": extended}], velocity).is_empty())


func _traffic_state(north: float, east: float, down: float, heading: float,
		speed_m_s: float) -> PackedFloat64Array:
	return RigidBody.make_state(PackedFloat64Array([north, east, down]),
		PackedFloat64Array([speed_m_s, 0.0, 0.0]), Math3D.q_from_euler(heading, 0.0, 0.0),
		PackedFloat64Array([0.0, 0.0, 0.0]))


func _packet_axes(packet: Dictionary) -> PackedFloat64Array:
	return PackedFloat64Array([float(packet.get("roll", NAN)), float(packet.get("pitch", NAN)),
		float(packet.get("yaw", NAN)), float(packet.get("throttle", NAN))])


func _packet_bounded(packet: Dictionary) -> bool:
	for key: String in ["roll", "pitch", "yaw", "throttle"]:
		if typeof(packet.get(key)) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(packet[key])):
			return false
	return float(packet.roll) >= -1.0 and float(packet.roll) <= 1.0 \
		and float(packet.pitch) >= -1.0 and float(packet.pitch) <= 1.0 \
		and float(packet.yaw) >= -1.0 and float(packet.yaw) <= 1.0 \
		and float(packet.throttle) >= 0.0 and float(packet.throttle) <= 1.0


func _near(first: float, second: float, tolerance: float = 1e-12) -> bool:
	return is_finite(first) and is_finite(second) and absf(first - second) <= tolerance
