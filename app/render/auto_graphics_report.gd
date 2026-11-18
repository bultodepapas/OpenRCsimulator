extends RefCounted
## VQ-07h-A0 (docs/plans/automatic-graphics.md): one explanation of every automatic graphics decision.
## `decide()` is pure: for given hardware inputs it returns what Automatic chooses today, by calling the existing
## entry points (renderer, Scene detail, first-launch values). The decision snapshot test and the runtime report
## both use it, so a later consolidation (A1) can be checked against today's behaviour line by line.
## `runtime()` adds the actual host: adapter, renderer, display, RAM, CPU, driver, saved mode and calibration.

const GpuCapability := preload("res://render/gpu_capability.gd")
const RendererPreference := preload("res://app_state/renderer_preference.gd")
const SceneDetail := preload("res://render/scene_detail.gd")
const AutoCalibration := preload("res://render/auto_calibration.gd")

const FORMAT := "openrc-auto-graphics-report v1"


## inputs: {adapter, os, arm64, screen: Vector2i, scale, refresh}. Returns {renderer, scene_detail, first_run, reasons}.
static func decide(inputs: Dictionary) -> Dictionary:
	var adapter := str(inputs.get("adapter", ""))
	var os_name := str(inputs.get("os", ""))
	var screen: Vector2i = inputs.get("screen", Vector2i.ZERO)
	var scale := float(inputs.get("scale", 1.0))
	var refresh := float(inputs.get("refresh", 60.0))
	var renderer := RendererPreference.auto_profile({os = os_name, arm64 = bool(inputs.get("arm64", false)),
		adapter = adapter, pixels = screen.x * screen.y})
	# Retina Macs judge Scene detail at the pixels rendered under Automatic MetalFX (AGENTS display exception).
	var render_pixels := GpuCapability.mac_render_pixels(screen) \
		if GpuCapability.mac_native_target(os_name, scale) and bool(inputs.get("arm64", false)) else 0
	var scene: Dictionary = SceneDetail.recommend(adapter, "", render_pixels)
	var first_run := GpuCapability.first_run_settings(adapter, os_name, scale, refresh)
	return {"renderer": str(renderer.profile), "scene_detail": str(scene.level), "first_run": first_run,
		"reasons": {"renderer": str(renderer.reason), "scene_detail": str(scene.get("detail", scene.reason))}}


## One compact line per decision, for snapshots and logs: renderer|scene|msaa|window|max_fps ("-" = default).
static func compact(decision: Dictionary) -> String:
	var first_run: Dictionary = decision.get("first_run", {})
	return "|".join([str(decision.renderer), str(decision.scene_detail),
		str(first_run.get("msaa_3d", "-")), str(first_run.get("window_mode", "-")), str(first_run.get("max_fps", "-"))])


## The actual host and what Automatic decided for it, including saved and measured state.
static func runtime() -> Dictionary:
	var adapter := RenderingServer.get_video_adapter_name()
	var headless := DisplayServer.get_name() == "headless"
	var screen := Vector2i.ZERO if headless else DisplayServer.screen_get_size(DisplayServer.window_get_current_screen())
	var inputs := {adapter = adapter, os = OS.get_name(), arm64 = OS.has_feature("arm64"), screen = screen,
		scale = 1.0 if headless else DisplayServer.screen_get_scale(),
		refresh = 60.0 if headless else DisplayServer.screen_get_refresh_rate()}
	var memory := OS.get_memory_info()
	var method := RenderingServer.get_current_rendering_method()
	var gpu := GpuCapability.lookup(adapter)
	var detected := SceneDetail.detected()
	return {
		"format": FORMAT,
		"inputs": {
			"adapter": adapter, "vendor": RenderingServer.get_video_adapter_vendor(),
			"adapter_key": AutoCalibration.adapter_key(adapter), "gpu": gpu,
			"driver_info": OS.get_video_adapter_driver_info(),
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
