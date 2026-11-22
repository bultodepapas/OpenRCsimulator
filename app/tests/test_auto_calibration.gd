extends SceneTree
## VQ-07h: first-flight measured calibration of the automatic graphics choice.

const AutoCalibration := preload("res://render/auto_calibration.gd")
const SceneDetail := preload("res://render/scene_detail.gd")
const RendererPreference := preload("res://app_state/renderer_preference.gd")
const TimingLease := preload("res://render/render_timing_lease.gd")
const Reconstruction := preload("res://render/reconstruction.gd")
const UiScale := preload("res://ui/ui_scale.gd")

const PRIVATE_PATH := "user://test graphics calibration.cfg"

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	AutoCalibration.calibration_path = PRIVATE_PATH
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PRIVATE_PATH))
	_test_evaluate()
	_test_read_rate()
	_test_storage()
	_test_incomplete_attempts()
	_test_reset_invalidates_attempts()
	_test_scene_detail()
	_test_renderer()
	_test_workload_identity()
	await _test_output_identity()
	_test_view_tracking()
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


## VQ-07h T5: with a separate render thread each timing read is a render-thread sync, so reads are rate-limited
## there; the default thread model reads every frame exactly as before.
func _test_read_rate() -> void:
	_check("this project renders with the default (Safe) thread model", not AutoCalibration.uses_separate_render_thread())
	var every_frame := true
	for frame in 10:
		every_frame = every_frame and AutoCalibration.reads_timings(false, 1000 + frame * 3000, 1000 + (frame - 1) * 3000)
	_check("Safe reads the timings every frame", every_frame)
	var step := AutoCalibration.SEPARATE_READ_INTERVAL_USEC
	_check("Separate reads the first frame", AutoCalibration.reads_timings(true, 5000, 0))
	_check("Separate skips frames inside the read interval", not AutoCalibration.reads_timings(true, 5000 + step - 1, 5000))
	_check("Separate reads again once the interval has passed", AutoCalibration.reads_timings(true, 5000 + step, 5000))
	var reads := 0
	var last := 0
	for frame in 300 * 20: # 300 fps for SAMPLE_S = 20 s
		var now := 1_000_000 + frame * 3333
		if AutoCalibration.reads_timings(true, now, last):
			reads += 1
			last = now
	_check("Separate still gathers MIN_SAMPLES over SAMPLE_S", reads >= AutoCalibration.MIN_SAMPLES and reads <= 420, reads)


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
	_check("offsets are bounded", AutoCalibration.save_result({"adapter": "Example GPU", "method": "mobile", "scene_offset": 5,
		"complete": true})
		and AutoCalibration.load_result("Example GPU", "mobile").scene_offset == 1)
	AutoCalibration.clear()
	_check("Restore graphics defaults forgets every verdict", AutoCalibration.load_result(uhd, "forward_plus").is_empty()
		and AutoCalibration.load_result("NVIDIA GeForce RTX 3060", "forward_plus").is_empty())
	_check("levels shift within Low..High and never reach Extreme",
		AutoCalibration.shifted_level("high", 1) == "high" and AutoCalibration.shifted_level("medium", 1) == "high"
		and AutoCalibration.shifted_level("low", -1) == "low" and AutoCalibration.shifted_level("high", -1) == "medium")
	_check("an Automatic Extreme that misses the frame drops to High and never rises",
		AutoCalibration.shifted_level("extreme", -1) == "high" and AutoCalibration.shifted_level("extreme", 1) == "extreme"
		and AutoCalibration.shifted_level("extreme", 0) == "extreme")
	_test_measured_level()


## Incomplete attempts are session-local cooldowns, not reusable measurements or permanent retry suppression.
func _test_incomplete_attempts() -> void:
	AutoCalibration.clear()
	var gpu := "NVIDIA GeForce RTX 3090"
	var workload := {"pixels": 2073600, "render_pixels": 2073600, "msaa_3d": 0}
	var incomplete := workload.duplicate()
	incomplete.merge({"adapter": gpu, "method": "forward_plus", "level": "high", "complete": false,
		"scene_offset": -1, "reject_high": true})
	var legacy := ConfigFile.new()
	legacy.set_value("meta", "format", AutoCalibration.FORMAT)
	var section := "gpu %s | forward_plus" % AutoCalibration.adapter_key(gpu)
	for key: String in incomplete:
		legacy.set_value(section, key, incomplete[key])
	_check("legacy incomplete fixture saves", legacy.save(PRIVATE_PATH) == OK)
	_check("legacy incomplete evidence cannot suppress retry or veto High",
		AutoCalibration.needed(gpu, "forward_plus", 2073600, "high", workload)
		and not AutoCalibration.rejects_high(gpu, 2073600))
	AutoCalibration.clear()
	var session := Node.new()
	var interrupted := AutoCalibration.new(session, gpu, "high")
	interrupted.free()
	session.free()
	_check("an interrupted flight is still eligible", AutoCalibration.needed(gpu, "forward_plus", 2073600, "high", workload))
	_check("an insufficient attempt never creates a persistent verdict", not AutoCalibration.record_attempt(incomplete)
		and not FileAccess.file_exists(PRIVATE_PATH))
	_check("the same workload waits for the next session or explicit reset",
		not AutoCalibration.needed(gpu, "forward_plus", 2073600, "high", workload)
		and AutoCalibration.retry_delayed(gpu, "forward_plus", 2073600, workload))
	_check("changed pixels, MSAA or renderer remain eligible",
		AutoCalibration.needed(gpu, "forward_plus", 3840 * 2160, "high", workload)
		and AutoCalibration.needed(gpu, "forward_plus", 2073600, "high", {"render_pixels": 1036800, "msaa_3d": 0})
		and AutoCalibration.needed(gpu, "forward_plus", 2073600, "high", {"render_pixels": 2073600, "msaa_3d": 1})
		and AutoCalibration.needed(gpu, "mobile", 2073600, "high", workload))
	_check("a kept Restore clears the session cooldown", AutoCalibration.clear() == OK
		and AutoCalibration.needed(gpu, "forward_plus", 2073600, "high", workload))
	var complete := incomplete.duplicate()
	complete.complete = true
	_check("a later complete attempt is stored", AutoCalibration.record_attempt(complete))
	var accepted := FileAccess.get_file_as_string(PRIVATE_PATH)
	_check("incomplete evidence cannot overwrite a complete verdict", not AutoCalibration.save_result(incomplete)
		and not AutoCalibration.record_attempt(incomplete) and FileAccess.get_file_as_string(PRIVATE_PATH) == accepted
		and AutoCalibration.load_result(gpu, "forward_plus").complete)
	AutoCalibration.clear()
	AutoCalibration.calibration_path = "user://test_calibration_missing_parent/result.cfg"
	_check("a failed persistent write is reported and remains retryable", not AutoCalibration.record_attempt(complete)
		and AutoCalibration.needed(gpu, "forward_plus", 2073600, "high", workload))
	AutoCalibration.calibration_path = PRIVATE_PATH
	AutoCalibration.clear()


## A paused partial collection cannot undo a successful Restore. The invalidation runs before lease/focus
## checks, so it can be exercised on headless hosts without inventing GPU timings or forcing a timing lease.
func _test_reset_invalidates_attempts() -> void:
	var gpu := "NVIDIA GeForce RTX 3090"
	var session := Node.new()
	var collector := AutoCalibration.new(session, gpu, "high")
	collector._samples = _samples(20.0, 30)
	collector._active_s = AutoCalibration.WARMUP_S + 1.0
	var finished: Array[Dictionary] = []
	collector.finished.connect(func(result: Dictionary) -> void: finished.append(result))
	var blocked := PRIVATE_PATH + ".directory"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(blocked))
	AutoCalibration.calibration_path = blocked
	_check("failed reset reports the deletion error", AutoCalibration.clear() != OK)
	collector._process(0.0)
	_check("failed reset preserves the current partial collector", not collector.is_queued_for_deletion()
		and collector._samples.size() == 30)
	AutoCalibration.calibration_path = PRIVATE_PATH
	AutoCalibration.clear()
	collector._process(AutoCalibration.SAMPLE_S)
	_check("successful reset retires a paused partial collector without a verdict or cooldown",
		collector.is_queued_for_deletion() and finished.is_empty() and not FileAccess.file_exists(PRIVATE_PATH)
		and AutoCalibration.needed(gpu, "forward_plus", 2073600, "high", {"render_pixels": 2073600, "msaa_3d": 0}))
	collector.free()
	session.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(blocked))


## VQ-07h-A4: a verdict is relative to the level it measured (format 3).
func _test_measured_level() -> void:
	var gpu := "NVIDIA GeForce RTX 3060"
	_check("the measured level is stored", AutoCalibration.save_result({"adapter": gpu, "method": "forward_plus",
		"scene_offset": 0, "complete": true, "pixels": 2073600, "level": "high"})
		and AutoCalibration.load_result(gpu, "forward_plus").level == "high")
	_check("a policy update to Extreme measures again", AutoCalibration.needed(gpu, "forward_plus", 2073600, "extreme")
		and not AutoCalibration.needed(gpu, "forward_plus", 2073600, "high")
		and not AutoCalibration.needed(gpu, "forward_plus", 2073600, "medium")
		and not AutoCalibration.needed(gpu, "forward_plus", 2073600))
	AutoCalibration.save_result({"adapter": gpu, "method": "forward_plus", "scene_offset": -1, "complete": true,
		"pixels": 2073600, "level": "high"})
	_check("a down verdict below the new level needs no new measurement",
		not AutoCalibration.needed(gpu, "forward_plus", 2073600, "extreme"))
	var down_high := {"scene_offset": -1, "level": "high"}
	_check("a down verdict at High caps a later Automatic Extreme at Medium",
		AutoCalibration.apply_verdict("extreme", down_high) == "medium"
		and AutoCalibration.apply_verdict("high", down_high) == "medium"
		and AutoCalibration.apply_verdict("medium", down_high) == "medium"
		and AutoCalibration.apply_verdict("low", down_high) == "low")
	_check("a down verdict at Extreme leaves High", AutoCalibration.apply_verdict("extreme",
		{"scene_offset": -1, "level": "extreme"}) == "high")
	var up_medium := {"scene_offset": 1, "level": "medium"}
	_check("an up verdict raises only the level it measured", AutoCalibration.apply_verdict("medium", up_medium) == "high"
		and AutoCalibration.apply_verdict("low", up_medium) == "low"
		and AutoCalibration.apply_verdict("high", up_medium) == "high")
	_check("a verdict without a measured level changes nothing",
		AutoCalibration.apply_verdict("high", {"scene_offset": -1}) == "high")
	var stale := ConfigFile.new()
	stale.set_value("meta", "format", 2)
	stale.set_value("gpu %s | forward_plus" % AutoCalibration.adapter_key(gpu), "scene_offset", -1)
	stale.save(AutoCalibration.calibration_path)
	_check("a format 2 verdict is discarded and measured again", AutoCalibration.load_result(gpu, "forward_plus").is_empty()
		and AutoCalibration.needed(gpu, "forward_plus", 2073600))
	AutoCalibration.clear()


func _test_scene_detail() -> void:
	var method := RenderingServer.get_current_rendering_method()
	var pixels := root.size.x * root.size.y
	SceneDetail.adapter_override = PackedStringArray(["NVIDIA GeForce RTX 3090", "NVIDIA"])
	SceneDetail.calibration = {}
	_check("without a verdict Automatic follows the table", SceneDetail.detected().level == "high")
	var key := AutoCalibration.adapter_key("NVIDIA GeForce RTX 3090")
	SceneDetail.calibration = {"adapter": key, "method": method, "pixels": pixels, "scene_offset": -1, "level": "high", "complete": true}
	var shifted := SceneDetail.detected()
	_check("a measured verdict lowers Automatic one level", shifted.level == "medium" and bool(shifted.get("calibrated", false)), shifted)
	SceneDetail.calibration.complete = false
	_check("an incomplete verdict never changes Automatic", SceneDetail.detected().level == "high")
	SceneDetail.calibration.erase("complete")
	_check("a verdict without completeness evidence never changes Automatic", SceneDetail.detected().level == "high")
	SceneDetail.calibration = {"adapter": key, "method": "another_renderer", "pixels": pixels, "scene_offset": -1, "level": "high", "complete": true}
	_check("a verdict from another renderer is ignored", SceneDetail.detected().level == "high")
	SceneDetail.calibration = {"adapter": key, "method": method, "pixels": maxi(pixels, 1) * 4, "scene_offset": -1, "level": "high", "complete": true}
	_check("a verdict from a very different output size is ignored", SceneDetail.detected().level == "high")
	SceneDetail.calibration = {"adapter": AutoCalibration.adapter_key("Intel(R) Iris(R) Xe Graphics"), "method": method,
		"pixels": pixels, "scene_offset": -1, "level": "high", "complete": true}
	_check("a verdict for another GPU is ignored", SceneDetail.detected().level == "high")
	SceneDetail.set_preference("high")
	SceneDetail.calibration = {"adapter": key, "method": method, "pixels": pixels, "scene_offset": -1, "level": "high", "complete": true}
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


## Audit 2026-11-19 F05/F07: a verdict only speaks for a comparable workload.
func _test_workload_identity() -> void:
	var gpu := "NVIDIA GeForce RTX 3090"
	AutoCalibration.save_result({"adapter": gpu, "method": "forward_plus", "level": "high", "pixels": 3840 * 2160,
		"render_pixels": 3840 * 2160, "msaa_3d": 0, "complete": true, "reject_high": true, "scene_offset": 0,
		"gpu_p95_ms": 20.0, "samples": 300})
	var loaded := AutoCalibration.load_result(gpu, "forward_plus")
	_check("the workload identity reads back", loaded.render_pixels == 3840 * 2160 and loaded.msaa_3d == 0, loaded)
	_check("a 4K High rejection vetoes High on a 4K screen", AutoCalibration.rejects_high(gpu, 3840 * 2160))
	_check("a 4K High rejection does not veto High on a 1080p screen", not AutoCalibration.rejects_high(gpu, 1920 * 1080))
	AutoCalibration.save_result({"adapter": gpu, "method": "forward_plus", "level": "high", "pixels": 1920 * 1080,
		"complete": true, "reject_high": true})
	_check("a High rejection in a 1080p window still vetoes High on a 4K screen",
		AutoCalibration.rejects_high(gpu, 3840 * 2160) and AutoCalibration.rejects_high(gpu, 1920 * 1080)
		and AutoCalibration.rejects_high(gpu, 0))
	_check("but not on a much smaller screen", not AutoCalibration.rejects_high(gpu, 1280 * 720))
	AutoCalibration.save_result({"adapter": gpu, "method": "forward_plus", "level": "high", "pixels": 3840 * 2160,
		"complete": true, "reject_high": true})
	var facts := {os = "Windows", arm64 = false, adapter = gpu, headless = false, template = true, cli_renderer = false,
		session_method = "gl_compatibility", project_standard = "gl_compatibility", build = "b", guard_failed_method = "",
		guard_failed_build = "", pixels = 1920 * 1080,
		calibration_reject_high = AutoCalibration.rejects_high(gpu, 1920 * 1080)}
	var state := {mode = "auto", renderer = "", standard_method = "", high_blocked_build = ""}
	_check("Automatic picks High at 1080p after a 4K rejection", RendererPreference.plan(facts, state).profile == "high")
	var incomplete := ConfigFile.new()
	incomplete.load(AutoCalibration.calibration_path)
	var section := "gpu %s | forward_plus" % AutoCalibration.adapter_key(gpu)
	incomplete.set_value(section, "pixels", 1920 * 1080)
	incomplete.set_value(section, "complete", false)
	incomplete.save(AutoCalibration.calibration_path) # a legacy writer, before incomplete storage was refused
	_check("an incomplete measurement never vetoes High", not AutoCalibration.rejects_high(gpu, 1920 * 1080))
	var native := {"render_pixels": 3840 * 2160, "msaa_3d": 0}
	var verdict := {"render_pixels": 3840 * 2160, "msaa_3d": 0}
	_check("the same 3D scale and MSAA match", AutoCalibration.workload_matches(verdict, native))
	_check("a half 3D scale (a quarter of the pixels) does not match",
		not AutoCalibration.workload_matches(verdict, {"render_pixels": 1920 * 1080, "msaa_3d": 0}))
	_check("another 3D MSAA does not match", not AutoCalibration.workload_matches(verdict, {"render_pixels": 3840 * 2160,
		"msaa_3d": Viewport.MSAA_4X}))
	_check("unknown workload values match", AutoCalibration.workload_matches({}, native)
		and AutoCalibration.workload_matches(verdict, {}))
	AutoCalibration.save_result({"adapter": gpu, "method": "gl_compatibility", "level": "high", "pixels": 2073600,
		"render_pixels": 2073600, "msaa_3d": 0, "complete": true, "scene_offset": -1})
	_check("a measured workload is not measured again",
		not AutoCalibration.needed(gpu, "gl_compatibility", 2073600, "high", {"render_pixels": 2073600, "msaa_3d": 0}))
	_check("a changed 3D scale or MSAA measures again",
		AutoCalibration.needed(gpu, "gl_compatibility", 2073600, "high", {"render_pixels": 1036800, "msaa_3d": 0})
		and AutoCalibration.needed(gpu, "gl_compatibility", 2073600, "high",
			{"render_pixels": 2073600, "msaa_3d": Viewport.MSAA_2X}))
	var stale := ConfigFile.new()
	stale.set_value("meta", "format", 3)
	stale.set_value("gpu %s | forward_plus" % AutoCalibration.adapter_key(gpu), "reject_high", true)
	stale.set_value("gpu %s | forward_plus" % AutoCalibration.adapter_key(gpu), "pixels", 2073600)
	stale.save(AutoCalibration.calibration_path)
	_check("a format 3 verdict (logical UI pixels) is discarded and measured again",
		AutoCalibration.load_result(gpu, "forward_plus").is_empty() and not AutoCalibration.rejects_high(gpu, 2073600)
		and AutoCalibration.needed(gpu, "forward_plus", 2073600))
	AutoCalibration.clear()


## Audit 2026-11-19 F04/F06: measurement and consumers use the same output pixels at any UI scale.
func _test_output_identity() -> void:
	var original := root.size
	for size: Vector2i in [Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3840, 2160)]:
		root.size = size
		UiScale.apply(root)
		await process_frame
		var workload := AutoCalibration.current_workload(root)
		var label := "%dx%d" % [size.x, size.y]
		_check(label + " measures window pixels, not the logical UI canvas",
			int(workload.get("pixels", 0)) == root.size.x * root.size.y, [workload, root.get_visible_rect().size])
		_check(label + " verdict matches the same window", AutoCalibration.size_matches(workload, root.size.x * root.size.y)
			and AutoCalibration.workload_matches(workload, AutoCalibration.current_workload(root)))
	var had_policy := root.has_meta(Reconstruction.POLICY_META)
	var scale := root.scaling_3d_scale
	root.set_meta(Reconstruction.POLICY_META, {"scale": 0.5})
	root.scaling_3d_scale = 0.5
	var halved := AutoCalibration.current_workload(root)
	_check("the internal 3D size follows the applied 3D scale",
		int(halved.render_pixels) < int(halved.pixels) and int(halved.render_pixels) * 4 >= int(halved.pixels) - 4 * root.size.x,
		halved)
	_check("Retina estimates use the applied 3D scale", is_equal_approx(SceneDetail._applied_3d_scale(Vector2i(2560, 1600)), 0.5))
	root.remove_meta(Reconstruction.POLICY_META)
	var fallback := SceneDetail._applied_3d_scale(Vector2i(2560, 1600))
	_check("before reconstruction is applied the Automatic estimate is used",
		is_equal_approx(fallback, float(Reconstruction.SCALES.get(Reconstruction.auto_mode(
			Reconstruction.runtime_capabilities(), Vector2i(2560, 1600)), 1.0))), fallback)
	root.scaling_3d_scale = scale
	if had_policy:
		root.set_meta(Reconstruction.POLICY_META, {"scale": scale})
	root.size = original
	UiScale.apply(root)
	await process_frame


## Audit 2026-11-19 F08: SubViewport activity is tracked through the sample without per-frame tree scans.
func _test_view_tracking() -> void:
	var session := Node.new()
	var calibration := AutoCalibration.new(session, "NVIDIA GeForce RTX 3090")
	root.add_child(calibration)
	calibration._track_views()
	var quiet := calibration._subviewports_active()
	var view := SubViewport.new()
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var added := calibration._subviewports_active()
	view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var disabled := calibration._subviewports_active()
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	view.free()
	var freed := calibration._subviewports_active()
	calibration.free()
	session.free()
	_check("a SubViewport added during the sample is seen and a disabled or freed one is not",
		added and not disabled and not freed, [quiet, added, disabled, freed])
	_check("a freed measurement leaves no node_added listener",
		not node_added.get_connections().any(func(c: Dictionary) -> bool: return c.callable.get_object() == null))


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
