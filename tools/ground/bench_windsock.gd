extends SceneTree
## CPU batch means only. Run alone; this does not measure GPU or whole-flight frame time.
const Sock = preload("res://render/windsock.gd")
const Loader = preload("res://data/field_loader.gd")
var sock: Node3D
func _initialize() -> void:
	var out_path: String = ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="): out_path = argument.trim_prefix("--out=")
	if out_path.is_empty():
		push_error("--out=<absolute JSON path> required")
		quit(1)
		return
	var cue: Dictionary = Loader.load_from().field.flight_cues.filter(func(c: Dictionary) -> bool: return c.type == "windsock")[0]
	sock = Sock.build(cue)
	var tick: int = 0
	var wind: Array = [2.0, 5.0, -0.5]
	for warmup: int in 1200:
		tick += 1
		Sock.advance(sock, tick / 240.0, wind)
		if tick % 4 == 0: Sock.update(sock, tick / 240.0, wind)
	var advance_samples: Array[float] = []
	var upload_samples: Array[float] = []
	for batch: int in 30:
		var advance_us: int = 0
		var upload_us: int = 0
		for sample: int in 240:
			tick += 1
			var start: int = Time.get_ticks_usec()
			Sock.advance(sock, tick / 240.0, wind)
			advance_us += Time.get_ticks_usec() - start
			if tick % 4 == 0:
				start = Time.get_ticks_usec()
				Sock.update(sock, tick / 240.0, wind)
				upload_us += Time.get_ticks_usec() - start
		advance_samples.append(advance_us / 240.0)
		upload_samples.append(upload_us / 60.0)
	advance_samples.sort()
	upload_samples.sort()
	var report := {format = "openrc-windsock-cost v1", godot = Engine.get_version_info().string,
		advance_tick_batch_mean_usec_p50 = advance_samples[15], advance_tick_batch_mean_usec_p95 = advance_samples[28],
		upload_batch_mean_usec_p50 = upload_samples[15], upload_batch_mean_usec_p95 = upload_samples[28],
		advance_batches = advance_samples, upload_batches = upload_samples,
		limitations = "Headless CPU batch means on this desktop; no GPU or complete flight frame qualification.",
		sources_sha256 = {
			motion = FileAccess.get_sha256("res://render/windsock_motion.gd"),
			renderer = FileAccess.get_sha256("res://render/windsock.gd"),
			benchmark = FileAccess.get_sha256(get_script().resource_path)}}
	print(JSON.stringify(report))
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	if f == null:
		push_error("cannot create benchmark output")
		sock.free()
		quit(1)
		return
	f.store_string(JSON.stringify(report, "  ") + "\n")
	sock.free()
	quit()
