extends SceneTree
## VQ-07h: saved graphics mode, Automatic policy and the exported-build renderer override.

const RendererPreference := preload("res://app_state/renderer_preference.gd")
const HighGraphics := preload("res://render/high_graphics_profile.gd")
const RendererGuard := preload("res://app_state/renderer_guard.gd")

const PRIVATE_PATH := "user://test renderer preference.cfg"
const BUILD := "0.2.8|abc|4.8"

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_test_auto_policy()
	_test_plan()
	_test_automatic_restart_sequence()
	_test_file_roundtrip()
	_test_standard_method()
	_test_project_setting()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PRIVATE_PATH))
	RendererPreference.override_path = RendererPreference.OVERRIDE_PATH
	print("renderer preference: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _check(name: String, ok: bool, detail: Variant = "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL: %s %s" % [name, str(detail)])


func _auto(adapter: String, vendor: String = "", os := "Windows", arm64 := false, pixels := 1920 * 1080) -> String:
	return str(RendererPreference.auto_profile({os = os, arm64 = arm64, adapter = adapter, vendor = vendor,
		pixels = pixels}).profile)


func _test_auto_policy() -> void:
	var high := [["NVIDIA GeForce RTX 3090", "NVIDIA"], ["NVIDIA GeForce RTX 3060", "NVIDIA"],
		["NVIDIA GeForce RTX 4060 Laptop GPU", "NVIDIA"], ["NVIDIA GeForce RTX 5070", "NVIDIA"],
		["NVIDIA GeForce GTX 1660 SUPER", "NVIDIA"], ["NVIDIA GeForce GTX 1070", "NVIDIA"],
		["AMD Radeon RX 6800 XT", "ATI Technologies Inc."], ["AMD Radeon RX 7900 XTX", "ATI Technologies Inc."],
		["AMD Radeon RX 9070 XT", "ATI Technologies Inc."], ["AMD Radeon RX 6600", "ATI Technologies Inc."],
		["Intel(R) Arc(TM) A770 Graphics", "Intel"], ["Intel(R) Arc(TM) B580 Graphics", "Intel"]]
	for gpu: Array in high:
		_check("Automatic picks High for %s" % gpu[0], _auto(gpu[0], gpu[1]) == "high")
	var standard := [["NVIDIA GeForce GTX 1060 6GB", "NVIDIA"], ["NVIDIA GeForce GTX 1650", "NVIDIA"],
		["NVIDIA GeForce MX450", "NVIDIA"], ["NVIDIA GeForce GT 1030", "NVIDIA"],
		["NVIDIA GeForce RTX 3050 Laptop GPU", "NVIDIA"], ["NVIDIA GeForce RTX 2050", "NVIDIA"],
		["NVIDIA RTX A2000", "NVIDIA"], ["NVIDIA GeForce RTX 6060", "NVIDIA"],
		["NVIDIA RTX A1000 Laptop GPU", "NVIDIA"], ["AMD Radeon RX 5500M", "ATI Technologies Inc."],
		["Radeon RX 580 Series", "ATI Technologies Inc."], ["AMD Radeon 780M Graphics", "ATI Technologies Inc."],
		["AMD Radeon(TM) Graphics", "ATI Technologies Inc."], ["Intel(R) Arc(TM) Graphics", "Intel"],
		["Intel(R) Iris(R) Xe Graphics", "Intel"], ["Intel(R) UHD Graphics 770", "Intel"],
		["llvmpipe (LLVM 15.0.7, 256 bits)", "Mesa"], ["Microsoft Basic Render Driver", "Microsoft"],
		["", ""], ["Unknown Accelerator", "Example"]]
	for gpu: Array in standard:
		_check("Automatic keeps Standard for '%s'" % gpu[0], _auto(gpu[0], gpu[1]) == "standard")
	_check("Linux desktop GPUs get Automatic High", _auto("NVIDIA GeForce RTX 3090", "NVIDIA", "Linux") == "high"
		and _auto("AMD Radeon RX 6600 (radeonsi, navi23, LLVM 17.0.6, DRM 3.57, 6.8.0)", "AMD", "Linux") == "high")
	_check("a Mesa chip shared by several models keeps Standard",
		_auto("AMD Radeon Graphics (radeonsi, gfx1201, LLVM 19.1.7, DRM 3.61, 6.14.0)", "AMD", "Linux") == "standard")
	_check("Linux laptops, iGPUs and handhelds keep Standard",
		_auto("NVIDIA GeForce RTX 4060 Laptop GPU", "NVIDIA", "Linux") == "standard"
		and _auto("AMD Custom GPU 0405 (radeonsi, vangogh, LLVM 17.0.6, DRM 3.57, 6.8.0)", "AMD", "Linux") == "standard"
		and _auto("Mesa Intel(R) UHD Graphics 620 (WHL GT2)", "Intel", "Linux") == "standard"
		and _auto("llvmpipe (LLVM 15.0.7, 256 bits)", "Mesa", "Linux") == "standard")
	_check("Macs never get Automatic High", _auto("Apple M4 Max (Apple9)", "Apple", "macOS", true) == "standard")
	_check("Automatic High excludes arm64 Windows", _auto("NVIDIA GeForce RTX 3090", "NVIDIA", "Windows", true) == "standard")
	var uhd := 3840 * 2160
	_check("a 4K screen asks more of the GPU: RTX 3060 stays Standard, RTX 3080 keeps High",
		_auto("NVIDIA GeForce RTX 3060", "NVIDIA", "Windows", false, uhd) == "standard"
		and _auto("NVIDIA GeForce RTX 3080", "NVIDIA", "Windows", false, uhd) == "high")
	_check("a small window is judged at 1080p", _auto("NVIDIA GeForce RTX 3060", "NVIDIA", "Windows", false, 1280 * 720) == "high")
	var detail := RendererPreference.auto_profile({os = "Windows", adapter = "NVIDIA GeForce RTX 3090", pixels = 1920 * 1080})
	_check("the decision explains its GPU entry and estimate", str(detail.reason).begins_with("rtx_3090")
		and absf(float(detail.predicted_ms) - 1.07) < 0.05, detail)
	_check("too little video memory keeps Standard", str(RendererPreference.auto_profile({os = "Windows",
		adapter = "NVIDIA GeForce GT 1030"}).reason).contains("video memory"))


func _facts(overrides: Dictionary = {}) -> Dictionary:
	var base := {os = "Windows", arm64 = false, adapter = "NVIDIA GeForce RTX 3090/PCIe/SSE2",
		vendor = "NVIDIA Corporation", headless = false, template = true, cli_renderer = false,
		session_method = "gl_compatibility", project_standard = "gl_compatibility", build = BUILD,
		guard_failed_method = "", guard_failed_build = ""}
	base.merge(overrides, true)
	return base


func _state(overrides: Dictionary = {}) -> Dictionary:
	var base := {mode = "auto", renderer = "", standard_method = "", high_blocked_build = "", auto_trial_build = ""}
	base.merge(overrides, true)
	return base


func _test_plan() -> void:
	var first := RendererPreference.plan(_facts(), _state())
	_check("first RTX launch saves Forward+ and restarts into it", first.write and first.restart
		and first.profile == "high" and first.state.renderer == "forward_plus"
		and first.state.standard_method == "gl_compatibility", first)
	var second := RendererPreference.plan(_facts({session_method = "forward_plus"}), first.state)
	_check("the High launch accepts the trial without another restart", second.write and not second.restart
		and second.state.renderer == "forward_plus" and second.state.auto_trial_build == "", second)
	var stable := RendererPreference.plan(_facts({session_method = "forward_plus"}), second.state)
	_check("later High launches neither write nor restart", not stable.write and not stable.restart, stable)
	var fallback := RendererPreference.plan(_facts(), first.state)
	_check("engine OpenGL fallback blocks High for this build without a restart", fallback.write
		and not fallback.restart and fallback.state.renderer == "" and fallback.state.high_blocked_build == BUILD
		and fallback.profile == "standard", fallback)
	var after_fallback := RendererPreference.plan(_facts(), fallback.state)
	_check("a blocked build stays in Standard on later launches", not after_fallback.write
		and not after_fallback.restart and after_fallback.profile == "standard", after_fallback)
	var guard := RendererPreference.plan(_facts({cli_renderer = true, guard_failed_method = "forward_plus",
		guard_failed_build = BUILD}), first.state)
	_check("an unconfirmed High launch removes the override in the recovery session", guard.write
		and not guard.restart and guard.state.renderer == "" and guard.state.high_blocked_build == BUILD, guard)
	var other_build := RendererPreference.plan(_facts({build = "0.2.9|def|4.8"}), fallback.state)
	_check("a new build retries High once", other_build.write and other_build.restart
		and other_build.state.renderer == "forward_plus", other_build)
	var stale_guard := RendererPreference.plan(_facts({guard_failed_method = "forward_plus",
		guard_failed_build = "0.2.7|old|4.8"}), _state())
	_check("a guard failure from another build does not block High", stale_guard.profile == "high", stale_guard)
	var explicit_standard := RendererPreference.plan(_facts(), _state({mode = "standard"}))
	_check("an explicit Standard choice wins over Automatic", not explicit_standard.write
		and explicit_standard.profile == "standard", explicit_standard)
	var explicit_high := RendererPreference.plan(_facts({adapter = "NVIDIA GeForce GTX 1060/PCIe/SSE2"}),
		_state({mode = "high"}))
	_check("an explicit High choice applies to GPUs Automatic leaves in Standard", explicit_high.write
		and explicit_high.restart and explicit_high.profile == "high", explicit_high)
	var leaving_high := RendererPreference.plan(_facts({session_method = "forward_plus"}),
		_state({mode = "standard", renderer = "forward_plus", standard_method = "gl_compatibility"}))
	_check("switching a saved High back to Standard removes the key and restarts", leaving_high.write
		and leaving_high.restart and leaving_high.state.renderer == "" and leaving_high.state.standard_method == "", leaving_high)
	var cli := RendererPreference.plan(_facts({cli_renderer = true}), _state())
	_check("a command-line renderer is never overridden by a restart", cli.write and not cli.restart, cli)
	_check("renderer and driver arguments count as deliberate choices",
		RendererPreference._has_renderer_argument(PackedStringArray(["--rendering-method", "gl_compatibility"]))
		and RendererPreference._has_renderer_argument(PackedStringArray(["--rendering-driver=opengl3"]))
		and not RendererPreference._has_renderer_argument(PackedStringArray(["--path", "app", "--", "--rendering-method"]))
		and not RendererPreference._has_renderer_argument(PackedStringArray()))
	var editor := RendererPreference.plan(_facts({template = false}), _state())
	_check("an editor binary cannot honor the file, so it never restarts", not editor.restart, editor)
	var linux := RendererPreference.plan(_facts({os = "Linux"}), _state())
	_check("Automatic on a Linux desktop RTX saves High", linux.write and linux.restart and linux.profile == "high", linux)
	var linux_igpu := RendererPreference.plan(_facts({os = "Linux", adapter = "Mesa Intel(R) UHD Graphics 620 (WHL GT2)"}), _state())
	_check("Automatic on a Linux iGPU stays Standard", not linux_igpu.write and linux_igpu.profile == "standard", linux_igpu)
	var linux_high := RendererPreference.plan(_facts({os = "Linux"}), _state({mode = "high"}))
	_check("an explicit High choice persists on Linux x86_64", linux_high.write and linux_high.profile == "high", linux_high)
	for unsupported: Dictionary in [{headless = true}, {os = "macOS", arm64 = true}, {arm64 = true}, {os = "Android"}]:
		var result := RendererPreference.plan(_facts(unsupported), _state({mode = "high"}))
		_check("unsupported host %s never writes" % str(unsupported), not result.write and not result.restart, result)
	var corrupt := RendererPreference.plan(_facts({session_method = "forward_plus"}),
		{mode = "ultra", renderer = "vulkan", standard_method = "forward_plus"})
	_check("invalid saved values normalize to Automatic", corrupt.state.mode == "auto"
		and corrupt.state.renderer == "forward_plus" and corrupt.state.standard_method == "gl_compatibility", corrupt)


## OpenGL and Vulkan can report different active devices. Simulate process boundaries through the real file.
func _test_automatic_restart_sequence() -> void:
	var trial := RendererPreference.plan(_facts(), _state())
	_check("the pending automatic High trial is recorded before restart", trial.restart and trial.state.auto_trial_build == BUILD
		and RendererPreference.save_state(trial.state, PRIVATE_PATH))
	var child := _facts({session_method = "forward_plus", adapter = "Intel(R) UHD Graphics 630"})
	var persisted := RendererPreference.load_state(PRIVATE_PATH)
	var cli := RendererPreference.plan(_facts({session_method = "forward_plus", cli_renderer = true}), persisted)
	_check("an explicit renderer session cannot accept an Automatic trial", not cli.restart and cli.state == persisted)
	var recovery := RendererPreference.plan(child, persisted)
	_check("a conflicting active adapter rolls back once", recovery.restart and recovery.state.mode == "auto"
		and recovery.state.renderer == "" and recovery.state.high_blocked_build == BUILD and recovery.state.auto_trial_build == ""
		and RendererPreference.save_state(recovery.state, PRIVATE_PATH), recovery)
	var settled := RendererPreference.plan(_facts(), RendererPreference.load_state(PRIVATE_PATH))
	_check("the original adapter reaches Standard with a reason", not settled.restart and not settled.write
		and settled.profile == "standard" and str(settled.reason).contains("blocked"), settled)
	var retry := RendererPreference.plan(_facts({build = "new build"}), settled.state)
	_check("a new build can try High again", retry.restart and retry.state.auto_trial_build == "new build", retry)
	var later_demotion := RendererPreference.plan(child, _state({renderer = "forward_plus", standard_method = "gl_compatibility"}))
	_check("demotion on an established High install retains future eligibility", later_demotion.restart
		and later_demotion.state.high_blocked_build == "", later_demotion)


func _test_file_roundtrip() -> void:
	RendererPreference.override_path = PRIVATE_PATH
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PRIVATE_PATH))
	_check("a missing file reads as Automatic with no override",
		RendererPreference.load_state() == _state())
	var high := _state({renderer = "forward_plus", standard_method = "gl_compatibility", high_blocked_build = "x"})
	_check("High state saves and verifies", RendererPreference.save_state(high))
	_check("High state reads back exactly", RendererPreference.load_state() == high)
	var text := FileAccess.get_file_as_string(PRIVATE_PATH)
	_check("the file carries the engine's project-setting key", text.contains("[rendering]")
		and text.contains("renderer/rendering_method=\"forward_plus\""), text)
	var standard := _state({mode = "standard"})
	_check("Standard state saves", RendererPreference.save_state(standard))
	text = FileAccess.get_file_as_string(PRIVATE_PATH)
	_check("Standard removes the renderer key entirely", not text.contains("rendering_method"), text)
	_check("Standard state reads back", RendererPreference.load_state() == standard)
	_check("an editor-binary Settings choice is not persisted",
		not RendererPreference.save_choice("high", true, "gl_compatibility") or OS.has_feature("template"))
	_check("startup application is inert in editor or private profiles",
		not RendererPreference.apply_at_startup(self, {}, BUILD, false))


func _test_standard_method() -> void:
	var saved := _state({renderer = "forward_plus", standard_method = "gl_compatibility"})
	_check("an applied High override keeps Compatibility as Standard",
		RendererPreference.project_standard_method("forward_plus", true, saved) == "gl_compatibility")
	_check("a missing recorded Standard falls back to Compatibility",
		RendererPreference.project_standard_method("forward_plus", true, _state({renderer = "forward_plus"})) == "gl_compatibility")
	_check("an unhonored file leaves the project renderer",
		RendererPreference.project_standard_method("mobile", false, saved) == "mobile")
	_check("no saved override leaves the project renderer",
		RendererPreference.project_standard_method("gl_compatibility", true, _state()) == "gl_compatibility")
	# Regression (Good Enemy #1): once Standard is saved, this session's applied override still reports
	# Forward+, so _perform_graphics_restart must resolve its restart arguments before saving.
	_check("the Standard renderer is only known from the state before a Standard save",
		RendererPreference.project_standard_method("forward_plus", true, saved) == "gl_compatibility"
		and RendererPreference.project_standard_method("forward_plus", true, _state({mode = "standard"})) == "forward_plus")
	var app_root := FileAccess.get_file_as_string("res://app_root.gd")
	var restart_at := app_root.find("func _perform_graphics_restart")
	_check("graphics restart resolves its arguments before saving the choice", restart_at >= 0
		and app_root.find("HighGraphics.restart_arguments", restart_at) < app_root.find("RendererPreference.save_choice", restart_at))
	_check("the automatic restart keeps engine and user arguments",
		RendererPreference.restart_arguments(PackedStringArray(["--fullscreen"]), PackedStringArray(["--lang=de"]))
			== PackedStringArray(["--fullscreen", "--", "--lang=de"])
		and RendererPreference.restart_arguments(PackedStringArray(), PackedStringArray()).is_empty())
	var guard_path := "user://test renderer preference guard.cfg"
	RendererGuard.save_state(guard_path, {failed = {method = "forward_plus", build = BUILD},
		metalfx_failed = {build = BUILD}})
	RendererGuard.forget_failure(guard_path)
	var guard_state := RendererGuard.load_state(guard_path)
	_check("an explicit High request forgets only the renderer failure",
		not guard_state.has("failed") and guard_state.has("metalfx_failed"), guard_state)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(guard_path))
	if not OS.has_feature("template"):
		_check("editor launches keep the project default renderer",
			HighGraphics.default_rendering_method() == ("mobile" if OS.has_feature("arm64") else "gl_compatibility"))
		_check("editor Standard method is unchanged",
			HighGraphics.standard_rendering_method() == HighGraphics.default_rendering_method())


func _test_project_setting() -> void:
	var cfg := ConfigFile.new()
	_check("project.godot parses", cfg.load("res://project.godot") == OK)
	_check("exported builds read the saved renderer file",
		str(cfg.get_value("application", "config/project_settings_override.template", "")) == RendererPreference.OVERRIDE_PATH)
	_check("development launches have no untagged settings override",
		not cfg.has_section_key("application", "config/project_settings_override"))
	_check("the project renderer stays Compatibility",
		str(cfg.get_value("rendering", "renderer/rendering_method", "")) == "gl_compatibility")
