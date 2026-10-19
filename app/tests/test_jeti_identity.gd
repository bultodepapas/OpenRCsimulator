extends SceneTree

const JetiRadio := preload("res://input/jeti_radio.gd")
const Registry := preload("res://input/controller_registry.gd")
const Service := preload("res://input/controller_service.gd")
const Profile := preload("res://input/controller_profile.gd")
const RcInput := preload("res://input/rc_input.gd")
const Calibration := preload("res://input/rc_calibration.gd")
const PATH := "user://jeti_identity_profiles_test.cfg"
const LEGACY_PATH := "user://jeti_identity_legacy_test.cfg"

var checks := 0
var failures := 0
var duplicate_selection_events := 0
var ambiguity_ready_at_release := false
var reentrant_selection_at_release := -99


func check(label: String, passed: bool, detail: String = "") -> void:
	checks += 1
	if not passed:
		failures += 1
		printerr("FAIL ", label, " ", detail)


func jeti_device(id: int = 1) -> Dictionary:
	return {
		"id": id,
		"guid": "jeti-test-guid",
		"name": "JETI DC/DS Mass Storage",
		"raw_name": "model s.r.o. JETI DC/DS Mass Storage",
		"manufacturer": "JETI model s.r.o.",
		"known": true,
		"kind": "gamepad",
		"vendor_id": 0x0483,
		"product_id": 0xA07C,
		"serial_number": "jeti-test-serial",
		"backend": "SDL3",
		"transport": "usb",
	}


func service_for(path: String = PATH, legacy_path: String = LEGACY_PATH) -> Service:
	var service := Service.new()
	service.store = Service.Store.new(path, legacy_path)
	return service


func clean_paths(path: String = PATH, legacy_path: String = LEGACY_PATH) -> void:
	for suffix in ["", ".tmp", ".rollback"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(legacy_path))


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	clean_paths()
	var valid := jeti_device()
	check("integer USB identifiers and corroborating strings match", JetiRadio.matches(valid))
	check("display label names the family without guessing a model", JetiRadio.display_name(valid) == "JETI DC/DS Radio" \
		and "DC-16" not in JetiRadio.display_name(valid) and "DS-16" not in JetiRadio.display_name(valid))
	var decimal_ids := valid.duplicate(true)
	decimal_ids.vendor_id = "1155"
	decimal_ids.product_id = "41084"
	check("decimal VID and PID strings match", JetiRadio.matches(decimal_ids))
	var hexadecimal_ids := valid.duplicate(true)
	hexadecimal_ids.vendor_id = "0x0483"
	hexadecimal_ids.product_id = "0xA07C"
	check("hexadecimal VID and PID strings normalize", JetiRadio.matches(hexadecimal_ids))
	var native_name_only := valid.duplicate(true)
	native_name_only.erase("manufacturer")
	native_name_only.erase("raw_name")
	check("native JETI device name needs no optional manufacturer or raw name", JetiRadio.matches(native_name_only))
	var manufacturer_only := valid.duplicate(true)
	manufacturer_only.erase("name")
	manufacturer_only.erase("raw_name")
	check("one JETI USB manufacturer descriptor corroborates the complete pair", JetiRadio.matches(manufacturer_only))

	var no_ids := valid.duplicate(true)
	no_ids.erase("vendor_id")
	no_ids.erase("product_id")
	check("a JETI name alone is insufficient", not JetiRadio.matches(no_ids))
	var vendor_only := valid.duplicate(true)
	vendor_only.erase("product_id")
	check("VID alone is insufficient", not JetiRadio.matches(vendor_only))
	var product_only := valid.duplicate(true)
	product_only.erase("vendor_id")
	check("PID alone is insufficient", not JetiRadio.matches(product_only))
	var wrong_vendor := valid.duplicate(true)
	wrong_vendor.vendor_id = 0x1234
	check("wrong vendor identifier is rejected", not JetiRadio.matches(wrong_vendor))
	var wrong_product := valid.duplicate(true)
	wrong_product.product_id = 0x0001
	check("wrong product identifier is rejected", not JetiRadio.matches(wrong_product))
	var malformed_vendor := valid.duplicate(true)
	malformed_vendor.vendor_id = true
	check("malformed vendor identifier is rejected", not JetiRadio.matches(malformed_vendor))

	var unrelated_st := valid.duplicate(true)
	unrelated_st.manufacturer = "STMicroelectronics"
	unrelated_st.name = "USB HID Game Controller"
	unrelated_st.raw_name = "USB HID Game Controller"
	check("unrelated ST device with the same VID and PID evidence is rejected", not JetiRadio.matches(unrelated_st))
	var misleading_name := valid.duplicate(true)
	misleading_name.manufacturer = "Logitech"
	check("misleading JETI name with another manufacturer is rejected", not JetiRadio.matches(misleading_name))
	var conflicting_names := valid.duplicate(true)
	conflicting_names.raw_name = "Xbox Wireless Controller"
	check("contradictory raw and display names are rejected", not JetiRadio.matches(conflicting_names))
	var missing_corroboration := valid.duplicate(true)
	missing_corroboration.manufacturer = ""
	missing_corroboration.name = "USB HID Game Controller"
	missing_corroboration.raw_name = "USB HID Game Controller"
	check("a complete USB pair without a corroborating JETI string is rejected", not JetiRadio.matches(missing_corroboration))
	check("rejected identity keeps the raw display name", JetiRadio.display_name(wrong_product) == str(wrong_product.name))

	var ambiguous := valid.duplicate(true)
	ambiguous.ambiguous = true
	check("ambiguous identity is rejected", not JetiRadio.matches(ambiguous))
	var malformed_ambiguity := valid.duplicate(true)
	malformed_ambiguity.ambiguous = "false"
	check("malformed ambiguity metadata fails closed", not JetiRadio.matches(malformed_ambiguity))
	var emulated_flag := valid.duplicate(true)
	emulated_flag.is_emulated = true
	check("explicitly emulated identity is rejected", not JetiRadio.matches(emulated_flag))
	var emulated_name := valid.duplicate(true)
	emulated_name.name = "JETI DC/DS Mass Storage (virtual device)"
	check("emulated identity text is rejected", not JetiRadio.matches(emulated_name))

	var registry := Registry.new()
	registry.update_devices([valid])
	var normalized: Dictionary = registry.device_for_id(1)
	check("registry classifies corroborated JETI as radio over backend gamepad kind", normalized.kind == "radio")
	check("registry keeps backend names and exposes a separate family label", normalized.name == valid.name \
		and normalized.raw_name == valid.raw_name and normalized.display_name == "JETI DC/DS Radio")
	check("registry keeps raw connection identity", normalized.guid == valid.guid and normalized.vendor_id == 0x0483 \
		and normalized.product_id == 0xA07C)
	var name_only_registry := Registry.new()
	var name_only := no_ids.duplicate(true)
	name_only.id = 2
	name_only_registry.update_devices([name_only])
	check("unverified JETI claim remains an unknown joystick", name_only_registry.device_for_id(2).kind == "joystick")
	var id_only_registry := Registry.new()
	var id_only := valid.duplicate(true)
	id_only.id = 3
	id_only.name = "USB HID Game Controller"
	id_only.raw_name = "USB HID Game Controller"
	id_only.manufacturer = "STMicroelectronics"
	id_only_registry.update_devices([id_only])
	check("VID/PID collision without JETI evidence remains an unknown joystick", id_only_registry.device_for_id(3).kind == "joystick")
	var unverified_service := service_for("user://jeti_unverified_identity.cfg", "user://jeti_unverified_legacy.cfg")
	var unverified_device := valid.duplicate(true)
	unverified_device.id = 4
	unverified_device.product_id = 1
	unverified_service.registry.update_devices([unverified_device])
	check("misleading JETI name cannot trigger a generic known-gamepad profile", unverified_service.profile_for_device(4).is_empty())
	unverified_service.free()
	clean_paths("user://jeti_unverified_identity.cfg", "user://jeti_unverified_legacy.cfg")

	var changed_metadata_service := service_for("user://jeti_changed_metadata.cfg", "user://jeti_changed_metadata_legacy.cfg")
	var metadata_device := jeti_device(6)
	changed_metadata_service.registry.update_devices([metadata_device])
	var cached_metadata_profile: Dictionary = changed_metadata_service.profile_for_device(6)
	var metadata_generation := changed_metadata_service.registry.connection_generation(6)
	changed_metadata_service.registry.select_device("flight", 6)
	var contradictory_metadata := metadata_device.duplicate(true)
	contradictory_metadata.manufacturer = "STMicroelectronics"
	changed_metadata_service.registry.update_devices([contradictory_metadata])
	check("changed JETI manufacturer invalidates the same-handle generation and selection", 
		changed_metadata_service.registry.connection_generation(6) == metadata_generation + 1 \
		and changed_metadata_service.registry.selected_device_id("flight") == -1)
	check("changed contradictory metadata cannot reuse a cached JETI profile", 
		cached_metadata_profile.get("preset", "") == "jeti_mode2" \
		and changed_metadata_service.profile_for_device(6).is_empty())
	changed_metadata_service.free()
	clean_paths("user://jeti_changed_metadata.cfg", "user://jeti_changed_metadata_legacy.cfg")

	var emulated_service := service_for("user://jeti_emulated_metadata.cfg", "user://jeti_emulated_metadata_legacy.cfg")
	var emulated_device := jeti_device(7)
	emulated_service.registry.update_devices([emulated_device])
	var cached_emulated_profile: Dictionary = emulated_service.profile_for_device(7)
	var emulated_generation := emulated_service.registry.connection_generation(7)
	var now_emulated := emulated_device.duplicate(true)
	now_emulated.emulated = true
	emulated_service.registry.update_devices([now_emulated])
	check("adding an emulation flag invalidates the same-handle generation", 
		emulated_service.registry.connection_generation(7) == emulated_generation + 1)
	check("an emulated identity cannot reuse its cached JETI profile", 
		cached_emulated_profile.get("preset", "") == "jeti_mode2" \
		and emulated_service.profile_for_device(7).is_empty())
	emulated_service.free()
	clean_paths("user://jeti_emulated_metadata.cfg", "user://jeti_emulated_metadata_legacy.cfg")

	var service := service_for()
	service.enumerate_devices = func() -> Array: return [jeti_device(5), {
		"id": 2, "guid": "generic-pad", "name": "Generic Pad", "known": true, "kind": "gamepad",
		"vendor_id": 1111, "product_id": 2222,
	}]
	service.refresh()
	check("valid JETI outranks generic pad for flight while pad keeps menus", service.registry.selected_device_id("flight") == 5 \
		and service.registry.selected_device_id("ui") == 2)
	check("JETI HID gamepad is excluded from the menu role", not service.is_ui_gamepad(5))
	var starter: Dictionary = service.profile_for_device(5)
	check("unsaved JETI receives the named Mode 2 radio preset", starter.get("kind", "") == "radio" \
		and starter.get("preset", "") == "jeti_mode2")
	check("JETI starter keeps low-throttle radio safety", starter.get("throttle_mode", "") == "radio_absolute" \
		and starter.get("require_release", false) and starter.get("idle_threshold", 1.0) == 0.05)
	check("radio mapping follows supplied AETR axes", starter.get("roll", {}).get("axis", -1) == 0 \
		and starter.get("pitch", {}).get("axis", -1) == 1 and starter.get("pitch", {}).get("invert", false) \
		and starter.get("throttle", {}).get("axis", -1) == 2 and starter.get("yaw", {}).get("axis", -1) == 3)
	check("generic known gamepad retains its existing default", service.profile_for_device(2).get("kind", "") == "gamepad")
	service.free()

	# A saved schema-2 joystick profile associated with the supplied JETI identity outranks the new starter.
	var saved_device := jeti_device(44)
	clean_paths("user://jeti_saved_identity.cfg", "user://jeti_saved_legacy.cfg")
	saved_device.guid = "0300567e830400007ca0000000000000"
	saved_device.serial_number = ""
	var saved_service := service_for("user://jeti_saved_identity.cfg", "user://jeti_saved_legacy.cfg")
	var saved := Profile.defaults("joystick", "radio_custom")
	saved.name = "Supplied JETI custom"
	saved.roll.axis = 7
	saved.association = {"guid": saved_device.guid, "vendor_id": 1155, "product_id": 41084,
		"legacy_device_key": "0300567e830400007ca0000000000000|0483:a07c|model s.r.o. JETI DC/DS Mass Storage"}
	var saved_result := saved_service.store.save_profile(saved)
	check("saved supplied-style joystick profile fixture is valid", saved_result.ok, str(saved_result.get("error", "")))
	var saved_bytes := FileAccess.get_file_as_bytes("user://jeti_saved_identity.cfg")
	saved_service.registry.update_devices([saved_device])
	var loaded_saved: Dictionary = saved_service.profile_for_device(44)
	check("saved joystick kind and custom axes take precedence over JETI starter", loaded_saved.get("kind", "") == "joystick" \
		and loaded_saved.get("preset", "") == "radio_custom" and loaded_saved.get("roll", {}).get("axis", -1) == 7)
	check("reading saved JETI profile does not rewrite profile storage", FileAccess.get_file_as_bytes("user://jeti_saved_identity.cfg") == saved_bytes)
	saved_service.free()
	clean_paths("user://jeti_saved_identity.cfg", "user://jeti_saved_legacy.cfg")

	# A pre-existing RC calibration is read before any new radio preset is offered.
	var legacy_device := jeti_device(17)
	clean_paths("user://jeti_legacy_identity.cfg", "user://jeti_legacy_rc.cfg")
	legacy_device.guid = "jeti-legacy-guid"
	legacy_device.serial_number = ""
	var legacy_service := service_for("user://jeti_legacy_identity.cfg", "user://jeti_legacy_rc.cfg")
	var legacy_profile: Dictionary = RcInput.DEFAULT_PROFILE.duplicate(true)
	legacy_profile.roll.axis = 5
	var legacy_key := RcInput.key_for(17, legacy_device)
	check("legacy calibration fixture writes", Calibration.save_profile("user://jeti_legacy_rc.cfg", legacy_key, legacy_profile) == OK)
	legacy_service.registry.update_devices([legacy_device])
	var loaded_legacy: Dictionary = legacy_service.profile_for_device(17)
	check("legacy radio profile outranks JETI starter and keeps its axis", loaded_legacy.get("kind", "") == "radio" \
		and loaded_legacy.get("preset", "") == "radio_custom" and loaded_legacy.get("roll", {}).get("axis", -1) == 5)
	legacy_service.free()
	clean_paths("user://jeti_legacy_identity.cfg", "user://jeti_legacy_rc.cfg")

	# A cached default is blocked while the same connection identity becomes ambiguous.
	var startup_duplicate_service := service_for("user://jeti_duplicate_startup.cfg", "user://jeti_duplicate_startup_legacy.cfg")
	var startup_first := jeti_device(68)
	var startup_second := startup_first.duplicate(true)
	startup_second.id = 69
	startup_duplicate_service.enumerate_devices = func() -> Array: return [startup_first, startup_second]
	startup_duplicate_service.refresh()
	check("two unsaved identical JETIs do not take flight or menu ownership at startup", 
		startup_duplicate_service.registry.selected_device_id("flight") == -1 \
		and startup_duplicate_service.registry.selected_device_id("ui") == -1)
	check("ambiguous startup radios cannot receive a fallback profile", startup_duplicate_service.profile_for_device(68).is_empty() \
		and startup_duplicate_service.profile_for_device(69).is_empty())
	startup_duplicate_service.free()
	clean_paths("user://jeti_duplicate_startup.cfg", "user://jeti_duplicate_startup_legacy.cfg")

	var duplicate_service := service_for("user://jeti_duplicate_identity.cfg", "user://jeti_duplicate_legacy.cfg")
	clean_paths("user://jeti_duplicate_identity.cfg", "user://jeti_duplicate_legacy.cfg")
	duplicate_selection_events = 0
	ambiguity_ready_at_release = false
	reentrant_selection_at_release = -99
	duplicate_service.registry.selection_changed.connect(func(role: String, id: int) -> void:
		duplicate_selection_events += 1
		if role == "flight" and id == -1:
			ambiguity_ready_at_release = true
			for info: Dictionary in duplicate_service.registry.get_devices():
				if bool(info.get("connected", false)) and JetiRadio.has_jeti_identity_claim(info) \
						and not bool(info.get("ambiguous", false)):
					ambiguity_ready_at_release = false
			# Model Home reacting synchronously to a lost-selection notification.
			duplicate_service._apply_automatic_defaults()
			reentrant_selection_at_release = duplicate_service.registry.selected_device_id("flight")
	)
	var first_device := jeti_device(70)
	duplicate_service.registry.update_devices([first_device])
	var cached: Dictionary = duplicate_service.profile_for_device(70)
	duplicate_service.registry.select_device("flight", 70)
	var second_device := first_device.duplicate(true)
	second_device.id = 71
	duplicate_service.registry.update_devices([first_device, second_device])
	var first_ambiguous_generation := duplicate_service.registry.connection_generation(70)
	var second_ambiguous_generation := duplicate_service.registry.connection_generation(71)
	var ambiguous_selection_events := duplicate_selection_events
	check("duplicate JETI identities become ambiguous", duplicate_service.registry.device_for_id(70).ambiguous \
		and duplicate_service.registry.device_for_id(71).ambiguous)
	check("new ambiguity releases existing flight ownership", duplicate_service.registry.selected_device_id("flight") == -1)
	check("loss callback sees all duplicates ambiguous before reentrant selection", ambiguity_ready_at_release \
		and reentrant_selection_at_release == -1)
	duplicate_service.registry.update_devices([first_device, second_device])
	check("repeated duplicate snapshots keep generations and selection events stable", 
		duplicate_service.registry.connection_generation(70) == first_ambiguous_generation \
		and duplicate_service.registry.connection_generation(71) == second_ambiguous_generation \
		and duplicate_service.registry.selected_device_id("flight") == -1 \
		and duplicate_selection_events == ambiguous_selection_events)
	check("ambiguity blocks JETI matching and cached starter reuse", not JetiRadio.matches(duplicate_service.registry.device_for_id(70)) \
		and duplicate_service.profile_for_device(70).is_empty())
	duplicate_service.registry.disconnect_device(71)
	var reconnected_profile: Dictionary = duplicate_service.profile_for_device(70)
	var prior_generation := duplicate_service.registry.connection_generation(70)
	duplicate_service.registry.disconnect_device(70)
	duplicate_service.registry.update_devices([first_device])
	var next_generation_profile: Dictionary = duplicate_service.profile_for_device(70)
	check("same connection handle reconnect gets a new profile generation", duplicate_service.registry.connection_generation(70) > prior_generation \
		and next_generation_profile.get("preset", "") == "jeti_mode2" \
		and next_generation_profile.get("profile_id", "") != cached.get("profile_id", "") \
		and next_generation_profile.get("profile_id", "") != reconnected_profile.get("profile_id", ""))
	duplicate_service.free()
	clean_paths("user://jeti_duplicate_identity.cfg", "user://jeti_duplicate_legacy.cfg")

	var corrupt_path := "user://jeti_corrupt_identity.cfg"
	var corrupt_legacy := "user://jeti_corrupt_legacy.cfg"
	clean_paths(corrupt_path, corrupt_legacy)
	var corrupt := ConfigFile.new()
	corrupt.set_value(Service.Store.STORAGE_SECTION, "schema_version", 999)
	corrupt.set_value(Service.Store.STORAGE_SECTION, "profiles", [])
	check("corrupt profile store fixture writes", corrupt.save(corrupt_path) == OK)
	var corrupt_service := service_for(corrupt_path, corrupt_legacy)
	corrupt_service.registry.update_devices([jeti_device(80)])
	check("corrupt profile storage prevents JETI starter fallback", corrupt_service.profile_for_device(80).is_empty())
	corrupt_service.free()
	clean_paths(corrupt_path, corrupt_legacy)

	clean_paths()
	print("JETI identity/service: %d/%d checks passed" % [checks - failures, checks])
	quit(1 if failures else 0)
