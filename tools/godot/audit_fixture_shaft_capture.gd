extends "res://tests/test_shaft_publication.gd"


func _run() -> void:
	var out := OS.get_environment("OPENRC_AUDIT_CAPTURE")
	if out.is_empty() or FileAccess.file_exists(out):
		printerr("FAIL capture output must be a fresh path")
		quit(1)
		return
	Engine.physics_ticks_per_second = 240
	var report := {format = "ci-audit-shaft-capture-v1", engine = Engine.get_version_info(),
		os = OS.get_name(), cases = {}}
	for initial: String in ["split", "coupled-rk4"]:
		var f := flight(initial)
		check("capture starts", f != null)
		if f == null:
			continue
		var target := "split" if initial == "coupled-rk4" else "coupled-rk4"
		check("capture selects opposite mode", f.setup_shaft_integrator(target))
		f.reset()
		var hash := HashingContext.new()
		hash.start(HashingContext.HASH_SHA256)
		var frames: Array[String] = []
		var events: Array[String] = []
		var config: Dictionary = {aircraft = f.aircraft.model, weather = f.weather_configuration(),
			ground_surfaces = f.ground_surfaces, airframe_surfaces = f.airframe_surfaces,
			backend = f.stage_backend_identity(), checkpoint = f._checkpoint_configuration()}
		for tick: int in 25:
			var checkpoint: Dictionary = f.checkpoint()
			check("capture complete checkpoint", not checkpoint.is_empty() and f.sim.fault_reason.is_empty())
			var bytes := var_to_bytes(checkpoint)
			frames.append(bytes.hex_encode())
			events.append(var_to_bytes(f.sim.last_events).hex_encode())
			hash.update(bytes)
			if tick < 24:
				f.sim.step()
		report.cases[target] = {frames = frames, events = events, sha256 = hash.finish().hex_encode(),
			configuration = var_to_bytes(config).hex_encode()}
		f.free()
	var file := FileAccess.open(out, FileAccess.WRITE)
	check("capture opens", not out.is_empty() and file != null)
	if file != null:
		file.store_string(JSON.stringify(report))
		file.close()
	print("CI_AUDIT_SHAFT_CAPTURE checks=%d failures=%d cases=%d" % [checks, failed, report.cases.size()])
	quit(1 if failed else 0)
