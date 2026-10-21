# Phase-1 read-only startup observation; not a timing qualification run.
extends SceneTree

var app: Node

func _initialize() -> void:
	root.focus_entered.connect(func(): _note("window_focus_in"))
	root.focus_exited.connect(func(): _note("window_focus_out"))
	_run.call_deferred()

func _run() -> void:
	app = load("res://app_root.tscn").instantiate()
	root.add_child(app)
	_note("ready")
	for index in range(8):
		await create_timer(1.0).timeout
		_note("after_%ds" % (index + 1))

func _note(event: String) -> void:
	var item := {event = event, usec = Time.get_ticks_usec(),
		focused = DisplayServer.window_is_focused(root.get_window_id())}
	if app != null and app.get("flight") != null:
		var flight: Node = app.get("flight")
		var session: Node = flight.get("session")
		if session != null:
			item.merge({paused = session.sim.paused, tick = session.sim.tick,
				pause_reason = session.pause_reason, holds = session.holds,
				fault = session.sim.fault_reason, crash = session.crash,
				pause_menu = app.get("pause_menu") != null})
	print("phase1 startup: ", JSON.stringify(item))
