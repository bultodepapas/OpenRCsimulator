extends "res://ai/companions/circuit_controller.gd"

## AFC-04/AFC-12 experimental wind-aware reachable-turn response.
## Circuit guidance and the no-traffic controls remain in the source-bound base.
## Static containment and prediction uncertainty qualification remain open.
const AvoidanceMath := preload("res://physics/math3d.gd")
const AvoidanceRigidBody := preload("res://physics/rigid_body.gd")

const PREDICTION_HORIZON_S := 8.0
const PREDICTION_STEP_S := 0.25
const REACTION_MARGIN_S := 0.9
const BANK_RESPONSE_S := 0.75
const HOLD_TIME_TICKS := 480 # two seconds at the existing 240 Hz simulation clock
const RELEASE_CLEAR_TIME_TICKS := 240
const RELEASE_EXTRA_CLEARANCE_M := 5.0
const POSITION_UNCERTAINTY_M := 3.0
const TERRAIN_CLEARANCE_M := 20.0
const TERRAIN_UNCERTAINTY_M := 5.0
const AVOID_BANK_LIMIT_RAD := 0.4363323129985824
const BANK_CHOICES_DEG := [-25.0, -20.0, -15.0, -10.0, -5.0, 0.0, 5.0, 10.0, 15.0, 20.0, 25.0]
const AVOIDANCE_STATE_VERSION := "reachable-pilot-state-v1"
const MAX_PLAN_DIAGNOSTICS := 128

## Diagnostics are read-only, bounded and off in normal flight.
var diagnostics_enabled := false
var _planning_tick := 0
var _planning_clearance_m := NAN
var _has_held_maneuver := false
var _held_bank_rad := 0.0
var _hold_until_tick := -1
var _clear_since_tick := -1
var _last_decision: Dictionary = {}
var _override_roll_demand := false
var _selected_bank_target_rad := 0.0
var _planning_wind := PackedFloat64Array([0.0, 0.0, 0.0])
var _plan_diagnostic_count := 0


func configure(slot: int, count: int, seed_value: int, trim: Dictionary, field: Dictionary) -> bool:
	var configured: bool = super.configure(slot, count, seed_value, trim, field)
	if configured:
		_reset_reachable_state()
	return configured


func _reset_reachable_state() -> void:
	_planning_tick = 0
	_planning_clearance_m = NAN
	_has_held_maneuver = false
	_held_bank_rad = 0.0
	_hold_until_tick = -1
	_clear_since_tick = -1
	_last_decision.clear()
	_override_roll_demand = false
	_selected_bank_target_rad = 0.0
	_planning_wind = PackedFloat64Array([0.0, 0.0, 0.0])
	_plan_diagnostic_count = 0


func command(snapshot: Dictionary, tick: int, traffic: Array = []) -> Dictionary:
	_planning_tick = tick
	_override_roll_demand = false
	var wind_result: Dictionary = _vector3(snapshot.get("wind_ned", PackedFloat64Array([0.0, 0.0, 0.0])))
	_planning_wind = wind_result.value if wind_result.get("ok", false) else PackedFloat64Array([0.0, 0.0, 0.0])
	var clearance_value: Variant = snapshot.get("ground_clearance_m", NAN)
	_planning_clearance_m = float(clearance_value) if typeof(clearance_value) in [TYPE_FLOAT, TYPE_INT] else NAN
	var packet: Dictionary = super.command(snapshot, tick, traffic)
	if _override_roll_demand and bool(packet.get("ok", false)):
		var state_value: Variant = snapshot.get("state", PackedFloat64Array())
		if state_value is PackedFloat64Array and state_value.size() == AvoidanceRigidBody.SIZE:
			var state: PackedFloat64Array = state_value
			var attitude := AvoidanceMath.quat(state[AvoidanceRigidBody.ATT],
				state[AvoidanceRigidBody.ATT + 1], state[AvoidanceRigidBody.ATT + 2],
				state[AvoidanceRigidBody.ATT + 3])
			var euler: PackedFloat64Array = AvoidanceMath.q_to_euler(attitude)
			if euler.size() == 3:
				packet.roll = clampf(1.8 * (_selected_bank_target_rad - euler[2])
					- 0.35 * state[AvoidanceRigidBody.RATE], -1.0, 1.0)
	# The retained base applies its local-terrain floor only to a requested
	# avoidance descent. Horizontal-only avoidance still needs that floor when
	# actual terrain is above the circuit's field datum. Preserve its pitch law.
	if bool(packet.get("ok", false)) and bool(packet.get("avoidance_active", false)) \
			and is_finite(_planning_clearance_m):
		var state: PackedFloat64Array = snapshot.state
		var height: float = -state[AvoidanceRigidBody.POS + 2]
		var floor_height: float = height - _planning_clearance_m + BASE_HEIGHT_AGL_M
		if float(packet.target_height_m) < floor_height:
			var velocity: PackedFloat64Array = AvoidanceMath.q_rotate(state.slice(AvoidanceRigidBody.ATT, AvoidanceRigidBody.ATT + 4),
				state.slice(AvoidanceRigidBody.VEL, AvoidanceRigidBody.VEL + 3))
			var target_down: float = -clampf((floor_height - height) * 0.12, -1.5, 1.5)
			packet.target_height_m = floor_height
			packet.pitch = clampf(0.8 * (velocity[2] - target_down)
				- 0.5 * state[AvoidanceRigidBody.RATE + 1], -1.0, 1.0)
	if diagnostics_enabled and tick == 0 and not _last_decision.is_empty() and _plan_diagnostic_count < MAX_PLAN_DIAGNOSTICS:
		_plan_diagnostic_count += 1
		print("AFC_REACHABLE_INITIAL " + JSON.stringify(_last_decision))
	return packet


## Serializable controller-only state for deterministic checkpoint continuation.
## FlightSession state remains authoritative for physical position and velocity.
func snapshot_state() -> Dictionary:
	return {
		"version": AVOIDANCE_STATE_VERSION,
		"planning_tick": _planning_tick,
		"has_held_maneuver": _has_held_maneuver,
		"held_bank_rad": _held_bank_rad if _has_held_maneuver else 0.0,
		"hold_until_tick": _hold_until_tick if _has_held_maneuver else -1,
		"clear_since_tick": _clear_since_tick if _has_held_maneuver else -1,
	}


## Restore is atomic and strict so an untrusted/old checkpoint cannot poison control.
func restore_state(candidate: Dictionary) -> Dictionary:
	if candidate.size() != 6 or String(candidate.get("version", "")) != AVOIDANCE_STATE_VERSION:
		return {"ok": false, "reason": "state_version_or_shape_mismatch"}
	for key: String in ["planning_tick", "has_held_maneuver", "held_bank_rad", "hold_until_tick", "clear_since_tick"]:
		if not candidate.has(key):
			return {"ok": false, "reason": "state_missing_%s" % key}
	var planning_tick_value: Variant = candidate.planning_tick
	var has_held_value: Variant = candidate.has_held_maneuver
	var held_bank_value: Variant = candidate.held_bank_rad
	var hold_until_value: Variant = candidate.hold_until_tick
	var clear_since_value: Variant = candidate.clear_since_tick
	if typeof(planning_tick_value) != TYPE_INT or int(planning_tick_value) < 0 \
			or typeof(has_held_value) != TYPE_BOOL \
			or typeof(held_bank_value) not in [TYPE_FLOAT, TYPE_INT] \
			or typeof(hold_until_value) != TYPE_INT \
			or typeof(clear_since_value) != TYPE_INT:
		return {"ok": false, "reason": "invalid_state_types"}
	var planning_tick: int = int(planning_tick_value)
	var has_held: bool = bool(has_held_value)
	var held_bank: float = float(held_bank_value)
	var hold_until: int = int(hold_until_value)
	var clear_since: int = int(clear_since_value)
	if not is_finite(held_bank) or absf(held_bank) > AVOID_BANK_LIMIT_RAD \
			or clear_since < -1 or clear_since > planning_tick:
		return {"ok": false, "reason": "state_value_out_of_range"}
	if has_held:
		if hold_until < 0:
			return {"ok": false, "reason": "held_maneuver_missing_deadline"}
	else:
		if held_bank != 0.0 or hold_until != -1 or clear_since != -1:
			return {"ok": false, "reason": "inactive_maneuver_state_not_canonical"}
	_planning_tick = planning_tick
	_has_held_maneuver = has_held
	_held_bank_rad = held_bank if has_held else 0.0
	_hold_until_tick = hold_until if has_held else -1
	_clear_since_tick = clear_since if has_held else -1
	_override_roll_demand = false
	_selected_bank_target_rad = 0.0
	_last_decision.clear()
	return {"ok": true}


func _avoidance_velocity(
		state: PackedFloat64Array,
		attitude: PackedFloat64Array,
		own_velocity: PackedFloat64Array,
		base_air_north: float,
		base_air_east: float,
		traffic: Array) -> Dictionary:
	# This branch is deliberately the production implementation, preserving the
	# original controller path exactly when no moving traffic is present.
	if traffic.is_empty():
		_release_held_maneuver_if_clear()
		return super._avoidance_velocity(state, attitude, own_velocity, base_air_north, base_air_east, traffic)

	var own_air_north: float = own_velocity[0] - _planning_wind[0]
	var own_air_east: float = own_velocity[1] - _planning_wind[1]
	var own_speed: float = AvoidanceMath.sqrt_(own_air_north * own_air_north + own_air_east * own_air_east)
	if not is_finite(own_speed) or own_speed < 3.0:
		return super._avoidance_velocity(state, attitude, own_velocity, base_air_north, base_air_east, traffic)
	var own_euler: PackedFloat64Array = AvoidanceMath.q_to_euler(attitude)
	if own_euler.size() != 3:
		return super._avoidance_velocity(state, attitude, own_velocity, base_air_north, base_air_east, traffic)
	var prior_has_plan: bool = _has_held_maneuver
	var prior_plan_bank: float = _held_bank_rad
	var current_bank: float = clampf(own_euler[2], -AVOID_BANK_LIMIT_RAD, AVOID_BANK_LIMIT_RAD)
	var nominal_bank: float = clampf(_direction * atan2(_target_speed_mps * _target_speed_mps, G * _radius_m), -AVOID_BANK_LIMIT_RAD, AVOID_BANK_LIMIT_RAD)
	var threats: Array[Dictionary] = _prepare_threats(traffic, own_velocity)
	if threats.is_empty():
		_release_held_maneuver_if_clear()
		return super._avoidance_velocity(state, attitude, own_velocity, base_air_north, base_air_east, traffic)

	var clearance: float = _planning_clearance_m
	if not is_finite(clearance):
		clearance = -state[AvoidanceRigidBody.POS + 2] - _field_ground_up_m
	var baseline: Dictionary = _score_bank(state, own_velocity, own_speed, current_bank,
		nominal_bank, nominal_bank, clearance, threats)
	# Clear traffic with no held turn returns the unchanged nominal response.
	# Candidate scores are pure; the original later branch returned this packet.
	if not _has_held_maneuver and float(baseline.score) >= 0.0:
		return _unmodified_traffic_response(base_air_north, base_air_east)
	var best_bank: float = nominal_bank
	var best_score: float = float(baseline.score)
	for bank_degrees: float in BANK_CHOICES_DEG:
		var candidate_bank: float = deg_to_rad(bank_degrees)
		var result: Dictionary = _score_bank(state, own_velocity, own_speed, current_bank,
			nominal_bank, candidate_bank, clearance, threats)
		var tie_bias: float = 0.15 if candidate_bank > 0.0 else 0.0
		var candidate_score: float = float(result.score) - 0.75 * absf(candidate_bank - nominal_bank) + tie_bias
		if candidate_score > best_score:
			best_score = candidate_score
			best_bank = candidate_bank
	# Include the continuous nominal bank in the candidate set and favor it when
	# a reachable choice cannot improve the worst predicted clearance.
	var nominal_score: float = float(baseline.score)
	if nominal_score >= best_score:
		best_bank = nominal_bank
		best_score = nominal_score

	if _has_held_maneuver:
		var held_result: Dictionary = _score_bank(state, own_velocity, own_speed, current_bank,
			nominal_bank, _held_bank_rad, clearance, threats)
		var baseline_clear: bool = float(baseline.score) >= RELEASE_EXTRA_CLEARANCE_M
		if baseline_clear:
			if _clear_since_tick < 0:
				_clear_since_tick = _planning_tick
		else:
			_clear_since_tick = -1
		var held_is_unsafe: bool = float(held_result.score) < -2.0
		if held_is_unsafe and best_score > float(held_result.score) + 2.0:
			_set_held_maneuver(best_bank, _planning_tick + HOLD_TIME_TICKS, "retarget")
			_clear_since_tick = -1
		elif _planning_tick >= _hold_until_tick and _clear_since_tick >= 0 \
				and _planning_tick - _clear_since_tick >= RELEASE_CLEAR_TIME_TICKS:
			_clear_held_maneuver("threat_clear")
			return _unmodified_traffic_response(base_air_north, base_air_east)
		else:
			best_bank = _held_bank_rad
	else:
		if float(baseline.score) >= 0.0:
			return _unmodified_traffic_response(base_air_north, base_air_east)
		_set_held_maneuver(best_bank, _planning_tick + HOLD_TIME_TICKS, "conflict")
		_clear_since_tick = -1
	if not diagnostics_enabled:
		return _bank_response(base_air_north, base_air_east, nominal_bank, best_bank)
	var selected_prediction: Dictionary = _score_bank(state, own_velocity, own_speed, current_bank,
		nominal_bank, best_bank, clearance, threats, true)
	var predicted_traces: Array[Dictionary] = []
	var distance_traces: Array = selected_prediction.get("distance_traces_m", [])
	for threat_index in mini(threats.size(), distance_traces.size()):
		predicted_traces.append({
			"id": str(threats[threat_index].get("id", "")),
			"is_player": bool(threats[threat_index].get("is_player", false)),
			"distance_m": Array(distance_traces[threat_index]),
		})
	_last_decision = {
		"tick": _planning_tick,
		"selected_bank_deg": rad_to_deg(best_bank),
		"nominal_bank_deg": rad_to_deg(nominal_bank),
		"has_held_maneuver": _has_held_maneuver,
		"held_bank_deg": rad_to_deg(_held_bank_rad) if _has_held_maneuver else 0.0,
		"hold_until_tick": _hold_until_tick if _has_held_maneuver else -1,
		"clear_since_tick": _clear_since_tick if _has_held_maneuver else -1,
		"selected_bank_is_held": _has_held_maneuver and is_equal_approx(best_bank, _held_bank_rad),
		"baseline_score_m": float(baseline.score),
		"best_candidate_adjusted_score_m": best_score,
		"selected_score_m": float(selected_prediction.score),
		"selected_player_min_m": _finite_diagnostic(selected_prediction.minimum_player_distance_m),
		"selected_peer_min_m": _finite_diagnostic(selected_prediction.minimum_peer_distance_m),
		"selected_terrain_margin_m": float(selected_prediction.terrain_margin_m),
		"threat_count": threats.size(),
		"prediction_step_s": PREDICTION_STEP_S,
		"prediction_horizon_s": PREDICTION_HORIZON_S,
		"prediction_wind_ned_m_s": Array(_planning_wind),
		"prediction_air_speed_m_s": own_speed,
		"predicted_threat_distance_traces": predicted_traces,
	}
	var plan_changed: bool = _has_held_maneuver and (not prior_has_plan
		or not is_equal_approx(prior_plan_bank, _held_bank_rad))
	if plan_changed and _planning_tick > 0 and _plan_diagnostic_count < MAX_PLAN_DIAGNOSTICS:
		var event: Dictionary = _last_decision.duplicate(true)
		event["ground_velocity_ned_m_s"] = Array(own_velocity)
		print("AFC_REACHABLE_PLAN " + JSON.stringify(event))
		_plan_diagnostic_count += 1

	return _bank_response(base_air_north, base_air_east, nominal_bank, best_bank)


func _prepare_threats(traffic: Array, own_velocity: PackedFloat64Array) -> Array[Dictionary]:
	var threats: Array[Dictionary] = []
	var sample_count: int = int(round(PREDICTION_HORIZON_S / PREDICTION_STEP_S))
	for item_value: Variant in traffic:
		if typeof(item_value) != TYPE_DICTIONARY:
			continue
		var item: Dictionary = item_value
		var item_id: String = str(item.get("id", ""))
		if item_id == "companion-%d" % _slot \
				and (not item.has("slot") or int(item.get("slot", -1)) == _slot):
			continue
		var other: Dictionary = _traffic_kinematics(item)
		if not other.get("ok", false):
			continue
		var north: float = float(other.north)
		var east: float = float(other.east)
		var down: float = float(other.down)
		var velocity_north: float = float(other.velocity_north)
		var velocity_east: float = float(other.velocity_east)
		var velocity_down: float = float(other.velocity_down)
		var threat_wind: PackedFloat64Array = _planning_wind
		var threat_wind_result: Dictionary = _vector3(item.get("wind_ned", _planning_wind))
		if threat_wind_result.get("ok", false):
			threat_wind = threat_wind_result.value
		var air_velocity_north: float = velocity_north - threat_wind[0]
		var air_velocity_east: float = velocity_east - threat_wind[1]
		var heading: float = AvoidanceMath.atan2_(air_velocity_east, air_velocity_north)
		var bank: float = 0.0
		var other_state_value: Variant = item.get("state", PackedFloat64Array())
		if other_state_value is PackedFloat64Array and other_state_value.size() == AvoidanceRigidBody.SIZE:
			var other_state: PackedFloat64Array = other_state_value
			var other_attitude := AvoidanceMath.quat(other_state[AvoidanceRigidBody.ATT],
				other_state[AvoidanceRigidBody.ATT + 1], other_state[AvoidanceRigidBody.ATT + 2],
				other_state[AvoidanceRigidBody.ATT + 3])
			var other_euler: PackedFloat64Array = AvoidanceMath.q_to_euler(other_attitude)
			if other_euler.size() == 3:
				bank = clampf(other_euler[2], -AVOID_BANK_LIMIT_RAD, AVOID_BANK_LIMIT_RAD)
		elif item.has("bank_rad") and typeof(item.bank_rad) in [TYPE_FLOAT, TYPE_INT] and is_finite(float(item.bank_rad)):
			bank = clampf(float(item.bank_rad), -AVOID_BANK_LIMIT_RAD, AVOID_BANK_LIMIT_RAD)
		var air_horizontal_speed: float = AvoidanceMath.sqrt_(air_velocity_north * air_velocity_north
			+ air_velocity_east * air_velocity_east)
		var turn_rate: float = G * tan(bank) / maxf(air_horizontal_speed, 3.0)
		if item.has("intent_turn_rate_rad_s") and typeof(item.intent_turn_rate_rad_s) in [TYPE_FLOAT, TYPE_INT] \
				and is_finite(float(item.intent_turn_rate_rad_s)):
			turn_rate = float(item.intent_turn_rate_rad_s)
		turn_rate = clampf(turn_rate, -0.5, 0.5)
		var closure_north: float = velocity_north - own_velocity[0]
		var closure_east: float = velocity_east - own_velocity[1]
		var closure_down: float = velocity_down - own_velocity[2]
		var closure_speed: float = AvoidanceMath.sqrt_(closure_north * closure_north
			+ closure_east * closure_east + closure_down * closure_down)
		var is_player: bool = bool(item.get("is_player", item.get("player", true)))
		var wingspan: float = float(item.get("wingspan_m", 1.7))
		var base_separation: float = maxf(30.0 if is_player else 15.0, 3.0 * wingspan)
		var required_separation: float = base_separation + closure_speed * REACTION_MARGIN_S + POSITION_UNCERTAINTY_M
		var predicted_positions := PackedFloat64Array()
		predicted_positions.resize((sample_count + 1) * 3)
		predicted_positions[0] = north
		predicted_positions[1] = east
		predicted_positions[2] = down
		for sample_index in range(1, sample_count + 1):
			heading = wrapf(heading + turn_rate * PREDICTION_STEP_S, -PI, PI)
			north += air_horizontal_speed * cos(heading) * PREDICTION_STEP_S + threat_wind[0] * PREDICTION_STEP_S
			east += air_horizontal_speed * sin(heading) * PREDICTION_STEP_S + threat_wind[1] * PREDICTION_STEP_S
			down += velocity_down * PREDICTION_STEP_S
			var offset: int = sample_index * 3
			predicted_positions[offset] = north
			predicted_positions[offset + 1] = east
			predicted_positions[offset + 2] = down
		threats.append({"id": item_id, "is_player": is_player,
			"required_separation_m": required_separation, "positions": predicted_positions})
	return threats


func _score_bank(state: PackedFloat64Array, own_velocity: PackedFloat64Array, own_speed: float,
		current_bank: float, nominal_bank: float, candidate_bank: float, clearance: float,
		threats: Array[Dictionary], include_trace: bool = false) -> Dictionary:
	var sample_count: int = int(round(PREDICTION_HORIZON_S / PREDICTION_STEP_S))
	var own_north: float = state[AvoidanceRigidBody.POS]
	var own_east: float = state[AvoidanceRigidBody.POS + 1]
	var own_down: float = state[AvoidanceRigidBody.POS + 2]
	var heading: float = AvoidanceMath.atan2_(own_velocity[1] - _planning_wind[1],
		own_velocity[0] - _planning_wind[0])
	var minimum_by_threat := PackedFloat64Array()
	minimum_by_threat.resize(threats.size())
	var distance_traces: Array[PackedFloat64Array] = []
	for threat_index in threats.size():
		minimum_by_threat[threat_index] = INF
		if include_trace:
			var trace := PackedFloat64Array()
			trace.resize(sample_count + 1)
			distance_traces.append(trace)
	var minimum_terrain_margin: float = clearance - TERRAIN_CLEARANCE_M - TERRAIN_UNCERTAINTY_M
	var down_rate: float = own_velocity[2]
	var terrain_horizon: float = minf(PREDICTION_HORIZON_S, REACTION_MARGIN_S)
	minimum_terrain_margin = minf(minimum_terrain_margin,
		clearance - down_rate * terrain_horizon - TERRAIN_CLEARANCE_M - TERRAIN_UNCERTAINTY_M)
	for sample_index in range(sample_count + 1):
		if sample_index > 0:
			var midpoint_s: float = (float(sample_index) - 0.5) * PREDICTION_STEP_S
			var ramp: float = clampf((midpoint_s - REACTION_MARGIN_S) / BANK_RESPONSE_S, 0.0, 1.0)
			var bank: float = lerpf(current_bank, candidate_bank, ramp)
			var turn_rate: float = G * tan(bank) / maxf(own_speed, 3.0)
			heading = wrapf(heading + turn_rate * PREDICTION_STEP_S, -PI, PI)
			own_north += own_speed * cos(heading) * PREDICTION_STEP_S + _planning_wind[0] * PREDICTION_STEP_S
			own_east += own_speed * sin(heading) * PREDICTION_STEP_S + _planning_wind[1] * PREDICTION_STEP_S
			own_down = state[AvoidanceRigidBody.POS + 2] + down_rate * minf(float(sample_index) * PREDICTION_STEP_S, terrain_horizon)
			var remaining_clearance: float = clearance - (own_down - state[AvoidanceRigidBody.POS + 2])
			minimum_terrain_margin = minf(minimum_terrain_margin,
				remaining_clearance - TERRAIN_CLEARANCE_M - TERRAIN_UNCERTAINTY_M)
		var offset: int = sample_index * 3
		for threat_index in threats.size():
			var positions: PackedFloat64Array = threats[threat_index].positions
			var north_delta: float = positions[offset] - own_north
			var east_delta: float = positions[offset + 1] - own_east
			var down_delta: float = positions[offset + 2] - own_down
			var distance: float = AvoidanceMath.sqrt_(north_delta * north_delta
				+ east_delta * east_delta + down_delta * down_delta)
			minimum_by_threat[threat_index] = minf(minimum_by_threat[threat_index], distance)
			if include_trace:
				distance_traces[threat_index][sample_index] = distance
	var worst_margin: float = minimum_terrain_margin
	var minimum_player_distance: float = INF
	var minimum_peer_distance: float = INF
	for threat_index in threats.size():
		var threat: Dictionary = threats[threat_index]
		var separation: float = minimum_by_threat[threat_index]
		var margin: float = separation - float(threat.required_separation_m)
		if bool(threat.is_player):
			minimum_player_distance = minf(minimum_player_distance, separation)
			worst_margin = minf(worst_margin, margin * 1.2)
		else:
			minimum_peer_distance = minf(minimum_peer_distance, separation)
			worst_margin = minf(worst_margin, margin)
	var result := {"score": worst_margin, "terrain_margin_m": minimum_terrain_margin,
		"minimum_player_distance_m": minimum_player_distance,
		"minimum_peer_distance_m": minimum_peer_distance}
	if include_trace:
		result["distance_traces_m"] = distance_traces
	return result


func _bank_response(base_air_north: float, base_air_east: float,
		nominal_bank: float, selected_bank: float) -> Dictionary:
	var active: bool = absf(selected_bank - nominal_bank) > deg_to_rad(1.0) or _has_held_maneuver
	if not active:
		return _unmodified_traffic_response(base_air_north, base_air_east)
	_selected_bank_target_rad = clampf(selected_bank, -AVOID_BANK_LIMIT_RAD, AVOID_BANK_LIMIT_RAD)
	_override_roll_demand = true
	return {"active": true, "air_north": base_air_north,
		"air_east": base_air_east, "altitude_delta": 0.0}


func _unmodified_traffic_response(base_air_north: float, base_air_east: float) -> Dictionary:
	return {"active": false, "air_north": base_air_north,
		"air_east": base_air_east, "altitude_delta": 0.0}


func _release_held_maneuver_if_clear() -> void:
	if not _has_held_maneuver:
		return
	if _clear_since_tick < 0:
		_clear_since_tick = _planning_tick
	if _planning_tick >= _hold_until_tick \
			and _planning_tick - _clear_since_tick >= RELEASE_CLEAR_TIME_TICKS:
		_clear_held_maneuver("empty_traffic_clear")


func _set_held_maneuver(bank_rad: float, deadline_tick: int, reason: String) -> void:
	var changed: bool = not _has_held_maneuver or not is_equal_approx(_held_bank_rad, bank_rad)
	_has_held_maneuver = true
	_held_bank_rad = clampf(bank_rad, -AVOID_BANK_LIMIT_RAD, AVOID_BANK_LIMIT_RAD)
	_hold_until_tick = deadline_tick
	_clear_since_tick = -1
	if changed:
		_log_maneuver_transition("hold", reason)


func _clear_held_maneuver(reason: String) -> void:
	if not _has_held_maneuver:
		return
	_has_held_maneuver = false
	_held_bank_rad = 0.0
	_hold_until_tick = -1
	_clear_since_tick = -1
	_log_maneuver_transition("release", reason)


func _log_maneuver_transition(action: String, reason: String) -> void:
	if not diagnostics_enabled or _plan_diagnostic_count >= MAX_PLAN_DIAGNOSTICS:
		return
	_plan_diagnostic_count += 1
	print("AFC_REACHABLE_MANEUVER " + JSON.stringify({
		"action": action,
		"reason": reason,
		"tick": _planning_tick,
		"has_held_maneuver": _has_held_maneuver,
		"held_bank_deg": rad_to_deg(_held_bank_rad) if _has_held_maneuver else 0.0,
		"hold_until_tick": _hold_until_tick if _has_held_maneuver else -1,
		"clear_since_tick": _clear_since_tick if _has_held_maneuver else -1,
	}))


func _finite_diagnostic(value: float) -> Variant:
	return value if is_finite(value) else null
