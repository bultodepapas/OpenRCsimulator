## Headless semantic/lifecycle checks only: cue_requested records a logical request,
## not proof that a device produced sound. The injected wall clock makes gaps exact.
extends SceneTree

const Director := preload("res://render/overlays/alert_audio.gd")
var director: Node
var clock := {"wall": 0.0}
var cues: Array = []
var previews: Array = []
var checks := 0
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var bus := AudioServer.get_bus_index(&"Master")
	var old_mute := AudioServer.is_bus_mute(bus)
	var old_db := AudioServer.get_bus_volume_db(bus)
	AudioServer.set_bus_mute(bus, false)
	AudioServer.set_bus_volume_db(bus, 0.0)
	director = Director.new(func() -> float: return float(clock.wall))
	root.add_child(director)
	director.cue_requested.connect(func(cue: String, code: String) -> void: cues.append([cue, code]))
	director.preview_requested.connect(func(cue: String) -> void: previews.append(cue))
	_streams_and_priority()
	_global_gap_and_preemption()
	_rearm_and_clear()
	_baselines_and_configuration()
	_preview_and_volume()
	await _master_and_retirement(bus)
	AudioServer.set_bus_volume_db(bus, old_db)
	AudioServer.set_bus_mute(bus, old_mute)
	print("alert audio: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)


func _fresh() -> void:
	director.configure({})
	director.reset()
	cues.clear()
	previews.clear()
	clock.wall = 0.0


func _observe(sim_time: float, wall_time: float, codes: Array, audible := true) -> String:
	clock.wall = wall_time
	return director.observe(PackedStringArray(codes), sim_time, audible)


func _streams_and_priority() -> void:
	_fresh()
	var voice: AudioStreamPlayer = director.audio_player()
	_check("one voice is owned on Master", director.get_child_count() == 1 and voice.max_polyphony == 1 and voice.bus == &"Master")
	var streams: Array = []
	for key: String in ["danger", "caution", "info", "cleared"]:
		var stream: AudioStream = Director.STREAM_BY_CUE[key]
		_check(key + " uses a non-looping OGG", stream is AudioStreamOggVorbis and not (stream as AudioStreamOggVorbis).loop)
		streams.append(stream)
	_check("severity and clear clips are distinct", streams.size() == 4 and streams[0] != streams[1]
		and streams[0] != streams[2] and streams[0] != streams[3] and streams[1] != streams[2]
		and streams[1] != streams[3] and streams[2] != streams[3])
	_check("first sample is a silent baseline", _observe(0, 0, []) == "" and cues.is_empty())
	_check("one batch selects the highest-priority new code", _observe(1, 1, ["far", "battery", "stall", "stall"]) == "danger"
		and cues == [["danger", "stall"]] and voice.stream == Director.STREAM_BY_CUE.danger)
	_check("default gain and Master routing apply", is_equal_approx(voice.volume_db, linear_to_db(0.55 * Director.GAINS.danger))
		and voice.playing)
	_check("stable active codes never repeat", _observe(2, 2, ["stall", "battery", "far"]) == "" and cues.size() == 1)


func _global_gap_and_preemption() -> void:
	_fresh()
	_observe(0, 0, [])
	_check("new info uses info cue", _observe(1, 1, ["experimental"]) == "info")
	_check("global gap drops a caution", _observe(1.2, 1.2, ["experimental", "far"]) == "")
	_check("blocked cues never play later", _observe(2.5, 2.5, ["experimental", "far"]) == "" and cues == [["info", "experimental"]])
	_fresh()
	_observe(0, 0, [])
	_observe(1, 1, ["experimental"])
	_check("even a danger waits for urgent gap", _observe(1.2, 1.2, ["experimental", "stall"]) == "")
	_check("blocked danger is not queued", _observe(1.8, 1.8, ["experimental", "stall"]) == "")
	_fresh()
	_observe(0, 0, [])
	_observe(1, 1, ["experimental"])
	_check("new danger preempts lower severity after urgent gap", _observe(1.4, 1.4, ["experimental", "stall"]) == "danger"
		and cues == [["info", "experimental"], ["danger", "stall"]])
	_check("preemption keeps a single voice", director.get_child_count() == 1 and director.audio_player().stream == Director.STREAM_BY_CUE.danger)


func _rearm_and_clear() -> void:
	_fresh()
	_observe(0, 0, [])
	_observe(1, 1, ["far"])
	_observe(1.1, 1.1, [])
	_check("brief disappearance cannot rearm", _observe(1.5, 1.5, ["far"]) == "")
	_observe(1.6, 1.6, [])
	_check("per-code cooldown survives adequate absence", _observe(2.6, 2.6, ["far"]) == "")
	_observe(2.7, 2.7, [])
	_check("quiet period and cooldown permit a fresh crossing", _observe(5.2, 5.2, ["far"]) == "caution"
		and cues == [["caution", "far"], ["caution", "far"]])
	_fresh()
	_observe(0, 0, [])
	_observe(1, 1, ["far"])
	_observe(2.05, 2.05, ["far"])
	_check("all clear waits for debounce", _observe(2.1, 2.1, []) == "" and _observe(2.39, 2.39, []) == "")
	_check("sustained visible alert clears once after 0.3 s quiet", _observe(2.41, 2.41, []) == "cleared"
		and cues == [["caution", "far"], ["cleared", ""]])
	_check("no repeat clear", _observe(3.0, 3.0, []) == "")
	_fresh()
	_observe(0, 0, [])
	_observe(1, 1, ["far"])
	_observe(1.5, 1.5, [])
	_check("short alert produces no clearance", _observe(2, 2, []) == "" and cues.size() == 1)
	_fresh()
	director.configure({"warning_clear_sound": false})
	_observe(0, 0, [])
	_observe(1, 1, ["far"])
	_observe(2.2, 2.2, [])
	_check("clear cue can be disabled", _observe(2.6, 2.6, []) == "" and cues.size() == 1)


func _baselines_and_configuration() -> void:
	_fresh()
	_check("initial active condition is silent", _observe(0, 0, ["stall"]) == "" and cues.is_empty())
	director.reset()
	_check("reset establishes another silent baseline", _observe(0, 0, ["stall"]) == "" and cues.is_empty())
	_fresh()
	_observe(10, 1, [])
	_observe(11, 2, ["far"])
	_check("rewind does not invent an entry cue", _observe(1, 3, ["far"]) == "" and cues.size() == 1)
	_check("new post-rewind danger remains audible", _observe(2, 4, ["far", "stall"]) == "danger")
	_check("hidden or paused stops the active voice", _observe(2.1, 4.1, ["far", "stall"], false) == ""
		and not director.audio_player().playing)
	_check("returning from a menu is a silent baseline", _observe(2.2, 5, ["far", "stall"]) == "" and cues.size() == 2)
	_fresh()
	_observe(0, 0, [])
	_observe(1, 1, ["far"])
	director.configure({"warning_navigation": false})
	_check("category change stops voice and does not make an all-clear", not director.audio_player().playing
		and _observe(2.2, 2.2, []) == "" and _observe(2.6, 2.6, []) == "" and cues.size() == 1)
	director.configure({"visible": []})
	_check("Warnings off is silent even if caller asks to play", _observe(3, 3, []) == ""
		and _observe(4, 4, ["stall"]) == "" and cues.size() == 1)
	_fresh()
	_observe(0, 0, [])
	_observe(1, 1, ["far"])
	director.configure({"warning_sound": true, "warning_volume": 0.55, "warning_clear_sound": true})
	_check("equivalent defaults do not erase history", _observe(2, 2, ["far", "stall"]) == "danger" and cues.size() == 2)
	_check("non-finite sample resets silently", _observe(NAN, 3, ["stall"]) == "" and not director.audio_player().playing)


func _preview_and_volume() -> void:
	_fresh()
	_observe(0, 0, [])
	_observe(1, 1, ["far"])
	clock.wall = 1.1
	_check("explicit preview has a separate signal", director.preview("info") and previews == ["info"]
		and cues == [["caution", "far"]] and director.audio_player().stream == Director.STREAM_BY_CUE.info)
	_check("preview leaves semantic priority and cooldown history intact", _observe(1.4, 1.4, ["far", "stall"]) == "danger"
		and cues == [["caution", "far"], ["danger", "stall"]])
	_check("unknown preview is rejected", not director.preview("unknown") and director.audio_player().stream == Director.STREAM_BY_CUE.danger)
	director.configure({"warning_volume": 0.2})
	_check("volume change retires old audio", not director.audio_player().playing)
	_check("preview respects per-alert volume", director.preview("caution")
		and is_equal_approx(director.audio_player().volume_db, linear_to_db(0.2 * Director.GAINS.caution)))
	director.configure({"warning_volume": 0.0})
	_check("zero alert volume stops and mutes preview", not director.audio_player().playing and not director.preview("danger"))
	director.configure({"warning_sound": false})
	_check("alert mute silences observe and preview", _observe(1, 1, []) == "" and _observe(2, 2, ["stall"]) == ""
		and not director.preview("danger"))
	director.configure({"warning_volume": INF})
	_check("non-finite volume uses safe default", director.preview("danger")
		and is_equal_approx(director.audio_player().volume_db, linear_to_db(0.55 * Director.GAINS.danger)))
	director.configure({"warning_volume": 2.0})
	_check("volume clamps at one", director.preview("danger")
		and is_equal_approx(director.audio_player().volume_db, linear_to_db(Director.GAINS.danger)))


func _master_and_retirement(bus: int) -> void:
	_fresh()
	_observe(0, 0, [])
	_observe(1, 1, ["stall"])
	AudioServer.set_bus_mute(bus, true)
	await process_frame
	_check("Master mute stops a playing voice", not director.audio_player().playing)
	_check("Master mute suppresses preview and events", not director.preview("info") and _observe(2, 2, ["stall"]) == "")
	AudioServer.set_bus_mute(bus, false)
	_check("unmuting establishes a silent baseline", _observe(3, 3, ["stall"]) == "" and cues.size() == 1)
	director.preview("info")
	director.retire_playbacks()
	_check("retirement stops playback and clears pending state", not director.audio_player().playing
		and _observe(4, 4, ["stall"]) == "")
	var voice_ref: WeakRef = weakref(director.audio_player())
	director.queue_free()
	await process_frame
	_check("freeing the director releases its only voice", voice_ref.get_ref() == null)


func _check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
		push_error("alert audio: " + label)
