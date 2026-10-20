extends "res://ai/companions/pilot.gd"

## AFC-04/AFC-12 research candidate. It inherits the accepted Stik guidance and
## only replaces the moving-traffic response. The no-traffic command path still
## calls the production method unchanged.
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

var _planning_tick := 0
var _planning_clearance_m := NAN
var _has_held_maneuver := false
var _held_bank_rad := 0.0
var _hold_until_tick := -1
var _clear_since_tick := -1
var _last_decision: Dictionary = {}


func command(snapshot: Dictionary, tick: int, traffic: Array = []) -> Dictionary:
	_planning_tick = tick
	var clearance_value: Variant = snapshot.get("ground_clearance_m", NAN)
	_planning_clearance_m = float(clearance_value) if typeof(clearance_value) in [TYPE_FLOAT, TYPE_INT] else NAN
	var packet: Dictionary = super.command(snapshot, tick, traffic)
	if tick == 0 and not _last_decision.is_empty():
		print("AFC_REACHABLE_INITIAL " + JSON.stringify(_last_decision))
	return packet


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
		return super._avoidance_velocity(state, attitude, own_velocity, base_air_north, base_air_east, traffic)

	var own_speed: float = AvoidanceMath.sqrt_(own_velocity[0] * own_velocity[0] + own_velocity[1] * own_velocity[1])
	if not is_finite(own_speed) or own_speed < 3.0:
		return super._avoidance_velocity(state, attitude, own_velocity, base_air_north, base_air_east, traffic)
	var own_euler: PackedFloat64Array = AvoidanceMath.q_to_euler(attitude)
	if own_euler.size() != 3:
		return super._avoidance_velocity(state, attitude, own_velocity, base_air_north, base_air_east, traffic)
	var current_bank: float = clampf(own_euler[2], -AVOID_BANK_LIMIT_RAD, AVOID_BANK_LIMIT_RAD)
	var nominal_bank: float = clampf(_direction * atan2(_target_speed_mps * _target_speed_mps, G * _radius_m), -AVOID_BANK_LIMIT_RAD, AVOID_BANK_LIMIT_RAD)
	var threats: Array[Dictionary] = _prepare_threats(traffic, own_velocity)
	if threats.is_empty():
		return super._avoidance_velocity(state, attitude, own_velocity, base_air_north, base_air_east, traffic)

	var clearance: float = _planning_clearance_m
	if not is_finite(clearance):
		clearance = -state[AvoidanceRigidBody.POS + 2] - _field_ground_up_m
	var baseline: Dictionary = _score_bank(state, own_velocity, own_speed, current_bank,
		nominal_bank, nominal_bank, clearance, threats)
	var best_bank: float = nominal_bank
	var best_score: float = float(baseline.score)
	var best_prediction: Dictionary = baseline
	for bank_degrees: float in BANK_CHOICES_DEG:
		var candidate_bank: float = deg_to_rad(bank_degrees)
		var result: Dictionary = _score_bank(state, own_velocity, own_speed, current_bank,
			nominal_bank, candidate_bank, clearance, threats)
		var tie_bias: float = 0.15 if candidate_bank > 0.0 else 0.0
		var candidate_score: float = float(result.score) - 0.75 * absf(candidate_bank - nominal_bank) + tie_bias
		if candidate_score > best_score:
			best_score = candidate_score
			best_bank = candidate_bank
			best_prediction = result
	# Include the continuous nominal bank in the candidate set and favor it when
	# a reachable choice cannot improve the worst predicted clearance.
	var nominal_score: float = float(baseline.score)
	if nominal_score >= best_score:
		best_bank = nominal_bank
		best_score = nominal_score
		best_prediction = baseline

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
			_held_bank_rad = best_bank
			_hold_until_tick = _planning_tick + HOLD_TIME_TICKS
			_clear_since_tick = -1
		elif _planning_tick >= _hold_until_tick and _clear_since_tick >= 0 \
				and _planning_tick - _clear_since_tick >= RELEASE_CLEAR_TIME_TICKS:
			_has_held_maneuver = false
			_hold_until_tick = -1
			_clear_since_tick = -1
			return _unmodified_traffic_response(base_air_north, base_air_east)
		else:
			best_bank = _held_bank_rad
	else:
		if float(baseline.score) >= 0.0:
			return _unmodified_traffic_response(base_air_north, base_air_east)
		_has_held_maneuver = true
		_held_bank_rad = best_bank
		_hold_until_tick = _planning_tick + HOLD_TIME_TICKS
		_clear_since_tick = -1
	_last_decision = {
		"tick": _planning_tick,
		"selected_bank_deg": rad_to_deg(best_bank),
		"nominal_bank_deg": rad_to_deg(nominal_bank),
		"baseline_score_m": float(baseline.score),
		"candidate_score_m": best_score,
		"candidate_player_min_m": float(best_prediction.minimum_player_distance_m),
		"candidate_peer_min_m": float(best_prediction.minimum_peer_distance_m),
		"terrain_margin_m": float(best_prediction.terrain_margin_m),
		"threat_count": threats.size(),
	}

	return _bank_response(base_air_north, base_air_east, own_euler[0], nominal_bank, best_bank)


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
		var horizontal_speed: float = AvoidanceMath.sqrt_(velocity_north * velocity_north + velocity_east * velocity_east)
		var heading: float = AvoidanceMath.atan2_(velocity_east, velocity_north)
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
		var turn_rate: float = G * tan(bank) / maxf(horizontal_speed, 3.0)
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
			north += horizontal_speed * cos(heading) * PREDICTION_STEP_S
			east += horizontal_speed * sin(heading) * PREDICTION_STEP_S
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
		threats: Array[Dictionary]) -> Dictionary:
	var sample_count: int = int(round(PREDICTION_HORIZON_S / PREDICTION_STEP_S))
	var own_north: float = state[AvoidanceRigidBody.POS]
	var own_east: float = state[AvoidanceRigidBody.POS + 1]
	var own_down: float = state[AvoidanceRigidBody.POS + 2]
	var heading: float = AvoidanceMath.atan2_(own_velocity[1], own_velocity[0])
	var minimum_by_threat := PackedFloat64Array()
	minimum_by_threat.resize(threats.size())
	for threat_index in threats.size():
		minimum_by_threat[threat_index] = INF
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
			own_north += own_speed * cos(heading) * PREDICTION_STEP_S
			own_east += own_speed * sin(heading) * PREDICTION_STEP_S
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
	return {"score": worst_margin, "terrain_margin_m": minimum_terrain_margin,
		"minimum_player_distance_m": minimum_player_distance,
		"minimum_peer_distance_m": minimum_peer_distance}


func _bank_response(base_air_north: float, base_air_east: float, current_heading: float,
		nominal_bank: float, selected_bank: float) -> Dictionary:
	var feed_forward_bank: float = clampf(_direction * atan2(_target_speed_mps * _target_speed_mps,
		G * _radius_m), -AVOID_BANK_LIMIT_RAD, AVOID_BANK_LIMIT_RAD)
	var desired_course_error: float = clampf((selected_bank - feed_forward_bank) / 1.6,
		-deg_to_rad(12.0), deg_to_rad(12.0))
	var base_heading: float = AvoidanceMath.atan2_(base_air_east, base_air_north)
	var base_error: float = wrapf(base_heading - current_heading, -PI, PI)
	var adjusted_heading: float = base_heading + desired_course_error - base_error
	var air_speed: float = AvoidanceMath.sqrt_(base_air_north * base_air_north + base_air_east * base_air_east)
	var active: bool = absf(selected_bank - nominal_bank) > deg_to_rad(1.0) or _has_held_maneuver
	if not active:
		return _unmodified_traffic_response(base_air_north, base_air_east)
	return {"active": true,
		"air_north": air_speed * cos(adjusted_heading),
		"air_east": air_speed * sin(adjusted_heading),
		"altitude_delta": 0.0}


func _unmodified_traffic_response(base_air_north: float, base_air_east: float) -> Dictionary:
	return {"active": false, "air_north": base_air_north,
		"air_east": base_air_east, "altitude_delta": 0.0}
