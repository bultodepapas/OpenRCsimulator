extends RefCounted
## DT-MAC-05b: recovery for a RenderingDevice default renderer that initializes but then crashes or hangs.
## Godot already falls back to OpenGL when the Metal/Vulkan context cannot be created; this covers what follows.
## A normal Home launch on the project's RD Standard renderer (Mobile on Apple Silicon) writes a pending marker,
## cleared after CONFIRM_FRAMES process callbacks and CONFIRM_SECONDS, or on a clean quit. This detects continued
## process responsiveness; it does not prove images reached the display. A later launch that finds the marker
## unconfirmed records a failure for that build and restarts once into Compatibility. Compatibility sessions write
## no marker, so no restart loop is possible; a new build retries the RD renderer once.

const HighGraphics := preload("res://render/high_graphics_profile.gd")
const BuildInfo := preload("res://app_state/build_info.gd")
const SECTION := "renderer"
const CONFIRM_FRAMES := 120
const CONFIRM_SECONDS := 3.0
const FALLBACK_METHOD := "gl_compatibility"
const RD_METHODS := ["mobile", "forward_plus"]
const STATE_KEYS := ["pending", "failed", "metalfx_pending", "metalfx_failed"]
const MetalFX := preload("res://render/metalfx_policy.gd")
const METALFX_BLOCK_REASON := "metalfx_failed_previously"
const METALFX_STORAGE_REASON := "metalfx_guard_unavailable"
## DT-MAC-07a: the pinned engine stores MetalFX scaler creation without a null guard, so an unsupported
## descriptor can crash on first use. The same per-build marker pattern blocks MetalFX after such a session.
static var _metalfx_armed := false
static var _metalfx_activation := 0
static var _metalfx_configuration := {}
static var _metalfx_confirmer: WeakRef
## UI-28-R5: true while the startup intro still covers a staged first Home. Confirmers restart their
## frame and time window meanwhile, so confirmation still requires the 3D Home to have been drawn.
static var confirm_hold := false


## Pure decision. facts: {method, standard_method, profile, headless, build}; state: {pending, failed}.
## Returns {action: "none" | "guard" | "fallback", state, reason}. Pending and failure records are per build.
static func decide(facts: Dictionary, state: Dictionary) -> Dictionary:
	var method := str(facts.get("method", ""))
	var build := str(facts.get("build", ""))
	var out := {}
	for key: String in STATE_KEYS:
		var record: Variant = state.get(key, {})
		if record is Dictionary and not record.is_empty():
			out[key] = record.duplicate(true)
	var guarded: bool = not bool(facts.get("headless", true)) and method in RD_METHODS \
		and method == str(facts.get("standard_method", "")) and str(facts.get("profile", "")) != "high" \
		and not build.is_empty()
	if not guarded:
		return {action = "none", state = out, reason = "renderer not guarded"}
	var pending: Dictionary = out.get("pending", {})
	if str(pending.get("method", "")) == method and str(pending.get("build", "")) == build:
		out["failed"] = {method = method, build = build}
	out.erase("pending")
	var failed: Dictionary = out.get("failed", {})
	if str(failed.get("method", "")) == method and str(failed.get("build", "")) == build:
		return {action = "fallback", state = out,
			reason = "the previous %s launch of this build never confirmed process responsiveness" % method}
	out["pending"] = {method = method, build = build}
	return {action = "guard", state = out, reason = ""}


static func build_identity() -> String:
	var info: Dictionary = BuildInfo.current()
	return "%s|%s|%s" % [info.get("version", ""), info.get("commit", ""), info.get("godot", "")]


static func facts() -> Dictionary:
	return {method = RenderingServer.get_current_rendering_method(),
		standard_method = HighGraphics.standard_rendering_method(), profile = HighGraphics.requested(),
		headless = DisplayServer.get_name() == "headless", build = build_identity()}


static func load_state(path: String) -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return {}
	var state := {}
	for key: String in STATE_KEYS:
		var value: Variant = cfg.get_value(SECTION, key, {})
		if value is Dictionary and not value.is_empty():
			state[key] = value
	return state


static func save_state(path: String, state: Dictionary) -> bool:
	var cfg := ConfigFile.new()
	for key: String in STATE_KEYS:
		if state.has(key):
			cfg.set_value(SECTION, key, state[key])
	# The pinned ConfigFile::save can return OK after an opened file has a short write.
	# Observe the complete state again before treating a recovery marker as persisted.
	if cfg.save(path) != OK or not _saved_state_matches(path, cfg):
		push_warning("Renderer guard: cannot save %s" % path)
		return false
	return true


static func _saved_state_matches(path: String, expected: ConfigFile) -> bool:
	var actual := ConfigFile.new()
	if actual.load(path) != OK or actual.get_sections() != expected.get_sections():
		return false
	for section: String in expected.get_sections():
		if actual.get_section_keys(section) != expected.get_section_keys(section):
			return false
		for key: String in expected.get_section_keys(section):
			if actual.get_value(section, key) != expected.get_value(section, key):
				return false
	return true


## Call once from the normal Home route before building UI. Returns true when a Compatibility restart was
## scheduled and the caller must stop starting up.
static func begin(tree: SceneTree, path: String) -> bool:
	var before := load_state(path)
	var current := facts()
	var decision := decide(current, before)
	if not bool(current.headless):
		var metalfx := decide_metalfx(str(current.build), decision.state)
		decision.state = metalfx.state
		MetalFX.blocked_reason = METALFX_BLOCK_REASON if metalfx.blocked else ""
		if metalfx.blocked:
			push_warning("Renderer guard: MetalFX did not confirm in a previous session of this build; it stays off.")
	if decision.state != before:
		save_state(path, decision.state) # inert launches (headless, Compatibility, High) never touch the file
	if decision.action == "fallback":
		push_warning("Renderer guard: %s; restarting with %s." % [decision.reason, FALLBACK_METHOD])
		var args := PackedStringArray()
		if OS.has_feature("editor"):
			args.append_array(["--path", ProjectSettings.globalize_path("res://")])
		args.append_array(["--rendering-method", FALLBACK_METHOD])
		OS.set_restart_on_exit(true, args)
		tree.quit()
		return true
	if decision.action == "guard":
		tree.root.add_child.call_deferred(confirmer_for(path))
	return false


## Pure MetalFX decision: an unconfirmed MetalFX session of `build` becomes a failure that blocks MetalFX
## for that build; markers from other builds are dropped, so a new build may try again.
static func decide_metalfx(build: String, state: Dictionary) -> Dictionary:
	var out := state.duplicate(true)
	var pending: Variant = out.get("metalfx_pending", {})
	if pending is Dictionary and not pending.is_empty():
		if str(pending.get("build", "")) == build and not build.is_empty():
			out["metalfx_failed"] = {build = build}
		out.erase("metalfx_pending")
	var failed: Variant = out.get("metalfx_failed", {})
	var blocked: bool = failed is Dictionary and not build.is_empty() and str(failed.get("build", "")) == build
	return {state = out, blocked = blocked}


## Call before reconstruction apply. Entering MetalFX first persists a marker (confirmed after process callbacks);
## leaving it before confirmation is a user choice, not a failure.
static func observe_metalfx(tree: SceneTree, path: String, active: bool, configuration: Dictionary = {}) -> bool:
	if DisplayServer.get_name() == "headless":
		return true
	if active:
		var activation := _prepare_metalfx(path, str(build_identity()), configuration)
		if activation < 0:
			return false # the process capability block makes the following apply use its safe fallback
		if activation == 0:
			return true # unrelated preference changes do not restart the responsiveness window
		print("Renderer guard: MetalFX active; confirming process responsiveness.")
		var confirmer := confirmer_for(path)
		confirmer.name = "MetalFXGuardConfirm"
		confirmer.on_stable = func() -> void: _confirm_metalfx_activation(path, activation)
		_metalfx_confirmer = weakref(confirmer)
		tree.root.add_child.call_deferred(confirmer)
	elif not active:
		if not path.is_empty():
			_disarm_metalfx(path)
	return true


static func _prepare_metalfx(path: String, build: String, configuration: Dictionary) -> int:
	if _metalfx_armed and configuration == _metalfx_configuration:
		return 0
	return _arm_metalfx(path, build, configuration)


static func _arm_metalfx(path: String, build: String, configuration: Dictionary = {}) -> int:
	_metalfx_activation += 1
	_cancel_metalfx_confirmer()
	_metalfx_armed = false
	_metalfx_configuration = {}
	var state := load_state(path)
	state["metalfx_pending"] = {build = build, activation = _metalfx_activation, configuration = configuration.duplicate(true)}
	if path.is_empty() or not save_state(path, state):
		MetalFX.blocked_reason = METALFX_STORAGE_REASON
		return -1
	_metalfx_armed = true
	_metalfx_configuration = configuration.duplicate(true)
	return _metalfx_activation


static func _disarm_metalfx(path: String) -> void:
	if _metalfx_armed:
		_metalfx_activation += 1
		_metalfx_armed = false
	_metalfx_configuration = {}
	_cancel_metalfx_confirmer()
	clear_metalfx_pending(path)


static func _cancel_metalfx_confirmer() -> void:
	var previous: Variant = _metalfx_confirmer.get_ref() if _metalfx_confirmer != null else null
	_metalfx_confirmer = null
	if is_instance_valid(previous):
		previous.set_process(false)
		previous.queue_free()


## A previous on/off cycle cannot confirm the current activation, even if its timer fires late.
static func _confirm_metalfx_activation(path: String, activation: int) -> void:
	if not _metalfx_armed or activation != _metalfx_activation:
		return
	_metalfx_confirmer = null
	var state := load_state(path)
	var pending: Variant = state.get("metalfx_pending", {})
	if pending is Dictionary and int(pending.get("activation", -1)) == activation:
		state.erase("metalfx_pending")
		save_state(path, state)


static func clear_metalfx_pending(path: String) -> void:
	var state := load_state(path)
	if state.has("metalfx_pending"):
		state.erase("metalfx_pending")
		save_state(path, state)


## Clears this launch's pending markers on a clean quit. Failure records stay.
static func confirm(path: String) -> void:
	var state := load_state(path)
	if state.has("pending") or state.has("metalfx_pending"):
		state.erase("pending")
		state.erase("metalfx_pending")
		save_state(path, state)


## A node that confirms `path` after the process callback and time thresholds, then frees itself.
static func confirmer_for(path: String) -> Node:
	var confirmer := Confirmer.new()
	confirmer.name = "RendererGuardConfirm"
	# Home pauses the tree while unfocused; the responsiveness timer runs independently of that pause.
	confirmer.process_mode = Node.PROCESS_MODE_ALWAYS
	confirmer.on_stable = func() -> void: clear_renderer_pending(path)
	confirmer.held = func() -> bool: return confirm_hold
	return confirmer


## RD responsiveness clears only the renderer marker; MetalFX has a separate timer.
static func clear_renderer_pending(path: String) -> void:
	var state := load_state(path)
	if state.has("pending"):
		state.erase("pending")
		save_state(path, state)


class Confirmer extends Node:
	var on_stable := Callable()
	var held := Callable()
	var _frames := 0
	var _start_usec := 0

	func _ready() -> void:
		_start_usec = Time.get_ticks_usec()

	func _process(_delta: float) -> void:
		if held.is_valid() and bool(held.call()):
			_frames = 0
			_start_usec = Time.get_ticks_usec()
			return
		_frames += 1
		if _frames >= CONFIRM_FRAMES and float(Time.get_ticks_usec() - _start_usec) / 1.0e6 >= CONFIRM_SECONDS:
			if on_stable.is_valid():
				on_stable.call()
			queue_free()
