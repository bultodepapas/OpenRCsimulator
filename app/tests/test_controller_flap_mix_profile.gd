extends SceneTree

const Profile := preload("res://input/controller_profile.gd")
const ProfileStore := preload("res://input/controller_profile_store.gd")
const RcInput := preload("res://input/rc_input.gd")
const ControllerSetup := preload("res://ui/controller_setup.gd")
const ControllerDiagnostics := preload("res://input/controller_diagnostics.gd")

class FakeRegistry extends RefCounted:
	signal devices_changed
	var devices: Array[Dictionary] = [
		{"id": 5, "name": "Radio", "raw_name": "Radio", "kind": "radio", "known": true, "connected": true, "serial_number": "mix-radio"},
		{"id": 7, "name": "Joystick", "raw_name": "Joystick", "kind": "joystick", "known": false, "connected": true, "serial_number": "mix-joystick"},
		{"id": 9, "name": "Gamepad", "raw_name": "Gamepad", "kind": "gamepad", "known": true, "connected": true},
	]

	func get_devices() -> Array[Dictionary]:
		return devices.duplicate(true)

	func selected_device_id(_role: String) -> int:
		return -1

	func device_for_id(device_id: int) -> Dictionary:
		for device: Dictionary in devices:
			if device.id == device_id:
				return device.duplicate(true)
		return {}

	func connection_generation(device_id: int) -> int:
		return 4 if not device_for_id(device_id).is_empty() else 0


var checks := 0
var failures := 0
var output_path := ""


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	InputMap.load_from_project_settings()
	output_path = ProjectSettings.globalize_path("res://../tmp/avanti-control-r4/profile-ui/store-%d-%d" % [Time.get_unix_time_from_system(), Time.get_ticks_usec()])
	_check("create isolated storage directory", DirAccess.make_dir_recursive_absolute(output_path) == OK)
	_test_contract()
	await _test_persistence_and_ui()
	print("Controller flap mix profile: %d checks, %d failed" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
		printerr("FAIL ", label)


func _test_contract() -> void:
	for kind: String in ["gamepad", "radio", "joystick"]:
		var profile := Profile.defaults(kind, "mode2" if kind == "gamepad" else "radio_custom")
		_check("explicit simulator default for " + kind, profile.get("flap_elevator_mix_owner") == "simulator" and Profile.validate(profile).ok)
		var old := profile.duplicate(true)
		old.erase("flap_elevator_mix_owner")
		var upgraded := Profile.upgrade_legacy(old)
		_check("missing v2 owner remains valid and upgrades for " + kind, Profile.validate(old).ok \
			and Profile.flap_elevator_mix_owner(old) == "simulator" and upgraded.get("flap_elevator_mix_owner") == "simulator")
		var expected := old.duplicate(true)
		if expected.get("aux", null) == {}:
			expected.erase("aux") # Existing v2 upgrade sanitizes an empty AUX dictionary.
		upgraded.erase("flap_elevator_mix_owner")
		_check("v2 upgrade preserves old profile for " + kind, upgraded == expected and not old.has("flap_elevator_mix_owner"))
		_check("diagnostics report effective default for " + kind, ControllerDiagnostics.build({}, old).profile.flap_elevator_mix_owner == "simulator")
	var legacy: Dictionary = RcInput.DEFAULT_PROFILE.duplicate(true)
	var legacy_before := legacy.duplicate(true)
	var migrated := Profile.upgrade_legacy(legacy)
	_check("legacy radio defaults to simulator without changing source", migrated.get("flap_elevator_mix_owner") == "simulator" \
		and Profile.validate(migrated).ok and legacy == legacy_before)
	_check("legacy pitch normalization remains unchanged", Profile.normalize_axis(-0.4, migrated.pitch) == RcInput.normalize(-0.4, legacy.pitch))
	_check("non-profile input defaults to simulator", Profile.flap_elevator_mix_owner(null) == "simulator")
	for kind: String in ["radio", "joystick"]:
		var profile := Profile.defaults(kind, "radio_custom")
		profile["flap_elevator_mix_owner"] = "transmitter"
		_check("transmitter ownership accepted for " + kind, Profile.validate(profile).ok \
			and Profile.flap_elevator_mix_owner(profile) == "transmitter" \
			and Profile.upgrade_legacy(profile).get("flap_elevator_mix_owner") == "transmitter")
		_check("diagnostics report transmitter ownership for " + kind, ControllerDiagnostics.build({}, profile).profile.flap_elevator_mix_owner == "transmitter")
		for invalid: Variant in [null, true, 0, 1.0, "", "other", "TRANSMITTER", " transmitter ", &"transmitter", [], {}]:
			var malformed := profile.duplicate(true)
			malformed["flap_elevator_mix_owner"] = invalid
			_check("malformed owner rejected for " + kind + ": " + str(invalid), not Profile.validate(malformed).ok \
				and Profile.upgrade_legacy(malformed).is_empty() and Profile.flap_elevator_mix_owner(malformed) == "simulator")
	var pad := Profile.defaults()
	pad["flap_elevator_mix_owner"] = "transmitter"
	_check("gamepad transmitter owner is rejected and never effective", not Profile.validate(pad).ok \
		and Profile.upgrade_legacy(pad).is_empty() and Profile.flap_elevator_mix_owner(pad) == "simulator")
	_check("diagnostics do not normalize invalid or absent profiles", ControllerDiagnostics.build({}, pad).profile.flap_elevator_mix_owner == null \
		and ControllerDiagnostics.build({}, {}).profile.flap_elevator_mix_owner == null)


func _test_persistence_and_ui() -> void:
	var store := ProfileStore.new(output_path.path_join("profiles.cfg"))
	var radio := Profile.defaults("radio", "radio_custom")
	radio["name"] = "Test radio"
	var joystick := Profile.defaults("joystick", "radio_custom")
	joystick["name"] = "Test joystick"
	joystick["flap_elevator_mix_owner"] = "transmitter"
	_check("radio save succeeds", store.save_profile(radio).ok)
	_check("joystick transmitter save succeeds", store.save_profile(joystick).ok)
	var loaded := store.load_all()
	_check("radio and joystick reload their choices", loaded.ok and loaded.profiles.size() == 2 \
		and loaded.profiles[0].flap_elevator_mix_owner == "simulator" and loaded.profiles[1].flap_elevator_mix_owner == "transmitter")
	var old_radio := radio.duplicate(true)
	old_radio.erase("flap_elevator_mix_owner")
	old_radio["profile_id"] = Profile.defaults("radio", "radio_custom").profile_id
	var old_cfg := ConfigFile.new()
	old_cfg.set_value("controller_profiles", "schema_version", 2)
	old_cfg.set_value("controller_profiles", "profiles", [old_radio])
	_check("write old schema-v2 fixture", old_cfg.save(output_path.path_join("old.cfg")) == OK)
	var old_store := ProfileStore.new(output_path.path_join("old.cfg"))
	var old_loaded := old_store.load_all()
	_check("old schema-v2 storage remains readable with simulator behavior", old_loaded.ok and old_loaded.profiles.size() == 1 \
		and not old_loaded.profiles[0].has("flap_elevator_mix_owner") and Profile.flap_elevator_mix_owner(old_loaded.profiles[0]) == "simulator")
	var measured: Dictionary = RcInput.DEFAULT_PROFILE.duplicate(true)
	measured.roll.min = -0.8
	measured.roll.max = 0.9
	var radio_transmitter := radio.duplicate(true)
	radio_transmitter["flap_elevator_mix_owner"] = "transmitter"
	var merged := Profile.merge_radio_calibration(radio_transmitter, measured)
	_check("radio calibration preserves transmitter owner and updates ranges", merged.get("flap_elevator_mix_owner") == "transmitter" \
		and merged.roll.min == -0.8 and merged.roll.max == 0.9 and radio_transmitter.roll.min != -0.8)

	var registry := FakeRegistry.new()
	var setup := ControllerSetup.new()
	setup.configure(registry, store, 5)
	root.add_child(setup)
	await process_frame
	setup.load_selected_profile(radio.profile_id)
	setup.select_section("aux")
	await process_frame
	var picker: OptionButton = setup.flap_mix_owner_picker
	var help := setup.find_child("FlapElevatorMixHelp", true, false) as Label
	_check("radio picker and explanation appear under flaps", not picker.disabled and picker.selected == 0 \
		and setup._aux_controls.flaps.row.get_parent().is_ancestor_of(picker) and help != null \
		and help.text.contains("actual flap position") and help.text.contains("your radio"))
	picker.select(1)
	picker.item_selected.emit(1)
	_check("selection updates only the draft", setup.current_profile().flap_elevator_mix_owner == "transmitter" \
		and store.load_all().profiles[0].flap_elevator_mix_owner == "simulator")
	setup.load_selected_profile(joystick.profile_id)
	_check("joystick selection loads stored transmitter owner", not picker.disabled and picker.selected == 1)
	setup.load_selected_profile(radio.profile_id)
	_check("switching profiles restores unsaved radio choice", picker.selected == 1 and setup.current_profile().flap_elevator_mix_owner == "transmitter")
	setup._apply_preset("radio_custom")
	_check("restoring the radio preset preserves the choice", setup.current_profile().flap_elevator_mix_owner == "transmitter")
	_check("calibration handoff preserves the draft choice", setup.apply_calibration_draft(measured, 5, 4) \
		and setup.current_profile().flap_elevator_mix_owner == "transmitter")
	var applied: Array = []
	setup.save_and_apply = func(candidate: Dictionary, _flight_id: int, _ui_id: int) -> Dictionary:
		applied.append(candidate.duplicate(true))
		return {"ok": false, "error": "simulated apply failure"}
	_check("failed apply retains draft and saved choice", not setup._save_profile(false) \
		and setup.current_profile().flap_elevator_mix_owner == "transmitter" \
		and store.load_all().profiles[0].flap_elevator_mix_owner == "simulator")
	setup.save_and_apply = func(candidate: Dictionary, _flight_id: int, _ui_id: int) -> Dictionary:
		applied.append(candidate.duplicate(true))
		return store.save_profile(candidate)
	_check("save applies and persists the chosen owner", setup._save_profile(false) and applied.size() == 2 \
		and applied[1].flap_elevator_mix_owner == "transmitter" and store.load_all().profiles[0].flap_elevator_mix_owner == "transmitter")
	picker.select(0)
	picker.item_selected.emit(0)
	var closed := [false]
	setup.close_requested.connect(func() -> void: closed[0] = true)
	setup._cancel_edits()
	_check("cancel discards an uncommitted owner change", closed[0] and store.load_all().profiles[0].flap_elevator_mix_owner == "transmitter")
	setup.queue_free()
	await process_frame

	var reopened := ControllerSetup.new()
	reopened.configure(registry, store, 5)
	root.add_child(reopened)
	await process_frame
	reopened.load_selected_profile(radio.profile_id)
	_check("reopening reloads saved owner", reopened.flap_mix_owner_picker.selected == 1)
	var pad := Profile.defaults()
	reopened.load_selected_profile(pad)
	reopened.flap_mix_owner_picker.item_selected.emit(1)
	_check("gamepad picker is disabled and direct selection cannot change it", reopened.flap_mix_owner_picker.disabled \
		and reopened.flap_mix_owner_picker.selected == 0 and reopened.current_profile().flap_elevator_mix_owner == "simulator")
	reopened.load_selected_profile(old_radio)
	_check("editing old v2 profile exposes explicit simulator default", reopened.current_profile().get("flap_elevator_mix_owner") == "simulator" \
		and reopened.flap_mix_owner_picker.selected == 0)
	reopened._set_draft_profile({})
	_check("empty profile remains an empty sentinel", reopened.current_profile().is_empty())
	reopened.queue_free()
	await process_frame
