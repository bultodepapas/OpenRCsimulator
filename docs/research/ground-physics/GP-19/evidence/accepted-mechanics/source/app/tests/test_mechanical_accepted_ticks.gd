extends SceneTree

const Audio := preload("res://audio/mechanical_audio.gd")
const Motion := preload("res://audio/mechanical_motion.gd")
var checks := 0
var failed := 0

func check(label: String, passed: bool, detail := "") -> void:
	checks += 1
	if not passed:
		failed += 1
		printerr("FAIL ", label, " ", detail)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_edges()
	_lifecycle()
	_bounds()
	await _playback()
	print("Accepted mechanical ticks: %d checks, %d failed" % [checks, failed])
	quit(1 if failed else 0)

func _snapshot(tick: int, angle := 0.0, extension := 0.0, target := true, paused := false) -> Dictionary:
	return {tick = tick, tick_rate = 240.0, paused = paused,
		channels = [{id = "aileron", angle_deg = angle, position = Vector3(2.0, 0.0, 0.0)}],
		gear = {available = true, extension = extension, target_down = target, position = Vector3(3.0, 0.0, 0.0)},
		listener = Vector3.ZERO, engine_mask = 1.0}

func _keys(events: Array) -> Array:
	var found: Array = []
	for event: Dictionary in events: found.append(str(event.system) + ":" + str(event.event))
	return found

func _observer() -> Node:
	var audio := Audio.new()
	audio.set_accepted_tick_observation(true)
	return audio

func _edges() -> void:
	var audio := _observer()
	var first := _snapshot(0)
	check("explicit mode primes accepted tick zero", audio.observe_accepted(first))
	check("capture semantics carry an explicit presentation-law identity", audio.diagnostics().accepted_observation_law == Audio.ACCEPTED_OBSERVATION_LAW)
	var old := Motion.observe({}, first)
	audio.observe_accepted(_snapshot(1, 4.0, 0.2))
	audio.observe_accepted(_snapshot(2, 0.0, 0.1))
	audio.observe_accepted(_snapshot(3, 0.0, 0.1))
	var only_render := Motion.observe(old.state, _snapshot(3, 0.0, 0.1))
	check("retained frame-only reproduction misses servo reversal and stop", _keys(only_render.events) == ["gear:start"])
	var state_bytes := var_to_bytes(audio.get("_accepted_motion_state"))
	var result: Dictionary = audio.call("_accepted_result", _snapshot(3, 0.0, 0.1))
	check("all accepted start reverse stop edges survive one render frame", _keys(result.events) == ["servo:start", "gear:start", "servo:reverse", "gear:reverse", "servo:stop", "gear:stop"])
	check("edges retain actual endpoint ticks", result.events[0].accepted_tick == 1 and result.events[2].accepted_tick == 2 and result.events[4].accepted_tick == 3)
	check("final motion levels are stopped despite queued transient history", not result.channels[0].moving and not result.gear.moving)
	check("start speed derives from one accepted interval", result.events[0].speed_per_s == 960.0)
	check("drained batch counts once", audio.diagnostics().accepted_events_observed == 6 and audio.diagnostics().accepted_events_drained == 6 and audio.diagnostics().accepted_pending_event_count == 0)
	result.events[0].event = "modified"
	result.channels[0].value = 999.0
	check("render result is detached from accepted history", state_bytes == var_to_bytes(audio.get("_accepted_motion_state")))
	result = audio.call("_accepted_result", _snapshot(3, 22.0, 0.9))
	check("render-only values cannot change accepted motion or retrigger", result.events.is_empty() and not result.tick_advanced and result.channels[0].value == 0.0 and result.gear.value == 0.1)
	check("duplicate accepted delivery is a no-op", audio.observe_accepted(_snapshot(3, 88.0, 0.8)) and audio.diagnostics().accepted_tick_samples == 4)
	result = audio.call("_accepted_result", _snapshot(3))
	check("duplicate tick cannot replace accepted values", result.channels[0].value == 0.0 and result.gear.value == 0.1)
	audio.observe_accepted(_snapshot(4, 0.0, 0.1, false))
	check("request-only accepted tick remains silent", audio.call("_accepted_result", _snapshot(4, 0.0, 0.1, false)).events.is_empty())
	audio.observe_accepted(_snapshot(5, 0.0, 0.0, false))
	audio.observe_accepted(_snapshot(6, 0.0, 0.0, false))
	result = audio.call("_accepted_result", _snapshot(6, 0.0, 0.0, false))
	check("arrival and subsequent accepted stop produce one lock", _keys(result.events) == ["gear:start", "gear:lock"])
	check("current presentation source positions refresh", result.gear.position == Vector3(3.0, 0.0, 0.0))
	audio.free()

func _lifecycle() -> void:
	var audio := _observer()
	audio.observe_accepted(_snapshot(0))
	audio.observe_accepted(_snapshot(1, 4.0))
	var paused: Dictionary = audio.call("_accepted_result", _snapshot(1, 4.0, 0.0, true, true))
	check("pause discards queued edges and primes stationary history", paused.primed and paused.events.is_empty() and not paused.channels[0].moving
		and audio.diagnostics().accepted_events_discarded == 1)
	audio.observe_accepted(_snapshot(2, 4.0))
	check("resume does not replay paused motion", audio.call("_accepted_result", _snapshot(2, 4.0)).events.is_empty())
	audio.observe_accepted(_snapshot(3, 5.0))
	audio.observe_accepted(_snapshot(10, -2.0))
	var result: Dictionary = audio.call("_accepted_result", _snapshot(10, -2.0))
	check("missing accepted ticks discard stale transitions and prime", result.primed and result.events.is_empty() and audio.diagnostics().accepted_discontinuities == 1)
	audio.observe_accepted(_snapshot(11, -3.0))
	audio.observe_accepted(_snapshot(2, 30.0))
	result = audio.call("_accepted_result", _snapshot(2, 30.0))
	check("rewind primes without replay", result.primed and result.events.is_empty() and audio.diagnostics().accepted_discontinuities == 2)
	var changed_rate := _snapshot(3, 40.0)
	changed_rate.tick_rate = 480.0
	audio.observe_accepted(changed_rate)
	check("clock-rate change cannot create an invented velocity", audio.call("_accepted_result", changed_rate).primed)
	changed_rate = _snapshot(4, 41.0)
	changed_rate.tick_rate = 480.0
	audio.observe_accepted(changed_rate)
	changed_rate.tick_rate = 240.0
	audio.observe_accepted(changed_rate)
	result = audio.call("_accepted_result", changed_rate)
	check("same-tick clock replacement discards old-rate transitions", result.primed and result.events.is_empty() and not result.channels[0].moving)
	audio.reset()
	check("reset preserves capture mode and clears history", audio.diagnostics().accepted_tick_observation and audio.diagnostics().accepted_pending_event_count == 0)
	check("render cannot bootstrap unaccepted history", not audio.call("_accepted_result", _snapshot(0)).valid)
	audio.observe_accepted(_snapshot(0))
	audio.observe_accepted(_snapshot(1, 2.0))
	check("future render tick refuses stale accepted packet", not audio.call("_accepted_result", _snapshot(2, 2.0)).valid)
	check("refusal clears old queued cues", audio.diagnostics().accepted_pending_event_count == 0)
	audio.reset()
	audio.observe_accepted(_snapshot(0))
	audio.observe_accepted(_snapshot(1, 2.0))
	var tick_count: int = audio.diagnostics().accepted_tick_samples
	audio.observe_accepted(_snapshot(1, 2.0, 0.0, true, true))
	audio.observe_accepted(_snapshot(1, 2.0, 0.0, true, false))
	result = audio.call("_accepted_result", _snapshot(1, 2.0))
	check("pause and resume between renders cancel stale cues", result.events.is_empty() and result.primed and not result.channels[0].moving)
	check("pause notification does not invent another accepted tick", audio.diagnostics().accepted_tick_samples == tick_count)
	audio.observe_accepted(_snapshot(2, 4.0, 0.0, true, true))
	result = audio.call("_accepted_result", _snapshot(2, 4.0, 0.0, true, true))
	check("manual paused step tracks actual positions silently", result.channels[0].value == 4.0 and result.events.is_empty() and result.primed)
	audio.observe_accepted(_snapshot(2, 4.0))
	check("resume does not play manual-step movement", audio.call("_accepted_result", _snapshot(2, 4.0)).events.is_empty())
	audio.set_accepted_tick_observation(false)
	check("disabled accepted mode does not capture", not audio.observe_accepted(_snapshot(0)))
	audio.free()

func _bounds() -> void:
	var audio := _observer()
	for value: Variant in [null, true, -1, 0.5, "1", [], {}]:
		var malformed := _snapshot(0)
		malformed.tick = value
		check("malformed accepted tick refuses cleanly", not audio.observe_accepted(malformed))
	for value: Variant in [null, true, 0.0, -1.0, INF, NAN, 1e308, "240", [], {}]:
		var malformed := _snapshot(0)
		malformed.tick_rate = value
		check("malformed accepted clock refuses cleanly", not audio.observe_accepted(malformed))
	var malformed := _snapshot(0)
	malformed.paused = 1
	check("malformed pause refuses cleanly", not audio.observe_accepted(malformed))
	audio.observe_accepted(_snapshot(0))
	for tick in range(1, 101): audio.observe_accepted(_snapshot(tick, 1.0 if tick % 2 == 1 else -1.0))
	var diag: Dictionary = audio.diagnostics()
	check("unrendered transition history has a fixed bound", diag.accepted_pending_event_count == Audio.MAX_ACCEPTED_EVENTS)
	check("overflow is explicit and retains newest transitions", diag.accepted_events_overflowed == 100 - Audio.MAX_ACCEPTED_EVENTS)
	var result: Dictionary = audio.call("_accepted_result", _snapshot(100, -1.0))
	check("bounded batch is ordered through most recent tick", result.events.size() == Audio.MAX_ACCEPTED_EVENTS
		and result.events[0].accepted_tick == 37 and result.events[-1].accepted_tick == 100)
	audio.free()

func _playback() -> void:
	var rig := Node3D.new()
	root.add_child(rig)
	var audio := Audio.new()
	audio.configure(rig, &"Master", {servo_type = "standard", servo_level = 1.0, retract_type = "electric"})
	audio.set_accepted_tick_observation(true)
	audio.observe_accepted(_snapshot(0))
	audio.update_sound(_snapshot(0), 1.0 / 60.0)
	audio.observe_accepted(_snapshot(1, 1.0))
	audio.observe_accepted(_snapshot(2, -1.0))
	audio.observe_accepted(_snapshot(3, -1.0))
	audio.update_sound(_snapshot(3, -1.0), 1.0 / 60.0)
	check("real existing playback consumes all queued transitions", audio.diagnostics().accepted_events_drained == 3)
	var observed: int = audio.diagnostics().accepted_events_observed
	var drained: int = audio.diagnostics().accepted_events_drained
	var queued_or_played: int = audio.diagnostics().events_played + audio.diagnostics().pending_event_count
	audio.update_sound(_snapshot(3, -1.0), 1.0 / 60.0)
	check("duplicate render never replays accepted batch", audio.diagnostics().accepted_events_observed == observed
		and audio.diagnostics().accepted_events_drained == drained
		and audio.diagnostics().events_played + audio.diagnostics().pending_event_count == queued_or_played)
	audio.observe_accepted(_snapshot(4, 1.0))
	audio.update_sound(_snapshot(4, 1.0), 1.0 / 60.0)
	for i in 40: audio.update_sound(_snapshot(4, 1.0), 1.0 / 60.0)
	check("stale accepted motion fades to silence", audio.diagnostics().last_targets.active_motion_voices == 0)
	audio.observe_accepted(_snapshot(5, 2.0))
	audio.update_sound(_snapshot(5, 2.0), 1.0 / 60.0)
	check("fresh accepted tick resumes real motion", audio.diagnostics().last_targets.active_motion_voices > 0)
	audio.observe_accepted(_snapshot(6, -2.0))
	var distant := _snapshot(6, -2.0)
	distant.listener = Vector3(1000.0, 0.0, 0.0)
	audio.update_sound(distant, 1.0 / 60.0)
	check("distance culling discards queued transients", audio.diagnostics().accepted_pending_event_count == 0 and audio.diagnostics().last_targets.far_culled)
	check("existing voice bounds stay intact", audio.diagnostics().motion_voice_count <= Audio.MAX_MOTION_VOICES
		and audio.diagnostics().event_voice_count <= Audio.MAX_EVENT_VOICES)
	rig.remove_child(audio)
	check("detach clears queued observation history", audio.diagnostics().accepted_pending_event_count == 0 and audio.get("_accepted_motion_state").is_empty())
	audio.free()
	rig.queue_free()
	await process_frame
