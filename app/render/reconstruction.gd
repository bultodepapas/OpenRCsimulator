## VQ-07d: main-view reconstruction; presentation only, never simulation state.
extends RefCounted

const HighGraphics := preload("res://render/high_graphics_profile.gd")
const NvidiaReflex := preload("res://render/nvidia_reflex.gd")
const MetalFX := preload("res://render/metalfx_policy.gd")
const MODES: Array[String] = [
	"auto", "native",
	"fsr2_native", "fsr2_85", "fsr2_quality", "fsr2_balanced", "fsr2_performance",
	"fsr3_native", "fsr3_85", "fsr3_quality", "fsr3_balanced", "fsr3_performance",
	"dlss_native", "dlss_quality", "dlss_balanced", "dlss_performance",
	"metalfx_spatial_85", "metalfx_spatial_quality",
	"metalfx_temporal_native", "metalfx_temporal_85", "metalfx_temporal_quality",
]
const MODE_PROVIDERS := {
	"native": "native",
	"fsr2_native": "fsr2", "fsr2_85": "fsr2", "fsr2_quality": "fsr2",
	"fsr2_balanced": "fsr2", "fsr2_performance": "fsr2",
	"fsr3_native": "fsr3", "fsr3_85": "fsr3", "fsr3_quality": "fsr3",
	"fsr3_balanced": "fsr3", "fsr3_performance": "fsr3",
	"dlss_native": "dlss", "dlss_quality": "dlss", "dlss_balanced": "dlss",
	"dlss_performance": "dlss",
	"metalfx_spatial_85": "metalfx_spatial", "metalfx_spatial_quality": "metalfx_spatial",
	"metalfx_temporal_native": "metalfx_temporal", "metalfx_temporal_85": "metalfx_temporal",
	"metalfx_temporal_quality": "metalfx_temporal",
}
const SCALES := {
	"native": 1.0,
	"fsr2_native": 1.0, "fsr2_85": 0.85, "fsr2_quality": 2.0 / 3.0,
	"fsr2_balanced": 1.0 / 1.7, "fsr2_performance": 0.5,
	"fsr3_native": 1.0, "fsr3_85": 0.85, "fsr3_quality": 2.0 / 3.0,
	"fsr3_balanced": 1.0 / 1.7, "fsr3_performance": 0.5,
	"dlss_native": 1.0, "dlss_quality": 2.0 / 3.0, "dlss_balanced": 1.0 / 1.7,
	"dlss_performance": 0.5,
	"metalfx_spatial_85": 0.85, "metalfx_spatial_quality": 2.0 / 3.0,
	"metalfx_temporal_native": 1.0, "metalfx_temporal_85": 0.85, "metalfx_temporal_quality": 2.0 / 3.0,
}
## DT-MAC-07b: "auto" picks MetalFX Spatial only when its 3D input stays at least 1080p-class
## (AUTO_MIN_INPUT_HEIGHT rows, e.g. Quality on a 2560 × 1600 Retina panel), else Native. Other
## providers are never chosen automatically. The output size is the viewport's pixel size at apply.
const AUTO := "auto"
const AUTO_MIN_INPUT_HEIGHT := 1000
const AUTO_METALFX_ORDER: Array[String] = ["metalfx_spatial_quality", "metalfx_spatial_85"]
static var auto_output_size := Vector2i.ZERO
const DEFAULT_SHARPNESS := 0.9 # User strength; matches Godot's default fsr_sharpness=0.2.
const ENVIRONMENT_KEY := "OPENRC_RECONSTRUCTION"
const SHARPNESS_ENVIRONMENT_KEY := "OPENRC_FSR2_SHARPNESS"
const FSR3_METHOD := "is_fsr3_available"
const DLSS_SINGLETON := "Streamline"
const DLSS_CAPABILITY := "STREAMLINE_CAPABILITY_DLSS"
const POLICY_META := &"openrc_reconstruction"
const CONFIG_META := &"openrc_reconstruction_config"
const RUNTIME_FAILURE_META := &"openrc_reconstruction_runtime_failure"
const METALFX_STATUS_META := &"openrc_metalfx_status_scope"
const METALFX_STATUS_METHOD := &"viewport_get_metalfx_status"
const METALFX_RESET_META := &"openrc_metalfx_pending_reset"
const METALFX_RESET_MAX_ATTEMPTS := 2
const OUTPUT_SIZE_SCOPE := "viewport_render_target_estimate_v1"
const NOMINAL_SIZE_SCOPE := "scaled_viewport_estimate_not_sdk_execution"
const HISTORY_RESET_META := &"openrc_reconstruction_history_reset"
const HISTORY_RESET_METHOD := &"viewport_request_temporal_history_reset"
const METALFX_RESET_STATUS_FIELDS := ["generation", "requested_mode", "configured_mode", "render_buffers_available",
	"provider", "allocation", "submission", "reset_gpu_completion", "temporal_attempts",
	"reset_requested_serial", "reset_submitted_serial", "reset_encoded_serial"]
const METALFX_RESET_RECEIPT_FIELDS := ["accepted", "generation", "serial", "reset_request_attempt"]


## MetalFX trials are method/device gated independently of the High effects profile.
static func available() -> bool:
	return options_available(runtime_capabilities())


static func options_available(capabilities: Dictionary) -> bool:
	return bool(capabilities.get("high", false)) or bool(capabilities.get("metalfx_spatial", false)) \
		or bool(capabilities.get("metalfx_temporal", false)) or bool(capabilities.get("recovery_selectable", false))


## Runtime gates are provider-specific. No GPU name or vendor heuristic is used.
static func runtime_capabilities() -> Dictionary:
	var high := HighGraphics.active()
	var fsr2_mode: Variant = _integer_constant_or_null("Viewport", "SCALING_3D_MODE_FSR2")
	var fsr3_mode: Variant = _integer_constant_or_null("Viewport", "SCALING_3D_MODE_FSR3")
	var dlss_mode: Variant = _integer_constant_or_null("Viewport", "SCALING_3D_MODE_DLSS")
	var fsr3_backend_method := RenderingServer.has_method(FSR3_METHOD)
	var fsr3_backend := fsr3_backend_method and bool(RenderingServer.call(FSR3_METHOD))
	var fsr2_reason := "engine_mode_missing" if high and fsr2_mode == null else ""
	var fsr2_failed := bool(_backend_status("fsr2").get("backend_failed", false))
	if high and fsr2_mode != null and fsr2_failed:
		fsr2_reason = "fsr2_runtime_failure"
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
	var result := {
		"high": high,
		"fsr2": high and fsr2_mode != null and not fsr2_failed,
		"fsr3": high and fsr3_mode != null and fsr3_backend,
		"dlss": high and dlss_mode != null and dlss_reason.is_empty(),
		"fsr2_reason": fsr2_reason,
		"fsr3_reason": fsr3_reason,
		"dlss_reason": dlss_reason,
		"fsr2_mode": fsr2_mode,
		"fsr3_mode": fsr3_mode,
		"dlss_mode": dlss_mode,
	}
	result.merge(MetalFX.runtime_capabilities())
	return result


## Preserve old `resolve(mode, high_available)` callers while allowing deterministic
## provider injection as `resolve(mode, capabilities)` or `resolve(mode, high, caps)`.
static func resolve(requested: String, high_available_or_capabilities: Variant = true,
		capabilities: Dictionary = {}) -> Dictionary:
	var gates := _resolve_capabilities(high_available_or_capabilities, capabilities)
	if requested == AUTO:
		var chosen := auto_mode(gates, auto_output_size)
		var resolved := resolve(chosen, gates)
		resolved["requested"] = AUTO
		resolved["auto_selected"] = chosen
		resolved["auto_output_size"] = [auto_output_size.x, auto_output_size.y]
		resolved["auto_output_size_scope"] = OUTPUT_SIZE_SCOPE
		return resolved
	var status := option_status(requested, gates)
	var selected := requested if bool(status.available) else "native"
	var provider := str(MODE_PROVIDERS.get(selected, "native"))
	var mode_id: Variant = _scaling_mode_id(provider, gates)
	var fallback_reason := str(status.reason) if selected != requested else ""
	if provider != "native" and mode_id == null:
		selected = "native"
		provider = "native"
		mode_id = Viewport.SCALING_3D_MODE_BILINEAR
		fallback_reason = "engine_mode_missing"
	return {
		"requested": requested,
		"requested_provider": str(MODE_PROVIDERS.get(requested, "unknown")),
		"selected": selected,
		"effective": "unknown" if provider in MetalFX.PROVIDERS else selected,
		"provider": provider,
		"effective_provider": "unknown" if provider in MetalFX.PROVIDERS else provider,
		"execution_status": "unverified_trial" if provider in MetalFX.PROVIDERS else "policy_selected",
		"provider_available": bool(status.available),
		"fallback": selected != requested,
		"fallback_reason": fallback_reason,
		"scale": float(SCALES.get(selected, 1.0)),
		"temporal": provider not in ["native", "metalfx_spatial"],
		"scaling_3d_mode": mode_id,
	}


## The concrete mode "auto" selects for these capabilities and output pixels.
static func auto_mode(capabilities: Dictionary, output_size: Vector2i) -> String:
	for mode: String in AUTO_METALFX_ORDER:
		if float(output_size.y) * float(SCALES[mode]) >= AUTO_MIN_INPUT_HEIGHT \
				and bool(option_status(mode, capabilities).available):
			return mode
	return "native"


## Explain why a menu entry is disabled without discarding its saved request.
static func option_status(mode: String, capabilities: Dictionary = {}) -> Dictionary:
	if mode == AUTO:
		return {"available": true, "reason": ""}
	var gates := runtime_capabilities() if capabilities.is_empty() else capabilities.duplicate(true)
	if not MODE_PROVIDERS.has(mode):
		return {"available": false, "reason": "unknown_mode"}
	var provider := str(MODE_PROVIDERS[mode])
	if provider == "native":
		return {"available": true, "reason": ""}
	if provider not in MetalFX.PROVIDERS and not bool(gates.get("high", false)):
		return {"available": false, "reason": "high_profile_inactive"}
	if not bool(gates.get(provider, false)):
		return {"available": false, "reason": str(gates.get(provider + "_reason", provider + "_unavailable"))}
	if _scaling_mode_id(provider, gates) == null:
		return {"available": false, "reason": "engine_mode_missing"}
	if provider in MetalFX.PROVIDERS and not MetalFX.scale_available(provider, float(SCALES[mode]), gates):
		return {"available": false, "reason": "metalfx_scale_out_of_range"}
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
	for key: String in ["fsr3_mode", "dlss_mode", "metalfx_temporal_mode"]:
		var candidate: Variant = gates.get(key)
		if typeof(candidate) == TYPE_INT and mode == int(candidate):
			temporal_mode = true
	if not temporal_mode:
		return 2
	var input_scale := clampf(scale, 0.5, 1.0)
	return clampi(ceili(8.0 / (input_scale * input_scale)) * 2, 16, 64)


## Keep the reset failure visible to both the viewport and its settings controls.
static func capabilities_for_viewport(viewport: Viewport, capabilities: Dictionary = {}) -> Dictionary:
	var gates := runtime_capabilities() if capabilities.is_empty() else capabilities.duplicate(true)
	var failure: Variant = viewport.get_meta(RUNTIME_FAILURE_META, {}) if is_instance_valid(viewport) else {}
	# A failed provider stays unavailable through settings reapplication. The
	# picker must remain usable to choose Native, even when no other provider works.
	if typeof(failure) == TYPE_DICTIONARY:
		var failed_provider := str(failure.get("provider", ""))
		var reason := str(failure.get("reason", ""))
		if failed_provider in MetalFX.PROVIDERS and reason == "backend_failed":
			gates[failed_provider] = false
			gates[failed_provider + "_reason"] = failed_provider + "_runtime_failure"
			gates["recovery_selectable"] = true
		elif failed_provider == "metalfx_temporal" and reason == "history_reset_unavailable":
			gates["metalfx_temporal"] = false
			gates["metalfx_temporal_reason"] = "metalfx_history_reset_unavailable"
	return gates


## Resolve before changing renderer properties so the application can persist its recovery marker first.
static func resolve_for_viewport(viewport: Viewport, config: Dictionary, capabilities: Dictionary = {}) -> Dictionary:
	auto_output_size = viewport_output_size(viewport)
	var gates := capabilities_for_viewport(viewport, capabilities)
	var requested := str(config.get("reconstruction", "native"))
	return resolve(requested, gates)


static func apply(viewport: Viewport, config: Dictionary, capabilities: Dictionary = {}) -> void:
	var previous_failure: Variant = viewport.get_meta(RUNTIME_FAILURE_META, {})
	var policy := resolve_for_viewport(viewport, config, capabilities)
	var provider := str(policy.get("provider", ""))
	var status_before := _metalfx_status(viewport) if provider in MetalFX.PROVIDERS else {}
	var mode_changed := int(viewport.scaling_3d_mode) != int(policy.scaling_3d_mode) \
		or not is_equal_approx(viewport.scaling_3d_scale, float(policy.scale))
	NvidiaReflex.apply(str(config.get("nvidia_reflex", NvidiaReflex.DEFAULT_MODE)))
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
	if provider != "metalfx_temporal":
		var history: Variant = viewport.get_meta(HISTORY_RESET_META, {})
		if viewport.has_meta(METALFX_RESET_META) \
				or (typeof(history) == TYPE_DICTIONARY and history.get("reset_state") in ["encoded", "initial_history"]):
			_finish_metalfx_reset(viewport, "superseded")
	if provider in MetalFX.PROVIDERS:
		_track_metalfx_status(viewport, policy, status_before, mode_changed)
	elif viewport.has_meta(METALFX_STATUS_META):
		viewport.remove_meta(METALFX_STATUS_META)
	if viewport.has_meta(RUNTIME_FAILURE_META) and (typeof(previous_failure) != TYPE_DICTIONARY
			or (str(previous_failure.get("provider", "")) != str(policy.get("requested_provider", ""))
			and not (str(policy.get("requested", "")) == AUTO
			and str(previous_failure.get("provider", "")) == "metalfx_spatial"))):
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
	if provider in MetalFX.PROVIDERS:
		return _guard_metalfx_failure(viewport, policy, capabilities)
	if provider not in ["fsr2", "fsr3", "dlss"]:
		return false
	var status := backend_status.duplicate(true)
	if status.is_empty():
		status = _backend_status(provider)
	if not bool(status.get("backend_failed", false)):
		return false
	return _rollback_runtime_failure(viewport, provider, status, capabilities)


static func _rollback_runtime_failure(viewport: Viewport, provider: String, status: Dictionary,
		capabilities: Dictionary) -> bool:
	var saved_config: Variant = viewport.get_meta(CONFIG_META, {})
	if typeof(saved_config) != TYPE_DICTIONARY:
		return false
	var gates := runtime_capabilities() if capabilities.is_empty() else capabilities.duplicate(true)
	gates[provider] = false
	gates[provider + "_reason"] = provider + "_runtime_failure"
	if provider in MetalFX.PROVIDERS:
		# Set the latch first so an Auto reapply cannot select the failed provider.
		viewport.set_meta(RUNTIME_FAILURE_META, {"provider": provider, "reason": "backend_failed", "backend": status.duplicate(true)})
	apply(viewport, saved_config, gates)
	var fallback_policy: Dictionary = viewport.get_meta(POLICY_META, {})
	fallback_policy["fallback"] = true
	fallback_policy["fallback_reason"] = provider + "_runtime_failure"
	viewport.set_meta(POLICY_META, fallback_policy)
	viewport.set_meta(RUNTIME_FAILURE_META, {
		"provider": provider,
		"reason": "backend_failed",
		"backend": status.duplicate(true),
	})
	return true


## The native getter is ordered after viewport setters and is scoped by this RID.
## It returns an unknown/not-attempted state while its current buffers are pending.
static func _metalfx_status(viewport: Viewport, backend: Object = null) -> Dictionary:
	if not is_instance_valid(viewport):
		return {}
	var rid := viewport.get_viewport_rid()
	var target: Object = RenderingServer if backend == null else backend
	if not rid.is_valid() or not is_instance_valid(target) or not target.has_method(METALFX_STATUS_METHOD):
		return {}
	var status: Variant = target.call(METALFX_STATUS_METHOD, rid)
	return status.duplicate(true) if typeof(status) == TYPE_DICTIONARY else {}


static func _track_metalfx_status(viewport: Viewport, policy: Dictionary, before: Dictionary, changed: bool) -> void:
	var generation := -1
	if typeof(before.get("generation")) == TYPE_INT and int(before.generation) >= 0:
		generation = int(before.generation) + (1 if changed else 0)
	var after := _metalfx_status(viewport)
	if typeof(after.get("generation")) == TYPE_INT and int(after.generation) >= generation:
		generation = int(after.generation)
	_expire_metalfx_reset_receipt(viewport, after)
	viewport.set_meta(METALFX_STATUS_META, {"rid": viewport.get_viewport_rid(),
		"provider": policy.get("provider", ""), "mode": policy.get("scaling_3d_mode"), "generation": generation})


static func _guard_metalfx_failure(viewport: Viewport, policy: Dictionary, capabilities: Dictionary,
		backend: Object = null) -> bool:
	var provider := str(policy.get("provider", ""))
	var scope: Variant = viewport.get_meta(METALFX_STATUS_META, {})
	var actual_mode: Variant = _integer_constant_or_null("Viewport", "SCALING_3D_MODE_" + provider.to_upper())
	if typeof(scope) != TYPE_DICTIONARY or scope.is_empty() or typeof(actual_mode) != TYPE_INT \
			or not _metalfx_scope_matches(viewport, policy, scope, int(actual_mode)):
		if viewport.has_meta(METALFX_RESET_META):
			return _fallback_metalfx_reset(viewport, capabilities)
		return false
	var status := _metalfx_status(viewport, backend)
	if viewport.has_meta(METALFX_RESET_META) \
			and _poll_metalfx_reset(viewport, status, int(actual_mode), scope, capabilities):
		return true
	_expire_metalfx_reset_receipt(viewport, status)
	# The engine explicitly configures Bilinear when Temporal cannot support the
	# view layout. Do not leave the application claiming a Temporal selection.
	if provider == "metalfx_temporal" and _metalfx_configured_native(status, int(actual_mode), int(scope.generation)):
		return _rollback_runtime_failure(viewport, provider, status, capabilities)
	var reason := MetalFX.runtime_failure(status, provider, int(actual_mode), int(scope.generation))
	if typeof(status.get("generation")) == TYPE_INT and int(status.generation) >= int(scope.generation):
		scope["generation"] = int(status.generation)
		viewport.set_meta(METALFX_STATUS_META, scope)
	return _rollback_runtime_failure(viewport, provider, status, capabilities) if not reason.is_empty() else false


static func _metalfx_configured_native(status: Dictionary, mode: int, minimum_generation: int) -> bool:
	return typeof(status.get("generation")) == TYPE_INT and int(status.generation) >= maxi(0, minimum_generation) \
		and typeof(status.get("requested_mode")) == TYPE_INT and int(status.requested_mode) == mode \
		and typeof(status.get("configured_mode")) == TYPE_INT \
		and int(status.configured_mode) == Viewport.SCALING_3D_MODE_BILINEAR \
		and typeof(status.get("render_buffers_available")) == TYPE_BOOL and status.render_buffers_available


static func _metalfx_scope_matches(viewport: Viewport, policy: Dictionary, scope: Dictionary, mode: int) -> bool:
	var rid := viewport.get_viewport_rid()
	return rid.is_valid() and scope.get("rid") == rid and scope.get("provider") == policy.get("provider") \
		and typeof(scope.get("mode")) == TYPE_INT and int(scope.mode) == mode \
		and typeof(policy.get("scaling_3d_mode")) == TYPE_INT and int(policy.scaling_3d_mode) == mode \
		and int(viewport.scaling_3d_mode) == mode and typeof(scope.get("generation")) == TYPE_INT


## Discontinuities invalidate history; ordinary camera movement must not call this.
## A MetalFX acceptance is pending until its matching CPU-side encode is observed.
## Only a caller that has just placed the final pose, before the next draw, may
## rely on the first reset of a proven empty MetalFX buffer generation.
static func request_history_reset(viewport: Viewport, reason: String, backend: Object = null,
		after_pose_before_draw: bool = false) -> bool:
	if not is_instance_valid(viewport) or viewport.is_queued_for_deletion():
		return false
	if after_pose_before_draw and not viewport.is_inside_tree():
		return false
	var previous: Dictionary = viewport.get_meta(HISTORY_RESET_META, {})
	var receipt := {"notifications": int(previous.get("notifications", 0)) + 1,
		"submitted": int(previous.get("submitted", 0)), "last_reason": reason.left(80)}
	var target: Object = RenderingServer if backend == null else backend
	var policy: Dictionary = viewport.get_meta(POLICY_META, {})
	var supported := is_instance_valid(target) and target.has_method(HISTORY_RESET_METHOD)
	var provider := str(policy.get("provider", "native"))
	# Older custom engines wire this API only to DLSS. FSR needs explicit support.
	var provider_supported := provider == "dlss"
	if supported and target.has_method("get_temporal_history_reset_providers"):
		var providers: Variant = target.call("get_temporal_history_reset_providers")
		provider_supported = (typeof(providers) == TYPE_PACKED_STRING_ARRAY or typeof(providers) == TYPE_ARRAY) and provider in providers
	if provider == "metalfx_temporal":
		var scope: Variant = viewport.get_meta(METALFX_STATUS_META, {})
		var actual_mode: Variant = _integer_constant_or_null("Viewport", "SCALING_3D_MODE_METALFX_TEMPORAL")
		var request := {}
		var failure := {}
		if not supported:
			failure.reason = "reset_api_missing"
		elif not provider_supported:
			failure.reason = "provider_unsupported"
		elif not target.has_method(METALFX_STATUS_METHOD):
			failure.reason = "status_api_missing"
		elif typeof(scope) != TYPE_DICTIONARY:
			failure.reason = "scope_invalid"
		elif typeof(actual_mode) != TYPE_INT:
			failure.reason = "mode_unavailable"
		elif not _metalfx_scope_matches(viewport, policy, scope, int(actual_mode)):
			failure.reason = "scope_mismatch"
		else:
			request = _request_metalfx_reset(viewport, target, int(actual_mode), int(scope.generation), failure,
				after_pose_before_draw)
		if not request.is_empty():
			if request.state == "initial_history":
				# No explicit request or encode was observed. A new generation has
				# no old picture, and its first Temporal encode must reset history.
				receipt.merge({"reset_state": "initial_history", "pending": false, "encoded": false,
					"generation": request.generation, "serial": 0, "reset_submitted_serial": 0,
					"reset_encoded_serial": 0, "gpu_completion": "unobserved"}, true)
				viewport.set_meta(HISTORY_RESET_META, receipt)
				if viewport.has_meta(METALFX_RESET_META):
					viewport.remove_meta(METALFX_RESET_META)
				return false # No explicit request was submitted.
			receipt.submitted += 1
			_update_metalfx_reset_receipt(receipt, request, str(request.state))
			viewport.set_meta(HISTORY_RESET_META, receipt)
			if request.state == "pending":
				viewport.set_meta(METALFX_RESET_META, request)
			elif viewport.has_meta(METALFX_RESET_META):
				viewport.remove_meta(METALFX_RESET_META)
			return true
		receipt["reset_state"] = "unavailable"
		receipt["pending"] = false
		receipt["encoded"] = false
		receipt["gpu_completion"] = "unobserved"
		if typeof(scope) == TYPE_DICTIONARY:
			failure["scope"] = _metalfx_diagnostic_fields(scope, ["provider", "mode", "generation"])
		failure["policy"] = _metalfx_diagnostic_fields(policy, ["provider", "scaling_3d_mode"])
		failure["viewport_mode"] = int(viewport.scaling_3d_mode)
		if typeof(actual_mode) == TYPE_INT:
			failure["expected_mode"] = int(actual_mode)
		receipt["failure"] = failure
		viewport.set_meta(HISTORY_RESET_META, receipt)
		_fallback_metalfx_reset(viewport)
		return false
	var submit: bool = supported and provider_supported and viewport.get_viewport_rid().is_valid()
	if submit:
		target.call(HISTORY_RESET_METHOD, viewport.get_viewport_rid())
		receipt.submitted += 1
	viewport.set_meta(HISTORY_RESET_META, receipt)
	return submit


## This helper takes an injected backend for deterministic tests. Production has
## already verified the real engine enum, viewport property, RID and scope.
static func _request_metalfx_reset(viewport: Viewport, backend: Object, mode: int, minimum_generation: int,
		diagnostic: Dictionary = {}, after_pose_before_draw: bool = false) -> Dictionary:
	var before := _metalfx_status(viewport, backend)
	if not _metalfx_reset_ready(before, mode, minimum_generation):
		if after_pose_before_draw and _metalfx_empty_generation(before, mode, minimum_generation):
			return {"state": "initial_history", "generation": int(before.generation)}
		diagnostic["reason"] = "before_status_not_ready"
		diagnostic["before_status"] = _metalfx_diagnostic_fields(before, METALFX_RESET_STATUS_FIELDS)
		return {}
	var raw: Variant = backend.call(HISTORY_RESET_METHOD, viewport.get_viewport_rid())
	if typeof(raw) == TYPE_DICTIONARY and typeof(raw.get("accepted")) == TYPE_BOOL and not raw.accepted:
		diagnostic["reason"] = "reset_rejected"
		diagnostic["before_status"] = _metalfx_diagnostic_fields(before, METALFX_RESET_STATUS_FIELDS)
		diagnostic["reset_receipt"] = _metalfx_diagnostic_fields(raw, METALFX_RESET_RECEIPT_FIELDS)
		return {}
	if typeof(raw) != TYPE_DICTIONARY or typeof(raw.get("accepted")) != TYPE_BOOL or not raw.accepted \
			or typeof(raw.get("generation")) != TYPE_INT or int(raw.generation) != int(before.generation) \
			or typeof(raw.get("serial")) != TYPE_INT or int(raw.serial) <= int(before.reset_requested_serial) \
			or typeof(raw.get("reset_request_attempt")) != TYPE_INT \
			or int(raw.reset_request_attempt) < int(before.temporal_attempts):
		diagnostic["reason"] = "reset_receipt_malformed"
		diagnostic["before_status"] = _metalfx_diagnostic_fields(before, METALFX_RESET_STATUS_FIELDS)
		if typeof(raw) == TYPE_DICTIONARY:
			diagnostic["reset_receipt"] = _metalfx_diagnostic_fields(raw, METALFX_RESET_RECEIPT_FIELDS)
		return {}
	var request := {"rid": viewport.get_viewport_rid(), "mode": mode, "generation": int(raw.generation),
		"serial": int(raw.serial), "reset_request_attempt": int(raw.reset_request_attempt)}
	var after := _metalfx_status(viewport, backend)
	request["state"] = _metalfx_reset_state(after, request)
	request["status"] = after
	if request.state not in ["pending", "encoded"]:
		diagnostic["reason"] = "post_status_unavailable"
		diagnostic["before_status"] = _metalfx_diagnostic_fields(before, METALFX_RESET_STATUS_FIELDS)
		diagnostic["reset_receipt"] = _metalfx_diagnostic_fields(raw, METALFX_RESET_RECEIPT_FIELDS)
		diagnostic["after_status"] = _metalfx_diagnostic_fields(after, METALFX_RESET_STATUS_FIELDS)
	return request if request.state in ["pending", "encoded"] else {}


## This deliberately excludes merely "not ready" states: only a viewport with
## no buffers and no observed work can use the engine's initial-reset contract.
static func _metalfx_empty_generation(status: Dictionary, mode: int, minimum_generation: int) -> bool:
	if minimum_generation < 0 \
			or typeof(status.get("generation")) != TYPE_INT or int(status.generation) < minimum_generation \
			or typeof(status.get("requested_mode")) != TYPE_INT or int(status.requested_mode) != mode \
			or typeof(status.get("configured_mode")) != TYPE_INT or int(status.configured_mode) != -1 \
			or typeof(status.get("render_buffers_available")) != TYPE_BOOL or status.render_buffers_available \
			or typeof(status.get("provider")) != TYPE_STRING or status.provider != "none" \
			or typeof(status.get("allocation")) != TYPE_STRING or status.allocation != "not_attempted" \
			or typeof(status.get("submission")) != TYPE_STRING or status.submission != "not_attempted" \
			or typeof(status.get("reset_gpu_completion")) != TYPE_STRING or status.reset_gpu_completion != "unobserved":
		return false
	for key: String in ["reset_requested_serial", "reset_submitted_serial", "reset_encoded_serial", "temporal_attempts"]:
		if typeof(status.get(key)) != TYPE_INT or int(status[key]) != 0:
			return false
	return true


## Keep failure receipts small even if an injected or future backend returns extra data.
static func _metalfx_diagnostic_fields(source: Dictionary, keys: Array) -> Dictionary:
	var result := {}
	for key: String in keys:
		if not source.has(key):
			continue
		var value: Variant = source[key]
		if typeof(value) in [TYPE_BOOL, TYPE_INT]:
			result[key] = value
		elif typeof(value) == TYPE_STRING:
			result[key] = str(value).left(64)
		else:
			result[key] = "invalid_type"
	return result


static func _metalfx_reset_ready(status: Dictionary, mode: int, minimum_generation: int) -> bool:
	if typeof(status.get("generation")) != TYPE_INT or int(status.generation) < maxi(0, minimum_generation) \
			or typeof(status.get("requested_mode")) != TYPE_INT or int(status.requested_mode) != mode \
			or typeof(status.get("configured_mode")) != TYPE_INT or int(status.configured_mode) != mode \
			or typeof(status.get("render_buffers_available")) != TYPE_BOOL or not status.render_buffers_available \
			or typeof(status.get("provider")) != TYPE_STRING or status.provider != "temporal" \
			or typeof(status.get("allocation")) != TYPE_STRING or status.allocation != "created" \
			or typeof(status.get("submission")) != TYPE_STRING or status.submission != "enqueued" \
			or typeof(status.get("reset_gpu_completion")) != TYPE_STRING or status.reset_gpu_completion != "unobserved":
		return false
	for key: String in ["reset_requested_serial", "reset_submitted_serial", "reset_encoded_serial", "temporal_attempts"]:
		if typeof(status.get(key)) != TYPE_INT or int(status[key]) < 0:
			return false
	return int(status.reset_submitted_serial) <= int(status.reset_requested_serial) \
		and int(status.reset_encoded_serial) <= int(status.reset_requested_serial)


static func _metalfx_reset_state(status: Dictionary, request: Dictionary) -> String:
	if not _metalfx_reset_ready(status, int(request.mode), int(request.generation)) \
			or int(status.generation) != int(request.generation) \
			or int(status.reset_requested_serial) != int(request.serial) \
			or int(status.temporal_attempts) < int(request.reset_request_attempt):
		return "unavailable"
	if int(status.reset_submitted_serial) >= int(request.serial) \
			and int(status.reset_encoded_serial) >= int(request.serial):
		return "encoded"
	# Only actual Temporal render attempts consume the bound; polling a paused or
	# unrendered viewport does not. CPU encoding is not GPU completion.
	if int(status.temporal_attempts) - int(request.reset_request_attempt) >= METALFX_RESET_MAX_ATTEMPTS:
		return "unavailable"
	return "pending"


static func _update_metalfx_reset_receipt(receipt: Dictionary, request: Dictionary, state: String) -> void:
	var status: Dictionary = request.get("status", {})
	receipt["reset_state"] = state
	receipt["pending"] = state == "pending"
	receipt["encoded"] = state == "encoded"
	receipt["generation"] = request.get("generation", -1)
	receipt["serial"] = request.get("serial", 0)
	receipt["reset_submitted_serial"] = status.get("reset_submitted_serial", 0)
	receipt["reset_encoded_serial"] = status.get("reset_encoded_serial", 0)
	receipt["gpu_completion"] = "unobserved"


static func _finish_metalfx_reset(viewport: Viewport, state: String) -> void:
	var receipt: Dictionary = viewport.get_meta(HISTORY_RESET_META, {})
	receipt["reset_state"] = state
	receipt["pending"] = false
	receipt["encoded"] = state == "encoded"
	viewport.set_meta(HISTORY_RESET_META, receipt)
	if viewport.has_meta(METALFX_RESET_META):
		viewport.remove_meta(METALFX_RESET_META)


static func _expire_metalfx_reset_receipt(viewport: Viewport, status: Dictionary) -> void:
	if viewport.has_meta(METALFX_RESET_META):
		return
	var receipt: Variant = viewport.get_meta(HISTORY_RESET_META, {})
	if typeof(receipt) == TYPE_DICTIONARY and receipt.get("reset_state") in ["encoded", "initial_history"] \
			and (typeof(receipt.get("generation")) != TYPE_INT or typeof(status.get("generation")) != TYPE_INT \
			or int(receipt.generation) != int(status.generation)):
		_finish_metalfx_reset(viewport, "superseded")


static func _poll_metalfx_reset(viewport: Viewport, status: Dictionary, mode: int,
		scope: Dictionary, capabilities: Dictionary = {}) -> bool:
	var request: Variant = viewport.get_meta(METALFX_RESET_META, {})
	if typeof(request) != TYPE_DICTIONARY or request.get("rid") != viewport.get_viewport_rid() \
			or typeof(request.get("mode")) != TYPE_INT or int(request.mode) != mode \
			or typeof(request.get("generation")) != TYPE_INT or int(request.generation) < int(scope.generation) \
			or typeof(request.get("serial")) != TYPE_INT or int(request.serial) <= 0 \
			or typeof(request.get("reset_request_attempt")) != TYPE_INT or int(request.reset_request_attempt) < 0:
		return _fallback_metalfx_reset(viewport, capabilities)
	var state := _metalfx_reset_state(status, request)
	if state == "unavailable":
		return _fallback_metalfx_reset(viewport, capabilities)
	request["status"] = status.duplicate(true)
	var receipt: Dictionary = viewport.get_meta(HISTORY_RESET_META, {})
	_update_metalfx_reset_receipt(receipt, request, state)
	viewport.set_meta(HISTORY_RESET_META, receipt)
	if state == "encoded":
		viewport.remove_meta(METALFX_RESET_META)
	return false


static func _fallback_metalfx_reset(viewport: Viewport, capabilities: Dictionary = {}) -> bool:
	_finish_metalfx_reset(viewport, "unavailable")
	var saved: Variant = viewport.get_meta(CONFIG_META, {})
	if typeof(saved) != TYPE_DICTIONARY or saved.is_empty():
		return false
	viewport.set_meta(RUNTIME_FAILURE_META, {"provider": "metalfx_temporal", "reason": "history_reset_unavailable"})
	apply(viewport, saved, capabilities)
	return true


## Estimated render-target pixels; visible_rect is the logical 2D canvas when a size override is active.
static func viewport_output_size(viewport: Viewport) -> Vector2i:
	if not is_instance_valid(viewport):
		return Vector2i.ZERO
	if viewport is SubViewport:
		return (viewport as SubViewport).size
	if viewport is Window and not (viewport as Window).is_embedded():
		var logical := viewport.get_visible_rect().size
		var stretch := viewport.get_stretch_transform().get_scale()
		return Vector2i(roundi(logical.x * stretch.x), roundi(logical.y * stretch.y))
	# Embedded windows can render at their embedder's separate oversampling scale.
	return Vector2i.ZERO


## Mirrors the pinned renderer's positive-size truncation; this is not a backend allocation query.
static func nominal_input_size(output: Vector2i, scale: float) -> Vector2i:
	if output.x <= 0 or output.y <= 0 or not is_finite(scale) or scale <= 0.0:
		return Vector2i.ZERO
	return Vector2i(maxi(1, int(output.x * scale)), maxi(1, int(output.y * scale)))


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
	if policy.get("requested_provider", "") in MetalFX.PROVIDERS:
		policy["viewport_property_scope"] = "requested inputs; internal engine fallback and SDK execution are not observed"
		policy["metalfx_capabilities"] = MetalFX.runtime_capabilities()
	policy["fsr_sharpness"] = viewport.fsr_sharpness
	policy.merge(_sharpening_receipt(str(policy.provider), viewport.fsr_sharpness), true)
	policy["texture_mipmap_bias"] = viewport.texture_mipmap_bias
	var backend := _backend_status(str(policy.provider))
	if not backend.is_empty():
		policy["backend"] = backend
	if viewport.has_meta(RUNTIME_FAILURE_META):
		policy["runtime_failure"] = viewport.get_meta(RUNTIME_FAILURE_META).duplicate(true)
	var output := viewport_output_size(viewport)
	var logical := viewport.get_visible_rect().size
	policy["output_size"] = [output.x, output.y]
	policy["output_size_scope"] = OUTPUT_SIZE_SCOPE if output.x > 0 and output.y > 0 else "unavailable"
	policy["logical_canvas_size"] = [logical.x, logical.y]
	# Nominal dimensions, not a GPU allocation or SDK execution measurement (engine rounding may differ).
	var nominal := nominal_input_size(output, viewport.scaling_3d_scale)
	policy["nominal_3d_size"] = [nominal.x, nominal.y]
	policy["nominal_3d_size_scope"] = NOMINAL_SIZE_SCOPE
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
		"metalfx_spatial", "metalfx_temporal": return capabilities.get(provider + "_mode")
	return null


static func _engine_sharpness_value(provider: String, user_strength: float) -> float:
	if provider == "dlss" or provider in MetalFX.PROVIDERS:
		return 0.0
	return 2.0 * (1.0 - user_strength)


static func _sharpening_receipt(provider: String, engine_value: float) -> Dictionary:
	var strength := 0.0 if provider == "dlss" or provider in MetalFX.PROVIDERS else 1.0 - engine_value / 2.0
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
	var backend: Object = RenderingServer if provider in ["fsr2", "fsr3"] else null
	if provider == "dlss" and Engine.has_singleton(DLSS_SINGLETON):
		backend = Engine.get_singleton(DLSS_SINGLETON)
	var status_method := "get_" + provider + "_status"
	if backend != null and backend.has_method(status_method):
		var status: Variant = backend.call(status_method)
		if typeof(status) == TYPE_DICTIONARY:
			return status
	return {}
