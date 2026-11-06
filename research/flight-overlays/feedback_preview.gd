## HUD-09-R3 review fixture: production alert rail and audio, no simulation state.
## Always pass --out=<new absolute directory>. For real mixer evidence use a native
## WASAPI driver and --record-audio, without --fixed-fps or --write-movie. It records
## a default and a Master-muted pass with AudioEffectRecord. For a visual movie use
## --write-movie and --fixed-fps externally, without --record-audio; the injected
## presentation clock then follows the fixed frame delta. Output stays outside app/.
extends SceneTree

const WarningsBar := preload("res://render/overlays/warnings_bar.gd")
const AlertAudio := preload("res://render/overlays/alert_audio.gd")
const UiTheme := preload("res://ui/ui_theme.gd")
const DURATION_S := 8.2
const STAGES := [
	{"at": 0.0, "label": "Clear", "codes": []},
	{"at": 0.5, "label": "Model notice", "codes": ["experimental"]},
	{"at": 1.8, "label": "Range reminder", "codes": ["far", "experimental"]},
	{"at": 3.1, "label": "Critical warning", "codes": ["stall", "far", "experimental"]},
	{"at": 4.5, "label": "Critical warning clears", "codes": ["far", "experimental"]},
	{"at": 5.7, "label": "Range reminder clears", "codes": ["experimental"]},
	{"at": 7.1, "label": "Alerts clear", "codes": []},
	{"at": 7.5, "label": "All clear", "codes": []},
]

var _out := ""
var _record_audio := false
var _elapsed := 0.0
var _pass_name := ""
var _events: Array = []
var _bar: Control
var _audio: Node
var _status: Label
var _timer: Label
var _layer: CanvasLayer


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): _out = arg.trim_prefix("--out=")
		elif arg == "--record-audio": _record_audio = true
	_run.call_deferred()


func _run() -> void:
	if _out.is_empty() or not _out.is_absolute_path() or DirAccess.dir_exists_absolute(_out) or FileAccess.file_exists(_out):
		printerr("Use --out=<new absolute directory>")
		quit(1)
		return
	if _record_audio and AudioServer.get_driver_name() != "WASAPI":
		printerr("--record-audio requires the native WASAPI driver")
		quit(1)
		return
	if _record_audio:
		for arg: String in OS.get_cmdline_args():
			if arg in ["--fixed-fps", "--write-movie"] or arg.begins_with("--fixed-fps=") or arg.begins_with("--write-movie="):
				printerr("Native recording requires real time; omit --fixed-fps and --write-movie")
				quit(1)
				return
	if DirAccess.make_dir_recursive_absolute(_out) != OK:
		printerr("Cannot create output directory: ", _out)
		quit(1)
		return
	await process_frame
	root.size = Vector2i(1920, 1080)
	_build_scene()
	for i in 3: await process_frame
	var bus := AudioServer.get_bus_index(&"Master")
	var old_mute := AudioServer.is_bus_mute(bus)
	var old_db := AudioServer.get_bus_volume_db(bus)
	AudioServer.set_bus_mute(bus, false)
	AudioServer.set_bus_volume_db(bus, 0.0)
	var recorder: AudioEffectRecord = null
	var effect_index := -1
	if _record_audio:
		recorder = AudioEffectRecord.new()
		recorder.format = AudioStreamWAV.FORMAT_16_BITS
		effect_index = AudioServer.get_bus_effect_count(bus)
		AudioServer.add_bus_effect(bus, recorder)
		await create_timer(0.2).timeout
	var passes: Array = []
	passes.append(await _run_pass("default", recorder))
	if _record_audio:
		_audio.retire_playbacks()
		await create_timer(0.35).timeout # let the unmuted mixer release the last tail
		AudioServer.set_bus_mute(bus, true)
		AudioServer.set_bus_volume_db(bus, -80.0)
		passes.append(await _run_pass("master-muted", recorder))
	AudioServer.set_bus_volume_db(bus, old_db)
	AudioServer.set_bus_mute(bus, old_mute)
	_audio.retire_playbacks()
	if effect_index >= 0: AudioServer.remove_bus_effect(bus, effect_index)
	var ok := _passes_ok(passes)
	var report := {
		"ok": ok, "driver": AudioServer.get_driver_name(), "platform": OS.get_name(),
		"engine": Engine.get_version_info(), "viewport": [root.size.x, root.size.y],
		"record_audio": _record_audio, "duration_s": DURATION_S, "passes": passes,
		"note": "Production rail and reused OGGs; logical cues and mixer PCM do not establish speaker or hardware audibility.",
	}
	var file := FileAccess.open(_out.path_join("report.json"), FileAccess.WRITE)
	if file == null:
		printerr("Cannot write report: ", FileAccess.get_open_error())
		ok = false
	else:
		file.store_string(JSON.stringify(report, "\t") + "\n")
		file.close()
	print("Alert feedback preview: ", JSON.stringify(report))
	_layer.queue_free()
	await process_frame
	await process_frame
	# Fixed-FPS movies may render 8.2 simulated seconds in milliseconds. Mixer
	# retirement still needs actual wall time before the process exits.
	OS.delay_msec(150)
	quit(0 if ok else 1)


func _build_scene() -> void:
	_layer = CanvasLayer.new()
	root.add_child(_layer)
	var surface := Control.new()
	surface.name = "FeedbackPreview"
	surface.set_anchors_preset(Control.PRESET_FULL_RECT)
	surface.theme = UiTheme.build()
	_layer.add_child(surface)
	var background := ColorRect.new()
	background.name = "NeutralBackground"
	background.color = Color("#1D2229")
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	surface.add_child(background)
	var title := Label.new()
	title.text = "FLIGHT ALERTS"
	title.position = Vector2(640, 300)
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color("#B5BEC7"))
	surface.add_child(title)
	_status = Label.new()
	_status.position = Vector2(640, 334)
	_status.add_theme_font_size_override("font_size", 16)
	_status.add_theme_color_override("font_color", Color("#8E9AA6"))
	surface.add_child(_status)
	_bar = WarningsBar.new()
	_bar.position = Vector2(640, 390)
	_bar.configure({"warning_detail": true, "warning_limit": 3, "warning_motion": "playful"})
	_bar.presentation_changed.connect(func() -> void:
		if _bar.codes.is_empty(): _bar.visible = false)
	surface.add_child(_bar)
	_timer = Label.new()
	_timer.position = Vector2(640, 760)
	_timer.add_theme_font_size_override("font_size", 15)
	_timer.add_theme_color_override("font_color", Color("#74818D"))
	surface.add_child(_timer)
	_audio = AlertAudio.new(func() -> float: return _elapsed)
	_audio.configure({"warning_sound": true, "warning_volume": 0.55, "warning_clear_sound": true})
	_audio.cue_requested.connect(func(cue: String, code: String) -> void:
		_events.append({"cue": cue, "code": code, "time_s": _elapsed}))
	_layer.add_child(_audio)


func _run_pass(name: String, recorder: AudioEffectRecord) -> Dictionary:
	_pass_name = name
	_elapsed = 0.0
	_events = []
	_audio.reset()
	_bar.clear_immediate()
	_bar.visible = false
	var transitions: Array = []
	var stage_index := 0
	_apply_stage(STAGES[0], transitions)
	if recorder != null:
		recorder.set_recording_active(true)
		await create_timer(0.15).timeout
	var started_usec := Time.get_ticks_usec()
	while _elapsed < DURATION_S:
		await process_frame
		if recorder != null:
			_elapsed = float(Time.get_ticks_usec() - started_usec) / 1000000.0
		else:
			_elapsed += root.get_process_delta_time()
		while stage_index + 1 < STAGES.size() and _elapsed >= float(STAGES[stage_index + 1].at):
			stage_index += 1
			_apply_stage(STAGES[stage_index], transitions)
		_audio.observe(PackedStringArray(STAGES[stage_index].codes), _elapsed, true)
		_timer.text = "%04.1f s" % _elapsed
	var capture := {}
	if recorder != null:
		recorder.set_recording_active(false)
		capture = _capture(recorder, name)
	return {"name": name, "transitions": transitions, "cues": _events.duplicate(true),
		"elapsed_s": _elapsed, "wall_s": float(Time.get_ticks_usec() - started_usec) / 1000000.0,
		"capture": capture}


func _apply_stage(stage: Dictionary, transitions: Array) -> void:
	var codes := PackedStringArray(stage.codes)
	if not codes.is_empty(): _bar.visible = true
	if not _bar.refresh(codes): _bar.visible = false
	_status.text = str(stage.label)
	transitions.append({"target_s": stage.at, "observed_s": _elapsed, "codes": Array(codes)})


func _capture(recorder: AudioEffectRecord, name: String) -> Dictionary:
	var sample := recorder.get_recording()
	if sample == null: return {"error": ERR_INVALID_DATA, "nonzero": 0}
	var error := sample.save_to_wav(_out.path_join(name + ".wav"))
	var pcm := sample.data
	var peak := 0.0
	var sum_squared := 0.0
	var nonzero := 0
	for offset: int in range(0, pcm.size(), 2):
		var value := float(pcm.decode_s16(offset)) / 32768.0
		peak = maxf(peak, absf(value))
		sum_squared += value * value
		if value != 0.0: nonzero += 1
	var samples := pcm.size() / 2
	return {"error": error, "rate": sample.mix_rate, "stereo": sample.stereo,
		"seconds": float(samples) / float(sample.mix_rate * (2 if sample.stereo else 1)),
		"peak": peak, "rms": sqrt(sum_squared / maxf(1.0, samples)), "nonzero": nonzero}


func _passes_ok(passes: Array) -> bool:
	if passes.size() != (2 if _record_audio else 1): return false
	for pass_result: Dictionary in passes:
		if pass_result.transitions.size() != STAGES.size() or float(pass_result.elapsed_s) < DURATION_S: return false
		var actual: Array = []
		for event: Dictionary in pass_result.cues: actual.append(event.cue)
		if pass_result.name == "default" and actual != ["info", "caution", "danger", "cleared"]: return false
		if pass_result.name == "master-muted" and not actual.is_empty(): return false
		if _record_audio:
			var capture: Dictionary = pass_result.capture
			if int(capture.get("error", FAILED)) != OK or float(capture.get("peak", 1.0)) >= 0.95: return false
			if pass_result.name == "default" and int(capture.get("nonzero", 0)) <= 0: return false
			if pass_result.name == "master-muted" and int(capture.get("nonzero", -1)) != 0: return false
	return true
