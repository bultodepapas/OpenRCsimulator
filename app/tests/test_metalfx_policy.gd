extends SceneTree
const MetalFX := preload("res://render/metalfx_policy.gd")
const Reconstruction := preload("res://render/reconstruction.gd")
const Preferences := preload("res://app_state/display_preferences.gd")
const CameraRig := preload("res://render/camera/camera_rig.gd")
const Settings := preload("res://ui/settings_screen.gd")

class AdvertisingBackend extends RefCounted:
	var requests: Array[RID] = []
	func get_temporal_history_reset_providers() -> PackedStringArray:
		return PackedStringArray(["metalfx_temporal"])
	func viewport_request_temporal_history_reset(viewport: RID) -> void:
		requests.append(viewport)

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var facts := {"trial": true, "headless": false, "driver": "metal", "method": "mobile",
		"rd_available": true, "metalfx_spatial_mode": 201, "metalfx_temporal_mode": 202,
		"metalfx_spatial_supported": true, "metalfx_temporal_supported": true,
		"min_scale": 0.5, "max_scale": 1.0}
	var mobile := MetalFX.from_facts(facts)
	mobile.high = false
	var spatial := Reconstruction.resolve("metalfx_spatial_85", mobile)
	_check("Mobile spatial does not require High effects", spatial.provider == "metalfx_spatial" and spatial.scale == 0.85)
	_check("spatial preserves MSAA and has no temporal history", not spatial.temporal and Reconstruction.capture_settle_frames(201, 0.85, mobile) == 2)
	_check("trial separates the selected mode from unknown GPU execution", spatial.selected == "metalfx_spatial_85"
		and spatial.effective == "unknown" and spatial.effective_provider == "unknown"
		and spatial.execution_status == "unverified_trial")
	_check("Mobile rejects temporal before applying an engine enum", Reconstruction.resolve("metalfx_temporal_85", mobile).fallback_reason == "metalfx_requires_forward_plus")
	_check("provider picker can operate without High", Reconstruction.options_available(mobile))
	# DT-MAC-07b: "auto" keeps MetalFX input at >= 1000 rows (1080p-class), else Native.
	var auto_caps := MetalFX.from_facts(facts)
	auto_caps.high = false
	for row: Array in [[Vector2i(2560, 1600), "metalfx_spatial_quality"], [Vector2i(2880, 1800), "metalfx_spatial_quality"],
			[Vector2i(2560, 1440), "metalfx_spatial_85"], [Vector2i(1920, 1200), "metalfx_spatial_85"],
			[Vector2i(1920, 1080), "native"], [Vector2i(1280, 720), "native"]]:
		_check("auto at %s selects %s" % [row[0], row[1]], Reconstruction.auto_mode(auto_caps, row[0]) == row[1])
	var no_metal := facts.duplicate(true)
	no_metal.driver = "opengl3"
	no_metal.method = "gl_compatibility"
	_check("auto without MetalFX stays Native", Reconstruction.auto_mode(MetalFX.from_facts(no_metal), Vector2i(2560, 1600)) == "native")
	Reconstruction.auto_output_size = Vector2i(2560, 1600)
	var auto_policy := Reconstruction.resolve("auto", auto_caps)
	_check("auto reports its request and concrete choice", auto_policy.requested == "auto"
		and auto_policy.auto_selected == "metalfx_spatial_quality" and auto_policy.provider == "metalfx_spatial")
	_check("auto is always a selectable option", Reconstruction.option_status("auto", MetalFX.from_facts(no_metal)).available)
	Reconstruction.auto_output_size = Vector2i.ZERO
	# DT-MAC-07a: Spatial no longer needs the trial; Temporal does; a guard block disables both.
	var no_trial := facts.duplicate(true)
	no_trial.trial = false
	_check("Spatial is available without the trial", Reconstruction.resolve("metalfx_spatial_85",
		MetalFX.from_facts(no_trial)).provider == "metalfx_spatial")
	var no_trial_forward := no_trial.duplicate(true)
	no_trial_forward.method = "forward_plus"
	_check("Temporal still requires the trial", Reconstruction.resolve("metalfx_temporal_85",
		MetalFX.from_facts(no_trial_forward)).fallback_reason == "metalfx_trial_disabled")
	var blocked := facts.duplicate(true)
	blocked.blocked = "metalfx_failed_previously"
	blocked.method = "forward_plus"
	for mode: String in ["metalfx_spatial_85", "metalfx_temporal_85"]:
		var policy := Reconstruction.resolve(mode, MetalFX.from_facts(blocked))
		_check("guard block returns %s to Native" % mode, policy.provider == "native"
			and policy.fallback_reason == "metalfx_failed_previously")
	for variant: Array in [["headless", true], ["driver", "vulkan"], ["method", "gl_compatibility"],
			["rd_available", false], ["metalfx_spatial_supported", false], ["metalfx_spatial_mode", null]]:
		var unsupported := facts.duplicate(true)
		unsupported[variant[0]] = variant[1]
		var policy := Reconstruction.resolve("metalfx_spatial_85", MetalFX.from_facts(unsupported))
		_check("unsupported fact falls back to Native: " + str(variant), policy.provider == "native" and policy.scale == 1.0 and not policy.temporal and policy.requested == "metalfx_spatial_85")
	facts.method = "forward_plus"
	var forward := MetalFX.from_facts(facts)
	forward.high = false
	var temporal := Reconstruction.resolve("metalfx_temporal_85", forward)
	_check("Forward temporal uses its own capability gate", temporal.provider == "metalfx_temporal" and temporal.temporal)
	_check("temporal trial also leaves effective mode unknown", temporal.selected == "metalfx_temporal_85"
		and temporal.effective == "unknown" and not temporal.fallback)
	_check("temporal history settles separately", Reconstruction.capture_settle_frames(202, 0.85, forward) >= 16)
	for limits: Array in [[0.0, 1.0], [NAN, 1.0], [0.5, INF], [0.8, 0.5], ["0.5", 1.0], [0.5, null], [true, 1.0]]:
		var invalid := facts.duplicate(true)
		invalid.min_scale = limits[0]
		invalid.max_scale = limits[1]
		var policy := Reconstruction.resolve("metalfx_temporal_85", MetalFX.from_facts(invalid))
		_check("invalid limits rejected: " + str(limits), policy.provider == "native" and policy.fallback_reason == "metalfx_invalid_scale_limits")
	var restricted := facts.duplicate(true)
	restricted.min_scale = 0.75
	var restricted_caps := MetalFX.from_facts(restricted)
	_check("valid device rejects unsupported Quality scale", Reconstruction.resolve("metalfx_temporal_quality", restricted_caps).fallback_reason == "metalfx_scale_out_of_range")
	_check("same device still offers 85 percent", Reconstruction.resolve("metalfx_temporal_85", restricted_caps).provider == "metalfx_temporal")
	_check("native temporal AA respects max limit", Reconstruction.resolve("metalfx_temporal_native", forward).temporal)
	for provider: String in MetalFX.PROVIDERS:
		_check("MetalFX does not borrow FSR sharpening", Reconstruction._engine_sharpness_value(provider, 0.9) == 0.0
			and not Reconstruction._sharpening_receipt(provider, 0.0).sharpening_active)
	for mode: String in Reconstruction.MODES:
		if mode.begins_with("metalfx_"):
			var config := Preferences.DEFAULTS.duplicate(true)
			config.reconstruction = mode
			_check("MetalFX saved preference validated: " + mode, Preferences.validate(config).ok)
	# No fake Metal enum is assigned to Windows. Model only the active policy so a
	# missing reset can exercise real Native restoration on the stock viewport.
	var config := Preferences.DEFAULTS.duplicate(true)
	config.reconstruction = "metalfx_temporal_85"
	config.msaa_3d = Viewport.MSAA_8X
	var before := config.duplicate(true)
	root.set_meta(Reconstruction.CONFIG_META, config)
	root.set_meta(Reconstruction.POLICY_META, temporal)
	var no_backend := RefCounted.new()
	_check("missing reset never claims submission", not Reconstruction.request_history_reset(root, "camera_cut", no_backend))
	var report := Reconstruction.describe(root)
	_check("camera discontinuity restores Native and AA", report.provider == "native" and root.scaling_3d_scale == 1.0 and root.msaa_3d == Viewport.MSAA_8X)
	_check("camera fallback preserves saved request", config == before and report.requested == "metalfx_temporal_85")
	_check("fallback records missing reset separately", report.runtime_failure.reason == "history_reset_unavailable" and report.history_reset.submitted == 0)
	Reconstruction.apply(root, config, forward)
	_check("settings reapply cannot revive invalid temporal history", Reconstruction.describe(root).provider == "native")
	config.reconstruction = "native"
	Reconstruction.apply(root, config)
	_check("explicit Native clears the per-viewport latch", not root.has_meta(Reconstruction.RUNTIME_FAILURE_META))
	config.reconstruction = "metalfx_temporal_85"
	root.set_meta(Reconstruction.CONFIG_META, config)
	root.set_meta(Reconstruction.POLICY_META, temporal)
	var advertised := AdvertisingBackend.new()
	_check("provider advertisement cannot acknowledge a MetalFX reset",
		not Reconstruction.request_history_reset(root, "camera_cut", advertised) and advertised.requests.is_empty())
	report = Reconstruction.describe(root)
	_check("unacknowledged reset falls back and never counts a submission", report.provider == "native"
		and report.effective == "native" and report.history_reset.submitted == 0
		and report.runtime_failure.reason == "history_reset_unavailable")

	# Model the startup seam used by Main: the rig starts at pilot and applies the
	# requested non-pilot view before its first placement. No fake Metal enum is
	# assigned to a Windows viewport. A cut must still roll the policy back.
	var view := SubViewport.new()
	view.size = Vector2i(1920, 1080)
	root.add_child(view)
	var camera := Camera3D.new()
	view.add_child(camera)
	var rig := CameraRig.new(camera, 1.5)
	view.set_meta(Reconstruction.CONFIG_META, config.duplicate(true))
	view.set_meta(Reconstruction.POLICY_META, temporal.duplicate(true))
	var settings := Settings.new(Preferences.new("user://test_metalfx_policy.cfg"), "en")
	view.add_child(settings)
	settings._draft.reconstruction = config.reconstruction
	settings._draft.msaa_3d = config.msaa_3d
	settings.presentation_changed.connect(func(draft: Dictionary) -> void: Reconstruction.apply(view, draft, forward))
	settings._sync_reconstruction_controls(forward)
	settings._refresh_graphics_info()
	_check("unverified trial is labelled unconfirmed and reserves temporal AA",
		settings._graphics_info.text.contains("Unconfirmed") and settings._msaa_picker.disabled)
	_check("the full selected option remains in the picker tooltip",
		settings._reconstruction_picker.tooltip_text.contains("MetalFX Temporal · 85%"))
	settings._draft.reconstruction = "native"
	settings._sync_reconstruction_controls(forward)
	_check("a different draft does not inherit the prior temporal receipt", not settings._msaa_picker.disabled)
	settings._draft.reconstruction = config.reconstruction
	settings._sync_reconstruction_controls(forward)
	_check("default pilot view causes no startup cut", rig.set_view("pilot")
		and not view.has_meta(Reconstruction.HISTORY_RESET_META))
	_check("initial non-pilot view reports a cut", rig.set_view("chase")
		and view.get_meta(Reconstruction.HISTORY_RESET_META).last_reason == "camera_view_changed")
	var cut_report := Reconstruction.describe(view)
	_check("initial non-pilot cut latches Native and restores MSAA", cut_report.provider == "native"
		and cut_report.effective == "native" and view.msaa_3d == Viewport.MSAA_8X
		and cut_report.runtime_failure.reason == "history_reset_unavailable")
	settings._process(0.5)
	_check("periodic settings refresh notices the viewport rollback", not settings._msaa_picker.disabled
		and settings._graphics_info.text.contains("Native"))
	# The periodic refresh must expose the same fallback, even if no other
	# reconstruction provider is available to enable the picker.
	var only_temporal := forward.duplicate(true)
	only_temporal.metalfx_spatial = false
	settings._sync_reconstruction_controls(only_temporal)
	settings._refresh_graphics_info()
	var temporal_index := Preferences.RECONSTRUCTION_MODES.find("metalfx_temporal_85")
	_check("latched fallback keeps MSAA and Native selection available", not settings._msaa_picker.disabled
		and not settings._reconstruction_picker.disabled and settings._reconstruction_picker.is_item_disabled(temporal_index)
		and settings._graphics_info.text.contains("Native"))
	_check("latched option explains how to retry", settings._reconstruction_picker.get_item_tooltip(temporal_index).contains("Select Native")
		and settings._reconstruction_picker.tooltip_text.contains("Select Native"))
	settings._reconstruction_picker.select(0)
	settings._reconstruction_picker.item_selected.emit(0)
	settings._sync_reconstruction_controls(forward)
	_check("choosing Native clears the latch and reopens the trial option", not view.has_meta(Reconstruction.RUNTIME_FAILURE_META)
		and not settings._reconstruction_picker.is_item_disabled(temporal_index))
	view.free()
	var runtime := MetalFX.runtime_capabilities()
	if OS.get_name() != "macOS" or DisplayServer.get_name() == "headless":
		_check("unsupported host never offers MetalFX", not runtime.metalfx_spatial and not runtime.metalfx_temporal)
	print("metalfx policy: %d checks, %d failed" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

