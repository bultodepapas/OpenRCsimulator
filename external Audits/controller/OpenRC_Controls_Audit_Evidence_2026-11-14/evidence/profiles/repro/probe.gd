extends SceneTree

const Setup = preload("res://ui/controller_setup.gd")
const Profile = preload("res://input/controller_profile.gd")
const Service = preload("res://input/controller_service.gd")
const Store = preload("res://input/controller_profile_store.gd")

var failed := 0
func check(label: String, condition: bool, detail := "") -> void:
	if condition:
		print("OBSERVED ", label, " ", detail)
	else:
		failed += 1
		print("NOT OBSERVED ", label, " ", detail)

func _initialize() -> void:
	_run.call_deferred()

func device(id: int, key: String, kind: String = "gamepad") -> Dictionary:
	return {"id": id, "name": "fixture " + key, "raw_name": "fixture " + key,
		"kind": kind, "known": kind == "gamepad", "guid": "guid-" + key,
		"vendor_id": 100, "product_id": 200 if key == "A" else 201,
		"serial_number": "serial-" + key}

func make_profile(kind: String, assoc: Dictionary) -> Dictionary:
	var p: Dictionary = Profile.defaults(kind, "mode2" if kind == "gamepad" else "radio_custom")
	p.association = {"serial_number": assoc.serial_number, "guid": assoc.guid,
		"vendor_id": assoc.vendor_id, "product_id": assoc.product_id}
	return p

func setup_screen(service: Node, flight: int) -> CanvasLayer:
	var setup := Setup.new()
	setup.save_and_apply = service.save_settings_from_setup
	setup.configure(service.registry, service.store, flight, -1)
	root.add_child(setup)
	return setup

func _run() -> void:
	root.size = Vector2i(1920,1080)
	InputMap.load_from_project_settings()
	var dir := "user://audit-" + str(Time.get_ticks_usec())
	var service := Service.new()
	service.store = Store.new(dir + "/profiles.cfg", dir + "/legacy.cfg")
	var a := device(5, "A")
	var b := device(5, "B")
	var p_a := make_profile("gamepad", a)
	var p_b := Profile.defaults("gamepad", "mode1")
	p_b.name = "Clean B"
	p_b.association = {"serial_number": "saved-B"}
	check("setup baseline writes A and B", service.store.save_profile(p_a).ok and service.store.save_profile(p_b).ok)
	service.registry.update_devices([a])
	service.registry.select_device("flight", 5)
	var screen := setup_screen(service, 5)
	await process_frame
	var a_id: String = screen.current_profile().profile_id
	screen.profile_name_edit.text = "Unsaved A edit"
	check("A draft becomes dirty", screen.has_unsaved_changes())
	check("switch to B succeeds", screen.load_selected_profile(p_b.profile_id))
	var remembered_name: String = screen._drafts_by_context["profile:" + a_id].name
	var clean_b: bool = not screen.has_unsaved_changes()
	var closes := [0]
	screen.close_requested.connect(func() -> void: closes[0] += 1)
	screen.request_close()
	check("closing clean B bypasses unsaved A question", clean_b and remembered_name == "Unsaved A edit" and closes[0] == 1,
		"remembered=" + remembered_name + " has_unsaved=" + str(not clean_b) + " close_count=" + str(closes[0]))
	screen.free()
	await process_frame
	service.free()
	await process_frame
	await check_hotplug("gamepad", "gamepad")
	await check_hotplug("radio", "gamepad")
	check_serial_collision(dir)
	print("AUDIT_PROBE_COMPLETE failures=", failed)
	quit(0 if failed == 0 else 1)

func check_hotplug(kind_a: String, kind_b: String) -> void:
	var dir := "user://hotplug-" + kind_a + "-" + str(Time.get_ticks_usec())
	var service := Service.new()
	service.store = Store.new(dir + "/profiles.cfg", dir + "/legacy.cfg")
	var a := device(5, "A", kind_a)
	var b := device(5, "B", kind_b)
	var p := make_profile(kind_a, a)
	p.name = "Saved mapping A"
	check("hotplug baseline saves " + kind_a, service.store.save_profile(p).ok)
	service.registry.update_devices([a])
	service.registry.select_device("flight", 5)
	var initial_generation: int = service.registry.connection_generation(5)
	var screen := setup_screen(service, 5)
	await process_frame
	check("hotplug opens A " + kind_a, screen.current_profile().profile_id == p.profile_id)
	screen.profile_name_edit.text = "Edited mapping A"
	service.registry.disconnect_device(5)
	service.registry.update_devices([b])
	var next_generation: int = service.registry.connection_generation(5)
	var submitted_id: int = screen.selected_flight_device_id()
	var submitted: bool = screen._save_profile(false)
	var loaded: Dictionary = service.store.load_all()
	var persisted: Dictionary = loaded.profiles[0] if loaded.ok and not loaded.profiles.is_empty() else {}
	var associated_with_b := str(persisted.get("association", {}).get("serial_number", "")) == "serial-B"
	check("same-ID replacement commits A " + kind_a + " to B", next_generation > initial_generation and submitted_id == 5 and submitted and associated_with_b and persisted.profile_id == p.profile_id and service.registry.selected_device_id("flight") == 5,
		"generation=" + str(initial_generation) + "->" + str(next_generation) + " save=" + str(submitted) + " persisted=" + str(persisted.get("association", {})) + " kind=" + str(persisted.get("kind", "")))
	screen.free()
	await process_frame
	service.free()
	await process_frame

func check_serial_collision(dir: String) -> void:
	var store := Store.new(dir + "/collision.cfg", dir + "/legacy.cfg")
	var p := Profile.defaults("radio", "radio_custom")
	p.association = {"serial_number": "shared", "guid": "guid-A", "vendor_id": 0, "product_id": 0}
	check("serial collision baseline saves", store.save_profile(p).ok)
	var other := {"id": 9, "connected": true, "serial_number": "shared", "guid": "guid-B", "vendor_id": 0, "product_id": 0}
	var matched: Dictionary = store.match_profile(other, [other])
	check("same serial matches different known GUID when VID/PID absent", not matched.is_empty() and matched.profile_id == p.profile_id,
		"saved_guid=guid-A observed_guid=guid-B match=" + str(not matched.is_empty()))
