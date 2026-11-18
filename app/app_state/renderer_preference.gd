extends RefCounted
## VQ-07h: the saved graphics mode (Automatic, Standard or High) and the renderer it starts with.
## Godot selects its renderer before any script runs, so exported builds read OVERRIDE_PATH through
## `application/config/project_settings_override.template` in project.godot. Editor-binary launches
## (development, tests, captures, research tools) ignore that key and keep the project renderer.
## Automatic chooses High on Windows x86_64 when the GPU capability table (data/gpu/capability.json, estimates
## extrapolated from the measured RTX 3090 anchor) predicts enough headroom at the screen's resolution;
## every other host starts in Standard. A Forward+ launch that never confirms (RendererGuard) or that the engine
## replaced with its OpenGL fallback blocks High for that build, so it cannot become a restart loop.

const GpuCapability := preload("res://render/gpu_capability.gd")
const OVERRIDE_PATH := "user://renderer.cfg"
const MODES: Array[String] = ["auto", "standard", "high"]
const DEFAULT_MODE := "auto"
const HIGH_METHOD := "forward_plus"
const FALLBACK_STANDARD_METHOD := "gl_compatibility"
const VALID_METHODS: Array[String] = ["gl_compatibility", "mobile", "forward_plus"]
const RENDER_SECTION := "rendering"
const RENDER_KEY := "renderer/rendering_method"
const SETTING := "rendering/renderer/rendering_method"
const STATE_SECTION := "openrc_renderer"
## Automatic High: a known dedicated GPU (data/gpu/capability.json) whose extrapolated High GPU time at the
## screen's resolution (at least 1080p) stays within HIGH_BUDGET_MS. 4.3 ms is rel 0.25 at 1080p and keeps
## more than 3.5x headroom inside a 60 Hz frame for heavier scenes and the estimate's error.
const HIGH_BUDGET_MS := 4.3
const MIN_HIGH_VRAM_GB := 4
const MIN_PIXELS := 1920 * 1080

## Test seam: tests point this at a private file.
static var override_path := OVERRIDE_PATH


## Persisted state. `renderer` is the renderer key the engine will apply ("" = project default).
static func load_state(path: String = "") -> Dictionary:
	var cfg := ConfigFile.new()
	var state := {mode = DEFAULT_MODE, renderer = "", standard_method = "", high_blocked_build = ""}
	if cfg.load(_path(path)) != OK:
		return state
	var mode := str(cfg.get_value(STATE_SECTION, "mode", DEFAULT_MODE))
	state.mode = mode if mode in MODES else DEFAULT_MODE
	var renderer := str(cfg.get_value(RENDER_SECTION, RENDER_KEY, ""))
	state.renderer = renderer if renderer in VALID_METHODS else ""
	var standard := str(cfg.get_value(STATE_SECTION, "standard_method", ""))
	state.standard_method = standard if standard in VALID_METHODS else ""
	state.high_blocked_build = str(cfg.get_value(STATE_SECTION, "high_blocked_build", ""))
	return state


static func save_state(state: Dictionary, path: String = "") -> bool:
	var cfg := ConfigFile.new()
	if str(state.get("renderer", "")) in VALID_METHODS:
		cfg.set_value(RENDER_SECTION, RENDER_KEY, str(state.renderer))
	cfg.set_value(STATE_SECTION, "mode", str(state.get("mode", DEFAULT_MODE)))
	if str(state.get("standard_method", "")) in VALID_METHODS:
		cfg.set_value(STATE_SECTION, "standard_method", str(state.standard_method))
	if not str(state.get("high_blocked_build", "")).is_empty():
		cfg.set_value(STATE_SECTION, "high_blocked_build", str(state.high_blocked_build))
	if cfg.save(_path(path)) != OK or load_state(path) != _normalized(state):
		push_warning("Renderer preference: cannot save %s" % _path(path))
		return false
	return true


## The renderer the Standard profile uses on this host, excluding this file's override.
## `effective` is the project setting after feature tags and any applied override.
static func project_standard_method(effective: String, honored: bool, state: Dictionary) -> String:
	if honored and not str(state.get("renderer", "")).is_empty() and effective == str(state.renderer):
		var recorded := str(state.get("standard_method", ""))
		return recorded if recorded in VALID_METHODS else FALLBACK_STANDARD_METHOD
	return effective


## Pure Automatic policy. facts: {os, arm64, adapter, pixels}. Returns {profile, reason, gpu, predicted_ms}.
static func auto_profile(facts: Dictionary) -> Dictionary:
	if str(facts.get("os", "")) != "Windows" or bool(facts.get("arm64", false)):
		return {profile = "standard", reason = "High is chosen automatically only on Windows x86_64"}
	var gpu := GpuCapability.lookup(str(facts.get("adapter", "")))
	if not bool(gpu.matched):
		return {profile = "standard", reason = "GPU not in the capability table", gpu = gpu}
	if str(gpu["class"]) in ["integrated", "software"]:
		return {profile = "standard", reason = "%s GPU" % gpu["class"], gpu = gpu}
	if int(gpu.vram_gb) < MIN_HIGH_VRAM_GB:
		return {profile = "standard", reason = "less than %d GB of video memory" % MIN_HIGH_VRAM_GB, gpu = gpu}
	var pixels := maxi(int(facts.get("pixels", 0)), MIN_PIXELS)
	var predicted := GpuCapability.predicted_high_ms(float(gpu.rel), pixels)
	var within := predicted <= HIGH_BUDGET_MS
	return {profile = "high" if within else "standard", gpu = gpu, predicted_ms = predicted,
		reason = "%s: estimated High GPU %.1f ms at %.1f MP (budget %.1f ms)" % [gpu.id, predicted,
			float(pixels) / 1.0e6, HIGH_BUDGET_MS]}


## Pure startup decision. facts: {os, arm64, adapter, vendor, headless, template, cli_renderer,
## session_method, project_standard, build, guard_failed_method, guard_failed_build}.
## Returns {state, write, restart, profile, reason}. Only supported desktop hosts persist anything.
static func plan(facts: Dictionary, state: Dictionary) -> Dictionary:
	var out := _normalized(state)
	var result := {state = out, write = false, restart = false, profile = "standard", reason = ""}
	if bool(facts.get("headless", true)) or not supported(facts):
		result.reason = "renderer preference unsupported on this host"
		return result
	var build := str(facts.get("build", ""))
	var standard := str(facts.get("project_standard", FALLBACK_STANDARD_METHOD))
	if standard not in VALID_METHODS or standard == HIGH_METHOD:
		standard = FALLBACK_STANDARD_METHOD
	var session := str(facts.get("session_method", ""))
	var honored := bool(facts.get("template", false))
	var cli := bool(facts.get("cli_renderer", false))
	# The engine replaced a saved Forward+ start with its OpenGL fallback: block High for this build.
	if honored and not cli and out.renderer == HIGH_METHOD and session != HIGH_METHOD and not build.is_empty():
		out.high_blocked_build = build
		result.reason = "the engine could not start High; Standard is used for this build"
	if str(facts.get("guard_failed_method", "")) == HIGH_METHOD and str(facts.get("guard_failed_build", "")) == build \
			and not build.is_empty():
		out.high_blocked_build = build
		result.reason = "High did not confirm on this build; Standard is used"
	var profile := "standard"
	match str(out.mode):
		"high": profile = "high"
		"standard": profile = "standard"
		_:
			var automatic := auto_profile(facts)
			profile = str(automatic.profile)
			if result.reason.is_empty():
				result.reason = "automatic: " + str(automatic.reason)
	if profile == "high" and not build.is_empty() and out.high_blocked_build == build:
		profile = "standard"
	result.profile = profile
	var renderer := HIGH_METHOD if profile == "high" else ""
	if out.renderer != renderer or (renderer == HIGH_METHOD and out.standard_method != standard):
		out.renderer = renderer
		out.standard_method = standard if renderer == HIGH_METHOD else ""
		result.write = true
		# Apply now only when the file governs this launch and nothing on the command line overrides it.
		var wanted := HIGH_METHOD if renderer == HIGH_METHOD else standard
		result.restart = honored and not cli and session != wanted
	return result


## Hosts whose project Standard is Compatibility on x86_64, so the base renderer key is not shadowed
## by a feature-tagged project override (Apple Silicon uses rendering_method.arm64).
static func supported(facts: Dictionary) -> bool:
	return str(facts.get("os", "")) in ["Windows", "Linux"] and not bool(facts.get("arm64", false))


static func facts(guard_state: Dictionary = {}, build: String = "") -> Dictionary:
	var failed: Variant = guard_state.get("failed", {})
	var state := load_state()
	var effective := str(ProjectSettings.get_setting_with_override(SETTING))
	return {
		os = OS.get_name(), arm64 = OS.has_feature("arm64"),
		adapter = RenderingServer.get_video_adapter_name(), vendor = RenderingServer.get_video_adapter_vendor(),
		pixels = _screen_pixels(),
		headless = DisplayServer.get_name() == "headless", template = OS.has_feature("template"),
		cli_renderer = _has_renderer_argument(OS.get_cmdline_args()),
		session_method = RenderingServer.get_current_rendering_method(),
		project_standard = project_standard_method(effective, OS.has_feature("template"), state),
		build = build,
		guard_failed_method = str((failed as Dictionary).get("method", "")) if failed is Dictionary else "",
		guard_failed_build = str((failed as Dictionary).get("build", "")) if failed is Dictionary else "",
	}


## Normal player Home launch, after RendererGuard.begin. Returns true when a restart into the saved
## mode was scheduled and the caller must stop starting up. `persistent` is false for private profiles.
static func apply_at_startup(tree: SceneTree, guard_state: Dictionary, build: String, persistent: bool) -> bool:
	if not persistent or not OS.has_feature("template"):
		return false
	var before := load_state()
	var decision := plan(facts(guard_state, build), before)
	if not str(decision.reason).is_empty():
		print("Graphics mode: %s (%s)" % [decision.profile, decision.reason])
	if decision.state == _normalized(before):
		return false
	if not save_state(decision.state):
		return false
	if decision.restart:
		print("Graphics mode: restarting into %s." % decision.profile)
		OS.set_restart_on_exit(true, restart_arguments(OS.get_cmdline_args(), OS.get_cmdline_user_args()))
		tree.quit()
		return true
	return false


## A deliberate Settings choice is remembered for later launches (exported builds only).
static func save_choice(profile: String, persistent: bool, project_standard: String) -> bool:
	if profile not in ["standard", "high"] or not persistent or not OS.has_feature("template") \
			or not supported({os = OS.get_name(), arm64 = OS.has_feature("arm64")}):
		return false
	var state := load_state()
	state.mode = profile
	state.renderer = HIGH_METHOD if profile == "high" else ""
	state.standard_method = project_standard if profile == "high" and project_standard in VALID_METHODS \
		and project_standard != HIGH_METHOD else ("" if profile != "high" else FALLBACK_STANDARD_METHOD)
	if profile == "high":
		state.high_blocked_build = "" # an explicit request retries High once; the guard still protects it
	return save_state(state)


static func _normalized(state: Dictionary) -> Dictionary:
	var mode := str(state.get("mode", DEFAULT_MODE))
	var renderer := str(state.get("renderer", ""))
	var standard := str(state.get("standard_method", ""))
	return {mode = mode if mode in MODES else DEFAULT_MODE, renderer = renderer if renderer in VALID_METHODS else "",
		standard_method = standard if standard in VALID_METHODS else "",
		high_blocked_build = str(state.get("high_blocked_build", ""))}


## The display the game opens on; fullscreen play renders at its size.
static func _screen_pixels() -> int:
	if DisplayServer.get_name() == "headless":
		return 0
	var size := DisplayServer.screen_get_size(DisplayServer.window_get_current_screen())
	return maxi(size.x, 0) * maxi(size.y, 0)


## The automatic restart keeps the launch's own options; the saved file selects the renderer.
static func restart_arguments(engine_args: PackedStringArray, user_args: PackedStringArray) -> PackedStringArray:
	var args := engine_args.duplicate()
	if not user_args.is_empty():
		args.append("--")
		args.append_array(user_args)
	return args


## A deliberate command-line renderer or driver (recovery shortcuts, guard fallback, tools) is respected.
static func _has_renderer_argument(arguments: PackedStringArray) -> bool:
	for argument: String in arguments:
		if argument == "--":
			return false
		if argument.split("=", true, 1)[0] in ["--rendering-method", "--rendering-driver"]:
			return true
	return false


static func _path(path: String) -> String:
	return override_path if path.is_empty() else path
