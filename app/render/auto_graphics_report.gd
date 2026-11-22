extends RefCounted
## VQ-07h-A0 (docs/plans/automatic-graphics.md): one explanation of every automatic graphics decision.
## `decide()` is pure: for given hardware inputs it returns what Automatic chooses today, by calling the existing
## entry points (renderer, Scene detail, first-launch values). The decision snapshot test and the runtime report
## both use it, so a later consolidation (A1) can be checked against today's behaviour line by line.
## `runtime()` adds the actual host: adapter, renderer, display, RAM, CPU, driver, saved mode and calibration.

const GpuCapability := preload("res://render/gpu_capability.gd")
const AutoGraphicsPolicy := preload("res://render/auto_graphics_policy.gd")
const RendererPreference := preload("res://app_state/renderer_preference.gd")
const SceneDetail := preload("res://render/scene_detail.gd")
const AutoCalibration := preload("res://render/auto_calibration.gd")

const FORMAT := "openrc-auto-graphics-report v1"


## inputs: {adapter, os, arm64, screen: Vector2i, scale, refresh, cpu_threads, forward_plus}. Returns {renderer,
## scene_detail, first_run, reasons}.
static func decide(inputs: Dictionary) -> Dictionary:
	return AutoGraphicsPolicy.decide(inputs)


## One compact line per decision, for snapshots and logs: renderer, scene, MSAA, window, cap, resolution and shadows ("-" = default).
static func compact(decision: Dictionary) -> String:
	var first_run: Dictionary = decision.get("first_run", {})
	return "|".join([str(decision.renderer), str(decision.scene_detail),
		str(first_run.get("msaa_3d", "-")), str(first_run.get("window_mode", "-")), str(first_run.get("max_fps", "-")),
		str(first_run.get("window_resolution", "-")), str(first_run.get("shadow_quality", "-")),
		str(first_run.get("shadow_technique", "-"))])


## VQ-07h-A7: what Settings tells the player about Automatic on this host: the mode and Scene detail it picks, how
## far the GPU estimate is trusted, and the first-flight measurement when one exists. Pure; input is runtime().
## estimate: "measured", "benchmarks", "extrapolated" or "unknown"; measured_p95_ms is 0 until a complete verdict.
static func player_summary(report: Dictionary) -> Dictionary:
	var inputs: Dictionary = report.get("inputs", {})
	var decisions: Dictionary = report.get("decisions", {})
	var applied: Dictionary = report.get("applied", {})
	var gpu: Dictionary = inputs.get("gpu", {})
	var provenance := str(gpu.get("provenance", "unknown")).get_slice(":", 0) if not AutoGraphicsPolicy.needs_fallback(gpu) \
		else "unknown"
	var estimate: String = {"measured": "measured", "benchmark-derived": "benchmarks", "extrapolated": "extrapolated",
		"measured-circular": "extrapolated"}.get(provenance, "unknown")
	var automatic: Dictionary = applied.get("scene_detail_automatic", {})
	var calibration: Dictionary = applied.get("calibration", {})
	return {
		"mode": "high" if str(decisions.get("renderer", "")) == "high" else "standard",
		"scene_detail": str(automatic.get("level", decisions.get("scene_detail", ""))),
		"estimate": estimate,
		"measured_p95_ms": float(calibration.get("gpu_p95_ms", 0.0)) if bool(calibration.get("complete", false)) else 0.0,
	}


## The actual host and what Automatic decided for it, including saved and measured state.
static func runtime(include_driver_info: bool = true) -> Dictionary:
	var adapter := RenderingServer.get_video_adapter_name()
	var headless := DisplayServer.get_name() == "headless"
	var index := 0 if headless else DisplayServer.window_get_current_screen()
	var screen := Vector2i.ZERO if headless else DisplayServer.screen_get_size(index)
	var inputs := {adapter = adapter, os = OS.get_name(), arm64 = OS.has_feature("arm64"), screen = screen,
		usable = Vector2i.ZERO if headless else DisplayServer.screen_get_usable_rect(index).size,
		scale = 1.0 if headless else DisplayServer.screen_get_scale(index),
		refresh = 60.0 if headless else DisplayServer.screen_get_refresh_rate(index), cpu_threads = OS.get_processor_count(),
		forward_plus = RenderingServer.get_current_rendering_method() == "forward_plus"}
	if AutoGraphicsPolicy.startup_output_pixels > 0:
		inputs["output_pixels"] = AutoGraphicsPolicy.startup_output_pixels
	var memory := OS.get_memory_info()
	var method := RenderingServer.get_current_rendering_method()
	var gpu := GpuCapability.lookup(adapter)
	var detected := SceneDetail.detected()
	return {
		"format": FORMAT,
		"inputs": {
			"adapter": adapter, "vendor": RenderingServer.get_video_adapter_vendor(),
			"adapter_key": AutoCalibration.adapter_key(adapter), "gpu": gpu,
			"driver_info": OS.get_video_adapter_driver_info() if include_driver_info else PackedStringArray(),
			"os": OS.get_name(), "arm64": inputs.arm64, "template": OS.has_feature("template"),
			"rendering_method": method, "rendering_driver": RenderingServer.get_current_rendering_driver_name(),
			"screen": [screen.x, screen.y], "screen_scale": inputs.scale, "refresh_hz": inputs.refresh,
			"window": [] if headless else [DisplayServer.window_get_size().x, DisplayServer.window_get_size().y],
			"ram_physical_bytes": int(memory.get("physical", -1)),
			"cpu_name": OS.get_processor_name(), "cpu_threads": OS.get_processor_count(),
		},
		"decisions": decide(inputs),
		"applied": {
			"saved_renderer_mode": RendererPreference.load_state(),
			"scene_detail_automatic": detected,
			"calibration": AutoCalibration.load_result(adapter, method),
		},
	}
