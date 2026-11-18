extends SceneTree
## VQ-07h: first-flight measured calibration of the automatic graphics choice.

const AutoCalibration := preload("res://render/auto_calibration.gd")
const SceneDetail := preload("res://render/scene_detail.gd")
const RendererPreference := preload("res://app_state/renderer_preference.gd")
const TimingLease := preload("res://render/render_timing_lease.gd")

const PRIVATE_PATH := "user://test graphics calibration.cfg"

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	AutoCalibration.calibration_path = PRIVATE_PATH
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PRIVATE_PATH))
	_test_evaluate()
	_test_storage()
	_test_scene_detail()
	_test_renderer()
	await _test_lifecycle()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PRIVATE_PATH))
	AutoCalibration.calibration_path = AutoCalibration.CALIBRATION_PATH
	SceneDetail.calibration = {}
	SceneDetail.adapter_override = PackedStringArray()
	print("auto calibration: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _check(name: String, ok: bool, detail: Variant = "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL: %s %s" % [name, str(detail)])


func _samples(value: float, count: int = 600) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for i in count:
		out.append(value)
	return out


func _test_evaluate() -> void:
	var short := AutoCalibration.evaluate(_samples(20.0, 100))
	_check("too few measured frames give a neutral, incomplete verdict", not short.complete and short.scene_offset == 0
		and not short.reject_high)
	var slow := AutoCalibration.evaluate(_samples(15.0), true, "forward_plus")
	_check("a GPU near the 60 Hz frame lowers Scene detail but keeps High", slow.complete and slow.scene_offset == -1
		and not slow.reject_high, slow)
	var missing := AutoCalibration.evaluate(_samples(18.0), true, "forward_plus")
	_check("a High session missing the frame rejects High without also lowering Scene detail",
		missing.reject_high and missing.scene_offset == 0, missing)
	var standard := AutoCalibration.evaluate(_samples(18.0), true, "gl_compatibility")
	_check("a Standard session missing the frame lowers Scene detail and rejects nothing",
		not standard.reject_high and standard.scene_offset == -1, standard)
	var fast := AutoCalibration.evaluate(_samples(3.0))
	_check("a GPU with ample headroom raises Scene detail", fast.scene_offset == 1 and not fast.reject_high, fast)
	_check("unmeasured SubViewport work forbids raising it", AutoCalibration.evaluate(_samples(3.0), false).scene_offset == 0)
	var middle := AutoCalibration.evaluate(_samples(8.0))
	_check("a comfortable GPU keeps the recommendation", middle.scene_offset == 0 and not middle.reject_high, middle)
	var tail := _samples(5.0, 570)
	tail.append_array(_samples(30.0, 30))
	_check("the verdict follows the p95, not the median", AutoCalibration.evaluate(tail, true, "forward_plus").reject_high)
	# A5: a CPU-bound frame never raises Scene detail; the GPU verdicts ignore the CPU.
	var budget := AutoCalibration.FRAME_BUDGET_MS
	var light_cpu := AutoCalibration.evaluate(_samples(3.0), true, "", _samples(1.2), _samples(budget))
	_check("a light renderer CPU keeping 60 fps still raises Scene detail",
		light_cpu.scene_offset == 1 and not light_cpu.cpu_bound and absf(float(light_cpu.cpu_p95_ms) - 1.2) < 0.01, light_cpu)
	var heavy_cpu := AutoCalibration.evaluate(_samples(3.0), true, "", _samples(9.0), _samples(budget))
	_check("a heavy renderer CPU blocks raising Scene detail", heavy_cpu.scene_offset == 0 and heavy_cpu.cpu_bound, heavy_cpu)
	var missed := AutoCalibration.evaluate(_samples(3.0), true, "", _samples(1.2), _samples(25.0))
	_check("frames missing 60 Hz with an idle GPU are CPU-bound and never raise detail",
		missed.scene_offset == 0 and missed.cpu_bound and absf(float(missed.interval_p95_ms) - 25.0) < 0.01, missed)
	var fifty_hz := AutoCalibration.interval_floor_ms(50.0, true, 0)
	_check("a 50 Hz VSync display is not CPU-bound at its own refresh",
		AutoCalibration.evaluate(_samples(3.0), true, "", _samples(1.2), _samples(20.0), fifty_hz).scene_offset == 1)
	var capped := AutoCalibration.interval_floor_ms(144.0, true, 30)
	_check("a 30 fps cap is not CPU-bound", absf(capped - 1000.0 / 30.0) < 0.01
		and not AutoCalibration.evaluate(_samples(3.0), true, "", _samples(1.2), _samples(33.4), capped).cpu_bound)
	_check("a fast display with VSync keeps the 60 Hz floor", absf(AutoCalibration.interval_floor_ms(144.0, true, 0) - budget) < 0.01
		and absf(AutoCalibration.interval_floor_ms(50.0, false, 0) - budget) < 0.01)
	var gpu_bound := AutoCalibration.evaluate(_samples(15.0), true, "forward_plus", _samples(1.2), _samples(25.0))
	_check("a GPU-bound slow frame lowers detail and is not called CPU-bound",
		gpu_bound.scene_offset == -1 and not gpu_bound.cpu_bound and not gpu_bound.reject_high, gpu_bound)
	var slow_cpu_high := AutoCalibration.evaluate(_samples(6.0), true, "forward_plus", _samples(12.0), _samples(40.0))
	_check("a slow CPU never rejects High or lowers detail by itself",
		not slow_cpu_high.reject_high and slow_cpu_high.scene_offset == 0 and slow_cpu_high.cpu_bound, slow_cpu_high)
	var few_cpu := AutoCalibration.evaluate(_samples(3.0), true, "", _samples(12.0, 50), _samples(40.0, 50))
	_check("too few CPU samples leave the CPU unclassified", not few_cpu.cpu_bound and few_cpu.scene_offset == 1, few_cpu)
	var threshold := AutoCalibration.CPU_BLOCK_UP_ABOVE * budget
	_check("the render CPU limit is exclusive",
		AutoCalibration.evaluate(_samples(3.0), true, "", _samples(threshold), _samples(budget)).scene_offset == 1
		and AutoCalibration.evaluate(_samples(3.0), true, "", _samples(threshold + 0.01), _samples(budget)).cpu_bound)
	var limit := AutoCalibration.interval_limit_ms(budget)
	_check("a 60 fps cap keeps at least 2 ms of limiter jitter", absf(limit - (budget + 2.0)) < 0.01
		and AutoCalibration.evaluate(_samples(3.0), true, "", _samples(1.2), _samples(limit)).scene_offset == 1
		and AutoCalibration.evaluate(_samples(3.0), true, "", _samples(1.2), _samples(limit + 0.01)).cpu_bound)
	_check("slow frame intervals at 30 Hz use the proportional limit",
		absf(AutoCalibration.interval_limit_ms(1000.0 / 30.0) - 1.1 * 1000.0 / 30.0) < 0.01)
	var both := AutoCalibration.evaluate(_samples(15.0), true, "gl_compatibility", _samples(9.0), _samples(25.0))
	_check("a heavy CPU and a busy GPU still lower Scene detail", both.scene_offset == -1 and both.cpu_bound, both)
	var lake := AutoCalibration.evaluate(_samples(3.0), false, "", _samples(1.2), _samples(25.0))
	_check("SubViewport work is not mislabelled CPU-bound", not lake.cpu_bound and lake.subviewports
		and lake.scene_offset == 0, lake)
	_check("a heavy render CPU is CPU-bound even with SubViewports",
		AutoCalibration.evaluate(_samples(3.0), false, "", _samples(9.0), _samples(25.0)).cpu_bound)
	var cpu_only := AutoCalibration.evaluate(_samples(3.0), true, "", _samples(9.0), _samples(25.0, 50))
	_check("CPU samples alone can classify", cpu_only.cpu_bound and float(cpu_only.interval_p95_ms) == 0.0, cpu_only)
	var interval_only := AutoCalibration.evaluate(_samples(3.0), true, "", _samples(9.0, 50), _samples(25.0))
	_check("interval samples alone can classify", interval_only.cpu_bound and float(interval_only.cpu_p95_ms) == 0.0,
		interval_only)
	var on_time := AutoCalibration.evaluate(_samples(3.0), true, "", _samples(1.2),
		_samples(1000.0 / 59.94), AutoCalibration.interval_floor_ms(59.94, true, 0))
	_check("a 59.94 Hz display on time is not CPU-bound", on_time.scene_offset == 1 and not on_time.cpu_bound, on_time)
	var incomplete := AutoCalibration.evaluate(_samples(3.0, 10), true, "", _samples(9.0), _samples(25.0))
	_check("an incomplete verdict has the full shape and no CPU verdict", not incomplete.complete
		and not incomplete.cpu_bound and incomplete.has("interval_p95_ms") and incomplete.has("cpu_p95_ms"), incomplete)


func _test_storage() -> void:
	var uhd := "Intel(R) UHD Graphics 620"
	_check("a fresh profile still needs a measurement", AutoCalibration.needed(uhd, "forward_plus", 2073600))
	_check("no adapter never measures", not AutoCalibration.needed("", "forward_plus"))
	_check("a High verdict is stored", AutoCalibration.save_result({"adapter": uhd, "method": "forward_plus",
		"scene_offset": 0, "reject_high": true, "complete": true, "gpu_p95_ms": 21.5, "samples": 1200, "pixels": 2073600,
		"cpu_p95_ms": 7.5, "interval_p95_ms": 22.0, "cpu_bound": true, "refresh_hz": 60.0}))
	var loaded := AutoCalibration.load_result(uhd, "forward_plus")
	_check("the verdict reads back", loaded.reject_high and loaded.complete and loaded.pixels == 2073600
		and absf(float(loaded.gpu_p95_ms) - 21.5) < 0.01, loaded)
	_check("the CPU evidence reads back", loaded.cpu_bound and absf(float(loaded.cpu_p95_ms) - 7.5) < 0.01
		and absf(float(loaded.interval_p95_ms) - 22.0) < 0.01 and absf(float(loaded.refresh_hz) - 60.0) < 0.01, loaded)
	_check("the Vulkan name of the same GPU finds the same verdict",
		not AutoCalibration.load_result("Intel(R) UHD Graphics 620 (KBL GT2)", "forward_plus").is_empty())
	_check("another renderer has its own slot", AutoCalibration.load_result(uhd, "gl_compatibility").is_empty()
		and AutoCalibration.needed(uhd, "gl_compatibility", 2073600))
	_check("a Standard verdict for the same GPU keeps the High rejection",
		AutoCalibration.save_result({"adapter": uhd, "method": "gl_compatibility", "scene_offset": -1, "complete": true,
			"pixels": 2073600}) and AutoCalibration.load_result(uhd, "forward_plus").reject_high
		and AutoCalibration.load_result(uhd, "gl_compatibility").scene_offset == -1)
	_check("only a Forward+ slot can reject High", not AutoCalibration.load_result(uhd, "gl_compatibility").reject_high)
	_check("another GPU keeps its own verdicts", AutoCalibration.save_result({"adapter": "NVIDIA GeForce RTX 3060",
		"method": "forward_plus", "scene_offset": 1, "complete": true, "pixels": 2073600})
		and AutoCalibration.load_result(uhd, "forward_plus").reject_high)
	_check("a measured GPU at the same size is not measured again", not AutoCalibration.needed(uhd, "forward_plus", 2073600))
	_check("a very different output size measures again", AutoCalibration.needed(uhd, "forward_plus", 3840 * 2160)
		and not AutoCalibration.size_matches(loaded, 3840 * 2160) and AutoCalibration.size_matches(loaded, 2560 * 1080))
	var legacy := ConfigFile.new()
	legacy.load(PRIVATE_PATH)
	legacy.set_value("gpu legacy gpu | mobile", "scene_offset", -1) # a verdict written before the CPU fields
	legacy.save(PRIVATE_PATH)
	var old := AutoCalibration.load_result("Legacy GPU", "mobile")
	_check("an older verdict without CPU evidence loads with neutral defaults", old.scene_offset == -1
		and not old.cpu_bound and not old.subviewports and float(old.cpu_p95_ms) == 0.0
		and float(old.interval_p95_ms) == 0.0 and float(old.refresh_hz) == 0.0, old)
	_check("offsets are bounded", AutoCalibration.save_result({"adapter": "Example GPU", "method": "mobile", "scene_offset": 5})
		and AutoCalibration.load_result("Example GPU", "mobile").scene_offset == 1)
	AutoCalibration.clear()
	_check("Restore graphics defaults forgets every verdict", AutoCalibration.load_result(uhd, "forward_plus").is_empty()
		and AutoCalibration.load_result("NVIDIA GeForce RTX 3060", "forward_plus").is_empty())
	_check("levels shift within Low..High and never reach Extreme",
		AutoCalibration.shifted_level("high", 1) == "high" and AutoCalibration.shifted_level("medium", 1) == "high"
		and AutoCalibration.shifted_level("low", -1) == "low" and AutoCalibration.shifted_level("high", -1) == "medium"
		and AutoCalibration.shifted_level("extreme", -1) == "extreme")


func _test_scene_detail() -> void:
	var method := RenderingServer.get_current_rendering_method()
	var pixels := root.size.x * root.size.y
	SceneDetail.adapter_override = PackedStringArray(["NVIDIA GeForce RTX 3090", "NVIDIA"])
	SceneDetail.calibration = {}
	_check("without a verdict Automatic follows the table", SceneDetail.detected().level == "high")
	var key := AutoCalibration.adapter_key("NVIDIA GeForce RTX 3090")
	SceneDetail.calibration = {"adapter": key, "method": method, "pixels": pixels, "scene_offset": -1}
	var shifted := SceneDetail.detected()
	_check("a measured verdict lowers Automatic one level", shifted.level == "medium" and bool(shifted.get("calibrated", false)), shifted)
	SceneDetail.calibration = {"adapter": key, "method": "another_renderer", "pixels": pixels, "scene_offset": -1}
	_check("a verdict from another renderer is ignored", SceneDetail.detected().level == "high")
	SceneDetail.calibration = {"adapter": key, "method": method, "pixels": maxi(pixels, 1) * 4, "scene_offset": -1}
	_check("a verdict from a very different output size is ignored", SceneDetail.detected().level == "high")
	SceneDetail.calibration = {"adapter": AutoCalibration.adapter_key("Intel(R) Iris(R) Xe Graphics"), "method": method,
		"pixels": pixels, "scene_offset": -1}
	_check("a verdict for another GPU is ignored", SceneDetail.detected().level == "high")
	SceneDetail.set_preference("high")
	SceneDetail.calibration = {"adapter": key, "method": method, "pixels": pixels, "scene_offset": -1}
	_check("an explicit level is never changed", SceneDetail.level() == "high")
	SceneDetail.set_preference(SceneDetail.AUTO)
	_check("Automatic applies the verdict", SceneDetail.level() == "medium")
	SceneDetail.set_preference("")
	SceneDetail.calibration = {}


func _test_renderer() -> void:
	var facts := {os = "Windows", arm64 = false, adapter = "NVIDIA GeForce RTX 3060", headless = false, template = true,
		cli_renderer = false, session_method = "forward_plus", project_standard = "gl_compatibility", build = "b",
		guard_failed_method = "", guard_failed_build = "", calibration_reject_high = false}
	var state := {mode = "auto", renderer = "forward_plus", standard_method = "gl_compatibility", high_blocked_build = ""}
	_check("Automatic keeps High without a measured rejection", RendererPreference.plan(facts, state).profile == "high")
	facts.calibration_reject_high = true
	var rejected := RendererPreference.plan(facts, state)
	_check("a measured rejection returns Automatic to Standard with one restart", rejected.profile == "standard"
		and rejected.write and rejected.restart and rejected.state.renderer == "", rejected)
	state.mode = "high"
	_check("an explicit High choice is kept despite the measurement", RendererPreference.plan(facts, state).profile == "high")


func _test_lifecycle() -> void:
	var before := TimingLease.holders(root)
	var session := Node.new()
	var calibration := AutoCalibration.new(session, "NVIDIA GeForce RTX 3090")
	root.add_child(calibration)
	await process_frame
	var during := TimingLease.holders(root) if is_instance_valid(calibration) else before
	var gave_up := not is_instance_valid(calibration) or calibration.is_queued_for_deletion()
	if is_instance_valid(calibration):
		calibration.free()
	session.free()
	if during == before:
		_check("without a measurable viewport (headless) the measurement removes itself", gave_up)
	else:
		_check("the measurement holds a timing lease only while it lives", during == before + 1
			and TimingLease.holders(root) == before, "%d → %d → %d" % [before, during, TimingLease.holders(root)])
