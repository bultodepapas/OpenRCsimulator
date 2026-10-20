extends SceneTree

const MainScene = preload("res://main.tscn")
const SkyConfig = preload("res://environment/sky_appearance_config.gd")
const RB = preload("res://physics/rigid_body.gd")
const SceneryCollision = preload("res://sim/scenery_collision.gd")
const REPORT_PATH := "C:/DEVELOPMENT/OpenRCsimulator/tmp/runtime-audit-3/native-reference-3.json"
const RESULT_PATH := "C:/DEVELOPMENT/OpenRCsimulator/tmp/runtime-audit-3/ground-audit/main-profile-result.json"
const MEASURE_TICKS := 480

var _counts: Dictionary = {}
var _usec: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

func _record(name: String, started_usec: int) -> void:
	var elapsed := Time.get_ticks_usec() - started_usec
	_counts[name] = int(_counts.get(name, 0)) + 1
	_usec[name] = int(_usec.get(name, 0)) + elapsed

func _instrument(model: Variant) -> void:
	if model.pre_tick.is_valid():
		var original_pre: Callable = model.pre_tick
		model.pre_tick = func(aux, inputs, step_dt):
			var started := Time.get_ticks_usec()
			var result = original_pre.call(aux, inputs, step_dt)
			_record("pre_tick", started)
			return result
	if model.loads.is_valid():
		var original_loads: Callable = model.loads
		model.loads = func(body, stage_time):
			var started := Time.get_ticks_usec()
			var result = original_loads.call(body, stage_time)
			_record("loads", started)
			return result
	if model.stage.is_valid():
		var original_stage: Callable = model.stage
		model.stage = func(body, continuous, stage_time):
			var started := Time.get_ticks_usec()
			var result = original_stage.call(body, continuous, stage_time)
			_record("stage", started)
			return result
	if model.block_loads.is_valid():
		var original_block_loads: Callable = model.block_loads
		model.block_loads = func(body, continuous, stage_time):
			var started := Time.get_ticks_usec()
			var result = original_block_loads.call(body, continuous, stage_time)
			_record("block_loads", started)
			return result
	if model.block_derivative.is_valid():
		var original_block_derivative: Callable = model.block_derivative
		model.block_derivative = func(body, continuous, stage_time):
			var started := Time.get_ticks_usec()
			var result = original_block_derivative.call(body, continuous, stage_time)
			_record("block_derivative", started)
			return result
	if model.stage_rotor_momentum.is_valid():
		var original_stage_rotor: Callable = model.stage_rotor_momentum
		model.stage_rotor_momentum = func(body, continuous, stage_time):
			var started := Time.get_ticks_usec()
			var result = original_stage_rotor.call(body, continuous, stage_time)
			_record("stage_rotor_momentum", started)
			return result
	if model.rotor_momentum.is_valid():
		var original_rotor: Callable = model.rotor_momentum
		model.rotor_momentum = func(aux):
			var started := Time.get_ticks_usec()
			var result = original_rotor.call(aux)
			_record("rotor_momentum", started)
			return result
	if model.substeps.is_valid():
		var original_substeps: Callable = model.substeps
		model.substeps = func(body, continuous, stage_time):
			var started := Time.get_ticks_usec()
			var result = original_substeps.call(body, continuous, stage_time)
			_record("substeps", started)
			return result
	if model.step_policy.is_valid():
		var original_policy: Callable = model.step_policy
		model.step_policy = func(combined, start_time, step_dt, derivative, first):
			var started := Time.get_ticks_usec()
			var result = original_policy.call(combined, start_time, step_dt, derivative, first)
			_record("step_policy", started)
			return result
	if model.post_tick.is_valid():
		var original_post: Callable = model.post_tick
		model.post_tick = func(previous_body, candidate_body, next_tick):
			var started := Time.get_ticks_usec()
			var result = original_post.call(previous_body, candidate_body, next_tick)
			_record("post_tick", started)
			return result
	if model.post_tick_joint.is_valid():
		var original_post_joint: Callable = model.post_tick_joint
		model.post_tick_joint = func(previous_body, candidate_body, next_tick, previous_continuous, candidate_continuous):
			var started := Time.get_ticks_usec()
			var result = original_post_joint.call(previous_body, candidate_body, next_tick, previous_continuous, candidate_continuous)
			_record("post_tick_joint", started)
			return result
	if model.block_aux.is_valid():
		var original_block_aux: Callable = model.block_aux
		model.block_aux = func(continuous, aux):
			var started := Time.get_ticks_usec()
			var result = original_block_aux.call(continuous, aux)
			_record("block_aux", started)
			return result

func _run() -> void:
	var report_file := FileAccess.open(REPORT_PATH, FileAccess.READ)
	if report_file == null:
		push_error("Cannot open native reference report: " + REPORT_PATH)
		quit(2)
		return
	var report: Variant = JSON.parse_string(report_file.get_as_text())
	report_file.close()
	if typeof(report) != TYPE_DICTIONARY:
		push_error("Native reference report did not parse")
		quit(2)
		return
	var landing: Dictionary = {}
	for case_value: Variant in report.get("cases", []):
		if typeof(case_value) == TYPE_DICTIONARY and str(case_value.get("scenario", "")) == "landing":
			landing = case_value
			break
	if landing.is_empty() or not bool(landing.get("complete", false)):
		push_error("Completed landing case not found in native report")
		quit(2)
		return

	var flight = MainScene.instantiate()
	flight.set_user_args(PackedStringArray(["--rates=full"]))
	flight.interactive_start = true
	flight.external_controller_selection = true
	flight.start_choice = "airborne"
	flight.sky_config = SkyConfig.for_preset("distant_storm")
	flight.set_process(false)
	flight.set_physics_process(false)
	root.add_child(flight)
	if not flight.startup_error.is_empty() or flight.session == null:
		push_error("Main startup failed: " + str(flight.startup_error))
		quit(3)
		return

	var session = flight.session
	var sim = session.sim
	flight.set_process(false)
	flight.set_physics_process(false)
	session.set_process(false)
	session.set_physics_process(false)
	sim.set_paused(true)
	sim.set_process(false)
	sim.set_physics_process(false)

	var state := PackedFloat64Array(landing.final_state)
	if state.size() != RB.SIZE:
		push_error("Native landing endpoint has the wrong body-state size")
		quit(4)
		return
	sim.state = state.duplicate()
	sim.previous = state.duplicate()
	sim.tick = int(landing.tick)
	sim._remember_valid_state()
	session.commands = {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.0}
	session.raw = session.commands.duplicate()
	sim.inputs = session._inputs()

	var model = sim.model
	_instrument(model)
	var proxies: Array = session._collision_world.get("proxies", [])
	var bins: Dictionary = session._collision_world.get("bins", {})
	if session._collision_world.is_empty() or proxies.is_empty():
		push_error("Main did not load the real field collision world")
		quit(5)
		return
	var radius := float(session._hull_contact.get("reach", 0.0))
	var local_candidates: Array = SceneryCollision._candidate_indices(session._collision_world,
		state[RB.POS] - radius, state[RB.POS] + radius,
		state[RB.POS + 1] - radius, state[RB.POS + 1] + radius,
		state[RB.POS + 2] - radius, state[RB.POS + 2] + radius)
	print("fixture: report=native-reference-3.json scenario=landing tick=%d t=%.3f body=%d continuous=%d aux=%d field=%s landscape=%s world_identity=%s proxies=%d bins=%d local_bin_candidates=%d lake=%s soft_hull=%s delegates={stage:%s,loads:%s,post_tick:%s,post_tick_joint:%s,substeps:%s,step_policy:%s}" % [
		sim.tick, sim.time(), state.size(), sim.continuous.size(), sim.aux.size(),
		str(flight.field.get("id", "")), str(flight.landscape_id), str(session._collision_world.get("identity", "")),
		proxies.size(), bins.size(), local_candidates.size(), str(not session._lake.is_empty()), str(session.soft_hull_contacts),
		str(model.stage.is_valid()), str(model.loads.is_valid()), str(model.post_tick.is_valid()),
		str(model.post_tick_joint.is_valid()), str(model.substeps.is_valid()), str(model.step_policy.is_valid())
	])

	var start_tick: int = int(sim.tick)
	var started_usec := Time.get_ticks_usec()
	for i in MEASURE_TICKS:
		var before: int = int(sim.tick)
		sim.step()
		if sim.tick != before + 1:
			push_error("Simulation stopped accepting ticks at loop index %d: %s" % [i, sim.fault_reason])
			break
	var total_usec := Time.get_ticks_usec() - started_usec
	var accepted: int = int(sim.tick) - start_tick
	var summary := {
		"format": "openrc-ground-main-callback-profile v1",
		"source_report": "native-reference-3.json",
		"scenario": "landing-final-body-with-fresh-main-session-aux-and-continuous",
		"physics_hz": Engine.physics_ticks_per_second,
		"accepted_ticks": accepted,
		"requested_ticks": MEASURE_TICKS,
		"wall_usec": total_usec,
		"wall_usec_per_tick": float(total_usec) / float(maxi(accepted, 1)),
		"kernel_step_usec_ema": sim.step_usec,
		"fault": sim.fault_reason,
		"world_identity": str(session._collision_world.get("identity", "")),
		"world_proxy_count": proxies.size(),
		"world_bin_count": bins.size(),
		"local_bin_candidate_count_at_fixture": local_candidates.size(),
		"lake_enabled": not session._lake.is_empty(),
		"continuous_size_from_reset": sim.continuous.size(),
		"aux_size_from_reset": sim.aux.size(),
		"callbacks": {}
	}
	var names: Array = _counts.keys()
	names.sort()
	for name_value: Variant in names:
		var name := str(name_value)
		var count := int(_counts[name])
		var elapsed := int(_usec.get(name, 0))
		summary.callbacks[name] = {
			"calls": count,
			"usec": elapsed,
			"mean_usec_per_call": float(elapsed) / float(maxi(count, 1)),
			"usec_per_accepted_tick": float(elapsed) / float(maxi(accepted, 1))
		}
	print(JSON.stringify(summary))
	var out := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	if out == null:
		push_error("Could not save profile summary: " + RESULT_PATH)
	else:
		out.store_string(JSON.stringify(summary))
		out.close()
	flight.queue_free()
	quit(0 if accepted == MEASURE_TICKS else 5)

