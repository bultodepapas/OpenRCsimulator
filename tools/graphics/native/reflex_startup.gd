## Trial-only autoload. The engine owns Reflex scheduling and PCL frame markers.
## Kept outside the production application; prepare_candidate.py receipts this copy.
extends Node

const MODES := {"off": 0, "on": 1, "boost": 2}
var requested := "off"
var _backend: Object
var _poll_seconds := 0.0
var _last_state := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)
	requested = OS.get_environment("OPENRC_NVIDIA_REFLEX").strip_edges().to_lower()
	if requested.is_empty():
		requested = "off"
	if not MODES.has(requested):
		push_warning("Unknown OPENRC_NVIDIA_REFLEX mode; using Off.")
		requested = "off"
	if not Engine.has_singleton("Streamline"):
		print("NVIDIA_REFLEX|unavailable|reason=engine_missing")
		return
	_backend = Engine.get_singleton("Streamline")
	if not _backend.has_method("get_reflex_status") or not _backend.has_method("set_parameter") \
			or not ClassDB.class_has_integer_constant("Streamline", "STREAMLINE_PARAM_REFLEX_MODE"):
		print("NVIDIA_REFLEX|unavailable|reason=status_api_missing")
		return
	var parameter := ClassDB.class_get_integer_constant("Streamline", "STREAMLINE_PARAM_REFLEX_MODE")
	_backend.call("set_parameter", parameter, MODES[requested])
	# The SDK applies a request at the next frame boundary. Do not report it as active here.
	print("NVIDIA_REFLEX|requested=%s" % requested)
	set_process(true)


func _process(delta: float) -> void:
	_poll_seconds += delta
	if _poll_seconds < 1.0:
		return
	_poll_seconds = 0.0
	var status: Dictionary = _backend.call("get_reflex_status")
	var available := bool(status.get("available", false))
	var failed := bool(status.get("backend_failed", false))
	var applied := int(status.get("applied_mode", -1))
	var state := "%s|%s|%d" % [available, failed, applied]
	if state == _last_state:
		return
	_last_state = state
	var label := "unconfirmed"
	if applied >= 0 and applied <= 2:
		label = ["off", "on", "boost"][applied]
	print("NVIDIA_REFLEX|requested=%s|sdk_accepted=%s|available=%s|failed=%s" % [
		requested, label, available, failed])
	if failed or (requested != "off" and not available):
		push_warning("NVIDIA Reflex request could not be enabled; check the native backend status.")
