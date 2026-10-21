## AFC-00-R5 promotion draft; copy into app/tests only after the draft is reviewed and parsed.
extends SceneTree

const Flight := preload("res://sim/flight_session.gd")
const Manager := preload("res://ai/companions/manager.gd")
const Config := preload("res://ai/companions/config.gd")
const Air := preload("res://physics/air_data.gd")
const Math3D := preload("res://physics/math3d.gd")
const RigidBody := preload("res://physics/rigid_body.gd")
const ObservationAirdata := preload("res://../research/ai-companions/performance/observation_airdata_runtime_candidate.gd")
const CandidateAgentScript := preload("res://../research/ai-companions/performance/observation_agent_candidate.gd")
const WindConfig := preload("res://physics/wind_config.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const CollisionSetup := preload("res://scenery/collision_setup.gd")
const LakeLoader := preload("res://data/lake_loader.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")

const FLIGHT_TICKS := 1200
const COMMAND_INTERVAL := 4
const EXPECTED_SAMPLES_PER_AGENT := 300
const COUNTS := [1, 3]
const FIXTURE_SEED := 20261020

var _checks := 0
var _failures := 0


func _initialize() -> void:
	if OS.get_cmdline_user_args().has("--parse-only"):
		print("AFC COMPANION OBSERVATION TEST DRAFT PARSED")
		quit(0)
		return
	call_deferred("_run")


func _check(label: String, passed: bool, detail: String = "") -> void:
	_checks += 1
	print(("ok   " if passed else "FAIL ") + label + ("  " + detail if not detail.is_empty() else ""))
	if not passed:
		_failures += 1


func _run() -> void:
	_check("research Agent subclass draft is loadable", CandidateAgentScript != null)
	var arithmetic: Dictionary = _run_airdata_arithmetic()
	_check("airspeed helper is bitwise equal to authoritative Air.compute", arithmetic.mismatches.is_empty(),
		"%d/%d cases; signed-zero inputs=%d" % [arithmetic.matches, arithmetic.cases, arithmetic.signed_zero_cases])
	_check("signed-zero inputs retain distinct IEEE-754 bits", arithmetic.signed_zero_distinguishable)
	if not arithmetic.mismatches.is_empty():
		printerr("First airspeed mismatch: ", str(arithmetic.mismatches[0]))

	var field_result: Dictionary = FieldLoader.load_from()
	_check("Club field loads", field_result.get("ok", false), str(field_result.get("errors", [])))
	if not field_result.get("ok", false):
		_finish()
		return
	var collision: Dictionary = CollisionSetup.build(field_result.field)
	_check("Club field collision fixture builds", collision.get("ok", false), str(collision.get("errors", [])))
	if not collision.get("ok", false):
		_finish()
		return
	var lake: Dictionary = LakeLoader.load_from(LakeLoader.DEFAULT_PATH)
	_check("lake context loads", lake.get("ok", false), str(lake.get("errors", [])))
	if not lake.get("ok", false):
		_finish()
		return
	_check("physics rate remains 240 Hz", int(Engine.physics_ticks_per_second) == 240)
	for count: int in COUNTS:
		print("[observation-test] start companions=%d ticks=%d" % [count, FLIGHT_TICKS])
		var result: Dictionary = _run_admitted_case(count, field_result.field, collision.world, lake.lake)
		var expected_roster: int = count
		var expected_samples: int = count * EXPECTED_SAMPLES_PER_AGENT
		_check("count-%d admitted roster is exact and nonzero" % count,
			int(result.roster_count) == expected_roster and int(result.roster_count) > 0,
			str(result.roster_count))
		_check("count-%d player, manager, and companions finish %d ticks" % [count, FLIGHT_TICKS],
			bool(result.flight_complete), str(result.failure))
		_check("count-%d scheduled manager batches are exact" % count,
			int(result.manager_batches) == EXPECTED_SAMPLES_PER_AGENT,
			str(result.manager_batches))
		_check("count-%d production/legacy observation rows are exact and nonzero" % count,
			int(result.sample_count) == expected_samples and int(result.sample_count) > 0,
			"%d expected %d" % [result.sample_count, expected_samples])
		_check("count-%d every agent has %d byte-equal snapshots" % [count, EXPECTED_SAMPLES_PER_AGENT],
			bool(result.per_agent_counts_exact) and int(result.mismatch_count) == 0,
			"per-agent=%s mismatches=%d" % [str(result.per_slot_sample_counts), result.mismatch_count])
		_check("count-%d fixture reaches post-gust sampling" % count,
			int(result.observations_at_or_after_gust_delay) > 0,
			str(result.observations_at_or_after_gust_delay))
		print(JSON.stringify({companions = count, roster_count = result.roster_count,
			ticks = result.completed_ticks, manager_batches = result.manager_batches,
			observation_rows = result.sample_count, per_slot_sample_counts = result.per_slot_sample_counts,
			byte_mismatches = result.mismatch_count,
			observations_at_or_after_gust_delay = result.observations_at_or_after_gust_delay}))
	_finish()


func _finish() -> void:
	print("AFC COMPANION OBSERVATION CHECKS %d FAILED %d" % [_checks, _failures])
	print("AFC COMPANION OBSERVATION TEST COMPLETE")
	quit(0 if _failures == 0 else 1)


func _run_airdata_arithmetic() -> Dictionary:
	var mismatches: Array[Dictionary] = []
	var cases := 0
	for index in 512:
		var step: float = float(index)
		var attitude: PackedFloat64Array = Math3D.q_from_euler(
			sin(step * 0.071) * PI,
			sin(step * 0.037) * deg_to_rad(85.0),
			cos(step * 0.053) * PI)
		var velocity := PackedFloat64Array([
			cos(step * 0.109) * (3.0 + fmod(step, 44.0)),
			sin(step * 0.127) * (1.0 + fmod(step, 17.0)),
			cos(step * 0.163) * (0.25 + fmod(step, 5.0))])
		var state: PackedFloat64Array = RigidBody.make_state(
			PackedFloat64Array([step, -step * 0.25, -20.0 - fmod(step, 500.0)]),
			velocity, attitude, PackedFloat64Array([0.0, 0.0, 0.0]))
		var wind := PackedFloat64Array([
			sin(step * 0.193) * 18.0,
			cos(step * 0.211) * 12.0,
			sin(step * 0.239) * 4.0])
		_check_airdata_case("varied-%d" % index, state, wind, mismatches)
		cases += 1

	for edge in 3:
		var attitude: PackedFloat64Array = Math3D.q_from_euler(0.31 * float(edge), -0.17 * float(edge), 0.23 * float(edge))
		var velocity := PackedFloat64Array([0.0, 0.0, 0.0]) if edge == 0 else PackedFloat64Array([4.0, -2.0, 1.5])
		var state: PackedFloat64Array = RigidBody.make_state(
			PackedFloat64Array([0.0, 0.0, -50.0]), velocity, attitude, PackedFloat64Array([0.0, 0.0, 0.0]))
		var wind := PackedFloat64Array([0.0, 0.0, 0.0])
		if edge > 0:
			wind = Math3D.q_rotate(attitude, velocity)
		_check_airdata_case("edge-%d" % edge, state, wind, mismatches)
		cases += 1

	var negative_zero_bytes := PackedByteArray([0, 0, 0, 0, 0, 0, 0, 128])
	var negative_zero_array: PackedFloat64Array = negative_zero_bytes.to_float64_array()
	var negative_zero: float = negative_zero_array[0]
	var positive_zero: float = 0.0
	var signed_zero_distinguishable: bool = _float_bytes(negative_zero) != _float_bytes(positive_zero)
	for edge in 6:
		var phase: float = float(edge + 1)
		var attitude: PackedFloat64Array = Math3D.q_from_euler(phase * 0.19, -phase * 0.11, phase * 0.07)
		var z0: float = negative_zero if edge % 2 == 0 else positive_zero
		var z1: float = positive_zero if edge % 2 == 0 else negative_zero
		var velocity := PackedFloat64Array([z0, 2.0 - phase * 0.1, z1])
		var state: PackedFloat64Array = RigidBody.make_state(
			PackedFloat64Array([phase, -phase, -30.0]), velocity, attitude,
			PackedFloat64Array([0.0, 0.0, 0.0]))
		var wind := PackedFloat64Array([z1, -0.75 * phase, z0])
		_check_airdata_case("signed-zero-%d" % edge, state, wind, mismatches)
		cases += 1
	return {cases = cases, matches = cases - mismatches.size(), mismatches = mismatches,
		signed_zero_cases = 6, signed_zero_distinguishable = signed_zero_distinguishable}


func _check_airdata_case(label: String, state: PackedFloat64Array, wind: PackedFloat64Array,
		mismatches: Array[Dictionary]) -> void:
	var expected: float = float(Air.compute(state, wind, 1.225).V)
	var actual: float = ObservationAirdata.airspeed_m_s(state, wind)
	if not is_finite(expected) or not is_finite(actual) or _float_bytes(expected) != _float_bytes(actual):
		mismatches.append({case = label, expected = expected, actual = actual,
			state_velocity_bytes = state.slice(RigidBody.VEL, RigidBody.VEL + 3).to_byte_array().hex_encode(),
			wind_bytes = wind.to_byte_array().hex_encode()})


func _float_bytes(value: float) -> PackedByteArray:
	return PackedFloat64Array([value]).to_byte_array()


func _run_admitted_case(count: int, field: Dictionary, collision_world: Variant, lake: Variant) -> Dictionary:
	var player := Flight.new()
	player.input_enabled = false
	player.crash_auto_restart = false
	player.setup(Catalog.entry(Catalog.DEFAULT_ID).data, Catalog.DEFAULT_ID)
	if not player.set_field(field) or not player.set_collision_world(collision_world) \
			or not player.set_lake_context(lake) or not player.setup_weather(WindConfig.GENTLE_PRACTICE):
		player.free()
		return {failure = "player field, collision, lake, or weather setup failed"}
	player.reset()
	var fleet := Manager.new()
	var config: Dictionary = Config.defaults()
	config.enabled = true
	config.count = count
	config.seed = FIXTURE_SEED
	var prepared: Dictionary = fleet.configure(player, field, "club_field", config, false, false)
	if not prepared.get("ok", false) or fleet.agents.size() != count:
		var reason: String = str(prepared.get("errors", []))
		fleet.free()
		player.free()
		return {failure = "manager admitted the wrong roster: %s" % reason,
			roster_count = fleet.agents.size() if is_instance_valid(fleet) else 0}

	var mismatch_count := 0
	var sample_count := 0
	var observations_at_or_after_gust_delay := 0
	var per_slot_sample_counts := {}
	for agent: Node in fleet.agents:
		per_slot_sample_counts[str(agent.slot_id)] = 0
	var failure := ""
	var completed_ticks := 0
	for _step_index in FLIGHT_TICKS:
		var tick: int = int(player.sim.tick)
		var plan_this_tick := false
		for agent: Node in fleet.agents:
			plan_this_tick = plan_this_tick or agent.needs_command(tick)
		if plan_this_tick:
			for agent: Node in fleet.agents:
				var actual: Dictionary = agent.observation()
				var legacy: Dictionary = _legacy_observation(agent)
				sample_count += 1
				per_slot_sample_counts[str(agent.slot_id)] = int(per_slot_sample_counts[str(agent.slot_id)]) + 1
				if float(agent.session.sim.time()) >= float(WindConfig.GENTLE_PRACTICE.gust_delay_s):
					observations_at_or_after_gust_delay += 1
				if var_to_bytes(actual) != var_to_bytes(legacy):
					mismatch_count += 1
					if mismatch_count == 1:
						printerr("Observation dictionary mismatch at tick %d slot %d" % [tick, agent.slot_id])
		player._physics_process(player.sim.dt())
		player.sim._physics_process(player.sim.dt())
		completed_ticks = int(player.sim.tick)
		if completed_ticks != tick + 1 or not player.sim.fault_reason.is_empty() or not player.crash.is_empty():
			failure = "player stopped at tick %d: %s %s" % [completed_ticks, player.sim.fault_reason, str(player.crash)]
			break
		for agent: Node in fleet.agents:
			if int(agent.session.sim.tick) != completed_ticks or not agent.failure.is_empty() \
					or not agent.session.sim.fault_reason.is_empty() or not agent.session.crash.is_empty():
				failure = "companion %d stopped at tick %d: %s %s" % [agent.slot_id, completed_ticks,
					agent.failure, str(agent.session.crash)]
				break
		if not failure.is_empty():
			break
	var roster_count: int = fleet.agents.size()
	var manager_batches: int = int(fleet.observation_batches)
	var per_agent_counts_exact := manager_batches == EXPECTED_SAMPLES_PER_AGENT
	for agent: Node in fleet.agents:
		per_agent_counts_exact = per_agent_counts_exact \
			and int(per_slot_sample_counts[str(agent.slot_id)]) == EXPECTED_SAMPLES_PER_AGENT
	var result := {
		flight_complete = failure.is_empty() and completed_ticks == FLIGHT_TICKS \
			and int(fleet.accepted_ticks) == FLIGHT_TICKS,
		failure = failure,
		roster_count = roster_count,
		completed_ticks = completed_ticks,
		manager_batches = manager_batches,
		sample_count = sample_count,
		per_slot_sample_counts = per_slot_sample_counts,
		per_agent_counts_exact = per_agent_counts_exact,
		mismatch_count = mismatch_count,
		observations_at_or_after_gust_delay = observations_at_or_after_gust_delay,
	}
	fleet.free()
	player.free()
	return result


func _legacy_observation(agent: Node) -> Dictionary:
	var state: PackedFloat64Array = agent.session.sim.state.duplicate()
	var air: Dictionary = agent.session.air_data(state)
	return {
		id = "companion-%d" % agent.slot_id,
		slot = agent.slot_id,
		state = state,
		airspeed_m_s = float(air.V),
		wind_ned = agent.session.wind_at(agent.session.sim.time()),
		ground_clearance_m = -state[2] - float(agent.session.environment.ground(state[0], state[1])[0]),
		trim = agent._accepted_trim.duplicate(),
		turbulence_rms_m_s = agent._weather_rms.duplicate(),
		is_player = false,
	}
