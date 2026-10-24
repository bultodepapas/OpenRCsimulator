# UI-28: native output and closing-tail qualification; records the mixer, never a microphone.
extends SceneTree

const MenuSounds = preload("res://ui/menu_audio.gd")
const CUES: Array[StringName] = [&"focus", &"hover", &"press", &"select", &"change",
	&"open", &"back", &"pause", &"resume", &"accept", &"saved", &"cancel", &"restart", &"reject", &"exit", &"quit"]
var out := ""
var quit_only := false
var report: Dictionary = {}

class QuitTailApp extends "res://app_root.gd":
	var quit_calls := 0
	var quit_at_msec := -1
	var quit_recorder: AudioEffectRecord
	func _ready() -> void:
		menu_audio = MenuSounds.attach(self, func() -> Control: return null)
	func _request_app_quit() -> void:
		quit_calls += 1
		quit_at_msec = Time.get_ticks_msec()
		quit_recorder.set_recording_active(false) # measure only what precedes the production quit seam

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): out = arg.trim_prefix("--out=")
		elif arg == "--quit-only": quit_only = true
	run.call_deferred()

func run() -> void:
	if out.is_empty() or DirAccess.dir_exists_absolute(out) or AudioServer.get_driver_name() == "Dummy":
		printerr("Use a native audio driver and --out=<new directory>")
		quit(1)
		return
	if DirAccess.make_dir_recursive_absolute(out) != OK:
		printerr("Cannot create output directory: ", out)
		quit(1)
		return
	report = {driver = AudioServer.get_driver_name(), captures = [], cues = [], quit_tails = []}
	var host := Node.new()
	root.add_child(host)
	var service := MenuSounds.attach(host, func() -> Control: return null)
	var recorder := AudioEffectRecord.new()
	recorder.format = AudioStreamWAV.FORMAT_16_BITS
	AudioServer.add_bus_effect(0, recorder)
	await create_timer(0.2).timeout
	for level: float in ([] if quit_only else [0.35, 1.0, 0.0]):
		service.set_volume(level)
		recorder.set_recording_active(true)
		await create_timer(0.15).timeout
		for cue: StringName in CUES:
			report.cues.append({cue = String(cue), level = level, accepted = service.play(cue)})
			await create_timer(0.5).timeout
		recorder.set_recording_active(false)
		_capture(recorder, "menu-%d" % roundi(level * 100.0))
	# Use the production quit transaction without actually closing this probe.
	var original_time_scale := Engine.time_scale
	for time_scale: float in [1.0, 0.0, 16.0]:
		var app := QuitTailApp.new()
		app.quit_recorder = recorder
		root.add_child(app)
		var surface := preload("res://ui/screen.gd").new()
		app.screens.push("home", surface)
		app.menu_audio.set_volume(0.35)
		Engine.time_scale = time_scale
		recorder.set_recording_active(true)
		var started := Time.get_ticks_msec()
		app.quit_app()
		app.quit_app()
		var expected_ms: float = app.menu_audio.shutdown_delay() * 1000.0
		var waited := app.quit_calls == 0 and app._quit_audio_pending
		var input_locked := surface.mouse_behavior_recursive == Control.MOUSE_BEHAVIOR_DISABLED \
			and surface.focus_behavior_recursive == Control.FOCUS_BEHAVIOR_DISABLED
		await create_timer(0.65, true, false, true).timeout
		recorder.set_recording_active(false)
		_capture(recorder, "quit-tail-%d" % roundi(time_scale))
		report.quit_tails.append({time_scale = time_scale, waited = waited, input_locked = input_locked,
			calls = app.quit_calls, elapsed_ms = app.quit_at_msec - started if app.quit_at_msec >= 0 else -1,
			expected_ms = expected_ms})
		app.queue_free()
		Engine.time_scale = original_time_scale
		await process_frame
	service.set_volume(0.0)
	host.queue_free()
	AudioServer.remove_bus_effect(0, AudioServer.get_bus_effect_count(0) - 1)
	var ok := true
	for tail: Dictionary in report.quit_tails:
		ok = ok and bool(tail.waited) and bool(tail.input_locked) and int(tail.calls) == 1
		ok = ok and float(tail.elapsed_ms) >= float(tail.expected_ms) - 20.0 \
			and float(tail.elapsed_ms) <= float(tail.expected_ms) + 120.0
	for capture: Dictionary in report.captures:
		ok = ok and int(capture.error) == OK and float(capture.peak) < 0.95
		ok = ok and (int(capture.nonzero) == 0 if capture.name == "menu-0" else int(capture.nonzero) > 0)
		if String(capture.name).begins_with("quit-tail"):
			ok = ok and float(capture.tail_silence_ms) >= 15.0
	for event: Dictionary in report.cues:
		ok = ok and bool(event.accepted)
	report.ok = ok
	var file := FileAccess.open(out.path_join("report.json"), FileAccess.WRITE)
	if file == null:
		printerr("Cannot write report: ", FileAccess.get_open_error())
		quit(1)
		return
	file.store_string(JSON.stringify(report, "\t") + "\n")
	file.close()
	print("Menu native audio: ", JSON.stringify(report))
	await create_timer(0.2).timeout
	quit(0 if ok else 1)

func _capture(recorder: AudioEffectRecord, name: String) -> void:
	var sample: AudioStreamWAV = recorder.get_recording()
	if sample == null:
		report.captures.append({name = name, error = ERR_INVALID_DATA, peak = 0.0, nonzero = 0, tail_silence_ms = 0.0})
		return
	var error := sample.save_to_wav(out.path_join(name + ".wav"))
	var peak := 0.0
	var sum_squared := 0.0
	var nonzero := 0
	var last_nonzero := -1
	var pcm := sample.data
	for offset: int in range(0, pcm.size(), 2):
		var value := float(pcm.decode_s16(offset)) / 32768.0
		peak = maxf(peak, absf(value))
		sum_squared += value * value
		if value != 0.0:
			nonzero += 1
			last_nonzero = offset / 2
	var samples := pcm.size() / 2
	var samples_per_second := float(sample.mix_rate * (2 if sample.stereo else 1))
	report.captures.append({name = name, error = error, rate = sample.mix_rate,
		seconds = float(samples) / samples_per_second,
		tail_silence_ms = float(samples - last_nonzero - 1) / samples_per_second * 1000.0,
		peak = peak, rms = sqrt(sum_squared / maxf(1.0, samples)), nonzero = nonzero})
