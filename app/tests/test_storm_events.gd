extends SceneTree

const StormEvents = preload("res://environment/storm_events.gd")
const Lightning = preload("res://render/weather/lightning.gd")
const StormAudio = preload("res://audio/storm_audio.gd")

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_test_disabled_classic()
	_test_seeded_schedule_and_visual_modes()
	_test_render_cadence_independence()
	_test_global_rng_isolation()
	_test_event_window_bounds()
	await process_frame
	await _test_cloud_mask_contract()
	await _test_repeated_configuration_and_silent_audio()
	await _test_pause_resume_and_restored_thunder()
	print("storm event checks=%d failures=%d" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_disabled_classic() -> void:
	var schedule: StormEvents = StormEvents.new()
	schedule.configure({"preset": "classic", "seed": 42, "tick_rate_hz": 60})
	_check("classic preset disables storm events", not schedule.enabled())
	_check("disabled schedule returns no events", schedule.events_for_window(0, 100000).is_empty())


func _test_seeded_schedule_and_visual_modes() -> void:
	var full: StormEvents = _configured("full")
	var reduced: StormEvents = _configured("reduced")
	var off: StormEvents = _configured("off")
	var full_events: Array[Dictionary] = full.events_for_window(0, 60 * 240)
	var reduced_events: Array[Dictionary] = reduced.events_for_window(0, 60 * 240)
	var off_events: Array[Dictionary] = off.events_for_window(0, 60 * 240)
	_check("electrical storm produces repeatable scheduled events", not full_events.is_empty()
		and full_events == _configured("full").events_for_window(0, 60 * 240))
	_check("Full, Reduced and Off preserve event identity and geometry", full_events == reduced_events and full_events == off_events)
	_check("event records contain the FW-84 identity and sound fields", not full_events.is_empty()
		and full_events[0].has("event_id") and full_events[0].has("appearance_generation")
		and full_events[0].has("start_tick") and full_events[0].has("kind")
		and full_events[0].has("geometry_seed") and full_events[0].has("source_world")
		and full_events[0].has("channel_world") and full_events[0].has("pulse_envelope")
		and full_events[0].has("thunder_asset_id"))
	var other_seed: StormEvents = StormEvents.new()
	other_seed.configure({"preset": "electrical_storm", "seed": 71, "tick_rate_hz": 60, "flashes": "full"})
	var other_events: Array[Dictionary] = other_seed.events_for_window(0, 60 * 240)
	_check("a different visual seed changes the appearance generation", not other_events.is_empty()
		and full_events[0].appearance_generation != other_events[0].appearance_generation)
	var window: Array[Dictionary] = full.events_for_window(1000, 1100)
	var intervals_overlap: bool = true
	for event: Dictionary in window:
		intervals_overlap = intervals_overlap and int(event.start_tick) <= 1100 \
			and int(event.start_tick + ceil(float(event.duration_s) * 60.0)) >= 1000
	_check("active event query returns only intervals overlapping the requested ticks", intervals_overlap)


func _test_render_cadence_independence() -> void:
	var expected: Array[String] = _event_ids_at_cadence(60)
	_check("30 FPS sampling sees the same event IDs", _event_ids_at_cadence(30) == expected)
	_check("144 FPS sampling sees the same event IDs", _event_ids_at_cadence(144) == expected)


func _test_event_window_bounds() -> void:
	var schedule: StormEvents = _configured("full")
	var far_future: Array[Dictionary] = schedule.events_for_window(0, 60 * 60 * 24 * 365)
	_check("a large seek bounds work to the recent event slots", far_future.size() <= StormEvents.MAX_QUERY_SLOTS)
	var recent: Array[Dictionary] = schedule.events_started_in_window(60 * 45, 60 * 47)
	var only_recent_starts: bool = true
	for event: Dictionary in recent:
		only_recent_starts = only_recent_starts and int(event.start_tick) >= 60 * 45 \
			and int(event.start_tick) <= 60 * 47
	_check("restore query returns start events in its inclusive range", only_recent_starts)


func _test_global_rng_isolation() -> void:
	seed(712367)
	var expected: int = randi()
	seed(712367)
	var schedule: StormEvents = _configured("full")
	schedule.events_for_window(0, 60 * 240)
	var observed: int = randi()
	_check("storm schedule queries do not advance the global RNG", observed == expected)


func _event_ids_at_cadence(fps: int) -> Array[String]:
	var schedule: StormEvents = _configured("full")
	var ids: Array[String] = []
	var previous_tick: int = 0
	var frame_count: int = int(120.0 * float(fps))
	for frame: int in frame_count + 1:
		var t: float = float(frame) / float(fps)
		var tick: int = schedule.tick_for_time(t)
		for event: Dictionary in schedule.events_started_between(previous_tick, tick):
			ids.append(str(event.event_id))
		previous_tick = tick
	return ids


func _configured(flashes: String) -> StormEvents:
	var schedule: StormEvents = StormEvents.new()
	schedule.configure({
		"preset": "electrical_storm",
		"seed": 90210,
		"tick_rate_hz": 60,
		"flashes": flashes,
	})
	return schedule


func _test_repeated_configuration_and_silent_audio() -> void:
	var config: Dictionary = _storm_config("off")
	var node: Lightning = Lightning.new()
	root.add_child(node)
	node.set_audio_enabled(false)
	node.configure(config)
	node.update_at(0.0, Vector3.ZERO, false, 1.0)
	var stable_child_count: int = node.get_child_count()
	var audio: StormAudio = node.get_node("StormAudio") as StormAudio
	for iteration: int in 5:
		config.flashes = "reduced" if iteration % 2 == 0 else "full"
		node.configure(config)
		node.update_at(float(iteration + 1), Vector3.ZERO, false, 1.0)
	_check("repeated storm configuration reuses scene resources", node.get_child_count() == stable_child_count)
	_check("audio disabled allocates no thunder players", audio._players.is_empty() and audio.get_child_count() == 0)
	node.queue_free()
	await process_frame
	var audio_only: StormAudio = StormAudio.new()
	root.add_child(audio_only)
	audio_only.configure(_storm_config("full"))
	audio_only.set_audio_enabled(false)
	audio_only.update_at(10.0, Vector3.ZERO, false)
	_check("standalone audio-off remains allocation-free", audio_only._players.is_empty() and audio_only.get_child_count() == 0)
	audio_only.queue_free()
	await process_frame


func _test_cloud_mask_contract() -> void:
	var node: Lightning = Lightning.new()
	root.add_child(node)
	node.set_audio_enabled(false)
	node.configure(_storm_config("off"))
	node.set_cloud_state({
		"cloud_cover": 0.9,
		"cloud_density": 0.4,
		"cloud_layers": [{
			"type": "cumulonimbus",
			"altitude_m": 5200.0,
			"scale_m": 4700.0,
			"offset": Vector2(3.0, 7.0),
			"seed": 791,
			"coverage": 0.6,
			"density": 0.7,
			"cluster_strength": 0.65,
		}],
	})
	var expected_coverage: float = clampf(0.6 + (0.9 - 0.5) * 0.5, 0.0, 1.0)
	var expected_opacity: float = 0.7 * 0.4
	_check("deck coverage applies the profile cover offset once",
		is_equal_approx(node._cloud_coverage, expected_coverage))
	_check("deck opacity multiplies layer density by profile density once",
		is_equal_approx(node._cloud_density_scale, expected_opacity))
	_check("cloud overlay shader receives the effective shared mask values",
		is_equal_approx(float(node._cloud_material.get_shader_parameter("cloud_coverage")), expected_coverage)
		and is_equal_approx(float(node._cloud_material.get_shader_parameter("cloud_density_scale")), expected_opacity))
	_check("cloud flash keeps a localized 4.2 km horizontal falloff",
		is_equal_approx(float(node._cloud_material.get_shader_parameter("flash_radius_m")), 4200.0))
	node.queue_free()
	await process_frame


func _test_pause_resume_and_restored_thunder() -> void:
	var config: Dictionary = _storm_config("off")
	var node: Lightning = Lightning.new()
	root.add_child(node)
	node.configure(config)
	# The application resets the presentation queue on checkpoint restore before it replays the saved time.
	node.reset()
	var schedule: StormEvents = node._events
	var candidates: Array[Dictionary] = schedule.events_started_in_window(0, 60 * 240)
	if candidates.is_empty():
		_check("restore test has a scheduled event", false)
		node.queue_free()
		await process_frame
		return
	var event: Dictionary = candidates[0]
	var event_id: String = str(event.event_id)
	var channel: Vector3 = _as_vector3(event.channel_world)
	var listener: Vector3 = channel + Vector3(29900.0, 0.0, 0.0)
	var now_s: float = float(event.start_time_s) + 0.50
	var delay_s: float = listener.distance_to(channel) / 343.0
	var arrival_s: float = float(event.start_time_s) + delay_s
	node.update_at(now_s, listener, false, 0.7)
	var audio: StormAudio = node.get_node("StormAudio") as StormAudio
	_check("restore reconstructs thunder still travelling after its flash", _pending_count(audio, event_id) == 1)
	node.update_at(now_s, listener, true, 0.7)
	node.update_at(now_s, listener, false, 0.7)
	_check("pause and resume keep exactly one pending thunder", _pending_count(audio, event_id) == 1)
	var time_s: float = now_s
	while time_s < arrival_s + 0.05:
		time_s = minf(time_s + 0.4, arrival_s + 0.05)
		node.update_at(time_s, listener, false, 0.7)
	var heard_channel: bool = false
	for player: AudioStreamPlayer3D in audio._players:
		if player.playing and player.global_position.distance_to(channel) < 0.01:
			heard_channel = true
	_check("restored thunder reaches the pooled voice once after its delay", heard_channel
		and _pending_count(audio, event_id) == 0)
	node.queue_free()
	await process_frame


func _storm_config(flashes: String) -> Dictionary:
	return {
		"preset": "electrical_storm",
		"seed": 90210,
		"tick_rate_hz": 60,
		"flashes": flashes,
		"thunder_volume": 0.7,
	}


func _pending_count(audio: StormAudio, event_id: String) -> int:
	var count: int = 0
	for event: Dictionary in audio._pending:
		if str(event.get("event_id", "")) == event_id:
			count += 1
	return count


func _as_vector3(value: Variant) -> Vector3:
	if value is Vector3:
		return value
	if value is PackedFloat64Array and value.size() >= 3:
		return Vector3(value[0], value[1], value[2])
	return Vector3.ZERO


func _check(label: String, passed: bool) -> void:
	_checks += 1
	if not passed:
		_failures += 1
		printerr("FAIL %s" % label)
