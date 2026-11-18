extends Node
const GC := preload("res://render/gpu_capability.gd")
func _ready() -> void:
	await get_tree().process_frame
	var adapter := RenderingServer.get_video_adapter_name()
	var report := {"os": OS.get_name(), "arm64": OS.has_feature("arm64"), "adapter": adapter,
		"vendor": RenderingServer.get_video_adapter_vendor(), "method": RenderingServer.get_current_rendering_method(),
		"driver": RenderingServer.get_current_rendering_driver_name(), "lookup": GC.lookup(adapter),
		"window_screen": DisplayServer.window_get_current_screen(), "primary": DisplayServer.get_primary_screen(),
		"max_scale": DisplayServer.screen_get_max_scale(), "screens": []}
	for i in DisplayServer.get_screen_count():
		var size := DisplayServer.screen_get_size(i)
		var scale := DisplayServer.screen_get_scale(i)
		var refresh := DisplayServer.screen_get_refresh_rate(i)
		report.screens.append({"index": i, "size": [size.x, size.y], "scale": scale, "refresh": refresh,
			"usable": [DisplayServer.screen_get_usable_rect(i).size.x, DisplayServer.screen_get_usable_rect(i).size.y],
			"dpi": DisplayServer.screen_get_dpi(i), "native_target": GC.mac_native_target(OS.get_name(), scale),
			"render_pixels_metalfx": GC.mac_render_pixels(size),
			"first_run": GC.first_run_settings(adapter, OS.get_name(), scale, refresh),
			"scene_detail_native": GC.scene_detail_level(adapter, GC.mac_render_pixels(size)).level,
			"scene_detail_1080p": GC.scene_detail_level(adapter).level})
	print("MACPROBE " + JSON.stringify(report))
	get_tree().quit()
