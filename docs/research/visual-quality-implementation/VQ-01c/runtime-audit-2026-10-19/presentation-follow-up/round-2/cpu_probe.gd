extends SceneTree

const Hud = preload("res://render/hud.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var options := {}
	for arg in OS.get_cmdline_user_args():
		var pair := arg.trim_prefix("--").split("=", true, 1)
		if pair.size() == 2:
			options[pair[0]] = pair[1]
	var flight: Node = load(str(options.subject)).new()
	flight.external_controller_selection = true
	flight.overlays_enabled = true
	flight.overlay_settings = {preset = str(options.get("preset", "pilot"))}
	flight.user_args = PackedStringArray(["--soundscape=off"])
	root.add_child(flight)
	flight.process_mode = Node.PROCESS_MODE_DISABLED
	flight.session.input_enabled = false
	var samples := PackedFloat64Array()
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	for frame in 1260:
		for tick in 2:
			flight.session._physics_process(1.0 / 240.0)
			flight.session.sim._physics_process(1.0 / 240.0)
		var started: int = Time.get_ticks_usec()
		flight._process(1.0 / 120.0)
		var usec: int = Time.get_ticks_usec() - started
		if frame >= 60:
			samples.append(usec)
			digest.update(var_to_bytes([flight.session.sim.state, flight.session.sim.aux,
				flight.session.sim.continuous, flight.session.sim.inputs, flight.session.sim.tick]))
	var result := {subject = options.subject, preset = options.get("preset", "pilot"),
		scope = "manual Main._process CPU only; physics ticks outside timed interval; headless, no GPU/FPS claim",
		frames = samples.size(), p50_usec = Hud.percentile(samples, 0.5), p95_usec = Hud.p95(samples),
		tick = flight.session.sim.tick, paused = flight.session.sim.paused, fault = flight.session.sim.fault_reason,
		numeric_sha256 = digest.finish().hex_encode(), raw_usec = Array(samples)}
	if flight.get("observations") is Dictionary:
		var attributed := {}
		for key in flight.observations:
			var times: PackedFloat64Array = flight.observations[key]
			attributed[key] = {p50 = Hud.percentile(times, 0.5), p95 = Hud.p95(times), total_usec = 0.0, calls = times.size()}
			for time in times:
				attributed[key].total_usec += time
		result.attribution = attributed
	var out := FileAccess.open(str(options.output), FileAccess.WRITE)
	out.store_string(JSON.stringify(result, "\t") + "\n")
	out.close()
	print(JSON.stringify(result.merged({raw_usec = []}, true)))
	# The probe has no soundscape; stop scenery ambience before freeing its nodes.
	for voice: Node in flight.find_children("*", "AudioStreamPlayer", true, false):
		voice.stop()
		voice.stream = null
	for voice: Node in flight.find_children("*", "AudioStreamPlayer3D", true, false):
		voice.stop()
		voice.stream = null
	flight.free()
	await process_frame
	quit()
