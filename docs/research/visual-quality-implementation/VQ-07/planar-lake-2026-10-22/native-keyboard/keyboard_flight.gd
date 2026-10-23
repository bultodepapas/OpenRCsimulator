## Native VQ-07 diagnostic: ordinary Main + ControllerService, keyboard selected once.
## No pose, input callback, pause, physics tick or frame collector override.
extends SceneTree

func _initialize() -> void:
	_start.call_deferred()

func _start() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("Native renderer required")
		quit(1)
		return
	var service: Node = load("res://input/controller_service.gd").new()
	root.add_child(service)
	if not service.select_devices(-1, -1):
		printerr("Keyboard selection failed")
		quit(1)
		return
	var flight: Node = load("res://main.tscn").instantiate()
	flight.external_controller_selection = true
	root.add_child(flight)
	if not flight.startup_error.is_empty() or flight.session == null:
		printerr("Flight setup failed: ", flight.startup_error)
		quit(1)
		return
	service.attach_session(flight.session)
	if flight.session.radio.connected or not flight.session.input_enabled or not flight.session.physics_enabled:
		printerr("Expected live keyboard input and physical flight")
		quit(1)
		return
	print("Keyboard flight diagnostic: ", JSON.stringify({
		keyboard_selected=service.registry.selected_device_id("flight") == -1,
		radio_connected=flight.session.radio.connected, input_enabled=flight.session.input_enabled,
		physics_enabled=flight.session.physics_enabled, initial_paused=flight.session.sim.paused,
		initial_throttle=flight.session.commands.throttle, startup_error=flight.startup_error,
		focus=root.has_focus(), custom_bootstrap=true, prescribed_pose=false,
		pilot_acceptance=false}))
