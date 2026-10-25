extends SceneTree

const Reconstruction := preload("res://render/reconstruction.gd")
const Preferences := preload("res://app_state/display_preferences.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_check("preference modes match renderer policy", Reconstruction.MODES == Preferences.RECONSTRUCTION_MODES)
	for mode: String in Reconstruction.MODES:
		var fallback := Reconstruction.resolve(mode, false)
		_check("unsupported mode uses native: " + mode, fallback.effective == "native" and fallback.scale == 1.0 and not fallback.temporal)
	_check("invalid selection uses native", Reconstruction.resolve("fsr3", true).effective == "native")
	_check("native AA uses full resolution", Reconstruction.resolve("fsr2_native", true).scale == 1.0)
	_check("quality uses two-thirds resolution", is_equal_approx(Reconstruction.resolve("fsr2_quality", true).scale, 2.0 / 3.0))
	var previous_profile := OS.get_environment("OPENRC_GRAPHICS_PROFILE")
	var had_profile := OS.has_environment("OPENRC_GRAPHICS_PROFILE")
	var secondary := SubViewport.new()
	root.add_child(secondary)
	secondary.msaa_3d = Viewport.MSAA_2X
	var settings := Preferences.DEFAULTS.duplicate(true)
	settings.msaa_3d = 3
	settings.reconstruction = "fsr2_quality"
	var before := settings.duplicate(true)
	OS.set_environment("OPENRC_GRAPHICS_PROFILE", "high")
	var supported := Reconstruction.available()
	Reconstruction.apply(root, settings)
	_check("active mode matches runtime support", root.scaling_3d_mode == (Viewport.SCALING_3D_MODE_FSR2 if supported else Viewport.SCALING_3D_MODE_BILINEAR))
	_check("AA ownership follows effective reconstruction", root.msaa_3d == (Viewport.MSAA_DISABLED if supported else Viewport.MSAA_8X))
	_check("quality scale follows effective reconstruction", is_equal_approx(root.scaling_3d_scale, 2.0 / 3.0 if supported else 1.0))
	_check("applying policy never rewrites saved config", settings == before)
	_check("secondary viewports remain unchanged", secondary.msaa_3d == Viewport.MSAA_2X and secondary.scaling_3d_scale == 1.0)
	OS.set_environment("OPENRC_GRAPHICS_PROFILE", "standard")
	Reconstruction.apply(root, settings)
	_check("High to Standard restores native MSAA", root.scaling_3d_mode == Viewport.SCALING_3D_MODE_BILINEAR and root.scaling_3d_scale == 1.0 and root.msaa_3d == Viewport.MSAA_8X)
	var reported := Reconstruction.describe(root)
	_check("receipt distinguishes saved request and fallback", reported.requested == "fsr2_quality" and reported.effective == "native" and reported.msaa_3d == 3)
	if had_profile:
		OS.set_environment("OPENRC_GRAPHICS_PROFILE", previous_profile)
	else:
		OS.unset_environment("OPENRC_GRAPHICS_PROFILE")
	secondary.free()
	print("reconstruction: %d checks, %d failed; native High exercised=%s" % [checks, failures, supported])
	quit(0 if failures == 0 else 1)

func _check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

