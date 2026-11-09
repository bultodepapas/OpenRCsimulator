# Component screen only; prepare explicit historical sources outside app/ first.
extends SceneTree

const CurrentActions := preload("res://input/controller_actions.gd")
const CurrentVoice := preload("res://render/engine_voice.gd")
const PAIRS := 7
const CALLS := 2000
var _sink := 0

func _initialize() -> void:
	var options := {}
	for argument: String in OS.get_cmdline_user_args():
		var key := argument.get_slice("=", 0)
		if argument.count("=") != 1 or key not in ["--baseline-actions", "--baseline-voice", "--output"] or options.has(key):
			printerr("Require unique --baseline-actions=<path> --baseline-voice=<path> --output=<fresh-json>")
			quit(1)
			return
		options[key] = argument.get_slice("=", 1)
	if options.size() != 3 or FileAccess.file_exists(options["--output"]):
		printerr("Require two baseline source files and a fresh output path")
		quit(1)
		return
	var old_actions: Script = load(options["--baseline-actions"])
	var old_voice: Script = load(options["--baseline-voice"])
	if old_actions == null or old_voice == null:
		quit(1)
		return
	var profile := {kind = "gamepad", roll = {axis = 0}, pitch = {axis = 1}, yaw = {axis = 2},
		throttle = {axis = 3}, actions = {}, aux = {}}
	var explicit := profile.duplicate(true)
	explicit.actions = CurrentActions.effective_bindings(profile)
	var radio := profile.duplicate(true)
	radio.kind = "radio"
	var cases := [{id = "full-airplane", profile = profile, caps = CurrentActions.AIRPLANE_CAPABILITIES},
		{id = "rates-restart", profile = profile, caps = {rates = true}},
		{id = "explicit", profile = explicit, caps = CurrentActions.AIRPLANE_CAPABILITIES},
		{id = "radio", profile = radio, caps = CurrentActions.AIRPLANE_CAPABILITIES}]
	var report := {format = "openrc-report-component-screen v1", pairs = PAIRS, calls_per_batch = CALLS,
		warmup_calls_per_variant = 500, scope = "Windows headless component CPU only; no frame, GPU, hardware-input or listening qualification",
		machine = {os = OS.get_name(), processor = OS.get_processor_name(), godot = Engine.get_version_info()}, cases = []}
	report.source_sha256 = {}
	for source: String in [get_script().resource_path, options["--baseline-actions"], options["--baseline-voice"],
		"res://input/controller_actions.gd", "res://render/engine_voice.gd"]:
		report.source_sha256[source] = FileAccess.get_sha256(source)
	for item: Dictionary in cases:
		assert(var_to_bytes(old_actions.effective_bindings(item.profile, item.caps))
			== var_to_bytes(CurrentActions.effective_bindings(item.profile, item.caps)))
		for index: int in 500:
			old_actions.effective_bindings(item.profile, item.caps)
			CurrentActions.effective_bindings(item.profile, item.caps)
		var before: Array[float] = []
		var after: Array[float] = []
		for pair: int in PAIRS:
			for role: int in [0, 1] if pair % 2 == 0 else [1, 0]:
				var script: Script = old_actions if role == 0 else CurrentActions
				var start := Time.get_ticks_usec()
				for call_index: int in CALLS:
					var resolved: Dictionary = script.effective_bindings(item.profile, item.caps)
					_sink += resolved.size()
				var elapsed := float(Time.get_ticks_usec() - start) / CALLS
				if role == 0:
					before.append(elapsed)
				else:
					after.append(elapsed)
		var result := _result(item.id, before, after)
		report.cases.append(result)
		print(JSON.stringify(result))
	old_voice.prepare()
	CurrentVoice.prepare()
	var voices := [old_voice.new(), CurrentVoice.new()]
	for voice: RefCounted in voices:
		voice.reset(6000.0, 12000.0)
		for block: int in 100:
			voice.render(6500.0, 12000.0, 512)
	var audio_before: Array[float] = []
	var audio_after: Array[float] = []
	for pair: int in PAIRS:
		for voice: RefCounted in voices:
			voice.reset(6000.0, 12000.0)
		for role: int in [0, 1] if pair % 2 == 0 else [1, 0]:
			var voice: RefCounted = voices[role]
			var start := Time.get_ticks_usec()
			for block: int in 512:
				var pcm: PackedVector2Array = voice.render(6500.0, 12000.0, 512)
				_sink += pcm.size()
			var elapsed := float(Time.get_ticks_usec() - start) * CurrentVoice.RATE / (512.0 * 512.0)
			if role == 0:
				audio_before.append(elapsed)
			else:
				audio_after.append(elapsed)
		assert(PackedFloat64Array([voices[0].phase, voices[0].frequency, voices[0].amplitude]).to_byte_array()
			== PackedFloat64Array([voices[1].phase, voices[1].frequency, voices[1].amplitude]).to_byte_array())
	var audio := _result("voice-usec-per-generated-second", audio_before, audio_after)
	report.cases.append(audio)
	print(JSON.stringify(audio))
	var file := FileAccess.open(options["--output"], FileAccess.WRITE)
	if file == null:
		printerr("Cannot save component report: ", FileAccess.get_open_error())
		quit(1)
		return
	file.store_string(JSON.stringify(report, "\t", true, true) + "\n")
	file.close()
	print("component screen complete")
	quit()

func _result(id: String, before: Array[float], after: Array[float]) -> Dictionary:
	var sorted_before := before.duplicate()
	var sorted_after := after.duplicate()
	sorted_before.sort()
	sorted_after.sort()
	return {id = id, before_batches = before, after_batches = after, before_median = sorted_before[PAIRS / 2],
		after_median = sorted_after[PAIRS / 2], reduction_pct = 100.0 * (1.0 - sorted_after[PAIRS / 2] / sorted_before[PAIRS / 2])}
