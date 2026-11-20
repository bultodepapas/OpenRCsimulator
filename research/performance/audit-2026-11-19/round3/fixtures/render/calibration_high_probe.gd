extends SceneTree
const AC := preload("res://render/auto_calibration.gd")
func _initialize() -> void:
	AC.calibration_path = "user://high_workload_probe.cfg"
	AC.clear()
	var gpu := "Synthetic GPU"
	var pixels := 1920 * 1080
	var measured := {"pixels": pixels, "render_pixels": pixels, "msaa_3d": int(Viewport.MSAA_4X)}
	AC.save_result({"adapter": gpu, "method": "forward_plus", "level": "high", "pixels": pixels,
		"render_pixels": pixels, "msaa_3d": int(Viewport.MSAA_4X), "complete": true, "reject_high": true})
	var same_needed := AC.needed(gpu, "forward_plus", pixels, "high", measured)
	var changed := {"pixels": pixels, "render_pixels": pixels, "msaa_3d": int(Viewport.MSAA_DISABLED)}
	var changed_needed := AC.needed(gpu, "forward_plus", pixels, "high", changed)
	var veto := AC.rejects_high(gpu, pixels)
	var size_control := AC.rejects_high(gpu, 1280 * 720)
	print("OBS same_needed=",same_needed," changed_msaa_needed=",changed_needed," same_size_veto=",veto," small_screen_veto=",size_control)
	var ok := not same_needed and changed_needed and veto and not size_control
	AC.clear()
	print("high workload probe: 1 check, ", 0 if ok else 1, " failed")
	quit(0 if ok else 1)
