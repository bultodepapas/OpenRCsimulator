## DT-MAC-07: MetalFX policy only. The engine owns Metal resources and execution.
extends RefCounted

const TRIAL_ENVIRONMENT := "OPENRC_METALFX_TRIAL"
const PROVIDERS := ["metalfx_spatial", "metalfx_temporal"]

static func runtime_capabilities() -> Dictionary:
	var facts := {
		"trial": OS.get_environment(TRIAL_ENVIRONMENT) == "1",
		"headless": DisplayServer.get_name() == "headless",
		"method": RenderingServer.get_current_rendering_method(),
		"driver": RenderingServer.get_current_rendering_driver_name(),
		"rd_available": false,
	}
	for provider: String in PROVIDERS:
		facts[provider + "_mode"] = _constant("Viewport", "SCALING_3D_MODE_" + provider.to_upper())
		facts[provider + "_supported"] = false
	# Compatibility/headless cannot supply a usable RenderingDevice.
	if not facts.headless and facts.method in ["mobile", "forward_plus"] and facts.driver == "metal":
		var rd := RenderingServer.get_rendering_device()
		if rd != null:
			facts.rd_available = true
			for provider: String in PROVIDERS:
				var feature: Variant = _constant("RenderingDevice", "SUPPORTS_" + provider.to_upper())
				facts[provider + "_supported"] = feature != null and rd.has_feature(int(feature))
			for bound: String in ["min", "max"]:
				var limit: Variant = _constant("RenderingDevice", "LIMIT_METALFX_TEMPORAL_SCALER_" + bound.to_upper() + "_SCALE")
				facts[bound + "_scale"] = float(rd.limit_get(int(limit))) / 1000000.0 if limit != null else 0.0
	return from_facts(facts)

## Pure seam: tests inject facts, never pretend a Windows device can execute MetalFX.
static func from_facts(facts: Dictionary) -> Dictionary:
	var result := {
		"metalfx_trial": bool(facts.get("trial", false)),
		"metalfx_min_scale": facts.get("min_scale", 0.0),
		"metalfx_max_scale": facts.get("max_scale", 0.0),
		"metalfx_method": str(facts.get("method", "")),
		"metalfx_driver": str(facts.get("driver", "")),
	}
	for provider: String in PROVIDERS:
		var reason := ""
		if not bool(facts.get("trial", false)):
			reason = "metalfx_trial_disabled"
		elif bool(facts.get("headless", true)):
			reason = "metalfx_headless"
		elif facts.get("driver", "") != "metal":
			reason = "metalfx_requires_metal"
		elif facts.get("method", "") not in ["mobile", "forward_plus"]:
			reason = "metalfx_renderer_unavailable"
		elif provider == "metalfx_temporal" and facts.get("method", "") != "forward_plus":
			reason = "metalfx_requires_forward_plus"
		elif not bool(facts.get("rd_available", false)):
			reason = "metalfx_device_unavailable"
		elif facts.get(provider + "_mode") == null:
			reason = "engine_mode_missing"
		elif not bool(facts.get(provider + "_supported", false)):
			reason = "metalfx_device_unsupported"
		elif provider == "metalfx_temporal" and not valid_limits(result):
			reason = "metalfx_invalid_scale_limits"
		result[provider] = reason.is_empty()
		result[provider + "_reason"] = reason
		result[provider + "_mode"] = facts.get(provider + "_mode")
	return result

static func valid_limits(capabilities: Dictionary) -> bool:
	var lower: Variant = capabilities.get("metalfx_min_scale")
	var upper: Variant = capabilities.get("metalfx_max_scale")
	return typeof(lower) in [TYPE_FLOAT, TYPE_INT] and typeof(upper) in [TYPE_FLOAT, TYPE_INT] \
		and is_finite(float(lower)) and is_finite(float(upper)) \
		and float(lower) > 0.0 and float(upper) >= float(lower) and float(lower) <= 1.0

static func scale_available(provider: String, scale: float, capabilities: Dictionary) -> bool:
	if provider != "metalfx_temporal":
		return is_finite(scale) and scale > 0.0 and scale < 1.0
	return valid_limits(capabilities) and is_finite(scale) \
		and scale >= float(capabilities.metalfx_min_scale) and scale <= minf(1.0, float(capabilities.metalfx_max_scale))

static func _constant(type_name: String, constant_name: String) -> Variant:
	return ClassDB.class_get_integer_constant(type_name, constant_name) \
		if ClassDB.class_has_integer_constant(type_name, constant_name) else null

