extends SceneTree
## Synthetic policy witnesses, not a rendered benchmark or a hardware measurement.

const Calibration := preload("res://render/auto_calibration.gd")
const Preference := preload("res://app_state/renderer_preference.gd")
const Reconstruction := preload("res://render/reconstruction.gd")
const Report := preload("res://render/auto_graphics_report.gd")
const PRIVATE_PATH := "user://graphics-audit-private.cfg"
const ADAPTER := "NVIDIA GeForce RTX 3090"
const PIXELS := 1920 * 1080

var checks := 0
var failures := 0
var results: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func check(label: String, condition: bool) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + label)


func _run() -> void:
	Calibration.calibration_path = PRIVATE_PATH
	Calibration.clear()
	var saved := Calibration.save_result({adapter = ADAPTER, method = "forward_plus", level = "high",
		pixels = PIXELS, render_pixels = PIXELS, msaa_3d = Viewport.MSAA_4X,
		complete = true, reject_high = true, gpu_p95_ms = 18.0})
	check("synthetic high rejection saved", saved)
	var verdict := Calibration.load_result(ADAPTER, "forward_plus")
	var same := {render_pixels = PIXELS, msaa_3d = Viewport.MSAA_4X}
	check("same workload matches", Calibration.workload_matches(verdict, same))
	check("same workload needs no new measurement", not Calibration.needed(ADAPTER, "forward_plus", PIXELS, "high", same))
	var changes := {}
	for name: String in ["aa_only", "scale_only", "aa_and_scale"]:
		var changed := {render_pixels = PIXELS if name == "aa_only" else 960 * 540,
			msaa_3d = Viewport.MSAA_4X if name == "scale_only" else Viewport.MSAA_DISABLED}
		var mismatch := not Calibration.workload_matches(verdict, changed)
		var needed := Calibration.needed(ADAPTER, "forward_plus", PIXELS, "high", changed)
		var veto := Calibration.rejects_high(ADAPTER, PIXELS)
		check(name + " differs", mismatch)
		check(name + " needs remeasurement", needed)
		check(name + " still vetoes High", veto)
		changes[name] = {workload = changed, mismatch = mismatch, needs_remeasurement = needed, high_veto = veto}
	var facts := {os = "Windows", arm64 = false, adapter = ADAPTER, pixels = PIXELS,
		headless = false, template = true, cli_renderer = false, session_method = "gl_compatibility",
		project_standard = "gl_compatibility", build = "audit-synthetic-build", calibration_reject_high = true}
	var state := {mode = "auto", renderer = "", standard_method = "", high_blocked_build = ""}
	var vetoed := Preference.plan(facts, state)
	facts.calibration_reject_high = false
	var unvetoed := Preference.plan(facts, state)
	check("stored veto chooses Standard", vetoed.profile == "standard")
	check("unvetoed heuristic chooses High", unvetoed.profile == "high")
	check("smaller output is protected by existing fix", not Calibration.rejects_high(ADAPTER, 960 * 540))
	results["high_veto"] = {changes = changes, with_veto = vetoed.profile, without_veto = unvetoed.profile}

	# Different actual viewport mode values, equal dimensions/scale/MSAA. No GPU dispatch is claimed.
	var native_policy := Reconstruction.resolve("native", true)
	var fsr_policy := Reconstruction.resolve("fsr2_native", true)
	check("native and FSR2 policies differ", native_policy.provider == "native" and fsr_policy.provider == "fsr2"
		and native_policy.scaling_3d_mode != fsr_policy.scaling_3d_mode)
	var view := SubViewport.new()
	view.size = Vector2i(1920, 1080)
	view.scaling_3d_scale = 1.0
	view.msaa_3d = Viewport.MSAA_DISABLED
	view.scaling_3d_mode = int(native_policy.scaling_3d_mode)
	var native_workload := Calibration.current_workload(view)
	view.scaling_3d_mode = int(fsr_policy.scaling_3d_mode)
	var fsr_workload := Calibration.current_workload(view)
	check("viewport retains different mode", view.scaling_3d_mode == fsr_policy.scaling_3d_mode)
	check("different providers alias in workload identity", native_workload == fsr_workload)
	Calibration.clear()
	check("native synthetic verdict saved", Calibration.save_result({adapter = ADAPTER, method = "forward_plus",
		level = "high", pixels = PIXELS, render_pixels = PIXELS, msaa_3d = Viewport.MSAA_DISABLED,
		complete = true, scene_offset = 0, reject_high = false, gpu_p95_ms = 3.0}))
	var provider_needs := Calibration.needed(ADAPTER, "forward_plus", PIXELS, "high", fsr_workload)
	check("provider change does not schedule a new calibration", not provider_needs)
	results["provider_alias"] = {native_mode = native_policy.scaling_3d_mode, fsr_mode = fsr_policy.scaling_3d_mode,
		native_workload = native_workload, fsr_workload = fsr_workload, needs_remeasurement = provider_needs}
	view.free()

	# Positive polls carry no completed-frame identity. This is a classifier witness, not a stale-device proof.
	var gpu := PackedFloat64Array()
	var cpu := PackedFloat64Array()
	var interval := PackedFloat64Array()
	for index in 300:
		gpu.append(3.0)
		cpu.append(1.0)
		interval.append(1000.0 / 60.0)
	var floor_120 := Calibration.interval_floor_ms(120.0, true, 0)
	var polling := Calibration.evaluate(gpu, true, "forward_plus", cpu, interval, floor_120)
	check("300 repeated positive polls qualify classifier", polling.complete and polling.scene_offset == 1)
	check("120 Hz display retains intentional 60 Hz floor", is_equal_approx(floor_120, 1000.0 / 60.0))
	check("60 Hz process cadence is not blocked at that floor", not polling.cpu_bound)
	results["poll_classifier_only"] = {floor_at_120_hz_ms = floor_120, verdict = polling,
		fresh_gpu_samples_proven = false, device_or_display_performance_measured = false}
	# Pure formatter witness. Runtime loads the current renderer's slot, not the rejected Forward+ slot.
	var current_method_record := {complete = true, method = "gl_compatibility", pixels = PIXELS,
		gpu_p95_ms = 6.0}
	var tooltip := Report.player_summary({decisions = {renderer = unvetoed.profile, scene_detail = "high"},
		applied = {calibration = current_method_record}})
	check("summary retains raw heuristic mode", tooltip.mode == "high" and vetoed.profile == "standard")
	results["summary_scope"] = {heuristic_summary = tooltip, vetoed_plan = vetoed.profile,
		current_method_record = current_method_record, runtime_or_ui_executed = false}
	Calibration.clear()
	Calibration.calibration_path = Calibration.CALIBRATION_PATH
	results["checks"] = checks
	results["failures"] = failures
	print("GRAPHICS_AUDIT_RESULT " + JSON.stringify(results, "", true, true))
	print("graphics audit policy witnesses: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)
