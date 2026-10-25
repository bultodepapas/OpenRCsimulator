## Committed Quit drains menu playback even when the Dummy backend has no audible tail.
extends SceneTree

class ShortTail extends "res://ui/menu_audio.gd":
	func shutdown_delay() -> float:
		return 0.03


class QuitProbe extends "res://app_root.gd":
	var quit_requests := 0
	var force_tail := false
	var retired_at_quit := false

	func _ready() -> void:
		if force_tail:
			menu_audio = ShortTail.new()
			add_child(menu_audio)
		else:
			menu_audio = MenuSounds.attach(self, func() -> Control: return null)
		menu_audio.set_volume(0.35)

	func _request_app_quit() -> void:
		quit_requests += 1
		retired_at_quit = menu_audio._voices.all(func(voice: AudioStreamPlayer) -> bool:
			return not voice.playing and voice.stream == null)


var _failures := 0
var _checks := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(label: String, condition: bool) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL ", label)
	else:
		print("ok   ", label)


func _wait_quit(app: QuitProbe) -> bool:
	var deadline := Time.get_ticks_usec() + 2_000_000
	while app.quit_requests == 0 and Time.get_ticks_usec() < deadline:
		await process_frame
	return app.quit_requests == 1


func _run() -> void:
	_check("retirement regression uses the Dummy driver", AudioServer.get_driver_name() == "Dummy")
	var app := QuitProbe.new()
	root.add_child(app)
	app.menu_audio.play(&"accept")
	app.menu_audio.play(&"restart")
	_check("fixture includes a pending semantic fade", app.menu_audio._voice_fades.any(func(fade: Tween) -> bool: return fade != null))
	var original_time_scale := Engine.time_scale
	Engine.time_scale = 0.0
	app.quit_app()
	app.quit_app()
	app._commit_app_quit() # repeated finalization is guarded too
	var finished := await _wait_quit(app)
	Engine.time_scale = original_time_scale
	_check("actual commit reaches final quit once after an unmuted cue", finished and app.menu_audio.cue_count(&"quit") == 1)
	_check("actual quit seam sees cleared players and expired playback refs", app.retired_at_quit
		and app.last_quit_audio_retirement.get("complete", false)
		and not app.last_quit_audio_retirement.get("timed_out", true)
		and app.last_quit_audio_retirement.get("pending_playbacks", -1) == 0
		and app.last_quit_audio_retirement.get("captured_playbacks", 0) > 0)
	_check("shutdown cancels every pending fade", app.menu_audio._voice_fades.all(func(fade: Tween) -> bool: return fade == null))
	app.free()
	await process_frame

	# A short declared audible tail verifies coordinator timing independently of an output device.
	var tail := QuitProbe.new()
	tail.force_tail = true
	root.add_child(tail)
	var tail_started := Time.get_ticks_usec()
	Engine.time_scale = 0.0
	tail.quit_app()
	_check("declared audible tail keeps playback until its wall deadline", tail.quit_requests == 0
		and tail.menu_audio._voices.any(func(voice: AudioStreamPlayer) -> bool: return voice.playing))
	var tail_finished := await _wait_quit(tail)
	Engine.time_scale = original_time_scale
	_check("tail and mixer retirement finish with simulation time stopped", tail_finished
		and Time.get_ticks_usec() - tail_started >= 30_000
		and tail.last_quit_audio_retirement.get("complete", false))
	tail.free()
	await process_frame

	var silent := QuitProbe.new()
	root.add_child(silent)
	silent.menu_audio.set_volume(0.0)
	silent.quit_app()
	_check("no playback closes synchronously without a permanent drain delay", silent.quit_requests == 1
		and silent.last_quit_audio_retirement.get("captured_playbacks", -1) == 0
		and silent.last_quit_audio_retirement.get("complete", false))
	silent.quit_app()
	_check("silent committed quit also coalesces duplicate requests", silent.quit_requests == 1)
	silent.free()
	await process_frame

	# An external strong observer intentionally prevents one playback from expiring.
	var blocked := QuitProbe.new()
	root.add_child(blocked)
	blocked.menu_audio.play(&"accept")
	var held_playback: AudioStreamPlayback = blocked.menu_audio._voices[0].get_stream_playback()
	var held_ref: WeakRef = weakref(held_playback)
	blocked.quit_app()
	var bounded := await _wait_quit(blocked)
	_check("retained playback produces a finite timeout report before quit", bounded
		and not blocked.last_quit_audio_retirement.get("complete", true)
		and blocked.last_quit_audio_retirement.get("timed_out", false)
		and blocked.last_quit_audio_retirement.get("pending_playbacks", 0) > 0
		and blocked.last_quit_audio_retirement.get("elapsed_usec", 0) >= blocked.QUIT_AUDIO_RETIRE_TIMEOUT_USEC)
	held_playback = null
	blocked.free()
	var deadline := Time.get_ticks_usec() + 1_000_000
	while held_ref.get_ref() != null and Time.get_ticks_usec() < deadline:
		await process_frame
	_check("timeout fixture releases its deliberate strong observer", held_ref.get_ref() == null)
	print("Quit audio retirement: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
