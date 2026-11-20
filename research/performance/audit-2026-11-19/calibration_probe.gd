extends SceneTree

const AutoCalibration = preload("res://render/auto_calibration.gd")
const RendererPreference = preload("res://app_state/renderer_preference.gd")
const GpuCapability = preload("res://render/gpu_capability.gd")
const Policy = preload("res://render/auto_graphics_policy.gd")
const Hud = preload("res://render/hud.gd")
const UiScale = preload("res://ui/ui_scale.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var out := {engine = Engine.get_version_info().string, windows = []}
	AutoCalibration.calibration_path = "res://calibration_probe.cfg"
	var samples := PackedFloat64Array()
	samples.resize(300)
	samples.fill(1.0)
	for index: int in range(285, 300): samples[index] = 20.0
	out.percentile = {count = 300, low_count = 285, high_count = 15,
		hud_nearest_rank_p95 = Hud.percentile(samples, 0.95), calibration_p95 = AutoCalibration._p95(samples),
		verdict = AutoCalibration.evaluate(samples, true, "forward_plus")}
	var incomplete_samples := PackedFloat64Array()
	incomplete_samples.resize(200)
	incomplete_samples.fill(5.0)
	var incomplete := AutoCalibration.evaluate(incomplete_samples, true, "forward_plus")
	incomplete.merge({adapter = "NVIDIA GeForce RTX 3090", method = "forward_plus", level = "high", pixels = 1920 * 1080})
	out.incomplete_saved = AutoCalibration.save_result(incomplete)
	out.incomplete_loaded = AutoCalibration.load_result("NVIDIA GeForce RTX 3090", "forward_plus")
	out.incomplete_retry = AutoCalibration.needed("NVIDIA GeForce RTX 3090", "forward_plus", 1920 * 1080, "high")
	var rejected := {adapter = "NVIDIA GeForce RTX 3090", method = "forward_plus", level = "high", pixels = 3840 * 2160,
		complete = true, reject_high = true, scene_offset = 0, gpu_p95_ms = 20.0, samples = 300}
	out.rejection_saved = AutoCalibration.save_result(rejected)
	var verdict := AutoCalibration.load_result("NVIDIA GeForce RTX 3090", "forward_plus")
	out.rejection_size_matches_1080 = AutoCalibration.size_matches(verdict, 1920 * 1080)
	var facts := {os = "Windows", arm64 = false, adapter = "NVIDIA GeForce RTX 3090", pixels = 1920 * 1080,
		headless = false, template = true, cli_renderer = false, project_standard = "gl_compatibility",
		session_method = "gl_compatibility", build = "audit-fixture", calibration_reject_high = verdict.reject_high}
	var state := {mode = "auto", renderer = "", standard_method = "", high_blocked_build = ""}
	out.rejection_at_1080 = RendererPreference.plan(facts, state)
	facts.calibration_reject_high = false
	out.no_rejection_at_1080 = RendererPreference.plan(facts, state)
	for size: Vector2i in [Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3840, 2160)]:
		root.size = size
		UiScale.apply(root)
		await process_frame
		var visible := root.get_visible_rect().size
		var record := {requested = [size.x, size.y], window = [root.size.x, root.size.y],
			logical = [visible.x, visible.y], content = [root.content_scale_size.x, root.content_scale_size.y]}
		record.calibration_matches_same_window = AutoCalibration.size_matches({pixels = int(visible.x) * int(visible.y)}, root.size.x * root.size.y)
		out.windows.append(record)
	var panel := Vector2i(2560, 1600)
	var assumed := GpuCapability.mac_render_pixels(panel, 2.0 / 3.0)
	var actual_native := GpuCapability.mac_render_pixels(panel, 1.0)
	out.mac_policy_math = {scope = "pure capability-table calculation; no Mac or GPU execution",
		assumed_pixels = assumed, actual_native_pixels = actual_native,
		assumed_recommendation = Policy.scene_detail_from_capability("Apple M1", assumed),
		native_recommendation = Policy.scene_detail_from_capability("Apple M1", actual_native)}
	print("CALIBRATION_JSON " + JSON.stringify(out, "", true, true))
	print("Calibration probe complete")
	quit(0)
