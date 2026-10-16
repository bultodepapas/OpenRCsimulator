extends SceneTree

const Service := preload("res://input/controller_service.gd")
const Profile := preload("res://input/controller_profile.gd")
const PATH := "user://controller_auto_defaults_test.cfg"
var checks := 0
var failures := 0


func check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
		printerr("FAIL ", label)


func device(id: int, kind := "gamepad") -> Dictionary:
	return {"id": id, "guid": "auto-%d" % id, "name": "Auto device %d" % id,
		"known": kind == "gamepad", "kind": kind, "vendor_id": 700, "product_id": id,
		"serial_number": "auto-serial-%d" % id}


func clean() -> void:
	for suffix in ["", ".tmp", ".rollback", ".legacy"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH + suffix))


func service_for(observed: Array) -> Service:
	var service := Service.new()
	service.store = Service.Store.new(PATH, PATH + ".legacy")
	service.enumerate_devices = func() -> Array: return observed
	return service


func roles(service: Service, flight_id: int, ui_id: int) -> bool:
	return service.registry.selected_device_id("flight") == flight_id and service.registry.selected_device_id("ui") == ui_id


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	clean()
	var observed: Array = []
	var service := service_for(observed)
	root.add_child(service) # production _ready() enumerates devices, without any button press
	service.set_process(false)
	check("empty startup uses keyboard for flight and menus", roles(service, -1, -1))
	observed.append(device(9))
	service.refresh()
	check("Home hot-plug selects a mapped pad for both roles", roles(service, 9, 9))
	check("automatic pad has a usable Mode 2 profile", service.profile_for_device(9).get("preset", "") == "mode2")
	check("automatic selection never writes a controller profile", not FileAccess.file_exists(PATH))
	observed.append(device(3, "radio"))
	service.refresh()
	check("radio wins flight while pad retains menus", roles(service, 3, 9))
	check("radio keeps its existing radio profile and calibration gate", service.profile_for_device(3).get("kind", "") == "radio")
	observed.clear()
	service.refresh()
	check("unplugging everything at Home restores keyboard roles", roles(service, -1, -1))
	observed.append(device(17, "joystick"))
	service.refresh()
	check("an unknown joystick is selected for flight, never menus", roles(service, 17, -1))
	check("unknown axes are not silently treated as a gamepad", service.profile_for_device(17).is_empty())
	service.free()

	service = service_for([device(22), device(5)])
	root.add_child(service)
	service.set_process(false)
	check("controllers already connected at startup need no button press", roles(service, 5, 5))
	service.free()
	service = service_for([device(5), device(22)])
	service.refresh()
	check("selection does not depend on enumeration order", roles(service, 5, 5))
	service.free()

	# Saved identity evidence must survive different connection handles on restart.
	var saved_device := device(44, "joystick")
	var profile := Profile.defaults("joystick", "radio_custom")
	profile.association = {"serial_number": saved_device.serial_number, "vendor_id": 700, "product_id": 44}
	profile.roll.axis = 7
	service = service_for([device(1, "radio"), device(2), saved_device])
	check("custom joystick profile fixture saves", service.store.save_profile(profile).ok)
	var saved_bytes := FileAccess.get_file_as_bytes(PATH)
	service.refresh()
	check("configured joystick takes priority over factory defaults", roles(service, 44, 2))
	check("saved joystick axes are loaded unchanged", service.profile_for_device(44).roll.axis == 7)
	service.free()
	saved_device.id = 97
	service = service_for([device(1, "radio"), saved_device])
	service.refresh()
	check("saved profile follows identity rather than old connection ID", roles(service, 97, -1) and service.profile_for_device(97).profile_id == profile.profile_id)
	check("restart default selection does not rewrite storage", FileAccess.get_file_as_bytes(PATH) == saved_bytes)
	service.free()
	var twin := saved_device.duplicate(true)
	twin.id = 98
	service = service_for([saved_device, twin, device(2)])
	service.refresh()
	check("ambiguous saved identity does not outrank a known pad", roles(service, 2, 2))
	check("ambiguous calibration is never auto-loaded", service.profile_for_device(97).is_empty() and service.profile_for_device(98).is_empty())
	service.free()
	saved_device.id = 44
	var declared_pad := device(55, "joystick")
	var declared_profile := Profile.defaults()
	declared_profile.association = {"serial_number": declared_pad.serial_number, "vendor_id": 700, "product_id": 55}
	service = service_for([saved_device, declared_pad])
	check("unknown gamepad declaration fixture saves", service.store.save_profile(declared_profile).ok)
	service.refresh()
	check("saved joystick flies while a declared unknown gamepad navigates menus", roles(service, 44, 55))
	service.free()
	clean()

	observed = [device(6), device(8)]
	service = service_for(observed)
	service.refresh()
	check("explicit alternate pad selection succeeds", service.select_devices(8, 6))
	check("invalid UI ID is rejected without changing either role", not service.select_devices(6, -2) and roles(service, 8, 6))
	check("invalid flight ID is rejected without changing either role", not service.select_devices(-2, -1) and roles(service, 8, 6))
	observed.append(device(1, "radio"))
	service.refresh()
	check("new connections cannot replace a manual Home choice", roles(service, 8, 6))
	observed.remove_at(1)
	service.refresh()
	check("unplugging manual flight device restores Home default without changing menu choice", roles(service, 1, 6))
	check("explicit keyboard selection succeeds", service.select_devices(-1, -1))
	observed.append(device(4))
	service.refresh()
	check("explicit keyboard choice survives later hot-plug", roles(service, -1, -1))
	service.free()

	observed = [device(6), device(8)]
	service = service_for(observed)
	service.refresh()
	var save_result := service.save_settings_from_setup(Profile.defaults(), 8, 8)
	check("one Save still applies an alternate default", save_result.ok and roles(service, 8, 8))
	observed.append(device(1, "radio"))
	service.refresh()
	check("successful Save pins both manual choices", roles(service, 8, 8))
	service.free()
	clean()

	observed = [device(6)]
	service = service_for(observed)
	var context := {"home": false}
	service.allow_automatic_selection = func() -> bool: return context.home
	service.refresh()
	check("drafts and other activities defer automatic ownership", roles(service, -1, -1))
	context.home = true
	service.refresh()
	check("returning Home applies a pending default without another connection event", roles(service, 6, 6))
	context.home = false
	observed.append(device(1, "radio"))
	service.refresh()
	check("opening Controls preserves active roles while devices arrive", roles(service, 6, 6))
	context.home = true
	service.refresh()
	check("closing Controls without Save restores automatic policy", roles(service, 1, 6))
	service.free()

	# A rejected Save is not a manual override of the startup/Home policy.
	observed = [device(6)]
	service = service_for(observed)
	service.refresh()
	var invalid := Profile.defaults()
	invalid.roll.axis = 99
	check("invalid Save is rejected", not service.save_settings_from_setup(invalid, 6, 6).ok)
	observed.append(device(1, "radio"))
	service.refresh()
	check("rejected Save leaves automatic choices enabled", roles(service, 1, 6))
	service.free()

	var corrupt := ConfigFile.new()
	corrupt.set_value(Service.Store.STORAGE_SECTION, "schema_version", 999)
	corrupt.set_value(Service.Store.STORAGE_SECTION, "profiles", [])
	check("corrupt fixture writes", corrupt.save(PATH) == OK)
	service = service_for([device(6)])
	service.refresh()
	check("corrupt storage cannot silently activate a factory flight profile", roles(service, 6, 6) and service.profile_for_device(6).is_empty())
	service.free()
	clean()
	print("Controller automatic defaults: %d/%d checks passed" % [checks - failures, checks])
	quit(1 if failures else 0)
