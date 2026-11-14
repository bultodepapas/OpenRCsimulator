extends SceneTree

const Setup = preload("res://ui/controller_setup.gd")
const Profile = preload("res://input/controller_profile.gd")
const Service = preload("res://input/controller_service.gd")
const Store = preload("res://input/controller_profile_store.gd")
var failed := 0

func check(label: String, condition: bool, detail := "") -> void:
	print(("OBSERVED " if condition else "NOT OBSERVED ") + label + " " + detail)
	if not condition: failed += 1

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1920, 1080)
	InputMap.load_from_project_settings()
	var dir := "user://capture-audit-" + str(Time.get_ticks_usec())
	var service := Service.new()
	service.store = Store.new(dir + "/profiles.cfg", dir + "/legacy.cfg")
	var a := {"id": 5, "name": "Radio A", "raw_name": "Radio A", "kind": "radio", "known": false,
		"guid": "guid-A", "vendor_id": 100, "product_id": 200, "serial_number": "serial-A"}
	var b := {"id": 5, "name": "Radio B", "raw_name": "Radio B", "kind": "radio", "known": false,
		"guid": "guid-B", "vendor_id": 100, "product_id": 201, "serial_number": "serial-B"}
	var p := Profile.defaults("radio", "radio_custom")
	p.association = {"guid": a.guid, "vendor_id": a.vendor_id, "product_id": a.product_id, "serial_number": a.serial_number}
	p.aux = {"flaps": {"type": "switch", "buttons": [20, 21], "invert": false}}
	check("baseline radio saves", service.store.save_profile(p).ok)
	service.registry.update_devices([a])
	service.registry.select_device("flight", 5)
	var screen := Setup.new()
	screen.configure(service.registry, service.store, 5, -1)
	root.add_child(screen)
	await process_frame
	var button: Button = screen._aux_controls.flaps.switch_capture_buttons[0]
	screen._start_aux_capture("flaps", 0, button)
	var start_gen: int = service.registry.connection_generation(5)
	var capture_gen: int = screen._capturing_generation
	check("AUX capture starts without recording generation", screen._capturing_aux_name == "flaps" and capture_gen == 0)
	# Direct replacement snapshot: registry sees an identity change without a separate disconnected snapshot.
	service.registry.update_devices([b])
	var next_gen: int = service.registry.connection_generation(5)
	var still_capturing: bool = screen._capturing_aux_name == "flaps"
	var press := InputEventJoypadButton.new()
	press.device = 5
	press.button_index = 42
	press.pressed = true
	screen._input(press)
	var bound: Array = screen.current_profile().aux.flaps.buttons
	check("replacement button is accepted into A draft", next_gen > start_gen and still_capturing and bound[0] == 42,
		"generation=" + str(start_gen) + "->" + str(next_gen) + " held=" + str(still_capturing) + " buttons=" + str(bound))
	screen.free()
	await process_frame
	service.free()
	await process_frame
	await remap_case(dir)
	print("CAPTURE_PROBE_COMPLETE failures=", failed)
	quit(0 if failed == 0 else 1)

func remap_case(dir: String) -> void:
	var service := Service.new()
	service.store = Store.new(dir + "/remap.cfg", dir + "/legacy.cfg")
	var a := {"id": 5, "name": "Radio A", "raw_name": "Radio A", "kind": "radio", "known": false,
		"guid": "guid-A", "vendor_id": 100, "product_id": 200, "serial_number": "serial-A"}
	var p := Profile.defaults("radio", "radio_custom")
	p.association = {"guid": a.guid, "vendor_id": a.vendor_id, "product_id": a.product_id, "serial_number": a.serial_number}
	check("remap baseline radio saves", service.store.save_profile(p).ok)
	service.registry.update_devices([a])
	service.registry.select_device("flight", 5)
	var screen := Setup.new()
	screen.configure(service.registry, service.store, 5, -1)
	screen.axis_preview_provider = func(_device: int, axis: int) -> float: return -1.0 if axis == 2 else 0.0
	root.add_child(screen)
	await process_frame
	var button := screen.action_grid.find_child("Remap_camera_cycle", true, false) as Button
	check("camera remap button exists", button != null)
	screen._start_capture("camera_cycle", button)
	var captured := []
	screen.capture_finished.connect(func(target: String, ok: bool, message: String) -> void: captured.append([target, ok, message]))
	var noise := InputEventJoypadMotion.new()
	noise.device = 5
	noise.axis = 2
	noise.axis_value = -0.999
	screen._input(noise)
	check("idle throttle noise ends action capture as rejected conflict", not screen._is_capture_active() and captured.size() == 1 and captured[0][1] == false,
		"event=" + str(captured) + " status=" + screen.status_label.text)
	screen.free()
	await process_frame
	service.free()
	await process_frame
