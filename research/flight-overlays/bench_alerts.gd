## HUD-09-R4: matched alert callback timing and optional rendered parity.
## --reference-dir=<R3 source copies> --out=<fresh absolute directory> [--render-check]
## Optional --only=<scenario> --calls=<32..2048> isolate a noisy case with longer batches.
## CPU batches exclude deferred layout, drawing, GPU completion and audio mixing.
extends SceneTree

const UiTheme := preload("res://ui/ui_theme.gd")
const FILES := ["alert_policy.gd", "overlay_settings.gd", "warnings_bar.gd", "alert_audio.gd", "overlay_manager.gd"]
const CASES := ["empty", "stable_three", "muted_three", "preview_settled", "disabled_warmed_pool", "changing_rail", "optical_sweep"]
var A := PackedStringArray(["stall", "far", "experimental"])
var B := PackedStringArray(["stall", "low", "far", "experimental"])
var POOL_A := PackedStringArray(["stall", "low", "battery_empty", "fuel_empty", "far"])
var POOL_B := PackedStringArray(["controller_lost", "failsafe", "battery_hot", "battery", "experimental"])
const BATCHES := 8
const ROUNDS := 3

var _out := ""
var _reference := ""
var _render_check := false
var _only := ""
var _calls := 32
var _managers := {}
var _sources := {}
var _failed := false
var _backdrop: ColorRect


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): _out = arg.trim_prefix("--out=")
		elif arg.begins_with("--reference-dir="): _reference = arg.trim_prefix("--reference-dir=")
		elif arg == "--render-check": _render_check = true
		elif arg.begins_with("--only="): _only = arg.trim_prefix("--only=")
		elif arg.begins_with("--calls="): _calls = int(arg.trim_prefix("--calls="))
	_run.call_deferred()


func _run() -> void:
	if (not _only.is_empty() and _only not in CASES) or _calls < 32 or _calls > 2048:
		printerr("Invalid --only or --calls option")
		quit(1)
		return
	if not _out.is_absolute_path() or DirAccess.dir_exists_absolute(_out) or FileAccess.file_exists(_out) \
			or not _reference.is_absolute_path() or not DirAccess.dir_exists_absolute(_reference):
		printerr("Use --reference-dir=<source copies> --out=<fresh absolute directory>")
		quit(1)
		return
	if _render_check and DisplayServer.get_name() == "headless":
		printerr("--render-check requires a rendered display")
		quit(1)
		return
	if DirAccess.make_dir_recursive_absolute(_out.path_join("reference")) != OK:
		quit(1)
		return
	await process_frame
	root.size = Vector2i(1920, 1080)
	TranslationServer.set_locale("en")
	UiTheme.reduced_motion = false
	UiTheme.opaque_panels = false
	_backdrop = ColorRect.new()
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(_backdrop)
	# Only dependency paths change in the temporary reference scripts. Original hashes remain recorded.
	var manifest_path := _reference.get_base_dir().path_join("baseline-hashes.json")
	var expected: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if not expected is Dictionary:
		printerr("Missing/invalid reference baseline-hashes.json")
		quit(1)
		return
	for name: String in FILES:
		var original := _reference.path_join(name)
		var source := FileAccess.get_file_as_string(original)
		_sources["reference/" + name] = FileAccess.get_sha256(original)
		if expected.get(name, "") != _sources["reference/" + name]:
			printerr("Reference identity mismatch: ", name)
			quit(1)
			return
		_sources["candidate/" + name] = FileAccess.get_sha256("res://render/overlays/" + name)
		for dependency: String in FILES:
			source = source.replace("res://render/overlays/" + dependency, _out.path_join("reference/" + dependency))
		var file := FileAccess.open(_out.path_join("reference/" + name), FileAccess.WRITE)
		if file == null:
			quit(1)
			return
		file.store_string(source)
		file.close()
	for variant: String in ["reference", "candidate"]:
		var path := _out.path_join("reference/overlay_manager.gd") if variant == "reference" else "res://render/overlays/overlay_manager.gd"
		var script: Script = load(path)
		if script == null:
			quit(1)
			return
		var manager: CanvasLayer = script.new({preset = "custom", visible = ["warnings"]}, "en")
		root.add_child(manager)
		_managers[variant] = manager
	for frame in 6: await process_frame
	var results := []
	for scenario: String in (CASES if _only.is_empty() else [_only]):
		var samples := {reference = [], candidate = []}
		var groups := []
		for round_index in ROUNDS:
			for variant: String in ["reference", "candidate", "candidate", "reference"]:
				var manager: CanvasLayer = _managers[variant]
				_prepare(manager, scenario)
				for frame in 3: await process_frame
				var snap := _snapshot(scenario)
				for index in 64: _exercise(manager, scenario, snap, index)
				var group: Array = []
				for batch in BATCHES:
					var started := Time.get_ticks_usec()
					for index in _calls: _exercise(manager, scenario, snap, index)
					var per_call := float(Time.get_ticks_usec() - started) / _calls
					samples[variant].append(per_call)
					group.append(per_call)
				groups.append({variant = variant, round = round_index, median_us = _percentile(group, 0.5)})
				await process_frame
		var reference_median := _percentile(samples.reference, 0.5)
		var candidate_median := _percentile(samples.candidate, 0.5)
		var row := {scenario = scenario, reference_median_us = reference_median,
			candidate_median_us = candidate_median, reference_batch_mean_p95_us = _percentile(samples.reference, 0.95),
			candidate_batch_mean_p95_us = _percentile(samples.candidate, 0.95),
			change_percent = 100.0 * (candidate_median / maxf(reference_median, 0.000001) - 1.0),
			raw_us = samples, groups = groups}
		results.append(row)
		print("ALERT BENCH %s %.3f -> %.3f us/call (%+.1f%%)" % [scenario, reference_median, candidate_median, row.change_percent])
	var parity: Array = await _parity() if _render_check else []
	for name: String in FILES:
		if FileAccess.get_sha256("res://render/overlays/" + name) != _sources["candidate/" + name]:
			_failed = true
			printerr("Source changed during benchmark: ", name)
		if FileAccess.get_sha256(_reference.path_join(name)) != _sources["reference/" + name]:
			_failed = true
	var report := {ok = not _failed, engine = Engine.get_version_info(), platform = OS.get_name(),
		display = DisplayServer.get_name(), adapter = RenderingServer.get_video_adapter_name(),
		viewport = [root.size.x, root.size.y], sources = _sources, cpu = results, rendered_parity = parity,
		calls_per_batch = _calls, batches_per_group = BATCHES, abba_rounds = ROUNDS,
		note = "Five-script comparison under shared current-app dependencies. Timings are per-call means of fixed batches (calls_per_batch), including their p95; callback microbenchmark excludes deferred layout, drawing, GPU completion and audio mixing. Not whole-app history, flight FPS or hardware qualification."}
	var file := FileAccess.open(_out.path_join("report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t") + "\n")
	file.close()
	for manager: CanvasLayer in _managers.values(): manager.queue_free()
	await process_frame
	await create_timer(0.3).timeout
	print("Alert efficiency: ", "PASS" if not _failed else "FAIL")
	quit(1 if _failed else 0)


func _prepare(manager: CanvasLayer, scenario: String) -> void:
	manager.visible = true
	manager.layer = manager.FLIGHT_LAYER
	manager.apply({preset = "custom", visible = ["warnings"], warning_limit = 3,
		warning_motion = "playful", warning_sound = scenario in ["empty", "stable_three"]}, false)
	manager.reset_flight()
	if scenario == "disabled_warmed_pool":
		manager.frames.warnings.configure({warning_limit = 5})
		manager.frames.warnings.visible = true
		manager.frames.warnings.refresh(POOL_A)
		manager.frames.warnings.refresh(POOL_B)
		manager.frames.warnings.clear_immediate()
		manager.set_overlay_visible("warnings", false)
	elif scenario == "preview_settled":
		manager.preview(true)
	manager.refresh_numbers(_snapshot(scenario))
	manager.frames.warnings.refresh(manager.frames.warnings.codes, false)
	var rail: Control = manager.frames.warnings
	if rail.get("_entrance") != null or not rail.get("_ghosts").is_empty():
		_failed = true
		printerr("Prepare failed to settle optical/exit motion: ", scenario)
	for card: Dictionary in rail.get("_cards"):
		if not card.visual.position.is_zero_approx():
			_failed = true
			printerr("Prepare left a displaced card: ", scenario)


func _snapshot(scenario: String) -> Dictionary:
	return {telemetry = {time_s = 1.0, airspeed = 20.0, height_agl = 30.0},
		warnings = PackedStringArray() if scenario == "empty" else A, paused = false}


func _exercise(manager: CanvasLayer, scenario: String, snap: Dictionary, index: int) -> void:
	if scenario == "optical_sweep":
		manager.frames.warnings._reveal_light(float(index % _calls) / float(_calls - 1))
	else:
		snap.telemetry.time_s += 0.1
		if scenario == "changing_rail": snap.warnings = A if index % 2 == 0 else B
		manager.refresh_numbers(snap)


func _parity() -> Array:
	var comparisons := []
	var codes := PackedStringArray(["stall", "low", "far", "experimental"])
	for locale: String in ["en", "es"]:
		TranslationServer.set_locale(locale)
		for opaque: bool in [false, true]:
			UiTheme.opaque_panels = opaque
			for limit: int in [1, 3, 5]:
				for background: Color in [Color.BLACK, Color.WHITE]:
					_backdrop.color = background
					var images := []
					for variant: String in ["reference", "candidate"]:
						for other: CanvasLayer in _managers.values(): other.visible = false
						var manager: CanvasLayer = _managers[variant]
						manager.visible = true
						manager.frames.warnings.configure({warning_motion = "off", warning_limit = limit})
						manager.frames.warnings.visible = true
						manager.frames.warnings.refresh(codes, false)
						for frame in 6: await process_frame
						await RenderingServer.frame_post_draw
						var captured := root.get_texture().get_image()
						var rail: Control = manager.frames.warnings
						var complete: bool = captured.get_size() == Vector2i(1920, 1080) and rail.is_visible_in_tree() \
							and rail.chips.get_child_count() == mini(limit, codes.size()) \
							and rail.summary.visible == (codes.size() > limit)
						for card: Control in rail.chips.get_children():
							var rect := card.get_global_rect()
							complete = complete and Rect2(Vector2.ZERO, Vector2(root.size)).encloses(rect)
							var pixel := captured.get_pixelv(Vector2i(rect.position + Vector2(20, 10)))
							complete = complete and (absf(pixel.r - background.r) + absf(pixel.g - background.g) + absf(pixel.b - background.b) > 0.01)
						if not complete:
							_failed = true
							printerr("Incomplete rendered alert fixture: ", variant)
						images.append(captured)
					var equal: bool = images[0].get_data() == images[1].get_data()
					var id := "%s-opaque%d-limit%d-%s" % [locale, int(opaque), limit, "black" if background == Color.BLACK else "white"]
					comparisons.append({id = id, equal = equal})
					if not equal:
						_failed = true
						images[0].save_png(_out.path_join(id + "-reference.png"))
						images[1].save_png(_out.path_join(id + "-candidate.png"))
	return comparisons


func _percentile(values: Array, fraction: float) -> float:
	var sorted := values.duplicate()
	sorted.sort()
	return float(sorted[clampi(int(fraction * (sorted.size() - 1)), 0, sorted.size() - 1)])
