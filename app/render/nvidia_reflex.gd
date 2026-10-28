## NVIDIA Reflex requests are presentation-only. The engine owns SDK scheduling.
extends RefCounted

const MODES: Array[String] = ["off", "on", "boost"]
const DEFAULT_MODE := "on"
const ENVIRONMENT_KEY := "OPENRC_NVIDIA_REFLEX"
const SINGLETON := "Streamline"
const PARAMETER := "STREAMLINE_PARAM_REFLEX_MODE"


static func startup_mode() -> String:
	if not OS.has_environment(ENVIRONMENT_KEY):
		return DEFAULT_MODE
	var value := OS.get_environment(ENVIRONMENT_KEY).strip_edges().to_lower()
	return value if value in MODES else "off"


## Send the request even while availability is pending: the native backend gates
## the SDK mode and re-evaluates it when low-latency availability changes.
static func apply(requested: String, backend: Object = null, parameter: Variant = null) -> void:
	var target := _backend_or_runtime(backend)
	var parameter_id: Variant = _parameter_or_runtime(parameter)
	if not _api_available(target, parameter_id):
		return
	var mode := requested if requested in MODES else "off"
	target.call("set_parameter", int(parameter_id), MODES.find(mode))


## The SDK applies asynchronously; an accepted mode is not a latency measurement.
static func describe(requested: String, backend: Object = null, parameter: Variant = null) -> Dictionary:
	var result := {"requested": requested, "available": false, "accepted": "unconfirmed",
		"pending": false, "reason": "support_missing"}
	var target := _backend_or_runtime(backend)
	var parameter_id: Variant = _parameter_or_runtime(parameter)
	if not _api_available(target, parameter_id):
		return result
	var raw: Variant = target.call("get_reflex_status")
	if typeof(raw) != TYPE_DICTIONARY:
		result.reason = "status_invalid"
		return result
	result.backend = raw.duplicate(true)
	var accepted: Variant = raw.get("applied_mode", -1)
	if typeof(accepted) == TYPE_INT and accepted >= 0 and accepted < MODES.size():
		result.accepted = MODES[accepted]
	var failed: Variant = raw.get("backend_failed", false)
	var available: Variant = raw.get("available", false)
	if typeof(failed) != TYPE_BOOL or typeof(available) != TYPE_BOOL:
		result.reason = "status_invalid"
	elif failed:
		result.reason = "runtime_failure"
	elif not available:
		result.reason = "unavailable"
	else:
		result.available = true
		result.reason = ""
		result.pending = result.accepted != requested
	return result


## Off is always selectable. Unsupported On/Boost remain visible and saved.
static func option_status(mode: String, status: Dictionary) -> Dictionary:
	if mode not in MODES:
		return {"available": false, "reason": "unknown_mode"}
	if mode == "off":
		return {"available": true, "reason": ""}
	return {"available": bool(status.get("available", false)),
		"reason": str(status.get("reason", "unavailable"))}


static func _backend_or_runtime(backend: Object) -> Object:
	if backend != null:
		return backend
	return Engine.get_singleton(SINGLETON) if Engine.has_singleton(SINGLETON) else null


static func _parameter_or_runtime(parameter: Variant) -> Variant:
	if parameter != null:
		return parameter
	if ClassDB.class_has_integer_constant(SINGLETON, PARAMETER):
		return ClassDB.class_get_integer_constant(SINGLETON, PARAMETER)
	return null


static func _api_available(backend: Object, parameter: Variant) -> bool:
	return backend != null and is_instance_valid(backend) and typeof(parameter) == TYPE_INT \
		and backend.has_method("get_reflex_status") and backend.has_method("set_parameter")
