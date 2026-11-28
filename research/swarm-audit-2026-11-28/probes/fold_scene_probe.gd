extends SceneTree

const Main := preload("res://main.tscn")
const Ui := preload("res://tests/ui_driver.gd")
var _rows := []

func _initialize() -> void:
	call_deferred("_run")

func _accepted(tick: int, _time: float, _state: PackedFloat64Array, _loads: PackedFloat64Array,
		inputs: PackedFloat64Array, _aux: PackedFloat64Array) -> void:
	if _rows.size() < 40:
		_rows.append({"tick":tick,"throttle":inputs[3],"idle_frame":Engine.get_process_frames()})

func _run() -> void:
	var ui := Ui.new(self)
	var main: Node = Main.instantiate()
	main.external_controller_selection = true
	main.set_user_args(PackedStringArray(["--quick-flight", "--aircraft=f4u-corsair-250", "--start=runway", "--soundscape=off"]))
	root.add_child(main)
	var ready: bool = await ui.wait_until(func() -> bool: return main.startup_complete, 20000)
	if not ready or not main.startup_error.is_empty() or not is_instance_valid(main.session):
		printerr("Scene startup failed: ", main.startup_error)
		quit(1)
		return
	var session: Node = main.session
	session.resume()
	var parked: bool = await ui.wait_until(func() -> bool: return not session.sim.paused and main._stopped_on_wheels(), 3000)
	if not parked:
		printerr("Could not establish stopped runway start: ", session.pause_reason, " ", session.sim.fault_reason)
		await ui.close_app(main)
		quit(1)
		return
	await physics_frame
	var tick_before := int(session.sim.tick)
	session.commands.throttle = 1.0
	session.sim.stepped.connect(_accepted)
	var key := InputEventKey.new()
	key.physical_keycode = KEY_O
	key.pressed = true
	root.push_input(key, true)
	var accepted_action: bool = main._wing_fold_target == 1.0
	var held_immediately: bool = session.throttle_holds.has("wing_fold")
	var switched: bool = await ui.wait_until(func() -> bool:
		return not _rows.is_empty() and float(_rows[-1].throttle) == 0.0, 1500)
	session.sim.stepped.disconnect(_accepted)
	var qualified: bool = accepted_action and not held_immediately and switched and not _rows.is_empty() \
		and _rows[0].tick == tick_before + 1 and _rows[0].throttle == 1.0
	print("FOLD_SCENE_OBSERVATION ", JSON.stringify({"tick_before":tick_before,"accepted_action":accepted_action,
		"held_immediately":held_immediately,"rows":_rows,"switched":switched,"backend":session.stage_backend_identity()}))
	await ui.close_app(main)
	if qualified: print("CORSAIR_FOLD_SCENE_CONFIRMED")
	quit(0 if qualified else 1)
