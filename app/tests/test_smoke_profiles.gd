extends SceneTree

const Schedule := preload("res://render/smoke/profile_smoke_schedule.gd")
const ProfileSmoke := preload("res://render/smoke/profile_smoke.gd")
const TICKS_PER_SECOND := 240

var checks := 0
var failures := 0


func _initialize() -> void:
	_test_tick_rate_determinism()
	_test_tick_tape_bounds()
	_test_source_isolation()
	_test_profile_color_validation()
	await _test_runtime_budget_lifecycle()
	print("Profile smoke: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func check(label: String, passed: bool, detail := "") -> void:
	checks += 1
	if not passed:
		failures += 1
		printerr("FAIL ", label, " ", detail)


func _test_tick_rate_determinism() -> void:
	var logs: Array = []
	for rate in [30, 60, 144]:
		var run: Dictionary = _schedule_tape(int(rate))
		check("tick tape runs at %d fps" % rate, bool(run.ok), str(run.get("error", "")))
		logs.append(run.log)
	check("CPU smoke event logs match at 30, 60, and 144 fps", logs[0] == logs[1] and logs[1] == logs[2])
	check("pulse and palette transitions were emitted", logs[0].size() > 20)


func _schedule_tape(rate: int) -> Dictionary:
	var schedule = Schedule.new()
	var pulse := _entry("wing_left", "show", "pulse")
	pulse.pulse_period_s = 0.25
	pulse.pulse_duty = 0.4
	pulse.palette = ["#FF0000FF", "#0000FFFF", "#FFFFFFFF"]
	pulse.step_s = 0.1
	var source := _entry("engine_outlet", "source", "hold")
	var slots := {
		"wing_left": {"kind": "show"},
		"engine_outlet": {"kind": "source", "source_kind": "glow_prop"},
	}
	if not schedule.configure([pulse, source], slots):
		return {"ok": false, "error": schedule.fault_reason(), "log": []}
	var request_tape: Array[Dictionary] = [
		{"tick": 2, "level": 1.0}, {"tick": 443, "level": 0.0},
		{"tick": 511, "level": 0.8}, {"tick": 700, "level": 0.0},
		{"tick": 760, "level": 1.0}, {"tick": 945, "level": 0.0},
	]
	var source_tape: Array[Dictionary] = [
		{"tick": 215, "kind": "glow_prop", "running": false, "level": 0.0},
		{"tick": 317, "kind": "glow_prop", "running": true, "level": 0.7},
		{"tick": 400, "kind": "electric_prop", "running": true, "level": 1.0},
		{"tick": 489, "kind": "glow_prop", "running": true, "level": 0.6},
	]
	var request_level := 0.0
	var source_state := {"kind": "glow_prop", "running": true, "level": 0.7}
	var log: Array[Dictionary] = []
	var start_tick := 0
	var frame := 0
	var total_ticks := 960
	while start_tick < total_ticks:
		frame += 1
		var end_tick := mini(total_ticks, floori(float(frame * TICKS_PER_SECOND) / rate))
		if end_tick <= start_tick:
			continue
		var request_changes: Array[Dictionary] = []
		for change: Dictionary in request_tape:
			if change.tick > start_tick and change.tick <= end_tick:
				request_changes.append(change)
		var source_changes: Array[Dictionary] = []
		for change: Dictionary in source_tape:
			if change.tick > start_tick and change.tick <= end_tick:
				source_changes.append(change)
		var request: Dictionary = {"level": request_level, "changes": request_changes}
		var source_input: Dictionary = source_state.duplicate(true)
		source_input["changes"] = source_changes
		var result: Dictionary = schedule.advance(start_tick, end_tick, {"wing_left": request}, source_input)
		if not bool(result.get("ok", false)):
			return {"ok": false, "error": result.get("error", ""), "log": log}
		log.append_array(result.event_log)
		for change: Dictionary in request_changes:
			request_level = float(change.level)
		for change: Dictionary in source_changes:
			source_state = {"kind": str(change.kind), "running": bool(change.running), "level": float(change.level)}
		start_tick = end_tick
	return {"ok": true, "log": log}


func _test_tick_tape_bounds() -> void:
	var schedule = Schedule.new()
	var entry := _entry("wing", "show", "hold")
	check("bounded scheduler configures", schedule.configure([entry], {"wing": {"kind": "show"}}))
	var changes: Array[Dictionary] = []
	for tick in range(1, 25):
		changes.append({"tick": tick, "level": 1.0 if tick % 2 == 1 else 0.0})
	var dense: Dictionary = schedule.advance(0, 24, {"wing": {"level": 0.0, "changes": changes}}, 0.0)
	check("24 intra-interval input transitions are preserved without dropping", bool(dense.ok), str(dense.get("error", "")))
	check("event buffer represents every transition tick", dense.events.wing.size() == 25)
	var maximum_changes: Array[Dictionary] = []
	for tick in range(25):
		maximum_changes.append({"tick": tick, "level": 1.0 if tick % 2 == 0 else 0.0})
	var maximum := Schedule.new()
	maximum.configure([entry], {"wing": {"kind": "show"}})
	var maximum_result: Dictionary = maximum.advance(0, 24,
		{"wing": {"level": 0.0, "changes": maximum_changes}}, 0.0)
	check("maximum 25 input samples fit a 24-tick interval", maximum_result.ok
		and maximum_result.events.wing.size() == 25)
	var overflow := Schedule.new()
	overflow.configure([entry], {"wing": {"kind": "show"}})
	var too_many := maximum_changes.duplicate(true)
	too_many.append({"tick": 24, "level": 1.0})
	var overflow_result: Dictionary = overflow.advance(0, 24,
		{"wing": {"level": 0.0, "changes": too_many}}, 0.0)
	check("26 input samples fault closed instead of being truncated", not overflow_result.ok
		and not overflow.fault_reason().is_empty())
	var invalid := Schedule.new()
	invalid.configure([entry], {"wing": {"kind": "show"}})
	var malformed: Dictionary = invalid.advance(0, 4,
		{"wing": {"level": 0.0, "changes": [{"tick": 5, "level": 1.0}]}}, 0.0)
	check("out-of-window input transition fails closed", not malformed.ok and not invalid.fault_reason().is_empty())
	var after_fault: Dictionary = invalid.advance(4, 5, 0.0, 0.0)
	check("scheduler fault stays latched until reset", not after_fault.ok)
	invalid.reset()
	var after_reset: Dictionary = invalid.advance(0, 1, 0.0, 0.0)
	check("explicit reset clears scheduler fault", after_reset.ok)


func _test_source_isolation() -> void:
	var schedule = Schedule.new()
	var show_entry := _entry("wing", "show", "hold")
	var source_entry := _entry("engine", "source", "hold")
	var registration := {"wing": {"kind": "show"}, "engine": {"kind": "source", "source_kind": "glow_prop"}}
	check("show and source slots configure together", schedule.configure([show_entry, source_entry], registration))
	var wrong_kind: Dictionary = schedule.advance(0, 1, {"wing": 1.0},
		{"kind": "electric_prop", "running": true, "level": 1.0})
	check("show emitter can run beside an unsupported physical source", wrong_kind.ok
		and float(wrong_kind.events.wing.back().level) > 0.0 and float(wrong_kind.events.engine.back().level) == 0.0)
	var stopped: Dictionary = schedule.advance(1, 2, {"wing": 1.0},
		{"kind": "glow_prop", "running": false, "level": 1.0})
	check("a stopped source cannot emit while the show slot stays active", stopped.ok
		and float(stopped.events.engine.back().level) == 0.0 and float(stopped.events.wing.back().level) > 0.0)
	var accepted: Dictionary = schedule.advance(2, 3, {"wing": 1.0},
		{"kind": "glow_prop", "running": true, "level": 0.5})
	check("registered running source controls only its own emitter", accepted.ok
		and float(accepted.events.engine.back().level) == 0.5 and float(accepted.events.wing.back().level) == 1.0)


func _test_profile_color_validation() -> void:
	var invalid_base := _entry("wing_left", "show", "hold")
	invalid_base.color = "#GG0000FF"
	var base_smoke = ProfileSmoke.new()
	check("profile rejects non-hex base colors", not base_smoke.configure(_profile([invalid_base]), _bindings()))
	base_smoke.free()
	var invalid_palette := _entry("wing_left", "show", "hold")
	invalid_palette.palette = ["#FF0000FF", "#0000ZZFF"]
	invalid_palette.step_s = 0.1
	var palette_smoke = ProfileSmoke.new()
	check("profile rejects non-hex palette swatches", not palette_smoke.configure(_profile([invalid_palette]), _bindings()))
	palette_smoke.free()


func _test_runtime_budget_lifecycle() -> void:
	var bindings := _bindings()
	var entries: Array[Dictionary] = [
		_entry("wing_left", "show", "hold"),
		_entry("wing_right", "show", "hold"),
		_entry("tail", "show", "hold"),
		_entry("engine_outlet", "source", "hold"),
	]
	entries[0].palette = ["#FF0000FF", "#0000FFFF"]
	entries[0].step_s = 0.05
	for entry: Dictionary in entries:
		entry.lifetime_s = 8.0
	entries[0].width_m = 2.0
	entries[0].shape = "cloud"
	var smoke = ProfileSmoke.new()
	root.add_child(smoke)
	check("profile smoke configures show poses and selector-only source endpoints", smoke.configure(_profile(entries), bindings), str(smoke.budget_info().fault))
	var budget: Dictionary = smoke.budget_info()
	check("three show emitters and one source share a 768 budget", budget.capacity == 768
		and budget.budget_limit == 768 and budget.show_emitters == 3 and budget.source_emitters == 1)
	check("four-emitter allocation partitions are bounded and sum exactly", budget.slot_particles.values().reduce(func(a, b): return int(a) + int(b), 0) == 768
		and budget.slot_particles.values().all(func(value): return int(value) == 192))
	var material_ids: Dictionary = {}
	for slot: String in budget.slot_particles.keys():
		var emitter: GPUParticles3D = smoke._emitters[slot]
		material_ids[(emitter.process_material as ShaderMaterial).get_instance_id()] = true
	check("each registered endpoint has isolated shader state", material_ids.size() == 4)
	var transforms := {}
	for slot: String in budget.slot_particles.keys():
		transforms[slot] = Transform3D.IDENTITY
	var source_sample := {"kind": "glow_prop", "running": true, "level": 1.0}
	var first: Dictionary = smoke.advance(0.0, {"tick": 0, "slot_transforms": transforms}, Vector3.ZERO, 1.0, source_sample)
	var active: Dictionary = smoke.advance(8.0 / 240.0, {"tick": 8, "slot_transforms": transforms}, Vector3(1.0, 0.0, 0.0), 1.0, source_sample)
	check("tick clock primes then advances a bounded interval", first.get("primed", false) and active.ok and active.interval_ticks == 8)
	var left := smoke._emitters["wing_left"] as GPUParticles3D
	check("eight-second profile lifetime reaches the particle node", left.lifetime == 8.0)
	check("wide eight-second cloud expands its wind and puff visibility bound",
		left.visibility_aabb.size.x >= 30.0 and left.visibility_aabb.size.y >= 30.0
		and left.visibility_aabb.size.z >= 30.0, str(left.visibility_aabb))
	var process := left.process_material as ShaderMaterial
	var events: PackedVector4Array = process.get_shader_parameter("birth_event_states")
	var times: PackedFloat32Array = process.get_shader_parameter("birth_event_times")
	check("render boundary passes one ordered per-birth color in a fixed-size buffer", process.get_shader_parameter("birth_event_count") == 1
		and events.size() == 32 and times.size() == 32 and events[0].x > 0.9 and events[0].z < 0.1 and times[0] == 0.0
		and events[1] == Vector4.ZERO and times[1] == 0.0)
	var palette: Dictionary = smoke.advance(12.0 / 240.0, {"tick": 20, "slot_transforms": transforms}, Vector3(1.0, 0.0, 0.0), 1.0, source_sample)
	events = process.get_shader_parameter("birth_event_states")
	times = process.get_shader_parameter("birth_event_times")
	check("palette changes crossed within one request keep both birth colors", palette.ok
		and process.get_shader_parameter("birth_event_count") == 2 and events.size() == 32 and times.size() == 32
		and events[0].x > 0.9 and events[1].z > 0.9 and times[0] == 0.0 and times[1] > 0.0)
	var node_count := smoke.get_child_count()
	smoke.stop()
	var stopped: Dictionary = smoke.advance(8.0 / 240.0, {"tick": 28, "slot_transforms": transforms}, Vector3.ZERO, 1.0, source_sample)
	check("stop disables new births without reallocation", stopped.ok and not left.emitting and smoke.get_child_count() == node_count)
	smoke.pause()
	var paused: Dictionary = smoke.advance(1.0, {"tick": 268, "slot_transforms": transforms}, Vector3.ZERO, 1.0, source_sample)
	check("pause rebases the deterministic clock without advancing particles", paused.paused and smoke._last_tick == 268)
	smoke.play()
	var resumed: Dictionary = smoke.advance(4.0 / 240.0, {"tick": 272, "slot_transforms": transforms}, Vector3.ZERO, 1.0, source_sample)
	check("resume continues from paused tick without an unbounded bridge", resumed.ok and resumed.interval_ticks == 4)
	smoke.reset()
	check("reset clears schedule and history but keeps the bounded pool", smoke._history.is_empty()
		and smoke._last_tick == -1 and smoke.get_child_count() == node_count and smoke.budget_info().capacity == 768)
	var long_entry: Dictionary = entries[0]
	long_entry.lifetime_s = 7.9
	check("reconfiguration requires the explicit reset boundary", smoke.configure(_profile(entries), bindings))
	var reconfigured: Dictionary = smoke.budget_info()
	check("eight-second life is accepted and stays in the same shared budget",
		float(smoke._emitters["wing_left"].lifetime) == 7.9 and reconfigured.capacity == 768)
	var history_smoke: int = smoke._history.size()
	check("lifetime-derived history stays under its fixed sample cap", history_smoke <= 44)
	for index in 84:
		var tick := 272 + (index + 1) * 24
		smoke.advance(0.1, {"tick": tick, "slot_transforms": transforms, "camera_distance_m": 700.0},
			Vector3(0.0, 1.0, 0.0), 0.0, {"kind": "glow_prop", "running": false, "level": 0.0})
	check("off-camera path remains bounded beyond eight seconds", smoke._history.size() <= 44
		and smoke._emitters["wing_left"].visibility_aabb.size.is_finite())
	smoke.free()
	await process_frame


func _entry(slot: String, kind: String, mode: String) -> Dictionary:
	return {
		"slot": slot,
		"enabled": true,
		"color": "#FFFFFFFF",
		"amount": 1.0,
		"width_m": 0.2,
		"lifetime_s": 2.0,
		"shape": "ribbon",
		"mode": mode,
		"burst_s": 0.0,
		"pulse_period_s": 0.0,
		"pulse_duty": 0.0,
		"palette": [],
		"step_s": 0.0,
	}


func _bindings() -> Dictionary:
	return {"smoke_slots": [
		{"id": "wing_left", "label": "Left wingtip", "kind": "show", "position_m": [0.0, 0.0, 0.0], "direction": [0.0, 0.0, -1.0]},
		{"id": "wing_right", "label": "Right wingtip", "kind": "show", "position_m": [0.0, 0.0, 0.0], "direction": [0.0, 0.0, -1.0]},
		{"id": "tail", "label": "Tail", "kind": "show", "position_m": [0.0, 0.0, 0.0], "direction": [0.0, 0.0, -1.0]},
		{"id": "engine_outlet", "label": "Engine outlet", "kind": "source", "source_kind": "glow_prop",
			"source_anchor_ref": "exhausts[0]", "physical_source_ref": "propulsion.id",
			"physical_source_kind_ref": "propulsion.kind"},
	]}


func _profile(entries: Array[Dictionary]) -> Dictionary:
	return {"schedule_policy": "ticks-240-v1", "visual_seed": 42, "smoke": entries}
