extends SceneTree

const Setup := preload("res://ui/controller_setup.gd")
const Verify := preload("res://ui/radio_menu_setup.gd")
const Service := preload("res://input/controller_service.gd")
const Store := preload("res://input/controller_profile_store.gd")
const Profile := preload("res://input/controller_profile.gd")
const Menu := preload("res://input/radio_menu.gd")
const RcInput := preload("res://input/rc_input.gd")

const RADIO_A := 41
const RADIO_B := 42
var checks := 0
var failures := 0
var paths: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func check(label: String, ok: bool, detail: String = "") -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label, " ", detail)


func _path(label: String, extension := "cfg") -> String:
	var path := "user://radio_menu_setup_%d_%s.%s" % [OS.get_process_id(), label, extension]
	paths.append(path)
	return path


func _device(id: int, serial: String) -> Dictionary:
	return {"id": id, "name": "Sensitive transmitter " + serial, "raw_name": "Sensitive transmitter " + serial,
		"kind": "radio", "known": false, "guid": "private-device-guid", "vendor_id": 1209,
		"product_id": 490, "serial_number": serial}


func _fixture(label: String) -> Dictionary:
	var path := _path(label)
	var observations: Array = [_device(RADIO_A, "private-serial-A"), _device(RADIO_B, "private-serial-B")]
	var service := Service.new()
	service.store = Store.new(path, path + ".legacy")
	service.enumerate_devices = func() -> Array: return observations
	service.allow_automatic_selection = func() -> bool: return false
	service.refresh()
	var screen := Setup.new()
	screen.configure(service.registry, service.store, RADIO_A, -1)
	screen.save_and_apply = service.save_settings_from_setup
	screen.axis_preview_provider = func(_id: int, _axis: int) -> float: return 0.0
	return {"service": service, "setup": screen, "devices": observations, "path": path}


func _prepare_radio(screen: Setup, service: Service) -> Dictionary:
	var calibration: Dictionary = RcInput.DEFAULT_PROFILE.duplicate(true)
	calibration.roll.min = float(PackedFloat32Array([-0.987654321])[0])
	calibration.roll.center = float(PackedFloat32Array([0.031234567])[0])
	calibration.roll.max = float(PackedFloat32Array([0.876543219])[0])
	check("fresh current-connection radio calibration enters draft", screen.apply_calibration_draft(calibration, RADIO_A, service.registry.connection_generation(RADIO_A)))
	var draft: Dictionary = screen.current_profile()
	draft.name = "private-profile-name"
	draft.actions["accept"] = {"type": "button", "button": 10}
	draft.actions["back"] = {"type": "axis", "axis": 7, "sign": -1, "threshold": 0.65,
		"off": float(PackedFloat32Array([0.81234567])[0]), "on": float(PackedFloat32Array([0.12345678])[0]), "invert": true}
	draft.actions["pause"] = {"type": "button", "button": 11}
	screen._set_draft_profile(draft)
	check("physical menu controls form a valid radio draft", Profile.validate(draft).ok and not Menu.is_verified(draft), str(Profile.validate(draft).errors))
	return draft


func _run() -> void:
	root.size = Vector2i(1920, 1080)
	InputMap.load_from_project_settings()
	await _verification_and_cross_device()
	await _stale_generation()
	await _sparse_identity("serial_only", {"id": RADIO_A, "name": "Serial-only transmitter", "kind": "radio", "serial_number": "sparse-serial"})
	await _sparse_identity("guid_only", {"id": RADIO_A, "name": "GUID-only transmitter", "kind": "radio", "guid": "sparse-guid"})
	await _sparse_identity("name_only", {"id": RADIO_A, "name": "Name-only transmitter", "kind": "radio"})
	await _sparse_identity("ambiguous_name", {"id": RADIO_A, "name": "Indistinguishable transmitter", "kind": "radio"}, true)
	for path: String in paths:
		for suffix: String in ["", ".tmp", ".rollback", ".legacy"]:
			var target := path + suffix
			if FileAccess.file_exists(target): DirAccess.remove_absolute(ProjectSettings.globalize_path(target))
	print("Radio menu setup: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)


func _sample_twice(modal: Verify) -> void:
	modal._process(0.2)
	modal._process(0.2)


func _sparse_challenge(screen: Setup, service: Service, candidate: Dictionary) -> Dictionary:
	var modal := Verify.new()
	var axes: Array = [float(candidate.roll.center), float(candidate.pitch.center), -1.0, 0.0, 0.0, 0.0, 0.0, float(candidate.actions.back.off), 0.0, 0.0]
	var buttons := {10: false, 11: false}
	screen.axis_preview_provider = func(id: int, axis: int) -> Variant: return axes[axis] if id == RADIO_A else NAN
	screen.button_preview_provider = func(id: int, button: int) -> Variant: return buttons.get(button, false) if id == RADIO_A else null
	modal.read_axis = func(id: int, axis: int) -> float: return float(axes[axis]) if id == RADIO_A else NAN
	modal.read_button = func(id: int, button: int) -> bool: return bool(buttons.get(button, false)) if id == RADIO_A else true
	modal.set_process(false)
	if not modal.configure(service.registry, RADIO_A, candidate):
		modal.free()
		return {}
	var completed: Array[Dictionary] = []
	modal.completed.connect(func(profile: Dictionary) -> void: completed.append(profile))
	root.add_child(modal)
	await process_frame
	_sample_twice(modal)
	var roll: Dictionary = candidate.roll
	var pitch: Dictionary = candidate.pitch
	for movement: Array in [[int(roll.axis), float(roll.min if roll.invert else roll.max), float(roll.center)],
			[int(roll.axis), float(roll.max if roll.invert else roll.min), float(roll.center)],
			[int(pitch.axis), float(pitch.min if pitch.invert else pitch.max), float(pitch.center)],
			[int(pitch.axis), float(pitch.max if pitch.invert else pitch.min), float(pitch.center)]]:
		axes[int(movement[0])] = movement[1]
		_sample_twice(modal)
		axes[int(movement[0])] = movement[2]
		_sample_twice(modal)
	modal._process(0.2)
	buttons[10] = true
	_sample_twice(modal)
	buttons[10] = false
	_sample_twice(modal)
	modal._process(0.2)
	axes[7] = float(candidate.actions.back.on)
	_sample_twice(modal)
	axes[7] = float(candidate.actions.back.off)
	_sample_twice(modal)
	modal._process(0.2)
	buttons[11] = true
	_sample_twice(modal)
	buttons[11] = false
	_sample_twice(modal)
	if modal._done: modal.use_button.pressed.emit()
	modal.free()
	return completed[0] if completed.size() == 1 else {}


func _sparse_identity(label: String, observation: Dictionary, ambiguous := false) -> void:
	var path := _path("sparse_" + label)
	var observations: Array = [observation.duplicate(true)]
	if ambiguous:
		var duplicate := observation.duplicate(true)
		duplicate.id = RADIO_B
		observations.append(duplicate)
	var service := Service.new()
	service.store = Store.new(path, path + ".legacy")
	service.enumerate_devices = func() -> Array: return observations
	service.allow_automatic_selection = func() -> bool: return false
	service.refresh()
	var observed: Dictionary = service.registry.device_for_id(RADIO_A)
	var screen := Setup.new()
	screen.configure(service.registry, service.store, RADIO_A, -1)
	screen.save_and_apply = service.save_settings_from_setup
	root.add_child(screen)
	await process_frame
	screen.set_process(false)
	_prepare_radio(screen, service)
	var candidate: Dictionary = screen._profile_candidate()
	var expected := {"legacy_device_key": RcInput.key_for(RADIO_A, observed), "guid": str(observed.guid),
		"vendor_id": int(observed.vendor_id), "product_id": int(observed.product_id)}
	if not str(observed.serial_number).is_empty(): expected["serial_number"] = observed.serial_number
	check(label + ": challenge binds the same normalized identity shape as Save", candidate.association == expected, str([candidate.association, expected]))
	if str(observed.serial_number).is_empty() and (str(observed.guid).is_empty() or int(observed.vendor_id) == 0 or int(observed.product_id) == 0):
		check(label + ": incomplete metadata binds the legacy identity in its proof", \
			Menu.mapping_fingerprint(candidate).association.get("legacy_device_key") == expected.legacy_device_key)
	var proof: Dictionary = await _sparse_challenge(screen, service, candidate)
	check(label + ": complete physical challenge produces a verified proof", not proof.is_empty() and Menu.is_verified(proof))
	if proof.is_empty():
		screen.free()
		service.free()
		return
	var generation: int = service.registry.connection_generation(RADIO_A)
	check(label + ": same-connection challenge enters draft only", screen.apply_menu_verification(proof, RADIO_A, generation) \
		and Menu.is_verified(screen.current_profile()) and not screen.menu_verification_lease(screen.current_profile()).is_empty() \
		and service.registry.selected_device_id("ui") == -1 and service.store.load_all().profiles.is_empty())
	if ambiguous:
		check(label + ": both identical observations are marked ambiguous", observed.ambiguous \
			and service.registry.device_for_id(RADIO_B).ambiguous)
		var before: Dictionary = service.store.load_all()
		check(label + ": combined Save cannot assign either ambiguous radio", not screen._save_profile(false) \
			and service.registry.selected_device_id("ui") == -1 and service.store.load_all().profiles == before.profiles \
			and not service.is_ui_device(RADIO_A) and not service.is_ui_device(RADIO_B), screen.status_label.text)
		check(label + ": service also refuses explicit UI assignment", not service.select_devices(-1, RADIO_A) \
			and not service.select_devices(-1, RADIO_B) and service.registry.selected_device_id("ui") == -1)
		screen.free()
		service.free()
		return
	var preference := {"mode": "profile", "profile_id": proof.profile_id}
	var saved := screen._save_profile(false)
	var stored: Dictionary = service.store.load_all()
	check(label + ": combined Save persists proof and UI preference", saved and stored.ok and stored.profiles.size() == 1 \
		and Menu.is_verified(stored.profiles[0]) and stored.ui_preference == preference \
		and service.registry.selected_device_id("ui") == RADIO_A, screen.status_label.text)
	if not saved:
		screen.free()
		service.free()
		return
	check(label + ": canonicalized draft retains proof and live lease", Menu.is_verified(screen.current_profile()) \
		and not screen.menu_verification_lease(screen.current_profile()).is_empty())
	check(label + ": repeat Save preserves proof and preference", screen._save_profile(false) \
		and Menu.is_verified(screen.current_profile()) and service.store.load_all().ui_preference == preference, screen.status_label.text)
	if label == "name_only":
		var saved_a := screen.current_profile()
		observations.append({"id": RADIO_B, "name": "Different name-only transmitter", "kind": "radio"})
		service.refresh()
		var b_index: int = screen.flight_device_picker.get_item_index(RADIO_B)
		check("distinct name-only radios both remain connected", service.registry.device_for_id(RADIO_A).connected \
			and service.registry.device_for_id(RADIO_B).connected and b_index >= 0)
		if b_index >= 0:
			screen._on_flight_device_selected(b_index)
			check("saved name-only A profile can be loaded onto B", screen.load_selected_profile(saved_a.profile_id))
			check("distinct name-only B cannot inherit A proof or lease", not Menu.is_verified(screen.current_profile()) \
				and screen.menu_verification_lease(screen.current_profile()).is_empty() \
				and Menu.mapping_fingerprint(screen._profile_candidate()) != Menu.mapping_fingerprint(saved_a))
			var b_ui: int = screen.ui_device_picker.get_item_index(RADIO_B)
			check("unverified name-only B is disabled for UI", b_ui < 0 or screen.ui_device_picker.is_item_disabled(b_ui))
			var before_transfer: Dictionary = service.store.load_all()
			if b_ui >= 0: screen._on_ui_device_selected(b_ui)
			check("name-only B cannot Save with A's proof", not screen._save_profile(false) \
				and service.store.load_all().profiles == before_transfer.profiles \
				and service.store.load_all().ui_preference == before_transfer.ui_preference \
				and service.registry.selected_device_id("ui") == RADIO_A)
	screen.free()
	service.free()
	await process_frame
	var reconnected := observation.duplicate(true)
	reconnected.id = 51
	var reloaded := Service.new()
	reloaded.store = Store.new(path, path + ".legacy")
	reloaded.enumerate_devices = func() -> Array: return [reconnected]
	reloaded.allow_automatic_selection = func() -> bool: return true
	reloaded.refresh()
	var restored: Dictionary = reloaded.profile_for_device(51)
	check(label + ": new connection restores saved proof and preferred UI", reloaded.registry.selected_device_id("ui") == 51 \
		and reloaded.is_ui_device(51) and Menu.is_verified(restored) and restored.get("profile_id") == proof.profile_id \
		and reloaded.store.load_all().ui_preference == preference, str([reloaded.registry.selected_device_id("ui"), restored]))
	var reopened := Setup.new()
	reopened.configure(reloaded.registry, reloaded.store, 51, 51)
	root.add_child(reopened)
	await process_frame
	check(label + ": reopened setup displays saved verified profile", Menu.is_verified(reopened.current_profile()) \
		and reopened.current_profile().profile_id == proof.profile_id and reopened.selected_ui_device_id() == 51)
	reopened.free()
	reloaded.free()
	await process_frame


func _verification_and_cross_device() -> void:
	var fixture := _fixture("flow")
	var service: Service = fixture.service
	var screen: Setup = fixture.setup
	root.add_child(screen)
	await process_frame
	await process_frame
	screen.set_process(false)
	var original := _prepare_radio(screen, service)
	check("verification button is available for configured radio", screen.verify_menus_button.visible and not screen.verify_menus_button.disabled)
	var candidate: Dictionary = screen._profile_candidate()
	var modal := Verify.new()
	var axes: Array = [float(candidate.roll.center), float(candidate.pitch.center), -1.0, 0.0, 0.0, 0.0, 0.0, float(candidate.actions.back.off), 0.0, 0.0]
	var buttons := {10: false, 11: false}
	screen.axis_preview_provider = func(id: int, axis: int) -> Variant: return axes[axis] if id == RADIO_A else NAN
	screen.button_preview_provider = func(id: int, button: int) -> Variant: return buttons.get(button, false) if id == RADIO_A else null
	modal.read_axis = func(id: int, axis: int) -> float: return float(axes[axis]) if id == RADIO_A else NAN
	modal.read_button = func(id: int, button: int) -> bool: return bool(buttons.get(button, false)) if id == RADIO_A else true
	modal.set_process(false)
	check("modal accepts current selected radio candidate", modal.configure(service.registry, RADIO_A, candidate))
	var completed: Array[Dictionary] = []
	var cancelled: Array[String] = []
	modal.completed.connect(func(profile: Dictionary) -> void: completed.append(profile))
	modal.cancelled.connect(func(reason: String) -> void: cancelled.append(reason))
	root.add_child(modal)
	await process_frame
	var own := InputEventJoypadMotion.new()
	own.device = RADIO_A
	var foreign := InputEventJoypadMotion.new()
	foreign.device = RADIO_B
	check("modal consumes only selected controller events", modal.owns_controller_event(own) and not modal.owns_controller_event(foreign))
	modal._use_verified()
	check("uncompleted modal cannot issue a proof", completed.is_empty() and modal.use_button.disabled)
	_sample_twice(modal)
	var roll: Dictionary = candidate.roll
	var pitch: Dictionary = candidate.pitch
	var right := float(roll.min if roll.invert else roll.max)
	var left := float(roll.max if roll.invert else roll.min)
	var down := float(pitch.min if pitch.invert else pitch.max)
	var up := float(pitch.max if pitch.invert else pitch.min)
	for movement: Array in [[int(roll.axis), right, float(roll.center)], [int(roll.axis), left, float(roll.center)],
			[int(pitch.axis), down, float(pitch.center)], [int(pitch.axis), up, float(pitch.center)]]:
		axes[int(movement[0])] = movement[1]
		_sample_twice(modal)
		axes[int(movement[0])] = movement[2]
		_sample_twice(modal)
	modal._process(0.2) # observe Accept OFF at the new action step
	buttons[10] = true
	_sample_twice(modal)
	buttons[10] = false
	_sample_twice(modal)
	modal._process(0.2) # observe Back OFF
	axes[7] = float(candidate.actions.back.on)
	_sample_twice(modal)
	axes[7] = float(candidate.actions.back.off)
	_sample_twice(modal)
	modal._process(0.2) # observe Pause OFF
	buttons[11] = true
	_sample_twice(modal)
	buttons[11] = false
	_sample_twice(modal)
	check("completed physical challenge enables Use", not modal.use_button.disabled and modal._done)
	modal.use_button.pressed.emit()
	check("completed challenge emits one verified profile", completed.size() == 1 and Menu.is_verified(completed[0]) and cancelled.is_empty())
	modal.use_button.pressed.emit()
	check("completed modal cannot emit a duplicate proof", completed.size() == 1)
	modal.free()
	await process_frame
	if completed.is_empty():
		screen.free()
		service.free()
		return
	var generation: int = service.registry.connection_generation(RADIO_A)
	var wrong_profile: Dictionary = completed[0].duplicate(true)
	wrong_profile.profile_id = Profile.defaults("radio", "radio_custom").profile_id
	var before_wrong_profile := screen.current_profile()
	check("verification for a different profile cannot replace this draft", \
		not screen.apply_menu_verification(wrong_profile, RADIO_A, generation) and screen.current_profile() == before_wrong_profile)
	check("proof applies to the same current draft and connection", screen.apply_menu_verification(completed[0], RADIO_A, generation))
	check("verification only changes the draft and proposed menu role", Menu.is_verified(screen.current_profile()) \
		and screen.selected_ui_device_id() == RADIO_A and service.registry.selected_device_id("ui") == -1 \
		and service.store.load_all().profiles.is_empty())
	check("current draft carries a live verification lease", not screen.menu_verification_lease(screen.current_profile()).is_empty())
	var seed: Dictionary = screen.menu_seed_samples(screen.current_profile())
	check("verification lease exposes current selected-device seed samples", seed.get("axes", PackedFloat64Array()).size() == Menu.AXES \
		and seed.get("buttons", {}).get(10) == false and seed.get("buttons", {}).get(11) == false)
	var router := preload("res://ui/radio_menu_input.gd").new()
	check("fresh completed verification seed is accepted by the router", router.configure(RADIO_A, generation, screen.current_profile()) \
		and router.seed_verified_samples(seed.get("axes", PackedFloat64Array()), seed.get("buttons", {})))
	axes[7] = candidate.actions.back.on
	seed = screen.menu_seed_samples(screen.current_profile())
	var held_router := preload("res://ui/radio_menu_input.gd").new()
	check("a held control cannot seed a ready router even after verification", held_router.configure(RADIO_A, generation, screen.current_profile()) \
		and not held_router.seed_verified_samples(seed.get("axes", PackedFloat64Array()), seed.get("buttons", {})))
	axes[7] = candidate.actions.back.off
	_diagnostics(screen, service)
	var input_min: float = screen.current_profile().roll.min
	var input_off: float = screen.current_profile().actions.back.off
	var saved := screen._save_profile(false)
	var stored: Dictionary = service.store.load_all()
	check("Save atomically commits verified profile and menu preference", saved and stored.ok and stored.profiles.size() == 1 \
		and stored.ui_preference == {"mode": "profile", "profile_id": screen.current_profile().profile_id} \
		and service.registry.selected_device_id("ui") == RADIO_A, screen.status_label.text)
	if not saved:
		screen.free()
		service.free()
		return
	var canonical: Dictionary = screen.current_profile()
	check("fixture exercises ConfigFile float canonicalization", canonical.roll.min != input_min or canonical.actions.back.off != input_off, str([input_min, canonical.roll.min, input_off, canonical.actions.back.off]))
	check("saved proof remains verified after float canonicalization", Menu.is_verified(canonical) and not screen.menu_verification_lease(canonical).is_empty())
	var next_candidate: Dictionary = screen._profile_candidate()
	check("next Save candidate retains committed proof and canonical actions", Menu.is_verified(next_candidate) \
		and Menu.action_fingerprint(next_candidate) == Menu.action_fingerprint(canonical), \
		str([canonical.actions.back, next_candidate.actions.back, next_candidate.get("ui_navigation", {})]))
	check("saving the canonicalized profile a second time succeeds", screen._save_profile(false) and Menu.is_verified(screen.current_profile()), screen.status_label.text)
	var before_edit: Dictionary = screen.current_profile()
	screen._on_axis_invert(not bool(before_edit.roll.invert), "roll")
	check("editing a verified mapping clears its menu proof and proposed radio UI", not Menu.is_verified(screen.current_profile()) \
		and not screen.current_profile().has("ui_navigation") and screen.selected_ui_device_id() != RADIO_A)
	check("editing a verified mapping invalidates the live lease", screen.menu_verification_lease(screen.current_profile()).is_empty())
	# Discard unsaved edits, reopen the saved A profile, then explicitly load it onto B.
	screen.free()
	await process_frame
	screen = Setup.new()
	screen.configure(service.registry, service.store, RADIO_A, RADIO_A)
	screen.save_and_apply = service.save_settings_from_setup
	screen.axis_preview_provider = func(_id: int, _axis: int) -> float: return 0.0
	root.add_child(screen)
	await process_frame
	screen.set_process(false)
	check("saved A profile reopens with its proof", screen.current_profile().profile_id == canonical.profile_id and Menu.is_verified(screen.current_profile()))
	screen._clear_action_binding("accept")
	check("editing a verified shortcut clears menu proof and proposed UI", not Menu.is_verified(screen.current_profile()) \
		and not screen.current_profile().has("ui_navigation") and screen.selected_ui_device_id() != RADIO_A)
	screen.free()
	await process_frame
	screen = Setup.new()
	screen.configure(service.registry, service.store, RADIO_A, RADIO_A)
	screen.save_and_apply = service.save_settings_from_setup
	screen.axis_preview_provider = func(_id: int, _axis: int) -> float: return 0.0
	root.add_child(screen)
	await process_frame
	screen.set_process(false)
	check("discarding the shortcut edit preserves saved A proof", Menu.is_verified(screen.current_profile()))
	var previous_motion := InputEventJoypadMotion.new()
	previous_motion.device = RADIO_A
	previous_motion.axis = 4
	previous_motion.axis_value = 0.6
	screen._observe_diagnostics(previous_motion)
	var b_index: int = screen.flight_device_picker.get_item_index(RADIO_B)
	screen._on_flight_device_selected(b_index)
	check("both radios remain connected during proof transfer attempt", service.registry.device_for_id(RADIO_A).connected and service.registry.device_for_id(RADIO_B).connected)
	screen._observe_diagnostics(previous_motion)
	check("switching selected devices does not attribute A observations to B", screen.diagnostics_report().observations.axes[4].events == 0)
	var new_motion := InputEventJoypadMotion.new()
	new_motion.device = RADIO_B
	new_motion.axis = 6
	new_motion.axis_value = -0.3
	screen._observe_diagnostics(new_motion)
	check("new selected device gets its own diagnostic observations", screen.diagnostics_report().observations.axes[6].events == 1 \
		and screen.diagnostics_report().observations.axes[4].events == 0)
	check("saved A profile can be explicitly selected for B", screen.load_selected_profile(canonical.profile_id))
	check("A verification proof cannot be reused for distinct B", not Menu.is_verified(screen.current_profile()) \
		and screen.menu_verification_lease(screen.current_profile()).is_empty())
	var b_draft := screen.current_profile()
	check("late A proof callback cannot verify the selected B radio", not screen.apply_menu_verification(canonical, RADIO_B, service.registry.connection_generation(RADIO_B)) \
		and screen.current_profile() == b_draft)
	var stored_before_cross: Dictionary = service.store.load_all()
	var b_ui_index: int = screen.ui_device_picker.get_item_index(RADIO_B)
	check("unverified B is not enabled as a menu device", b_ui_index < 0 or screen.ui_device_picker.is_item_disabled(b_ui_index))
	if b_ui_index >= 0: screen._on_ui_device_selected(b_ui_index)
	check("B cannot save an inherited A proof as its own menu controller", not screen._save_profile(false) \
		and service.store.load_all().profiles == stored_before_cross.profiles \
		and service.store.load_all().ui_preference == stored_before_cross.ui_preference)
	screen.free()
	service.free()
	await process_frame


func _diagnostics(screen: Setup, service: Service) -> void:
	var foreign := InputEventJoypadMotion.new()
	foreign.device = RADIO_B
	foreign.axis = 4
	foreign.axis_value = 0.9
	screen._observe_diagnostics(foreign)
	var motion := InputEventJoypadMotion.new()
	motion.device = RADIO_A
	motion.axis = 4
	motion.axis_value = -0.4
	screen._observe_diagnostics(motion)
	motion.axis_value = 0.7
	screen._observe_diagnostics(motion)
	var press := InputEventJoypadButton.new()
	press.device = RADIO_A
	press.button_index = 30
	press.pressed = true
	screen._observe_diagnostics(press)
	press.pressed = false
	screen._observe_diagnostics(press)
	var report: Dictionary = screen.diagnostics_report()
	check("diagnostics observes selected radio axis only", report.observations.axes[4].events == 2 \
		and is_equal_approx(report.observations.axes[4].min, -0.4) and is_equal_approx(report.observations.axes[4].max, 0.7), str(report.observations.axes[4]))
	check("diagnostics records the selected button transitions", report.observations.buttons.size() == 1 \
		and report.observations.buttons[0].button == 30 and report.observations.buttons[0].events == 2)
	var text_report := JSON.stringify(report)
	check("default diagnostics redacts private identities", not report.privacy.identifiers_included \
		and not text_report.contains("private-serial") and not text_report.contains("private-device-guid") \
		and not text_report.contains("private-profile-name") and not text_report.contains("Sensitive transmitter"))
	var path := _path("export", "json")
	screen._export_diagnostics_to(ProjectSettings.globalize_path(path))
	check("diagnostics creates a JSON export", FileAccess.file_exists(path) and "exported" in screen.status_label.text.to_lower())
	var bytes := FileAccess.get_file_as_bytes(path)
	var decoded: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	check("export contains redacted selected-device evidence", decoded is Dictionary \
		and decoded.get("format") == "openrc-controller-diagnostics v1" and decoded.observations.axes[4].events == 2 \
		and not decoded.privacy.identifiers_included)
	motion.axis_value = 0.2
	screen._observe_diagnostics(motion)
	screen._export_diagnostics_to(ProjectSettings.globalize_path(path))
	check("diagnostics refuses overwriting an existing report", FileAccess.get_file_as_bytes(path) == bytes \
		and "not exported" in screen.status_label.text.to_lower())
	check("diagnostic export never changes controller roles or storage", service.registry.selected_device_id("ui") == -1 \
		and service.store.load_all().profiles.is_empty())


func _stale_generation() -> void:
	var fixture := _fixture("stale")
	var service: Service = fixture.service
	var screen: Setup = fixture.setup
	root.add_child(screen)
	await process_frame
	screen.set_process(false)
	_prepare_radio(screen, service)
	var candidate: Dictionary = screen._profile_candidate()
	var proof := Menu.verified_profile(candidate)
	var old_generation: int = service.registry.connection_generation(RADIO_A)
	check("current-generation proof establishes a lease", screen.apply_menu_verification(proof, RADIO_A, old_generation) \
		and not screen.menu_verification_lease(screen.current_profile()).is_empty())
	var modal := Verify.new()
	modal.set_process(false)
	check("generation fixture opens a verification modal", modal.configure(service.registry, RADIO_A, candidate))
	var cancelled: Array[String] = []
	var completed: Array[Dictionary] = []
	modal.cancelled.connect(func(reason: String) -> void: cancelled.append(reason))
	modal.completed.connect(func(profile: Dictionary) -> void: completed.append(profile))
	root.add_child(modal)
	await process_frame
	var before := screen.current_profile()
	service.registry.disconnect_device(RADIO_A)
	check("disconnect cancels current verification", cancelled.size() == 1 and completed.is_empty())
	check("stale-generation completion cannot modify draft", not screen.apply_menu_verification(proof, RADIO_A, old_generation) \
		and screen.current_profile() == before and service.store.load_all().profiles.is_empty())
	check("stale-generation challenge cannot expose seed samples", screen.menu_seed_samples(proof).is_empty())
	modal.free()
	screen.free()
	service.free()
	await process_frame
