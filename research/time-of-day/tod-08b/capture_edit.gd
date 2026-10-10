## TOD-08b rendered paused-edit probe. Run under Xvfb against the real production Main.
extends SceneTree

const Main = preload("res://main.gd")
const Config = preload("res://environment/time_of_day_config.gd")
const Evidence = preload("res://render/visual_evidence.gd")
var report: Dictionary = {format = "openrc-tod08-edit-probe v1", captures = {}, checks = {}, commit_ms = [], provenance = {}}
var out_dir: String = "/tmp/openrc-tod08b-render"

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--probe-out="):
			out_dir = arg.trim_prefix("--probe-out=")
	call_deferred("_run")

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.size = Vector2i(960, 540)
	var flight: Main = Main.new()
	flight.interactive_start = true
	root.add_child(flight)
	flight.set_process(false)
	flight.session.physics_enabled = false
	flight.session.input_enabled = false
	flight.session.sim.set_paused(true)
	flight._show_perf = false
	flight.set_overlays_visible(false)
	flight._look = Vector2(0.0, 5.0)
	flight._render_pose(flight._current_pose(), flight.session.surfaces(), 0.0)
	if flight._engine_audio != null:
		flight._engine_audio.stop()
		flight._engine_audio.stream = null
	var physical: Dictionary = flight.session.checkpoint()
	var night_config: Dictionary = Config.defaults()
	night_config.mode = "astronomical"
	night_config.local_seconds = 0
	report.provenance = Evidence.provenance()
	var day_before: Image = await _capture(flight, "legacy-before")
	report.checks.night_apply = _apply(flight, night_config)
	var night_first: Image = await _capture(flight, "night-applied")
	report.checks.legacy_apply = _apply(flight, Config.defaults())
	var day_after: Image = await _capture(flight, "legacy-applied")
	report.checks.night_repeat_apply = _apply(flight, night_config)
	var night_repeat: Image = await _capture(flight, "night-repeated")
	report.checks.legacy_pixels_exact = day_before.get_data() == day_after.get_data()
	report.checks.night_pixels_exact = night_first.get_data() == night_repeat.get_data()
	report.checks.day_night_differ = day_before.get_data() != night_first.get_data()
	report.checks.physics_exact = var_to_bytes(physical) == var_to_bytes(flight.session.checkpoint())
	report.checks.paused = flight.session.sim.paused
	report.ok = true
	for valid: Variant in report.checks.values():
		report.ok = report.ok and bool(valid)
	var file: FileAccess = FileAccess.open(out_dir.path_join("report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t", true, true) + "\n")
	file.close()
	flight.recorder.detach()
	flight.free()
	print("TOD-08b rendered apply: ", JSON.stringify(report.checks))
	quit(0 if report.ok else 1)

func _capture(flight: Main, label: String) -> Image:
	# QUALITY sky settles within one rendered frame (TOD-01). Explicit post-draw synchronization.
	await process_frame
	await RenderingServer.frame_post_draw
	var first: Image = root.get_texture().get_image()
	await process_frame
	await RenderingServer.frame_post_draw
	var settled: Image = root.get_texture().get_image()
	report.checks[label + "_first_frame_settled"] = first.get_data() == settled.get_data()
	var path: String = out_dir.path_join(label + ".png")
	report.checks[label + "_saved"] = settled.save_png(path) == OK
	report.captures[label] = {file = label + ".png", lighting = flight.capture_evidence().lighting, tick = flight.session.sim.tick}
	return settled

func _apply(flight: Main, config: Dictionary) -> bool:
	var started: int = Time.get_ticks_usec()
	var result: Dictionary = flight.apply_lighting_config(config)
	report.commit_ms.append(float(Time.get_ticks_usec() - started) / 1000.0)
	return result.ok
