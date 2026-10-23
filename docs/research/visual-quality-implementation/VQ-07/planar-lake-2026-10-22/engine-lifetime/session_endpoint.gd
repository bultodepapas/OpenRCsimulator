## Synthetic producer check, not active-flight or performance acceptance.
extends SceneTree

func _initialize() -> void:
	_start.call_deferred()

func _start() -> void:
	var scenario := "hold"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--endpoint-case="):
			scenario = arg.trim_prefix("--endpoint-case=")
	var service: Node = load("res://input/controller_service.gd").new()
	root.add_child(service)
	if not service.select_devices(-1, -1):
		push_error("Keyboard selection failed")
		quit(1)
		return
	var flight: Node = load("res://main.tscn").instantiate()
	flight.external_controller_selection = true
	root.add_child(flight)
	if not flight.startup_error.is_empty() or flight.session == null:
		push_error("Flight setup failed: " + flight.startup_error)
		quit(1)
		return
	service.attach_session(flight.session)
	match scenario:
		"hold":
			flight.session.hold("endpoint diagnostic hold")
		"failsafe":
			flight.session._failsafe("endpoint diagnostic failsafe")
		"resumed":
			flight.session.hold("endpoint diagnostic hold")
			flight.session.release("endpoint diagnostic hold")
			flight.session.resume()
		_:
			push_error("Unknown endpoint diagnostic")
			quit(1)
			return
	print("endpoint diagnostic ready: ", scenario)
