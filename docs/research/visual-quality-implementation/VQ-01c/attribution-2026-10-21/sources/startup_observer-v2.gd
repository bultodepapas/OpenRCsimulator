# Read-only, bounded scratch autoload. Never enables input, resumes, or changes launch order.
extends Node

var _app: Node
var _sim: Node
var _session: Node
var _events: Array[Dictionary] = []
var _elapsed := 0.0
var _output := ""

func _ready() -> void:
	_output = OS.get_environment("OPENRC_STARTUP_OBSERVATION")
	get_tree().node_added.connect(_added)
	get_window().focus_entered.connect(func(): _note("window_focus_entered"))
	get_window().focus_exited.connect(func(): _note("window_focus_exited"))
	_note("observer_ready")

func _added(node: Node) -> void:
	var script: Script = node.get_script()
	if script == null:
		return
	match script.resource_path:
		"res://app_root.gd":
			_app = node
			node.ready.connect(func(): _note("app_ready"))
		"res://sim/flight_session.gd":
			_session = node
		"res://sim/simulation.gd":
			_sim = node
			node.paused_changed.connect(func(_paused: bool): _note("paused_changed", get_stack()))
			_note("simulation_added")

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_note("application_focus_out")
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_note("application_focus_in")

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= 1.0:
		_elapsed = 0.0
		_note("sample")

func _note(event: String, stack: Array = []) -> void:
	if _events.size() >= 128 or not is_inside_tree():
		return
	if not is_instance_valid(_app):
		_app = get_tree().root.get_node_or_null("AppRoot")
	var item := {event = event, usec = Time.get_ticks_usec(),
		focused = DisplayServer.window_is_focused(get_window().get_window_id()), stack = stack}
	if is_instance_valid(_sim):
		item.merge({paused = _sim.paused, tick = _sim.tick, fault = _sim.fault_reason})
	if is_instance_valid(_session):
		item.merge({pause_reason = _session.pause_reason, holds = _session.holds.duplicate(true), crash = _session.crash})
	if is_instance_valid(_app):
		item.pause_menu = _app.get("pause_menu") != null
	_events.append(item)

func _exit_tree() -> void:
	if _output.is_empty() or FileAccess.file_exists(_output):
		return
	var file := FileAccess.open(_output, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({format = "openrc-startup-observation v1", events = _events,
			scope = "bounded read-only scratch autoload on the normal main-scene route; not timing acceptance"}, "\t") + "\n")
