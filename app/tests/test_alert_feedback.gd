## HUD-09-R3: production manager boundaries for motion, sound and automatic safety pause.
extends SceneTree

const Manager := preload("res://render/overlays/overlay_manager.gd")
const UiTheme := preload("res://ui/ui_theme.gd")

var _count := 0
var _failed := 0
var _clock := 0.0
var _cues: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	root.size = Vector2i(1920, 1080)
	var original_motion: bool = UiTheme.reduced_motion
	UiTheme.reduced_motion = false
	var manager := Manager.new({preset = "custom", visible = ["warnings"]}, "en")
	root.add_child(manager)
	manager.alert_audio.set("_clock", func() -> float: return _clock)
	manager.alert_audio.cue_requested.connect(func(cue: String, _code: String) -> void: _cues.append(cue))
	await process_frame
	_sample(manager, [], 0.0)
	_sample(manager, ["far"], 0.5)
	_check("a newly selected caution reaches the shared audio voice", _cues == ["caution"]
		and manager.alert_audio.audio_player().playing)
	_sample(manager, ["stall", "far"], 1.0, true)
	_check("ordinary pause immediately retires flight audio", _cues == ["caution"]
		and not manager.alert_audio.audio_player().playing)
	_sample(manager, ["stall", "far"], 1.5)
	_check("resume establishes a silent baseline instead of replaying missed alerts", _cues == ["caution"])
	manager.reset_flight()
	_check("reset clears the rail and voice immediately", not manager.frames.warnings.visible
		and not manager.frames.warnings.is_presenting() and not manager.alert_audio.audio_player().playing)
	_sample(manager, [], 2.0)
	_sample(manager, ["failsafe"], 2.5, true)
	_check("automatic radio-loss pause still allows its new danger cue", _cues == ["caution", "danger"]
		and manager.frames.warnings.codes == PackedStringArray(["failsafe"]))
	manager.visible = false
	_check("hidden flight layer retires an active cue", not manager.alert_audio.audio_player().playing)
	_sample(manager, ["controller_lost"], 3.0, true)
	manager.visible = true
	_sample(manager, ["controller_lost"], 3.5, true)
	_check("hidden changes never queue a delayed controller-loss sound", _cues == ["caution", "danger"])
	_sample(manager, [], 4.0)
	_check("cleared truth is empty while only its exit glass remains", manager.frames.warnings.codes.is_empty()
		and manager.frames.warnings.chips.get_child_count() == 0 and manager.frames.warnings.visible)
	await create_timer(0.3).timeout
	_check("the last completed silhouette hides the production rail", not manager.frames.warnings.visible
		and not manager.frames.warnings.is_presenting())
	_sample(manager, ["far"], 5.0)
	manager.preview(true)
	_check("menu preview immediately stops playback", not manager.alert_audio.audio_player().playing)
	var before_preview := _cues.size()
	_sample(manager, ["stall"], 6.0)
	_check("menu preview changes are visible and silent", manager.frames.warnings.codes.has("stall")
		and _cues.size() == before_preview)
	manager.preview(false)
	manager.visible = true
	_sample(manager, ["stall"], 7.0)
	_check("leaving preview does not replay its last alert", _cues.size() == before_preview)
	_sample(manager, [], 8.0)
	manager.set_overlay_visible("warnings", false)
	_check("explicit close removes all retiring glass immediately", not manager.frames.warnings.visible
		and not manager.frames.warnings.is_presenting())
	_sample(manager, ["far"], 9.0)
	manager.set_overlay_visible("warnings", true)
	_sample(manager, ["far"], 9.5)
	_check("reopening warnings silently shows the latest selected alert", manager.frames.warnings.codes.has("far")
		and _cues.size() == before_preview)
	_sample(manager, ["stall"], 1.0)
	_check("rewinding accepted flight time retires old audio history", _cues.size() == before_preview
		and not manager.alert_audio.audio_player().playing)
	_check("fuel and other alerts share exactly one bounded voice", manager.find_children("*", "AudioStreamPlayer", true, false).size() == 1
		and manager.alert_audio.audio_player().max_polyphony == 1)
	manager.queue_free()
	await process_frame
	await process_frame
	await create_timer(0.25).timeout # AudioServer releases stopped Ogg playbacks on its next mix blocks.
	UiTheme.reduced_motion = original_motion
	print("alert feedback: %d checks, %d failed" % [_count, _failed])
	quit(1 if _failed else 0)


func _sample(manager: CanvasLayer, codes: Array, at: float, paused := false) -> void:
	_clock = at
	manager.refresh_numbers({telemetry = {time_s = at, airspeed = 20.0},
		warnings = PackedStringArray(codes), paused = paused})


func _check(label: String, passed: bool) -> void:
	_count += 1
	if not passed:
		_failed += 1
		printerr("FAIL ", label)
