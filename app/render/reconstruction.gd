## VQ-07d: main-view reconstruction; presentation only, never simulation state.
extends RefCounted

const HighGraphics := preload("res://render/high_graphics_profile.gd")
const NvidiaReflex := preload("res://render/nvidia_reflex.gd")
const MODES: Array[String] = [
	"native",
	"fsr2_native", "fsr2_85", "fsr2_quality", "fsr2_balanced", "fsr2_performance",
	"fsr3_native", "fsr3_85", "fsr3_quality", "fsr3_balanced", "fsr3_performance",
	"dlss_native", "dlss_quality", "dlss_balanced", "dlss_performance",
]
const MODE_PROVIDERS := {
	"native": "native",
	"fsr2_native": "fsr2", "fsr2_85": "fsr2", "fsr2_quality": "fsr2",
	"fsr2_balanced": "fsr2", "fsr2_performance": "fsr2",
	"fsr3_native": "fsr3", "fsr3_85": "fsr3", "fsr3_quality": "fsr3",
	"fsr3_balanced": "fsr3", "fsr3_performance": "fsr3",
	"dlss_native": "dlss", "dlss_quality": "dlss", "dlss_balanced": "dlss",
	"dlss_performance": "dlss",
}
const SCALES := {
	"native": 1.0,
	"fsr2_native": 1.0, "fsr2_85": 0.85, "fsr2_quality": 2.0 / 3.0,
	"fsr2_balanced": 1.0 / 1.7, "fsr2_performance": 0.5,
	"fsr3_native": 1.0, "fsr3_85": 0.85, "fsr3_quality": 2.0 / 3.0,
	"fsr3_balanced": 1.0 / 1.7, "fsr3_performance": 0.5,
	"dlss_native": 1.0, "dlss_quality": 2.0 / 3.0, "dlss_balanced": 1.0 / 1.7,
	"dlss_performance": 0.5,
}
const DEFAULT_SHARPNESS := 0.9 # User strength; matches Godot's default fsr_sharpness=0.2.
const ENVIRONMENT_KEY := "OPENRC_RECONSTRUCTION"
const SHARPNESS_ENVIRONMENT_KEY := "OPENRC_FSR2_SHARPNESS"
const FSR3_METHOD := "is_fsr3_available"
const DLSS_SINGLETON := "Streamline"
const DLSS_CAPABILITY := "STREAMLINE_CAPABILITY_DLSS"
const POLICY_META := &"openrc_reconstruction"
const CONFIG_META := &"openrc_reconstruction_config"
const RUNTIME_FAILURE_META := &"openrc_reconstruction_runtime_failure"
const HISTORY_RESET_META := &"openrc_reconstruction_history_reset"
const HISTORY_RESET_METHOD := &"viewport_request_temporal_history_reset"


## High is the gate for every optional reconstruction provider.
static func available() -> bool:
	return HighGraphics.active()


## Runtime gates are provider-specific. No GPU name or vendor heuristic is used.
static func runtime_capabilities() -> Dictionary:
	var high := HighGraphics.active()
	var fsr2_mode: Variant = _integer_constant_or_null("Viewport", "SCALING_3D_MODE_FSR2")
	var fsr3_mode: Variant = _integer_constant_or_null("Viewport", "SCALING_3D_MODE_FSR3")
	var dlss_mode: Variant = _integer_constant_or_null("Viewport", "SCALING_3D_MODE_DLSS")
	var fsr3_backend_method := RenderingServer.has_method(FSR3_METHOD)
	var fsr3_backend := fsr3_backend_method and bool(RenderingServer.call(FSR3_METHOD))
	var fsr2_reason := "engine_mode_missing" if high and fsr2_mode == null else ""
	var fsr3_reason := ""
	if high:
		if fsr3_mode == null:
			fsr3_reason = "engine_mode_missing"
		elif not fsr3_backend_method:
			fsr3_reason = "fsr3_support_missing"
		elif not fsr3_backend:
			fsr3_reason = "fsr3_unavailable"
	var dlss_reason := ""
	if high:
		if dlss_mode == null:
			dlss_reason = "engine_mode_missing"
		else:
			dlss_reason = _streamline_dlss_unavailable_reason()
	return {
		"high": high,
		"fsr2": high and fsr2_mode != null,
		"fsr3": high and fsr3_mode != null and fsr3_backend,
		"dlss": high and dlss_mode != null and dlss_reason.is_empty(),
		"fsr2_reason": fsr2_reason,
		"fsr3_reason": fsr3_reason,
		"dlss_reason": dlss_reason,
		"fsr2_mode": fsr2_mode,
		"fsr3_mode": fsr3_mode,
		"dlss_mode": dlss_mode,
	}


## Preserve old `resolve(mode, high_available)` callers while allowing deterministic
## provider injection as `resolve(mode, capabilities)` or `resolve(mode, high, caps)`.
static func resolve(requested: String, high_available_or_capabilities: Variant = true,
		capabilities: Dictionary = {}) -> Dictionary:
	var gates := _resolve_capabilities(high_available_or_capabilities, capabilities)
	var status := option_status(requested, gates)
	var effective := requested if bool(status.available) else "native"
	var provider := str(MODE_PROVIDERS.get(effective, "native"))
	var mode_id: Variant = _scaling_mode_id(provider, gates)
	var fallback_reason := str(status.reason) if effective != requested else ""
	if provider != "native" and mode_id == null:
		effective = "native"
		provider = "native"
		mode_id = Viewport.SCALING_3D_MODE_BILINEAR
		fallback_reason = "engine_mode_missing"
	return {
		"requested": requested,
		"requested_provider": str(MODE_PROVIDERS.get(requested, "unknown")),
		"effective": effective,
		"provider": provider,
		"effective_provider": provider,
		"provider_available": bool(status.available),
		"fallback": effective != requested,
		"fallback_reason": fallback_reason,
		"scale": float(SCALES.get(effective, 1.0)),
		"temporal": provider != "native",
		"scaling_3d_mode": mode_id,
	}


## Explain why a menu entry is disabled without discarding its saved request.
static func option_status(mode: String, capabilities: Dictionary = {}) -> Dictionary:
	var gates := runtime_capabilities() if capabilities.is_empty() else capabilities.duplicate(true)
	if not MODE_PROVIDERS.has(mode):
		return {"available": false, "reason": "unknown_mode"}
	var provider := str(MODE_PROVIDERS[mode])
	if provider == "native":
		return {"available": true, "reason": ""}
	if not bool(gates.get("high", false)):
		return {"available": false, "reason": "high_profile_inactive"}
	if not bool(gates.get(provider, false)):
		return {"available": false, "reason": str(gates.get(provider + "_reason", provider + "_unavailable"))}
	if _scaling_mode_id(provider, gates) == null:
		return {"available": false, "reason": "engine_mode_missing"}
	return {"available": true, "reason": ""}


## Direct/technical launches may select a candidate without reading player preferences.
static func startup_config() -> Dictionary:
	var strength := OS.get_environment(SHARPNESS_ENVIRONMENT_KEY).strip_edges()
	return {"reconstruction": OS.get_environment(ENVIRONMENT_KEY).strip_edges().to_lower()
		if OS.has_environment(ENVIRONMENT_KEY) else "native",
		"fsr2_sharpness": sharpness_strength(strength.to_float() if strength.is_valid_float() else DEFAULT_SHARPNESS),
		"nvidia_reflex": NvidiaReflex.startup_mode()}


static func sharpness_strength(value: Variant) -> float:
	if typeof(value) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(value)):
		return DEFAULT_SHARPNESS
	return clampf(float(value), 0.0, 1.0)


## Temporal history is bounded for all three native temporal providers.
static func capture_settle_frames(mode: int, scale: float, capabilities: Dictionary = {}) -> int:
	var gates := runtime_capabilities() if capabilities.is_empty() else capabilities
	var temporal_mode := mode == Viewport.SCALING_3D_MODE_FSR2
	for key: String in ["fsr3_mode", "dlss_mode"]:
		var candidate: Variant = gates.get(key)
		if typeof(candidate) == TYPE_INT and mode == int(candidate):
			temporal_mode = true
	if not temporal_mode:
		return 2
	var input_scale := clampf(scale, 0.5, 1.0)
	return clampi(ceili(8.0 / (input_scale * input_scale)) * 2, 16, 64)


static func apply(viewport: Viewport, config: Dictionary, capabilities: Dictionary = {}) -> void:
	var previous_failure: Variant = viewport.get_meta(RUNTIME_FAILURE_META, {})
	NvidiaReflex.apply(str(config.get("nvidia_reflex", NvidiaReflex.DEFAULT_MODE)))
	var gates := runtime_capabilities() if capabilities.is_empty() else capabilities.duplicate(true)
	var requested := str(config.get("reconstruction", "native"))
	var policy := resolve(requested, gates)
	viewport.scaling_3d_mode = int(policy.scaling_3d_mode)
	viewport.scaling_3d_scale = float(policy.scale)
	var strength := sharpness_strength(config.get("fsr2_sharpness", DEFAULT_SHARPNESS))
	# Godot's DLSS path reads this value as its extra NIS sharpening control. Zero keeps it off;
	# the saved FSR preference remains untouched for switching back to FSR2 or FSR3.
	viewport.fsr_sharpness = _engine_sharpness_value(str(policy.provider), strength)
	# Temporal reconstruction owns AA. The user's MSAA choice remains in config.
	viewport.msaa_3d = Viewport.MSAA_DISABLED if policy.temporal else int(config.get("msaa_3d", 2)) as Viewport.MSAA
	viewport.use_taa = false
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	viewport.set_meta(POLICY_META, policy)
	viewport.set_meta(CONFIG_META, config.duplicate(true))
	if viewport.has_meta(RUNTIME_FAILURE_META) and (typeof(previous_failure) != TYPE_DICTIONARY
			or str(previous_failure.get("provider", "")) != str(policy.get("requested_provider", ""))):
		viewport.remove_meta(RUNTIME_FAILURE_META)


## Roll a native provider back to full resolution after its backend reports a runtime failure.
## The requested config remains stored and is never rewritten to the display preferences file.
static func guard_runtime_failure(viewport: Viewport, backend_status: Dictionary = {},
		capabilities: Dictionary = {}) -> bool:
	if not is_instance_valid(viewport):
		return false
	var policy: Variant = viewport.get_meta(POLICY_META, {})
	if typeof(policy) != TYPE_DICTIONARY:
		return false
	var provider := str(policy.get("provider", ""))
	if provider not in ["fsr3", "dlss"]:
		return false
	var status := backend_status.duplicate(true)
	if status.is_empty():
		status = _backend_status(provider)
	if not bool(status.get("backend_failed", false)):
		return false
	var saved_config: Variant = viewport.get_meta(CONFIG_META, {})
	if typeof(saved_config) != TYPE_DICTIONARY:
		return false
	var gates := runtime_capabilities() if capabilities.is_empty() else capabilities.duplicate(true)
	gates[provider] = false
	gates[provider + "_reason"] = provider + "_runtime_failure"
	apply(viewport, saved_config, gates)
	var fallback_policy: Dictionary = viewport.get_meta(POLICY_META, {})
	fallback_policy["fallback_reason"] = provider + "_runtime_failure"
	viewport.set_meta(POLICY_META, fallback_policy)
	viewport.set_meta(RUNTIME_FAILURE_META, {
		"provider": provider,
		"reason": "backend_failed",
		"backend": status,
	})
	return true


## Discontinuities invalidate history; ordinary camera movement must not call this.
## Submission is not SDK acknowledgement. The native backend reports successful resets.
static func request_history_reset(viewport: Viewport, reason: String, backend: Object = null) -> bool:
	if not is_instance_valid(viewport):
		return false
	var previous: Dictionary = viewport.get_meta(HISTORY_RESET_META, {})
	var receipt := {"notifications": int(previous.get("notifications", 0)) + 1,
		"submitted": int(previous.get("submitted", 0)), "last_reason": reason.left(80)}
	var target: Object = RenderingServer if backend == null else backend
	var policy: Dictionary = viewport.get_meta(POLICY_META, {})
	var supported := is_instance_valid(target) and target.has_method(HISTORY_RESET_METHOD)
	var submit: bool = supported and policy.get("provider", "native") == "dlss" and viewport.get_viewport_rid().is_valid()
	if submit:
		target.call(HISTORY_RESET_METHOD, viewport.get_viewport_rid())
		receipt.submitted += 1
	viewport.set_meta(HISTORY_RESET_META, receipt)
	return submit


static func describe(viewport: Viewport) -> Dictionary:
	var policy: Dictionary = viewport.get_meta(POLICY_META, resolve("native", runtime_capabilities())).duplicate(true)
	var config: Variant = viewport.get_meta(CONFIG_META, {})
	var reflex_request := NvidiaReflex.DEFAULT_MODE
	if typeof(config) == TYPE_DICTIONARY:
		reflex_request = str(config.get("nvidia_reflex", NvidiaReflex.DEFAULT_MODE))
	policy["nvidia_reflex"] = NvidiaReflex.describe(reflex_request)
	policy["history_reset"] = viewport.get_meta(HISTORY_RESET_META, {"notifications": 0, "submitted": 0, "last_reason": ""}).duplicate(true)
	policy.history_reset["api_available"] = RenderingServer.has_method(HISTORY_RESET_METHOD)
	policy["scaling_3d_mode"] = viewport.scaling_3d_mode
	policy["scale"] = viewport.scaling_3d_scale
	policy["msaa_3d"] = viewport.msaa_3d
	policy["fsr_sharpness"] = viewport.fsr_sharpness
	policy.merge(_sharpening_receipt(str(policy.provider), viewport.fsr_sharpness), true)
	policy["texture_mipmap_bias"] = viewport.texture_mipmap_bias
	var backend := _backend_status(str(policy.provider))
	if not backend.is_empty():
		policy["backend"] = backend
	if viewport.has_meta(RUNTIME_FAILURE_META):
		policy["runtime_failure"] = viewport.get_meta(RUNTIME_FAILURE_META).duplicate(true)
	policy["output_size"] = [viewport.get_visible_rect().size.x, viewport.get_visible_rect().size.y]
	# Nominal dimensions, not a GPU allocation measurement (engine rounding may differ).
	policy["nominal_3d_size"] = [roundi(policy.output_size[0] * viewport.scaling_3d_scale),
		roundi(policy.output_size[1] * viewport.scaling_3d_scale)]
	return policy


static func _resolve_capabilities(high_available_or_capabilities: Variant, extra: Dictionary) -> Dictionary:
	if typeof(high_available_or_capabilities) == TYPE_DICTIONARY:
		return high_available_or_capabilities.duplicate(true)
	if not extra.is_empty():
		var combined := extra.duplicate(true)
		combined["high"] = bool(high_available_or_capabilities)
		return combined
	var high := bool(high_available_or_capabilities)
	# Compatibility for existing callers/tests that passed one `high_available` flag.
	# New provider tests and production use explicit capabilities instead.
	return {"high": high, "fsr2": high, "fsr3": false, "dlss": false,
		"fsr2_mode": _integer_constant_or_null("Viewport", "SCALING_3D_MODE_FSR2")}


static func _scaling_mode_id(provider: String, capabilities: Dictionary) -> Variant:
	match provider:
		"native": return Viewport.SCALING_3D_MODE_BILINEAR
		"fsr2": return capabilities.get("fsr2_mode", Viewport.SCALING_3D_MODE_FSR2)
		"fsr3": return capabilities.get("fsr3_mode")
		"dlss": return capabilities.get("dlss_mode")
	return null


static func _engine_sharpness_value(provider: String, user_strength: float) -> float:
	if provider == "dlss":
		return 0.0
	return 2.0 * (1.0 - user_strength)


static func _sharpening_receipt(provider: String, engine_value: float) -> Dictionary:
	var strength := 0.0 if provider == "dlss" else 1.0 - engine_value / 2.0
	return {"sharpening_strength": strength,
		"sharpening_active": provider in ["fsr2", "fsr3"] and engine_value < 2.0}


static func _integer_constant_or_null(class_name_text: String, constant_name: String) -> Variant:
	if not ClassDB.class_has_integer_constant(class_name_text, constant_name):
		return null
	return ClassDB.class_get_integer_constant(class_name_text, constant_name)


static func _streamline_dlss_unavailable_reason() -> String:
	if not Engine.has_singleton(DLSS_SINGLETON):
		return "dlss_support_missing"
	var streamline: Object = Engine.get_singleton(DLSS_SINGLETON)
	if streamline == null:
		return "dlss_support_missing"
	# New native builds latch dispatch failure separately from initialization support.
	# Retain compatibility with experimental engines predating this status API.
	if streamline.has_method("get_dlss_status"):
		var status: Variant = streamline.call("get_dlss_status")
		if typeof(status) == TYPE_DICTIONARY:
			if bool(status.get("backend_failed", false)):
				return "dlss_runtime_failure"
			return "" if bool(status.get("available", false)) else "dlss_unavailable"
		return "dlss_unavailable"
	if not streamline.has_method("get_capability") \
			or not ClassDB.class_has_integer_constant(DLSS_SINGLETON, DLSS_CAPABILITY):
		return "dlss_support_missing"
	var capability := ClassDB.class_get_integer_constant(DLSS_SINGLETON, DLSS_CAPABILITY)
	return "dlss_unavailable" if not bool(streamline.call("get_capability", capability)) else ""


static func _backend_status(provider: String) -> Dictionary:
	var backend: Object = RenderingServer if provider == "fsr3" else null
	if provider == "dlss" and Engine.has_singleton(DLSS_SINGLETON):
		backend = Engine.get_singleton(DLSS_SINGLETON)
	var status_method := "get_" + provider + "_status"
	if backend != null and backend.has_method(status_method):
		var status: Variant = backend.call(status_method)
		if typeof(status) == TYPE_DICTIONARY:
			return status
	return {}
