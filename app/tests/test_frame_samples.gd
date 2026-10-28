# VQ-01b: monotonic wall-clock collection, warm-up/sample boundaries, aggregation and writes.
# Run: godot --headless --path . --script res://tests/test_frame_samples.gd
extends SceneTree

const FrameSamples := preload("res://render/frame_samples.gd")
const GroundShader: Shader = preload("res://render/ground.gdshader")
const ImportedGrassShader: Shader = preload("res://scenery/imported_grass.gdshader")
const ProceduralGrassShader: Shader = preload("res://render/near_grass.gdshader")
const TurfDetail: Texture2D = preload("res://assets/landscape/turf/detail.png")
const RcGrassAlbedo: Texture2D = preload("res://assets/landscape/rc-ground/grass-albedo.jpg")
const RcGrassNormal: Texture2D = preload("res://assets/landscape/rc-ground/grass-normal.jpg")
const RcGrassRoughness: Texture2D = preload("res://assets/landscape/rc-ground/grass-roughness.jpg")
const FieldLoader := preload("res://data/field_loader.gd")
const SceneryLoader := preload("res://scenery/scenery_loader.gd")
const ImportedNearGrass := preload("res://scenery/imported_near_grass.gd")
const LakeWorld := preload("res://render/lake/lake_world.gd")
const Ground := preload("res://render/ground.gd")
const TMP := "user://test_frame_samples.json"

var _failures: int = 0
var _checks: int = 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if ok:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _initialize() -> void:
	_test_options()
	_test_warmup_boundary_and_stall()
	_test_aggregation_and_write()
	_test_invalid_samples()
	_test_frame_limit()
	_test_stream_options_and_failures()
	_test_stream_precision()
	_test_stream_long_run(60)
	_test_stream_long_run(120)
	_test_effective_grass_state()
	_test_production_grass_profile_snapshot()
	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _stream_path(label: String) -> String:
	return "user://frame-stream-%d-%s.jsonl" % [OS.get_process_id(), label]


func _remove_stream(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _stream_records(path: String) -> Array:
	var records: Array = []
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return records
	while file.get_position() < file.get_length():
		var line: String = file.get_line()
		if not line.is_empty():
			records.append(JSON.parse_string(line))
	file.close()
	return records


func _test_stream_options_and_failures() -> void:
	var options: Dictionary = FrameSamples.options({"frametimes": "run.json", "frametimes-stream": true, "t": "1800"})
	_check("stream option permits a bounded 30-minute run", options.ok and options.stream_path == "run.json.frames.jsonl" and options.max_frames == FrameSamples.STREAM_DEFAULT_MAX_FRAMES, str(options))
	_check("stream flag requires a report path", not FrameSamples.options({"frametimes-stream": true}).ok)
	_check("stream flag cannot carry a value", not FrameSamples.options({"frametimes": "run.json", "frametimes-stream": "yes"}).ok)
	_check("stream duration and frame limits remain bounded", not FrameSamples.options({"frametimes": "run.json", "frametimes-stream": true, "t": "3601"}).ok and not FrameSamples.options({"frametimes": "run.json", "frametimes-stream": true, "frametimes-max-frames": "1000001"}).ok)

	var interrupted_path: String = _stream_path("interrupted")
	_remove_stream(interrupted_path)
	var interrupted := FrameSamples.new()
	_check("stream config accepted", interrupted.configure(0.0, 2.0, 10, interrupted_path), interrupted.failure)
	_check("stream sample accepted", interrupted.record_frame(0.1, 100000, 100000, {sim_tick = 1.0, sim_time_s = 0.1}))
	interrupted.abort("window closed")
	var partial: Dictionary = interrupted.report()
	var records: Array = _stream_records(interrupted_path)
	_check("interruption keeps an explicitly incomplete prefix", not partial.complete and partial.failure == "window closed" and partial.stream.frames == 1 and records.size() == 3 and not records[2].complete, str(partial))
	var second := FrameSamples.new()
	_check("existing stream is not overwritten", not second.configure(0.0, 1.0, 10, interrupted_path) and _stream_records(interrupted_path).size() == 3)
	_remove_stream(interrupted_path)

	var capped_path: String = _stream_path("frame-cap")
	_remove_stream(capped_path)
	var capped := FrameSamples.new()
	_check("stream frame-cap config accepted", capped.configure(0.0, 1.0, 2, capped_path))
	var accepted: bool = capped.record_frame(0.1, 100000, 100000, {sim_tick = 1.0}) and capped.record_frame(0.1, 100000, 200000, {sim_tick = 2.0})
	_check("frame overflow closes an incomplete stream", accepted and not capped.record_frame(0.1, 100000, 300000, {sim_tick = 3.0}) and not capped.report().complete and capped.report().stream.frames == 2 and capped.report().stream.rejected_frames == 1 and capped.report().stream.unstored_frames == 0 and capped.failure.contains("limit"))
	_remove_stream(capped_path)

	var bytes_path: String = _stream_path("byte-cap")
	_remove_stream(bytes_path)
	var bytes_capped := FrameSamples.new()
	_check("stream byte-cap config accepted", bytes_capped.configure(0.0, 1.0, 2, bytes_path))
	bytes_capped._stream_bytes = FrameSamples.STREAM_MAX_BYTES
	_check("byte-cap fixture accepts a buffered sample", bytes_capped.record_frame(0.1, 100000, 100000, {sim_tick = 1.0}))
	bytes_capped.abort("interrupt")
	_check("byte-cap stays incomplete and does not fabricate completion", not bytes_capped.report().complete and not bytes_capped.report().stream.complete and bytes_capped.report().stream.unstored_frames == 1 and _stream_records(bytes_path).size() == 1)
	_remove_stream(bytes_path)


func _test_stream_precision() -> void:
	var path: String = _stream_path("precision")
	var report_path: String = _stream_path("precision-report")
	_remove_stream(path)
	_remove_stream(report_path)
	var logger := FrameSamples.new()
	var original: float = 1234.567891234567
	var accepted: bool = logger.configure(0.0, 0.1, 10, path) and logger.record_frame(0.1, 100000, 100000, {sim_tick = 1.0, sim_time_s = original})
	var report: Dictionary = logger.report()
	var records: Array = _stream_records(path)
	var write_result: Dictionary = FrameSamples.write_json(report_path, report)
	var file := FileAccess.open(report_path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	if file != null:
		file.close()
	_check("stream and report preserve float64 values", accepted and write_result.ok and records.size() == 3 and parsed is Dictionary and absf(float(records[1].metrics.sim_time_s[0]) - original) < 1e-12 and absf(float(parsed.sample_endpoints.first.sim_time_s) - original) < 1e-12)
	_remove_stream(path)
	_remove_stream(report_path)


func _test_stream_long_run(hz: int) -> void:
	var path: String = _stream_path("%dhz" % hz)
	_remove_stream(path)
	var logger := FrameSamples.new()
	var count: int = hz * 1800
	_check("%d Hz long stream config accepted" % hz, logger.configure(0.0, 1800.0, count, path), logger.failure)
	var previous: int = 1000000
	var accepted: bool = true
	var max_chunk: int = 0
	for index in range(count):
		var endpoint: int = 1000000 + floori(float(index + 1) * 1800000000.0 / float(count))
		var delta: int = endpoint - previous
		var tick: int = floori(float(index + 1) * 432000.0 / float(count))
		if not logger.record_frame(float(delta) / 1000000.0, delta, endpoint, {sim_tick = float(tick), sim_time_s = float(tick) / 240.0}):
			accepted = false
			break
		previous = endpoint
		max_chunk = maxi(max_chunk, logger._wall_delta_usec.size())
	var report: Dictionary = logger.report()
	var records: Array = _stream_records(path)
	_check("%d Hz stream covers 30 minutes with bounded chunks" % hz, accepted and report.complete and report.frames == count and report.stream.frames == count and max_chunk < FrameSamples.STREAM_CHUNK_FRAMES and is_equal_approx(report.actual_sample_s, 1800.0), logger.failure)
	_check("%d Hz stream has ordered header, chunks, trailer and hash" % hz, records.size() == report.stream.chunks + 2 and records[0].type == "header" and records[-1].type == "trailer" and records[-1].complete and report.stream.sha256.length() == 64 and report.stream.unstored_frames == 0 and report.stream.rejected_frames == 0, str(report.stream))
	_check("%d Hz stream records write overhead" % hz, report.stream.write_calls == report.stream.chunks + 2 and report.stream.write_total_usec >= report.stream.write_max_usec)
	_check("%d Hz stream preserves measured endpoints without embedding raw arrays" % hz, report.raw_metrics.is_empty() and report.frame_wall_usec.is_empty() and report.sample_endpoints.first.sim_tick == 240.0 / hz and report.sample_endpoints.last.sim_tick == 432000.0)
	_remove_stream(path)


func _test_options() -> void:
	var defaults: Dictionary = FrameSamples.options({"frametimes": "/tmp/defaults.json"})
	_check("frametime defaults are 1 s warm-up and 20 s sample", defaults.ok and defaults.enabled and defaults.warmup_s == 1.0 and defaults.sample_s == 20.0, str(defaults))
	var custom: Dictionary = FrameSamples.options({"frametimes": "/tmp/custom.json", "warmup": "10", "t": "60"})
	_check("custom finite warm-up and duration parse", custom.ok and custom.warmup_s == 10.0 and custom.sample_s == 60.0, str(custom))
	var absent: Dictionary = FrameSamples.options({})
	var diagnostic: Dictionary = FrameSamples.options({"frametimes": "/tmp/diag.json", "frame-diagnostics": true, "frametimes-max-frames": "10"})
	_check("diagnostic flag and frame limit parse", diagnostic.ok and diagnostic.diagnostics and diagnostic.max_frames == 10)
	_check("logger stays disabled without its path", absent.ok and not absent.enabled, str(absent))
	var invalid: Array[Dictionary] = [
		{"frametimes": true},
		{"frametimes": ""},
		{"frametimes": "/tmp/a.json", "t": ""},
		{"frametimes": "/tmp/a.json", "t": "0"},
		{"frametimes": "/tmp/a.json", "t": "301"},
		{"frametimes": "/tmp/a.json", "warmup": "-1"},
		{"frametimes": "/tmp/a.json", "warmup": "3601"},
		{"frametimes": "/tmp/a.json", "warmup": "nan"},
		{"frametimes": "/tmp/a.json", "t": "inf"},
		{"frametimes": "/tmp/a.json", "trace": true},
		{"frametimes": "/tmp/a.json", "capture": true},
		{"warmup": "1"},
		{"frame-diagnostics": true},
		{"frametimes-max-frames": "10"},
		{"frametimes": "/tmp/a.json", "frame-diagnostics": "false"},
		{"frametimes": "/tmp/a.json", "frametimes-max-frames": true},
		{"frametimes": "/tmp/a.json", "frametimes-max-frames": "0"},
		{"frametimes": "/tmp/a.json", "frametimes-max-frames": "120001"},
		{"frametimes": "/tmp/a.json", "frametimes-max-frames": "2.5"},
	]
	for case in invalid:
		var result: Dictionary = FrameSamples.options(case)
		_check("invalid logger arguments rejected", not result.ok, str(case) + " -> " + str(result))


func _test_warmup_boundary_and_stall() -> void:
	var logger := FrameSamples.new()
	_check("10 s warm-up config accepted", logger.configure(10.0, 1.0), logger.failure)
	var origin: int = 1000000000
	# A single 11 s frame starts before the warm-up boundary and crosses it; it must not pollute the sample.
	_check("warm-up crossing frame accepted but excluded", logger.record_frame(11.0, 11000000, origin + 11000000, {sim_tick = 2640.0}))
	_check("logger waits for the next whole frame", not logger.finished and int(logger.report().frames) == 0)
	_check("first full post-warm-up frame recorded", logger.record_frame(0.5, 500000, origin + 11500000, {sim_tick = 2760.0}))
	_check("terminal whole frame recorded", logger.record_frame(1.1, 700000, origin + 12200000, {sim_tick = 2928.0}) and logger.finished)
	var report: Dictionary = logger.report()
	_check("actual warm-up moves past a warm-up stall", is_equal_approx(float(report.actual_warmup_s), 11.0), str(report.actual_warmup_s))
	_check("full sampled frames exclude the warm-up stall", report.frames == 2 and is_equal_approx(float(report.seconds), 1.2), str(report))
	_check("actual whole-frame sample end is reported", report.actual_sample_end_monotonic_usec == origin + 12200000 and is_equal_approx(float(report.actual_sample_s), 1.2), str(report))


func _test_aggregation_and_write() -> void:
	var logger := FrameSamples.new()
	_check("short aggregation config accepted", logger.configure(0.0, 0.025), logger.failure)
	var metrics_one: Dictionary = {sim_time_s = 0.01, sim_tick = 1.0, process_time_s = 0.001}
	var metrics_two: Dictionary = {sim_time_s = 0.02, sim_tick = 2.0, process_time_s = 0.002}
	var metrics_three: Dictionary = {sim_time_s = 0.03, sim_tick = 3.0, process_time_s = 0.003}
	_check("first aggregation frame accepted", logger.record_frame(0.011, 10000, 50010000, metrics_one))
	_check("second aggregation frame accepted", logger.record_frame(0.022, 10000, 50020000, metrics_two))
	_check("final frame completes at the whole-frame boundary", logger.record_frame(0.033, 10000, 50030000, metrics_three) and logger.finished)
	var report: Dictionary = logger.report()
	_check("versioned format and legacy summary fields remain", report.format == "openrc-frametimes v2" and report.version == 2 and report.frames == 3 and report.has("seconds") and report.has("fps_mean") and report.has("frame_ms"), str(report))
	_check("legacy summary now aggregates monotonic wall time", is_equal_approx(float(report.seconds), 0.03) and is_equal_approx(float(report.fps_mean), 100.0), str(report))
	_check("engine delta has separate aggregate and percentile channel", is_equal_approx(float(report.engine_seconds), 0.066) and is_equal_approx(float(report.engine_frame_ms.p50), 22.0) and report.engine_frame_deltas_s.size() == 3, str(report))
	_check("raw frame arrays preserve exact wall intervals", report.frame_deltas_s.size() == 3 and report.frame_wall_usec[0] == 10000 and report.frame_end_monotonic_usec[2] == 50030000, str(report))
	_check("per-frame simulation and performance metrics are retained", report.raw_metrics.sim_tick.size() == 3 and report.raw_metrics.sim_tick[2] == 3.0 and report.raw_metrics.process_time_s[1] == 0.002, str(report.raw_metrics))
	_check("actual start and end differ from requested duration only by whole frame overrun", report.actual_sample_start_monotonic_usec == 50000000 and report.actual_sample_end_monotonic_usec == 50030000 and is_equal_approx(float(report.actual_sample_s), 0.03), str(report))
	var write_result: Dictionary = FrameSamples.write_json(TMP, report)
	_check("valid report writes successfully", write_result.ok, str(write_result))
	if write_result.ok:
		var file := FileAccess.open(TMP, FileAccess.READ)
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		file.close()
		_check("written JSON round-trips raw samples", parsed is Dictionary and parsed.frame_deltas_s.size() == 3 and parsed.format == "openrc-frametimes v2", str(parsed))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	var write_error: Dictionary = FrameSamples.write_json("user://", report)
	_check("directory write failure is returned to the caller", not write_error.ok and int(write_error.error) != OK, str(write_error))


func _test_invalid_samples() -> void:
	var bad_config := FrameSamples.new()
	_check("zero sample duration rejected by helper", not bad_config.configure(0.0, 0.0))
	var logger := FrameSamples.new()
	_check("invalid metrics sample config accepted", logger.configure(0.0, 1.0))
	var first: Dictionary = {sim_tick = 0.0}
	_check("first frame establishes contiguous clock", logger.record_frame(0.01, 10000, 10000, first))
	_check("discontinuous monotonic interval rejected", not logger.record_frame(0.01, 10000, 30000, first) and logger.failure.contains("contiguous"), logger.failure)
	var metric_logger := FrameSamples.new()
	_check("metric schema config accepted", metric_logger.configure(0.0, 1.0))
	_check("first metric shape accepted", metric_logger.record_frame(0.01, 10000, 10000, {sim_tick = 1.0}))
	_check("changing raw metric shape rejected", not metric_logger.record_frame(0.01, 10000, 20000, {sim_tick = 2.0, draw_calls = 4.0}), metric_logger.failure)


func _test_frame_limit() -> void:
	var logger := FrameSamples.new()
	_check("bounded collector configured", logger.configure(0.0, 1.0, 2))
	_check("first retained frame", logger.record_frame(0.01, 10000, 10000))
	_check("last allowed frame", logger.record_frame(0.01, 10000, 20000))
	_check("overflow fails without another append", not logger.record_frame(0.01, 10000, 30000))
	var report: Dictionary = logger.report()
	_check("bounded prefix is incomplete and actionable", report.frames == 2 and not report.complete and report.failure.contains("frame retention") and report.max_frames == 2)
	var exact := FrameSamples.new()
	_check("exact limit configured", exact.configure(0.0, 0.02, 2))
	exact.record_frame(0.01, 10000, 10000)
	exact.record_frame(0.01, 10000, 20000)
	_check("completion at limit succeeds", exact.report().complete and exact.report().frames == 2)
	_check("reconfiguration cannot mix samples", not exact.configure(0.0, 1.0, 10))
	var invalid := FrameSamples.new()
	_check("invalid API frame limits rejected", not invalid.configure(0.0, 1.0, 0) and not invalid.configure(0.0, 1.0, FrameSamples.MAX_FRAMES + 1))
	var warmup := FrameSamples.new()
	warmup.configure(0.02, 0.01, 1)
	warmup.record_frame(0.01, 10000, 10000)
	warmup.record_frame(0.01, 10000, 20000)
	warmup.record_frame(0.01, 10000, 30000)
	_check("warmup frames do not consume retention", warmup.report().complete and warmup.report().frames == 1)


func _test_effective_grass_state() -> void:
	var field := Node3D.new()
	field.name = "Field"
	var ground_material := ShaderMaterial.new()
	ground_material.shader = GroundShader
	ground_material.set_shader_parameter("turf_detail_strength", 1.0)
	ground_material.set_shader_parameter("turf_detail", TurfDetail)
	var ground_instance := MeshInstance3D.new()
	ground_instance.name = "rough"
	ground_instance.mesh = PlaneMesh.new()
	ground_instance.material_override = ground_material
	field.add_child(ground_instance)
	var scenery := Node3D.new()
	scenery.name = "Scenery"
	scenery.set_meta("stats", {"quality": "high"})
	field.add_child(scenery)
	var near_grass := _imported_grass_fixture(StandardMaterial3D.new())
	field.add_child(near_grass)

	var baseline: Dictionary = FrameSamples.effective_grass_state(field)
	_check("effective grass snapshot verifies actual bindings and placement metadata", baseline.verified, str(baseline.errors))
	_check("scenery tier comes from built scenery stats", baseline.scenery.enabled and baseline.scenery.quality == "high", str(baseline.scenery))
	_check("ground detail flags and texture paths come from its bound material", not baseline.ground.grass_photo_enabled and baseline.ground.turf_detail_enabled and baseline.ground.texture_paths.has("res://assets/landscape/turf/detail.png"), str(baseline.ground))
	_check("imported route and species count come from the active MultiMesh", baseline.near_grass.route == "imported" and baseline.near_grass.material_variant == "source-static" and baseline.near_grass.species_counts == {"grass_common_short": 1} and baseline.near_grass.clump_count == 1, str(baseline.near_grass))
	_check("shader identity and source texture paths are stable resource evidence", baseline.near_grass.material_bindings.size() == 1 and baseline.near_grass.material_bindings[0]["class"] == "StandardMaterial3D", str(baseline.near_grass.material_bindings))

	var generated_grass_texture := ImageTexture.create_from_image(Image.create(1, 1, false, Image.FORMAT_RGB8))
	var matching_ground := _grass_fixture(false, _imported_grass_fixture(StandardMaterial3D.new()))
	var matching_first := (matching_ground.get_child(0) as MeshInstance3D).material_override as ShaderMaterial
	_configure_test_ground_textures(matching_first, generated_grass_texture)
	var matching_second_node := MeshInstance3D.new()
	matching_second_node.mesh = PlaneMesh.new()
	var matching_second := ShaderMaterial.new()
	matching_second.shader = GroundShader
	_configure_test_ground_textures(matching_second, generated_grass_texture)
	matching_second_node.material_override = matching_second
	matching_ground.add_child(matching_second_node)
	var matching_state: Dictionary = FrameSamples.effective_grass_state(matching_ground)
	_check("distinct ground materials with matching texture slots verify", matching_state.verified and matching_state.ground.material_count == 2, str(matching_state.errors))
	var matching_texture_bindings: Dictionary = matching_state.ground.get("texture_bindings", {})
	var generated_grass_binding: Dictionary = matching_texture_bindings.get("grass", {})
	var imported_grass_binding: Dictionary = matching_texture_bindings.get("rc_grass_albedo", {})
	_check("ground texture snapshot reports pathless and imported slot bindings", generated_grass_binding.get("bound", false) and str(generated_grass_binding.get("resource_path", "")).is_empty() and imported_grass_binding.get("bound", false) and imported_grass_binding.get("resource_path", "") == RcGrassAlbedo.resource_path, str(matching_texture_bindings))
	matching_ground.free()

	var mismatched_ground := _grass_fixture(false, _imported_grass_fixture(StandardMaterial3D.new()))
	var first_ground := mismatched_ground.get_child(0) as MeshInstance3D
	var first_material := first_ground.material_override as ShaderMaterial
	_configure_test_ground_textures(first_material, generated_grass_texture)
	var second_ground := MeshInstance3D.new()
	second_ground.mesh = PlaneMesh.new()
	var second_material := first_material.duplicate() as ShaderMaterial
	second_material.set_shader_parameter("rc_grass_albedo", RcGrassNormal)
	second_material.set_shader_parameter("rc_grass_normal", RcGrassAlbedo)
	second_ground.material_override = second_material
	mismatched_ground.add_child(second_ground)
	var original_paths := PackedStringArray([RcGrassAlbedo.resource_path, RcGrassNormal.resource_path, RcGrassRoughness.resource_path])
	var permuted_paths := PackedStringArray([RcGrassNormal.resource_path, RcGrassAlbedo.resource_path, RcGrassRoughness.resource_path])
	original_paths.sort()
	permuted_paths.sort()
	_check("ground texture swap fixture preserves the same resource-path set", original_paths == permuted_paths)
	var mismatched_state: Dictionary = FrameSamples.effective_grass_state(mismatched_ground)
	_check("ground texture binding snapshot detects swapped uniform slots", not mismatched_state.verified and str(mismatched_state.errors).contains("active ground material bindings disagree"), str(mismatched_state))
	mismatched_ground.free()

	var enhanced_field := _grass_fixture(true, _imported_grass_fixture(_grass_shader_material(ImportedGrassShader)))
	var enhanced: Dictionary = FrameSamples.effective_grass_state(enhanced_field)
	_check("enhanced route is recognized from the bound imported grass shader", enhanced.verified and enhanced.near_grass.route == "imported" and enhanced.near_grass.material_variant == "qualified-wind" and enhanced.near_grass.grass_wind and enhanced.ground.grass_photo_enabled, str(enhanced))

	var missing_near := _grass_fixture(false, null)
	var missing_state: Dictionary = FrameSamples.effective_grass_state(missing_near)
	_check("missing NearGrass fails closed", not missing_state.verified and str(missing_state.errors).contains("expected exactly one NearGrass"), str(missing_state.errors))
	var wrong_route := _grass_fixture(false, _imported_grass_fixture(_grass_shader_material(ProceduralGrassShader)))
	var wrong_state: Dictionary = FrameSamples.effective_grass_state(wrong_route)
	_check("unexpected imported grass shader route fails closed", not wrong_state.verified and wrong_state.near_grass.route == "unverified", str(wrong_state))
	var missing_root: Dictionary = FrameSamples.effective_grass_state(null)
	_check("missing field root fails closed with its cause", not missing_root.verified and missing_root.errors.has("field root is missing"), str(missing_root))
	var missing_ground := Node3D.new()
	missing_ground.add_child(_imported_grass_fixture(StandardMaterial3D.new()))
	var missing_ground_state: Dictionary = FrameSamples.effective_grass_state(missing_ground)
	_check("missing active Ground binding fails closed", not missing_ground_state.verified and str(missing_ground_state.errors).contains("no active ground ShaderMaterial"), str(missing_ground_state))

	field.free()
	enhanced_field.free()
	missing_near.free()
	wrong_route.free()
	missing_ground.free()


func _configure_test_ground_textures(material: ShaderMaterial, grass_texture: Texture2D) -> void:
	material.set_shader_parameter("grass_photo_enabled", false)
	material.set_shader_parameter("grass", grass_texture)
	material.set_shader_parameter("turf_detail_strength", 1.0)
	material.set_shader_parameter("turf_detail", TurfDetail)
	material.set_shader_parameter("rc_grass_albedo", RcGrassAlbedo)
	material.set_shader_parameter("rc_grass_normal", RcGrassNormal)
	material.set_shader_parameter("rc_grass_roughness", RcGrassRoughness)


func _grass_fixture(grass_photo_enabled: bool, near_grass: Node) -> Node3D:
	var field := Node3D.new()
	field.name = "Field"
	var material := ShaderMaterial.new()
	material.shader = GroundShader
	if grass_photo_enabled:
		material.set_shader_parameter("grass_photo_enabled", true)
	material.set_shader_parameter("turf_detail_strength", 1.0)
	material.set_shader_parameter("turf_detail", TurfDetail)
	var ground := MeshInstance3D.new()
	ground.mesh = PlaneMesh.new()
	ground.material_override = material
	field.add_child(ground)
	var scenery := Node3D.new()
	scenery.name = "Scenery"
	scenery.set_meta("stats", {"quality": "high"})
	field.add_child(scenery)
	if near_grass != null:
		field.add_child(near_grass)
	return field


func _imported_grass_fixture(material: Material) -> Node3D:
	var near_grass := Node3D.new()
	near_grass.name = "NearGrass"
	near_grass.set_meta("imported", true)
	near_grass.set_meta("quality", "high")
	near_grass.set_meta("clumps", 1)
	near_grass.set_meta("source_triangles", 155)
	near_grass.set_meta("groups", {"grass_common_short": {"plants": 1, "triangles": 155}})
	var array_mesh := ArrayMesh.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.UP])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.FORWARD, Vector3.FORWARD, Vector3.FORWARD])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2])
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	array_mesh.surface_set_material(0, material)
	var multimesh := MultiMesh.new()
	multimesh.mesh = array_mesh
	multimesh.instance_count = 1
	var instance := MultiMeshInstance3D.new()
	instance.name = "grass_common_short_Part_00"
	instance.multimesh = multimesh
	near_grass.add_child(instance)
	return near_grass


func _grass_shader_material(shader: Shader) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = shader
	return material


func _test_production_grass_profile_snapshot() -> void:
	var previous_grass_quality: String = OS.get_environment("OPENRC_GRASS_QUALITY")
	var loaded_field: Dictionary = FieldLoader.load_from()
	_check("default field data loads for the effective grass snapshot", bool(loaded_field.get("ok", false)), str(loaded_field.get("errors", [])))
	if not bool(loaded_field.get("ok", false)):
		return
	var scenery_result: Dictionary = SceneryLoader.load_from(SceneryLoader.DEFAULT_PATH, loaded_field.field)
	_check("default scenery data loads for the effective grass snapshot", bool(scenery_result.get("ok", false)), str(scenery_result.get("errors", [])))
	if not bool(scenery_result.get("ok", false)):
		return
	var lake_result: Dictionary = LakeWorld.resolve(loaded_field.field, {"enabled": true, "file_explicit": false})
	var lake: Dictionary = lake_result.get("lake", {}) if bool(lake_result.get("ok", false)) else {}
	var exclusions: Array = ImportedNearGrass.exclusions_for(scenery_result.scenery, lake)

	OS.set_environment("OPENRC_GRASS_QUALITY", "")
	var baseline_near: Node3D = ImportedNearGrass.build(loaded_field.field, "high", exclusions)
	var baseline_root: Node3D = _production_grass_field(Ground.grass_material(), baseline_near)
	var baseline: Dictionary = FrameSamples.effective_grass_state(baseline_root)
	_check("production baseline builds the static imported profile", baseline.verified and baseline.near_grass.route == "imported" and baseline.near_grass.material_variant == "source-static", str(baseline))
	_check("production baseline counts, batches, and source textures match the high-tier route", baseline.near_grass.species_counts == {"grass_common_short": 67, "grass_common_tall": 42, "grass_wispy_tall": 41} and baseline.near_grass.source_triangles == 49579 and baseline.near_grass.batch_count == 3 and baseline.near_grass.clump_count == 150 and not baseline.near_grass.texture_paths.is_empty() and not baseline.near_grass.material_bindings.is_empty(), str(baseline.near_grass))
	_check("production baseline binds the shader-default grass photo flag off", not baseline.ground.grass_photo_enabled and baseline.ground.grass_photo_source == "shader-default", str(baseline.ground))
	baseline_near.visible = false
	_check("hidden grass cannot qualify a performance profile", not FrameSamples.effective_grass_state(baseline_root).verified)
	baseline_near.visible = true
	var first_batch := baseline_near.get_child(0) as MultiMeshInstance3D
	first_batch.multimesh.visible_instance_count = 0
	_check("allocated but unsubmitted grass cannot qualify a performance profile", not FrameSamples.effective_grass_state(baseline_root).verified)
	first_batch.multimesh.visible_instance_count = -1
	_check("restored visible grass requalifies the observed profile", FrameSamples.effective_grass_state(baseline_root).verified)
	baseline_root.free()

	OS.set_environment("OPENRC_GRASS_QUALITY", "enhanced")
	var enhanced_near: Node3D = ImportedNearGrass.build(loaded_field.field, "high", exclusions)
	var enhanced_root: Node3D = _production_grass_field(Ground.grass_material(), enhanced_near)
	var enhanced: Dictionary = FrameSamples.effective_grass_state(enhanced_root)
	_check("production enhanced profile binds the qualified grass shader", enhanced.verified and enhanced.near_grass.route == "imported" and enhanced.near_grass.material_variant == "qualified-wind" and enhanced.near_grass.shader_paths.size() == 1 and enhanced.near_grass.shader_paths[0] == "res://scenery/imported_grass.gdshader", str(enhanced))
	_check("production enhanced profile reports its actual ground detail and normal maps", enhanced.ground.grass_photo_enabled and enhanced.ground.normal_texture_paths.has("res://assets/landscape/rc-ground/grass-normal.jpg") and enhanced.ground.roughness_texture_paths.has("res://assets/landscape/rc-ground/grass-roughness.jpg"), str(enhanced.ground))
	_check("production enhanced counts, batches, and source textures match the alternate high-tier route", enhanced.near_grass.species_counts == {"grass_common_short": 100, "grass_common_tall": 30, "grass_wispy_tall": 20} and enhanced.near_grass.source_triangles == 37720 and enhanced.near_grass.batch_count == 3 and enhanced.near_grass.clump_count == 150 and not enhanced.near_grass.texture_paths.is_empty() and not enhanced.near_grass.material_bindings.is_empty(), str(enhanced.near_grass))
	enhanced_root.free()
	OS.set_environment("OPENRC_GRASS_QUALITY", previous_grass_quality)


func _production_grass_field(ground_material: ShaderMaterial, near_grass: Node3D) -> Node3D:
	var field := Node3D.new()
	field.name = "Field"
	var ground := MeshInstance3D.new()
	ground.mesh = PlaneMesh.new()
	ground.material_override = ground_material
	field.add_child(ground)
	var scenery := Node3D.new()
	scenery.name = "Scenery"
	scenery.set_meta("stats", {"quality": "high"})
	field.add_child(scenery)
	field.add_child(near_grass)
	return field
