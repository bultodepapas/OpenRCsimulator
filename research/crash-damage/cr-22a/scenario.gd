## Production-scene crash capture/qualification. Run with -- --crash-out=<absolute folder>.
extends SceneTree
const RB = preload("res://physics/rigid_body.gd")
const M = preload("res://physics/math3d.gd")
var flight: Node3D
var frames := 0
var out := ""
var name_id := "ugly"
var timings: Array[float] = []
var effects_times: Array[float] = []
var update_times: Array[float] = []
var _clock := 0
var _snapshot: Array = []
var failures: Array[String] = []
# Keep PNG readback/encoding after the first collision: otherwise a capture
# stall can be mistaken for first-impact shader/physics cost.
var _captures := [36,60,90,240,480]
var _stats: Dictionary = {}
var _capture_audio := false
var _mixer: AudioEffectCapture
var _audio_samples := PackedVector2Array()
var _peak := 0.0
var _impact_frame_ms := 0.0
var _flown := false

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--crash-flown":
			_flown = true
		if arg == "--crash-audio":
			_capture_audio = true
		if arg.begins_with("--crash-out="):
			out = arg.trim_prefix("--crash-out=")
		if arg.begins_with("--crash-name="):
			name_id = arg.trim_prefix("--crash-name=")
	_run.call_deferred()

func _run() -> void:
	Engine.max_fps = 60
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280,720)
	root.position = Vector2i(120,90)
	root.show()
	if out.is_empty():
		push_error("--crash-out required")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(out)
	flight = load("res://main.tscn").instantiate()
	root.add_child(flight)
	flight.session.input_enabled = false
	flight.session.set_physics_process(false)
	flight.session.sim.set_physics_process(false)
	flight._show_perf = false
	flight._inspect = true
	if _capture_audio:
		root.audio_listener_enable_3d = true
		_mixer = AudioEffectCapture.new()
		_mixer.buffer_length = 1.0
		AudioServer.add_bus_effect(0,_mixer)
	_clock = Time.get_ticks_usec()

func _process(_delta: float) -> bool:
	if flight == null:
		return false
	var now := Time.get_ticks_usec()
	if _impact_frame_ms == 0.0 and flight._crash_director != null and flight._crash_director.active:
		_impact_frame_ms = (now-_clock)/1000.0
	if _mixer != null:
		var samples := _mixer.get_buffer(_mixer.get_frames_available())
		_audio_samples.append_array(samples)
		for sample: Vector2 in samples:
			_peak = maxf(_peak,maxf(absf(sample.x),absf(sample.y)))
	if frames > 20:
		timings.append((now-_clock)/1000.0)
		effects_times.append(float(flight._crash_director.effects.last_update_usec))
		update_times.append(float(flight._crash_director.last_update_usec))
	_clock = now
	frames += 1
	if _flown and _snapshot.is_empty() and not flight.session.crash.is_empty():
		_snapshot = observation()
	if frames == 12:
		trigger()
	if frames in _captures and DisplayServer.get_name() != "headless":
		capture.call_deferred(frames)
	if frames == 500:
		_stats = flight._crash_director.stats()
		if flight.session.crash.is_empty():
			failures.append("aftermath auto-restarted")
		if _snapshot != observation():
			failures.append("presentation mutated simulation")
		flight.session.hold("crash-probe")
	if frames == 515:
		flight.session.release("crash-probe")
	if frames == 540:
		flight.session.reset()
		if flight._crash_director.active or not flight._airplane.root.visible:
			failures.append("reset did not restore airplane")
		if flight._crash_director.effects.stats().marks != 0:
			failures.append("reset retained marks")
	if frames == 555:
		trigger()
	if frames == 600:
		finish.call_deferred()
	return false

func trigger() -> void:
	var speed := 40.0 if flight.aircraft_id.contains("avanti") else 22.0
	var pitch := -0.95
	var roll := 0.2
	if name_id == "scrape":
		speed = 3.0
		pitch = -0.03
		roll = 0.0
	elif name_id == "wingtip":
		pitch = -0.12
		roll = 1.0
	var att := M.q_from_euler(roll,pitch,0.55)
	var north := 15.0 if name_id == "scrape" else -25.0
	flight.session.sim.previous = RB.make_state(M.v3(north,-15,-5.0 if _flown else -2.0),M.v3(speed,0,0),att,M.v3(0.4,0.1,0.2))
	flight.session.sim.state = flight.session.sim.previous.duplicate() if _flown else RB.make_state(M.v3(north,-15,0.12),M.v3(speed,0,0),att,M.v3(0.4,0.1,0.2))
	flight.session.sim.set_paused(false)
	if _flown:
		flight.session.set_physics_process(true)
		flight.session.sim.set_physics_process(true)
		_snapshot = []
	else:
		flight.session._physics_process(flight.session.sim.dt())
		_snapshot = observation()

func observation() -> Array:
	var sim: Node = flight.session.sim
	return [sim.state.duplicate(),sim.previous.duplicate(),sim.continuous.duplicate(),sim.aux.duplicate(),sim.modes.duplicate(),sim.tick]

func capture(frame: int) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join("%s-%03d.png" % [name_id,frame]))

func percentile(values: Array[float], p: float) -> float:
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[mini(sorted.size()-1,int(ceil(sorted.size()*p))-1)] if not sorted.is_empty() else 0.0

func finish() -> void:
	if _capture_audio:
		if _peak <= 0.0001:
			failures.append("native master audio missing")
		# Float32 mixer/filter roundoff may overshoot the ceiling by a few ulps.
		if _peak > db_to_linear(-1.0) + 0.00001:
			failures.append("native master exceeds -1 dBFS")
		if _mixer.get_discarded_frames() != 0:
			failures.append("audio capture dropped frames")
		var wav := AudioStreamWAV.new()
		wav.format = AudioStreamWAV.FORMAT_16_BITS
		wav.mix_rate = int(AudioServer.get_mix_rate())
		wav.stereo = true
		var pcm := PackedByteArray()
		pcm.resize(_audio_samples.size()*4)
		for i in _audio_samples.size():
			pcm.encode_s16(i*4,int(clampf(_audio_samples[i].x,-1,1)*32767))
			pcm.encode_s16(i*4+2,int(clampf(_audio_samples[i].y,-1,1)*32767))
		wav.data = pcm
		wav.save_to_wav(out.path_join(name_id+"-master.wav"))
	var result := {case=name_id, aircraft=flight.aircraft_id, godot=Engine.get_version_info().string, adapter=RenderingServer.get_video_adapter_name(), renderer=RenderingServer.get_current_rendering_method(), frames=timings.size(),frame_ms_p50=percentile(timings,0.5),frame_ms_p95=percentile(timings,0.95),frame_ms_p99=percentile(timings,0.99),effects_us_p95=percentile(effects_times,0.95),update_us_p95=percentile(update_times,0.95),stats=_stats,failures=failures, note="60 FPS cap; native frame wall intervals including cap/vsync wait. Scenario kind distinguishes flown from manufactured contacts. Not a physical drop validation."}
	result["first_impact_frame_ms"] = _impact_frame_ms
	result["scenario_kind"] = "flown 5m descending start through production 240Hz solver" if _flown else "manufactured detector interval"
	result["master_audio"] = {captured=_capture_audio,peak=_peak,peak_db=linear_to_db(maxf(_peak,0.000001)),frames=_audio_samples.size(),discarded=_mixer.get_discarded_frames() if _mixer != null else 0}
	result["master_audio"]["peak_linear_tolerance"] = 0.00001
	result["budget"] = {full_scene_p95_ms=33.3,director_p95_us=1500,impact_setup_us=10000,first_impact_frame_ms=50,particles=700,bodies=24,marks=16,splinters=160}
	if result.frame_ms_p95 > 33.3 or result.update_us_p95 > 1500 or _stats.impact_usec > 10000 or _impact_frame_ms > 50:
		failures.append("native frame/CPU budget exceeded")
	if _stats.effects.particles > 700 or _stats.effects.splinters > 160 or _stats.effects.marks > 16 or _stats.wreck.active_body_count > 24:
		failures.append("pool budget exceeded")
	for frame in _captures:
		if not FileAccess.file_exists(out.path_join("%s-%03d.png" % [name_id,frame])):
			failures.append("missing rendered frame %d" % frame)
	FileAccess.open(out.path_join(name_id+".json"),FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	flight.free()
	if _mixer != null:
		AudioServer.remove_bus_effect(0,AudioServer.get_bus_effect_count(0)-1)
	await process_frame
	print(JSON.stringify(result))
	quit(1 if not failures.is_empty() else 0)
