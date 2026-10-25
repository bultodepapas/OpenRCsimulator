extends SceneTree

const Reconstruction := preload("res://render/reconstruction.gd")
const Preferences := preload("res://app_state/display_preferences.gd")
const HighGraphics := preload("res://render/high_graphics_profile.gd")
const FSR3_TEST_MODE := 101
const DLSS_TEST_MODE := 102
const PREFS_PATH := "user://test_reconstruction_preferences.cfg"
var checks := 0
var failures := 0

func _initialize() -> void:
	_check("preference modes match renderer policy", Reconstruction.MODES == Preferences.RECONSTRUCTION_MODES)
	var no_providers := _caps(false, false, false)
	for mode: String in Reconstruction.MODES:
		var fallback := Reconstruction.resolve(mode, no_providers)
		_check("unsupported mode preserves request and uses native: " + mode,
			fallback.requested == mode and fallback.effective == "native" and fallback.provider == "native"
			and fallback.scale == 1.0 and not fallback.temporal)
	_check("invalid selection uses native with an unknown-mode receipt",
		Reconstruction.resolve("fsr3", no_providers).fallback_reason == "unknown_mode")

	_check("FSR2 native AA uses full resolution", Reconstruction.resolve("fsr2_native", true).scale == 1.0)
	_check("FSR2 quality uses two-thirds resolution", is_equal_approx(Reconstruction.resolve("fsr2_quality", true).scale, 2.0 / 3.0))
	_check("FSR2 custom 85 percent retains more input detail", is_equal_approx(Reconstruction.resolve("fsr2_85", true).scale, 0.85))
	_check("FSR2 balanced follows AMD ratio", is_equal_approx(Reconstruction.resolve("fsr2_balanced", true).scale, 1.0 / 1.7))
	_check("FSR2 performance uses half resolution", Reconstruction.resolve("fsr2_performance", true).scale == 0.5)
	_check("FSR3 and DLSS offer the requested output scales",
		is_equal_approx(Reconstruction.resolve("fsr3_85", _caps(true, true, false, FSR3_TEST_MODE)).scale, 0.85)
		and is_equal_approx(Reconstruction.resolve("dlss_quality", _caps(true, false, true, -1, DLSS_TEST_MODE)).scale, 2.0 / 3.0)
		and is_equal_approx(Reconstruction.resolve("dlss_balanced", _caps(true, false, true, -1, DLSS_TEST_MODE)).scale, 1.0 / 1.7)
		and Reconstruction.resolve("dlss_performance", _caps(true, false, true, -1, DLSS_TEST_MODE)).scale == 0.5)
	var saved_fsr_strength := 0.35
	var dlss_engine_sharpness := Reconstruction._engine_sharpness_value("dlss", saved_fsr_strength)
	var dlss_sharpness_receipt := Reconstruction._sharpening_receipt("dlss", dlss_engine_sharpness)
	_check("DLSS forces the extra engine sharpener off and reports zero strength",
		dlss_engine_sharpness == 0.0 and dlss_sharpness_receipt.sharpening_strength == 0.0
		and not dlss_sharpness_receipt.sharpening_active)
	var saved_dlss_preferences := Preferences.DEFAULTS.duplicate(true)
	saved_dlss_preferences.reconstruction = "dlss_quality"
	saved_dlss_preferences.fsr2_sharpness = saved_fsr_strength
	var saved_dlss_validation := Preferences.validate(saved_dlss_preferences)
	_check("FSR sharpness remains a separate saved preference while DLSS is active",
		saved_dlss_validation.ok and saved_dlss_validation.config.fsr2_sharpness == saved_fsr_strength)

	var amd_caps := _caps(true, true, false, FSR3_TEST_MODE)
	var nvidia_caps := _caps(true, true, true, FSR3_TEST_MODE, DLSS_TEST_MODE)
	var intel_caps := _caps(true, true, false, FSR3_TEST_MODE)
	var unavailable_caps := _caps(false, false, false)
	_check("AMD-capability fixture enables FSR3 and rejects DLSS",
		Reconstruction.resolve("fsr3_quality", amd_caps).effective == "fsr3_quality"
		and Reconstruction.resolve("dlss_quality", amd_caps).fallback_reason == "dlss_unavailable")
	_check("NVIDIA-capability fixture enables DLSS without a GPU-name check",
		Reconstruction.resolve("dlss_balanced", nvidia_caps).effective == "dlss_balanced"
		and Reconstruction.resolve("dlss_balanced", nvidia_caps).provider == "dlss")
	_check("Intel-capability fixture enables FSR3 without DLSS",
		Reconstruction.resolve("fsr3_performance", intel_caps).effective == "fsr3_performance"
		and Reconstruction.resolve("dlss_performance", intel_caps).effective == "native")
	_check("unavailable runtime reports the requested provider and native effective provider",
		Reconstruction.resolve("dlss_quality", unavailable_caps).requested_provider == "dlss"
		and Reconstruction.resolve("dlss_quality", unavailable_caps).effective_provider == "native"
		and Reconstruction.resolve("dlss_quality", unavailable_caps).fallback_reason == "high_profile_inactive")
	_check("provider gates keep each menu choice independently disabled",
		not Reconstruction.option_status("fsr3_native", unavailable_caps).available
		and not Reconstruction.option_status("dlss_native", amd_caps).available
		and Reconstruction.option_status("native", unavailable_caps).available)
	var missing_native_modes := _caps(true, true, true)
	_check("FSR3 and DLSS fail closed when an engine mode constant is absent",
		Reconstruction.resolve("fsr3_native", missing_native_modes).fallback_reason == "engine_mode_missing"
		and Reconstruction.resolve("dlss_native", missing_native_modes).fallback_reason == "engine_mode_missing")
	var reason_caps := _caps(true, false, false)
	reason_caps["fsr3_reason"] = "fsr3_support_missing"
	reason_caps["dlss_reason"] = "dlss_support_missing"
	_check("provider menu status preserves the specific runtime limitation",
		Reconstruction.option_status("fsr3_quality", reason_caps).reason == "fsr3_support_missing"
		and Reconstruction.option_status("dlss_quality", reason_caps).reason == "dlss_support_missing")
	for mode: String in Preferences.RECONSTRUCTION_MODES:
		var candidate := Preferences.DEFAULTS.duplicate(true)
		candidate.reconstruction = mode
		_check("saved preference accepts provider mode: " + mode,
			Preferences.validate(candidate).ok and Preferences.save_to(PREFS_PATH, candidate) == OK
			and Preferences.load_from(PREFS_PATH).reconstruction == mode)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS_PATH))

	_check("native captures retain their two-frame settle", Reconstruction.capture_settle_frames(Viewport.SCALING_3D_MODE_BILINEAR, 1.0) == 2)
	_check("FSR2 Native AA captures allow temporal history", Reconstruction.capture_settle_frames(Viewport.SCALING_3D_MODE_FSR2, 1.0) == 16)
	_check("FSR2 Quality captures allow two jitter cycles", Reconstruction.capture_settle_frames(Viewport.SCALING_3D_MODE_FSR2, 2.0 / 3.0) == 36)
	_check("FSR2 Performance captures have bounded history", Reconstruction.capture_settle_frames(Viewport.SCALING_3D_MODE_FSR2, 0.5) == 64)
	_check("FSR3 and DLSS dynamic modes settle as temporal providers",
		Reconstruction.capture_settle_frames(FSR3_TEST_MODE, 2.0 / 3.0, amd_caps) == 36
		and Reconstruction.capture_settle_frames(DLSS_TEST_MODE, 0.5, nvidia_caps) == 64)

	var runtime_caps := Reconstruction.runtime_capabilities()
	var fsr3_enum_present := ClassDB.class_has_integer_constant("Viewport", "SCALING_3D_MODE_FSR3")
	var fsr3_method_present := RenderingServer.has_method("is_fsr3_available")
	var fsr3_backend_available := fsr3_enum_present and fsr3_method_present \
		and bool(RenderingServer.call("is_fsr3_available"))
	_check("FSR3 runtime gate requires the enum, native method and active High renderer",
		runtime_caps.fsr3 == (runtime_caps.high and fsr3_backend_available))
	if not Engine.has_singleton("Streamline"):
		_check("DLSS is unavailable without the Streamline singleton", not runtime_caps.dlss)

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
	var supported_caps := Reconstruction.runtime_capabilities()
	var supported_policy := Reconstruction.resolve(settings.reconstruction, supported_caps)
	Reconstruction.apply(root, settings, supported_caps)
	_check("active mode matches effective runtime provider", root.scaling_3d_mode == int(supported_policy.scaling_3d_mode))
	_check("AA ownership follows effective reconstruction", root.msaa_3d == (Viewport.MSAA_DISABLED if supported_policy.temporal else Viewport.MSAA_8X))
	_check("quality scale follows effective reconstruction", is_equal_approx(root.scaling_3d_scale, supported_policy.scale))
	_check("applying policy never rewrites saved config", settings == before)
	_check("secondary viewports remain unchanged", secondary.msaa_3d == Viewport.MSAA_2X and secondary.scaling_3d_scale == 1.0)
	for strength: float in [0.0, 0.5, 0.9, 1.0]:
		settings.fsr2_sharpness = strength
		Reconstruction.apply(root, settings, supported_caps)
		_check("user sharpening maps to inverted engine scale: %s" % strength, is_equal_approx(root.fsr_sharpness, 2.0 * (1.0 - strength)))
		var receipt := Reconstruction.describe(root)
		var fsr_active: bool = supported_policy.provider in ["fsr2", "fsr3"] and strength > 0.0
		_check("provider sharpening receipt: %s" % strength, receipt.sharpening_active == fsr_active)
	for invalid: Variant in [NAN, INF, "bad", null]:
		_check("invalid runtime strength falls back safely", Reconstruction.sharpness_strength(invalid) == Reconstruction.DEFAULT_SHARPNESS)
	_check("runtime strength clamps bounds", Reconstruction.sharpness_strength(-1) == 0.0 and Reconstruction.sharpness_strength(2) == 1.0)
	for mode: String in Reconstruction.MODES:
		settings.reconstruction = mode
		Reconstruction.apply(root, settings, supported_caps)
		var expected := Reconstruction.resolve(mode, supported_caps)
		_check("each mode applies its effective scale: " + mode, is_equal_approx(root.scaling_3d_scale, expected.scale)
			and Reconstruction.describe(root).provider == expected.provider)
	settings.reconstruction = "fsr2_quality"
	OS.set_environment("OPENRC_GRAPHICS_PROFILE", "standard")
	var standard_caps := Reconstruction.runtime_capabilities()
	Reconstruction.apply(root, settings, standard_caps)
	_check("High to Standard restores native MSAA", root.scaling_3d_mode == Viewport.SCALING_3D_MODE_BILINEAR
		and root.scaling_3d_scale == 1.0 and root.msaa_3d == Viewport.MSAA_8X)
	var reported := Reconstruction.describe(root)
	_check("receipt distinguishes saved request and effective fallback provider",
		reported.requested == "fsr2_quality" and reported.effective == "native"
		and reported.provider == "native" and reported.fallback)

	var failed_fsr3_config := Preferences.DEFAULTS.duplicate(true)
	failed_fsr3_config.reconstruction = "fsr3_quality"
	failed_fsr3_config.msaa_3d = 3
	failed_fsr3_config.fsr2_sharpness = 0.4
	var original_failed_fsr3_config := failed_fsr3_config.duplicate(true)
	# Model an already active FSR3 policy without assigning an engine-specific mode to
	# the stock test viewport. A false injected capability forces the rollback to native.
	root.set_meta(Reconstruction.POLICY_META, {
		"requested": "fsr3_quality", "requested_provider": "fsr3",
		"effective": "fsr3_quality", "effective_provider": "fsr3", "provider": "fsr3",
		"fallback": false,
	})
	root.set_meta(Reconstruction.CONFIG_META, failed_fsr3_config.duplicate(true))
	root.scaling_3d_scale = 2.0 / 3.0
	root.msaa_3d = Viewport.MSAA_DISABLED
	var healthy_backend := {available = true, backend_failed = false}
	var failure_caps := _caps(true, false, false)
	_check("healthy FSR3 status does not change the active preference",
		not Reconstruction.guard_runtime_failure(root, healthy_backend, failure_caps)
		and is_equal_approx(root.scaling_3d_scale, 2.0 / 3.0)
		and root.msaa_3d == Viewport.MSAA_DISABLED)
	var backend_failure := {available = false, backend_failed = true, last_return_code = 9}
	_check("FSR3 runtime failure rolls the owning viewport back to native AA and full resolution",
		Reconstruction.guard_runtime_failure(root, backend_failure, failure_caps)
		and root.scaling_3d_mode == Viewport.SCALING_3D_MODE_BILINEAR
		and root.scaling_3d_scale == 1.0 and root.msaa_3d == Viewport.MSAA_8X)
	var failure_receipt := Reconstruction.describe(root)
	_check("runtime rollback preserves the requested provider and records the native fallback",
		failure_receipt.requested == "fsr3_quality" and failure_receipt.effective == "native"
		and failure_receipt.requested_provider == "fsr3" and failure_receipt.provider == "native"
		and failure_receipt.fallback and failure_receipt.fallback_reason == "fsr3_runtime_failure"
		and failure_receipt.runtime_failure.reason == "backend_failed"
		and failure_receipt.runtime_failure.backend.last_return_code == 9)
	_check("runtime rollback does not alter the saved reconstruction preference",
		failed_fsr3_config == original_failed_fsr3_config
		and root.get_meta(Reconstruction.CONFIG_META) == original_failed_fsr3_config)
	Reconstruction.apply(root, failed_fsr3_config, failure_caps)
	var persisted_failure_receipt := Reconstruction.describe(root)
	_check("runtime failure receipt survives later presentation settings reapplication",
		persisted_failure_receipt.provider == "native"
		and persisted_failure_receipt.runtime_failure.reason == "backend_failed")
	_check("runtime rollback is idempotent after switching provider to native",
		not Reconstruction.guard_runtime_failure(root, backend_failure, failure_caps))
	if had_profile:
		OS.set_environment("OPENRC_GRAPHICS_PROFILE", previous_profile)
	else:
		OS.unset_environment("OPENRC_GRAPHICS_PROFILE")
	secondary.free()
	print("reconstruction: %d checks, %d failed; High active=%s" % [checks, failures, HighGraphics.active()])
	quit(0 if failures == 0 else 1)


func _caps(high: bool, fsr3: bool, dlss: bool, fsr3_mode := -1, dlss_mode := -1) -> Dictionary:
	return {"high": high, "fsr2": high, "fsr3": fsr3, "dlss": dlss,
		"fsr2_mode": Viewport.SCALING_3D_MODE_FSR2,
		"fsr3_mode": fsr3_mode if fsr3_mode >= 0 else null,
		"dlss_mode": dlss_mode if dlss_mode >= 0 else null}


func _check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)
