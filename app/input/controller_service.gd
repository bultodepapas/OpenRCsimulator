extends Node
## Interactive-only bridge. Home chooses defaults; active sessions retain explicit ownership.
const Registry := preload("res://input/controller_registry.gd")
const Store := preload("res://input/controller_profile_store.gd")
const Profile := preload("res://input/controller_profile.gd")
const RcInput := preload("res://input/rc_input.gd")
const Calibration := preload("res://input/rc_calibration.gd")
const JetiRadio := preload("res://input/jeti_radio.gd")
const RadioMenu := preload("res://input/radio_menu.gd")

signal flight_selection_changed
signal ui_selection_changed(id: int)
signal continuity_lost

var registry = Registry.new()
var store = Store.new()
var enumerate_devices: Callable = observed_devices
## The shell allows defaults only at startup/Home, never over a draft or another activity.
var allow_automatic_selection: Callable
var clock_msec: Callable = func() -> int: return Time.get_ticks_msec()
var session: Node
var _refreshing := false
var _profiles: Dictionary = {} # connection generation -> explicit selection, never a persistent device ID
## Rejections are reusable between device refreshes; input events must not reload storage.
var _profile_misses: Dictionary = {}
var _elapsed := 0.0
var _last_process_ms := 0
var _last_flight_selection_result := true
var _settings_save_transaction := false
var _defaults_pending := true
var _manual_roles: Dictionary = {}


func _init() -> void:
	registry.selection_changed.connect(_selection_changed)
	registry.devices_changed.connect(func() -> void:
		_profile_misses.clear()
		_defaults_pending = true)


func _ready() -> void:
	Input.joy_connection_changed.connect(_connection_changed)
	refresh()
	_last_process_ms = Time.get_ticks_msec()


func _process(delta: float) -> void:
	var now: int = int(clock_msec.call())
	# A long application suspension breaks continuity, irrespective of whether a stick moved.
	if _last_process_ms > 0 and now - _last_process_ms > 5000 and is_instance_valid(session) and session.radio.connected:
		session.controller_disconnected()
		continuity_lost.emit()
	_last_process_ms = now
	_elapsed += delta
	if _elapsed >= 0.5:
		_elapsed = 0.0
		refresh()


func refresh() -> void:
	# Recheck repaired/imported storage at the existing 0.5 s refresh boundary.
	# Clear before update_devices(), whose selection callbacks run synchronously.
	_profile_misses.clear()
	_refreshing = true
	registry.update_devices(enumerate_devices.call())
	var ui_id: int = registry.selected_device_id("ui")
	if ui_id >= 0 and not is_ui_device(ui_id):
		registry.select_device("ui", -1)
	_refreshing = false
	_apply_automatic_defaults()


## Selection is automatic only before flight. It never writes profiles or arms controls.
func _apply_automatic_defaults() -> void:
	if not _defaults_pending or is_instance_valid(session):
		return
	if allow_automatic_selection.is_valid() and not bool(allow_automatic_selection.call()):
		return
	_defaults_pending = false
	var devices: Array[Dictionary] = registry.get_devices() # stable ascending connection ID
	if not _manual_roles.has("flight"):
		var best_id := -1
		var best_priority := 100
		for info: Dictionary in devices:
			if not bool(info.get("connected", false)):
				continue
			var matching_profile: Dictionary = store.match_profile(info, devices)
			if bool(info.get("ambiguous", false)) and JetiRadio.has_jeti_identity_claim(info) and matching_profile.is_empty():
				continue
			var priority := 3
			if not matching_profile.is_empty():
				priority = 0
			elif info.get("kind", "") == "radio":
				priority = 1
			elif bool(info.get("known", false)) and info.get("kind", "") == "gamepad":
				priority = 2
			if priority < best_priority:
				best_priority = priority
				best_id = int(info.id)
		registry.select_device("flight", best_id)
	if not _manual_roles.has("ui"):
		if _restore_ui_preference(devices): return
		var ui_id: int = registry.selected_device_id("flight")
		if not is_ui_gamepad(ui_id):
			ui_id = -1
			for info: Dictionary in devices:
				if is_ui_gamepad(int(info.id)):
					ui_id = int(info.id)
					break
		registry.select_device("ui", ui_id)


func _restore_ui_preference(devices: Array[Dictionary]) -> bool:
	var loaded: Dictionary = store.load_all()
	if not bool(loaded.get("ok", false)): return false
	var preference: Dictionary = loaded.get("ui_preference", {})
	if preference.get("mode", "") == "keyboard":
		registry.select_device("ui", -1)
		return true
	if preference.get("mode", "") != "profile": return false
	var matches: Array[int] = []
	for info: Dictionary in devices:
		var matched: Dictionary = store.match_profile(info, devices)
		if matched.get("profile_id", "") == preference.get("profile_id", "") and is_ui_device(int(info.id)):
			matches.append(int(info.id))
	if matches.size() != 1: return false
	registry.select_device("ui", matches[0])
	return true


func _connection_changed(id: int, connected: bool) -> void:
	_profile_misses.clear()
	_refreshing = true
	if not connected:
		registry.disconnect_device(id)
	_refreshing = false
	refresh()


static func observed_devices() -> Array:
	var devices: Array = []
	for id: int in Input.get_connected_joypads():
		var info := Input.get_joy_info(id)
		info.merge({"id": id, "name": Input.get_joy_name(id), "guid": Input.get_joy_guid(id),
			"known": Input.is_joy_known(id), "platform": OS.get_name(), "backend": "SDL3"}, true)
		if JetiRadio.matches(info):
			info["kind"] = "radio"
		elif JetiRadio.has_jeti_identity_claim(info):
			info["kind"] = "joystick"
		elif RcInput.looks_like_radio(str(info.name)):
			info["kind"] = "radio"
		devices.append(info)
	return devices


func attach_session(target: Node, initial_start := true) -> void:
	var is_new_session := session != target
	session = target
	if not is_instance_valid(session): return
	if is_new_session:
		# A fresh flight may be built after a long menu/setup operation. Start the
		# suspension watchdog at this explicit session boundary, then monitor normally.
		_last_process_ms = int(clock_msec.call())
	session.external_controller_selection = true
	session.persist_controller_profile = save_calibration
	session.persist_full_controller_profile = save_profile_and_apply
	var id: int = registry.selected_device_id("flight")
	_bind_gamepad_confirmation(id)
	# A fresh keyboard flight retains its declared launch state.
	if id >= 0:
		session.apply_controller_selection(id, registry.device_for_id(id), profile_for_device(id), initial_start)


## A polled zero is trustworthy only for the current selected SDL gamepad while
## the app is focused. Never certify raw joystick layouts or a reused handle.
func _confirmed_gamepad_connection(id: int, expected_id: int, expected_generation: int) -> bool:
	if id != expected_id or registry.connection_generation(id) != expected_generation \
		or not is_inside_tree() or not get_window().has_focus() or registry.selected_device_id("flight") != id:
		return false
	var info: Dictionary = registry.device_for_id(id)
	if not bool(info.get("connected", false)) or not bool(info.get("known", false)) or info.get("kind", "") != "gamepad":
		return false
	return Input.get_connected_joypads().has(id) and Input.is_joy_known(id) \
		and Input.get_joy_guid(id) == str(info.get("guid", "")) \
		and Input.get_joy_name(id) == str(info.get("name", ""))


func _bind_gamepad_confirmation(id: int) -> void:
	if is_instance_valid(session) and session.radio is RcInput:
		session.radio.confirmed_gamepad_connection = _confirmed_gamepad_connection.bind(id, registry.connection_generation(id))


func select_devices(flight_id: int, ui_id: int) -> bool:
	# Check both before making either selection; radios require verified saved navigation.
	if flight_id < -1 or ui_id < -1:
		return false
	for id: int in [flight_id, ui_id]:
		if id >= 0 and not registry.device_for_id(id).get("connected", false): return false
	if ui_id >= 0 and not is_ui_device(ui_id): return false
	var previous: int = registry.selected_device_id("flight")
	_last_flight_selection_result = true
	registry.select_device("ui", ui_id)
	registry.select_device("flight", flight_id)
	# Explicit re-apply also acknowledges lost continuity and the deliberate keyboard fallback.
	if previous == flight_id and is_instance_valid(session) and session._controller_lost:
		_selection_changed("flight", flight_id)
	if _last_flight_selection_result:
		_manual_roles = {"flight": true, "ui": true}
	return _last_flight_selection_result


func is_ui_gamepad(id: int) -> bool:
	var info: Dictionary = registry.device_for_id(id)
	if not bool(info.get("connected", false)) or JetiRadio.has_jeti_identity_claim(info) \
			or info.get("kind", "") == "radio" or RcInput.looks_like_radio(str(info.get("name", ""))):
		return false
	var current: Dictionary = _profiles.get("%d:%d" % [id, registry.connection_generation(id)], {})
	var saved: Dictionary = store.match_profile(info, registry.get_devices())
	if current.get("kind", "") == "radio" or saved.get("kind", "") == "radio": return false
	if bool(info.get("known", false)) and info.get("kind", "") == "gamepad": return true
	# Unknown hardware needs a saved, unambiguous user declaration before it may drive menus.
	return saved.get("kind", "") == "gamepad" and bool(saved.get("configured", false)) and Profile.validate(saved).ok


func is_ui_device(id: int) -> bool:
	var info: Dictionary = registry.device_for_id(id)
	if not bool(info.get("connected", false)): return false
	var saved: Dictionary = store.match_profile(info, registry.get_devices())
	var current: Dictionary = _profiles.get("%d:%d" % [id, registry.connection_generation(id)], {})
	if current.get("kind", "") == "radio" and not RadioMenu.is_verified(current): return false
	if RadioMenu.is_verified(saved) and bool(saved.get("configured", false)) and Profile.validate(saved).ok:
		if not current.is_empty() and (not RadioMenu.is_verified(current) \
			or RadioMenu.mapping_fingerprint(current) != RadioMenu.mapping_fingerprint(saved) \
			or RadioMenu.action_fingerprint(current) != RadioMenu.action_fingerprint(saved)): return false
		return true
	return is_ui_gamepad(id)


func profile_for_device(id: int) -> Dictionary:
	var info: Dictionary = registry.device_for_id(id)
	if not info.get("connected", false): return {}
	# The registry advances the generation when identity-matching evidence changes.
	var key := "%d:%d" % [id, registry.connection_generation(id)]
	if _profiles.has(key): return _profiles[key].duplicate(true)
	# Duplicate arrival does not change an uninterrupted physical handle. Keep
	# its already active profile available to every session consumer, without
	# treating that profile as a match for any newly arrived or reconnected device.
	if bool(info.get("ambiguous", false)) and is_instance_valid(session) \
			and registry.selected_device_id("flight") == id and session.radio is RcInput \
			and session.radio.connected and session.radio.device_id == id \
			and not bool(session.get("_controller_lost")) \
			and session.radio.device_key == RcInput.key_for(id, info):
		return session.radio.profile.duplicate(true)
	if _profile_misses.has(key): return {}
	# A corrupt or unsupported V2 store must not look like an empty store and
	# silently enable a legacy mapping or a built-in default for this device.
	var storage := store.load_all()
	if not bool(storage.get("ok", false)):
		return _remember_profile_miss(key)
	var devices: Array[Dictionary] = registry.get_devices()
	var profile: Dictionary = store.match_profile(info, devices)
	if profile.is_empty() and not store.profiles_for_device(info).is_empty(): return _remember_profile_miss(key)
	# A serial-qualified V2 match remains valid even when a family is duplicated.
	# Legacy keys have no serial and need uniqueness across the current snapshot.
	if profile.is_empty() and (not JetiRadio.has_jeti_identity_claim(info) or JetiRadio.matches(info)) \
			and Store.legacy_identity_is_unique(info, devices):
		var legacy: Dictionary = Calibration.load_profile(store.legacy_path, RcInput.key_for(id, info))
		if not legacy.is_empty():
			if info.get("known", false) and info.get("kind", "") == "gamepad": return _remember_profile_miss(key)
			profile = Profile.upgrade_legacy(legacy, {"legacy_device_key": RcInput.key_for(id, info)})
	if profile.is_empty() and JetiRadio.has_jeti_identity_claim(info):
		return _remember_profile_miss(key)
	elif profile.is_empty() and info.get("known", false) and info.get("kind", "") == "gamepad":
		profile = Profile.defaults()
	# Names suggest a radio role, not a verified physical mapping. Setup can offer
	# a starter draft, but an unsaved radio cannot fly until it is calibrated.
	if profile.is_empty(): return _remember_profile_miss(key)
	_profiles[key] = profile.duplicate(true)
	return profile


func _remember_profile_miss(key: String) -> Dictionary:
	_profile_misses[key] = true
	return {}


func apply_profile(profile: Dictionary, device_id := -1, runtime_snapshot: Variant = null, defer_rollback_signal := false) -> bool:
	var id: int = registry.selected_device_id("flight") if device_id < 0 else device_id
	if id < 0 or not registry.device_for_id(id).get("connected", false): return false
	var prepared := validate_profile_for_session(profile)
	if not bool(prepared.get("ok", false)):
		return false
	var active_profile: Dictionary = prepared.profile
	_profile_misses.clear()
	var key := "%d:%d" % [id, registry.connection_generation(id)]
	var previous_profile: Dictionary = profile_for_device(id)
	if typeof(runtime_snapshot) == TYPE_DICTIONARY:
		previous_profile = runtime_snapshot.duplicate(true)
	_profiles[key] = active_profile.duplicate(true)
	if registry.selected_device_id("flight") == id:
		_last_flight_selection_result = true
		_selection_changed("flight", id)
		if not _last_flight_selection_result:
			if previous_profile.is_empty():
				_profiles.erase(key)
			else:
				_profiles[key] = previous_profile.duplicate(true)
			var previous_check := validate_profile_for_session(previous_profile)
			if is_instance_valid(session):
				if previous_profile.is_empty():
					session.apply_controller_selection(id, registry.device_for_id(id), {}, false)
				elif bool(previous_check.get("ok", false)) and previous_profile != active_profile:
					session.apply_controller_selection(id, registry.device_for_id(id), previous_check.profile, false)
			# Transactional saves wait until storage is restored before notifying observers;
			# otherwise a read from the signal handler could reload the rejected candidate.
			if not defer_rollback_signal:
				flight_selection_changed.emit()
			return false
	if registry.selected_device_id("ui") == id and active_profile.get("kind", "") == "radio" \
		and not RadioMenu.is_verified(active_profile):
		registry.select_device("ui", -1)
	return true


## Normalizes a complete candidate and asks the active session for any route-specific restriction.
func validate_profile_for_session(candidate: Variant) -> Dictionary:
	var profile: Dictionary = Profile.upgrade_legacy(candidate)
	if profile.is_empty():
		return {"ok": false, "profile": {}, "error": "Invalid controller profile."}
	if is_instance_valid(session) and session.has_method("controller_profile_rejection"):
		var rejection: Variant = session.call("controller_profile_rejection", profile)
		if typeof(rejection) != TYPE_STRING:
			return {"ok": false, "profile": {}, "error": "The active flight session returned an invalid controller compatibility result."}
		if not rejection.is_empty():
			return {"ok": false, "profile": {}, "error": rejection}
	return {"ok": true, "profile": profile, "error": ""}


func _selection_changed(role: String, id: int) -> void:
	# A removed/replaced handle releases its manual preference for the next Home.
	# An explicitly chosen keyboard (-1) remains manual for this application run.
	if _refreshing:
		_manual_roles.erase(role)
	if role == "ui":
		if not _settings_save_transaction:
			ui_selection_changed.emit(id)
		return
	var applied := true
	if is_instance_valid(session):
		if _refreshing:
			session.controller_disconnected()
			continuity_lost.emit()
		else:
			_bind_gamepad_confirmation(id)
			applied = bool(session.apply_controller_selection(id, registry.device_for_id(id), profile_for_device(id), false))
	_last_flight_selection_result = applied
	if not _settings_save_transaction:
		flight_selection_changed.emit()


func save_calibration(legacy_profile: Dictionary) -> Dictionary:
	var id: int = registry.selected_device_id("flight")
	var previous: Dictionary = profile_for_device(id)
	if id < 0 or previous.get("kind", "") != "radio":
		return {"ok": false, "error": "Select a radio profile before calibration."}
	var profile: Dictionary = Profile.merge_radio_calibration(previous, legacy_profile)
	if profile.is_empty():
		return {"ok": false, "error": "Invalid calibration."}
	return save_profile_and_apply(profile)


func save_profile_and_apply(candidate: Dictionary) -> Dictionary:
	var id: int = registry.selected_device_id("flight")
	var previous: Dictionary = profile_for_device(id)
	if id < 0 or not registry.device_for_id(id).get("connected", false):
		return {"ok": false, "error": "Select a connected flight controller before saving."}
	var prepared := validate_profile_for_session(candidate)
	if previous.is_empty() or not bool(prepared.get("ok", false)):
		return {"ok": false, "error": str(prepared.get("error", "Invalid controller profile or changed device role."))}
	var profile: Dictionary = prepared.profile
	if profile.kind != previous.kind:
		return {"ok": false, "error": "Invalid controller profile or changed device role."}
	var info: Dictionary = registry.device_for_id(id)
	_associate_profile_with_device(profile, id, info)
	return _save_and_apply(profile, id)


## Setup profiles may intentionally change a device's declared role; radio calibration may not.
func save_profile_from_setup(candidate: Dictionary, flight_device_id := -1) -> Dictionary:
	var selected_id: int = registry.selected_device_id("flight")
	var id: int = int(flight_device_id)
	if id < 0:
		if selected_id >= 0:
			return {"ok": false, "profile": {}, "error": "Apply the flight device selection before saving its profile."}
		var unassociated: Dictionary = Profile.upgrade_legacy(candidate)
		if unassociated.is_empty():
			return {"ok": false, "profile": {}, "error": "Invalid controller profile."}
		var saved := store.save_profile(unassociated)
		_profile_misses.clear()
		return saved
	if selected_id != id or not registry.device_for_id(id).get("connected", false):
		return {"ok": false, "profile": {}, "error": "The selected flight controller disconnected or changed before the profile was saved."}
	var prepared := validate_profile_for_session(candidate)
	if not bool(prepared.get("ok", false)):
		return prepared
	var profile: Dictionary = prepared.profile
	_associate_profile_with_device(profile, id, registry.device_for_id(id))
	return _save_and_apply(profile, id)


## Saves the setup profile and commits both explicit device roles as one operation.
## The caller passes -1 for a deliberate keyboard choice in either role.
func save_settings_from_setup(candidate: Dictionary, flight_device_id: int, ui_device_id: int) -> Dictionary:
	var old_flight_id: int = registry.selected_device_id("flight")
	var old_ui_id: int = registry.selected_device_id("ui")
	var flight_id := int(flight_device_id)
	var ui_id := int(ui_device_id)
	if flight_id < -1 or ui_id < -1:
		return {"ok": false, "profile": {}, "error": "Choose a connected device or keyboard for each role."}
	for id: int in [flight_id, ui_id]:
		if id >= 0 and not bool(registry.device_for_id(id).get("connected", false)):
			return {"ok": false, "profile": {}, "error": "A selected controller disconnected before settings were saved."}

	var prepared := validate_profile_for_session(candidate)
	if not bool(prepared.get("ok", false)):
		return prepared
	var profile: Dictionary = prepared.profile
	if flight_id >= 0:
		_associate_profile_with_device(profile, flight_id, registry.device_for_id(flight_id))

	# Read and validate storage before any role or runtime state can change. This
	# preserves corrupt-store errors and also supplies the rollback snapshot.
	var previous_store: Dictionary = store.load_all()
	if not bool(previous_store.get("ok", false)):
		return {"ok": false, "profile": {}, "error": "Existing controller profile storage is unreadable: " + "; ".join(previous_store.get("errors", []))}
	if not _ui_selection_eligible_for_setup(ui_id, flight_id, profile, previous_store):
		return {"ok": false, "profile": {}, "error": "Choose a connected gamepad or a radio with verified menu controls."}

	var previous_runtime_profile: Dictionary = profile_for_device(old_flight_id) if old_flight_id >= 0 else {}
	var previous_cache: Dictionary = _profiles.duplicate(true)
	var previous_selection_result := _last_flight_selection_result
	var flight_was_lost := is_instance_valid(session) and bool(session.get("_controller_lost"))
	var needs_flight_apply := flight_id != old_flight_id or (flight_id >= 0 and profile != previous_runtime_profile) or flight_was_lost
	var notify_flight := flight_id != old_flight_id or (flight_id >= 0 and profile != previous_runtime_profile) or flight_was_lost

	var preference := _ui_preference_for_setup(ui_id, flight_id, profile)
	var saved: Dictionary = store.save_profile_with_ui_preference(profile, preference) \
		if store.has_method("save_profile_with_ui_preference") else store.save_profile(profile)
	if not bool(saved.get("ok", false)):
		return saved
	_profile_misses.clear()

	_settings_save_transaction = true
	_last_flight_selection_result = true
	if flight_id >= 0:
		var cache_key := "%d:%d" % [flight_id, registry.connection_generation(flight_id)]
		_profiles[cache_key] = saved.profile.duplicate(true)
	var ui_selected: bool = registry.select_device("ui", ui_id)
	var had_session := is_instance_valid(session)
	var flight_selected: bool = registry.select_device("flight", flight_id)
	var attempted_flight_apply := flight_selected and flight_id != old_flight_id and had_session
	if flight_selected and flight_id == old_flight_id and needs_flight_apply and had_session:
		attempted_flight_apply = true
		_last_flight_selection_result = bool(session.apply_controller_selection(flight_id, registry.device_for_id(flight_id), saved.profile, false))
	var committed := ui_selected and flight_selected and _last_flight_selection_result
	if committed:
		_manual_roles = {"flight": true, "ui": true}
		_settings_save_transaction = false
		if ui_id != old_ui_id or (ui_id == flight_id and notify_flight):
			ui_selection_changed.emit(ui_id)
		if notify_flight:
			flight_selection_changed.emit()
		return saved

	# Restore durable data and runtime lookup state before reapplying the previous
	# route. Selection callbacks remain muted until the whole rollback is complete.
	var restored_store: Dictionary = store.restore_snapshot(previous_store)
	_profiles = previous_cache.duplicate(true)
	_profile_misses.clear()
	var current_flight_id: int = registry.selected_device_id("flight")
	var ui_role_restored: bool = registry.select_device("ui", old_ui_id)
	var flight_role_restored: bool = registry.select_device("flight", old_flight_id)
	var roles_restored := ui_role_restored and flight_role_restored \
		and registry.selected_device_id("ui") == old_ui_id \
		and registry.selected_device_id("flight") == old_flight_id
	var restored_runtime := true
	if attempted_flight_apply:
		if not flight_role_restored or not is_instance_valid(session):
			restored_runtime = false
		elif current_flight_id == old_flight_id:
			restored_runtime = bool(session.apply_controller_selection(old_flight_id, registry.device_for_id(old_flight_id), previous_runtime_profile, false))
		else:
			restored_runtime = _last_flight_selection_result
	_settings_save_transaction = false
	_last_flight_selection_result = previous_selection_result
	var error := "The active session rejected this controller profile."
	if bool(restored_store.get("ok", false)):
		error += " Previous stored profiles were restored."
	else:
		error += " Previous stored profiles could not be restored: " + str(restored_store.get("error", "unknown storage error"))
	if roles_restored:
		error += " Previous device selections were restored."
	else:
		error += " Previous device selections could not be fully restored."
	if not attempted_flight_apply:
		error += " The runtime route was unchanged."
	elif restored_runtime:
		error += " The previous runtime route was restored."
	else:
		error += " The previous runtime route could not be restored."
	return {"ok": false, "profile": {}, "error": error}


func _ui_selection_eligible_for_setup(ui_id: int, flight_id: int, candidate: Dictionary, previous_store: Dictionary) -> bool:
	if ui_id < 0:
		return true
	var info: Dictionary = registry.device_for_id(ui_id)
	if not bool(info.get("connected", false)):
		return false
	var radio_hint: bool = JetiRadio.has_jeti_identity_claim(info) or info.get("kind", "") == "radio" \
		or RcInput.looks_like_radio(str(info.get("name", "")))
	var explicit_radio: bool = ui_id == flight_id and candidate.get("kind", "") == "radio"
	var saved_ui: Dictionary = store.match_profile(info, registry.get_devices())
	explicit_radio = explicit_radio or saved_ui.get("kind", "") == "radio"
	if not radio_hint and not explicit_radio and bool(info.get("known", false)) and info.get("kind", "") == "gamepad":
		return true
	var matching_profiles: Array[Dictionary] = []
	var candidate_was_saved_for_ui := false
	for saved_profile in previous_store.get("profiles", []):
		if str(saved_profile.get("profile_id", "")) == str(candidate.get("profile_id", "")):
			candidate_was_saved_for_ui = store._association_matches(info, saved_profile.get("association", {}))
			continue
		if store._association_matches(info, saved_profile.get("association", {})):
			matching_profiles.append(saved_profile)
	var candidate_can_declare_ui := ui_id == flight_id or candidate_was_saved_for_ui
	if candidate_can_declare_ui and store._association_matches(info, candidate.get("association", {})):
		matching_profiles.append(candidate)
	if matching_profiles.size() != 1:
		return false
	var saved_profile: Dictionary = matching_profiles[0]
	var eligible_kind: bool = RadioMenu.is_verified(saved_profile) or (not radio_hint and saved_profile.get("kind", "") == "gamepad")
	if not eligible_kind or not bool(saved_profile.get("configured", false)) or not Profile.validate(saved_profile).ok:
		return false
	# A new unknown gamepad is trusted only when this save declares the flight
	# target itself. Existing separately saved menu pads remain eligible as usual.
	if ui_id == flight_id and saved_profile.get("profile_id", "") != candidate.get("profile_id", ""):
		return false
	return _association_is_unambiguous(saved_profile.get("association", {}))


func _ui_preference_for_setup(ui_id: int, flight_id: int, candidate: Dictionary) -> Dictionary:
	if ui_id < 0: return {"mode": "keyboard"}
	if ui_id == flight_id: return {"mode": "profile", "profile_id": str(candidate.profile_id)}
	var matched: Dictionary = store.match_profile(registry.device_for_id(ui_id), registry.get_devices())
	if not matched.is_empty(): return {"mode": "profile", "profile_id": str(matched.profile_id)}
	return {} # An unsaved mapped gamepad retains the existing automatic-startup policy.


func _association_is_unambiguous(association: Dictionary) -> bool:
	var matches := 0
	for device in registry.get_devices():
		if bool(device.get("connected", false)) and store._association_matches(device, association):
			matches += 1
	return matches == 1


func _save_and_apply(profile: Dictionary, id: int) -> Dictionary:
	# Capture runtime selection before the write: afterwards profile_for_device()
	# may find the candidate we just associated with this previously unknown device.
	var previous_runtime_profile: Dictionary = profile_for_device(id)
	var previous_store: Dictionary = store.load_all()
	if not bool(previous_store.get("ok", false)):
		return {"ok": false, "profile": {}, "error": "Existing controller profile storage is unreadable: " + "; ".join(previous_store.get("errors", []))}
	var saved: Dictionary = store.save_profile(profile)
	if not bool(saved.get("ok", false)):
		return saved
	if apply_profile(saved.profile, id, previous_runtime_profile, true):
		return saved
	var restored: Dictionary = store.restore_snapshot(previous_store)
	_profile_misses.clear()
	if bool(restored.get("ok", false)) and registry.selected_device_id("flight") == id:
		flight_selection_changed.emit()
	var error := "The active session rejected this controller profile."
	if bool(restored.get("ok", false)):
		error += " Previous stored profiles were restored."
	else:
		error += " Previous stored profiles could not be restored: " + str(restored.get("error", "unknown storage error"))
	return {"ok": false, "profile": {}, "error": error}


func _associate_profile_with_device(profile: Dictionary, id: int, info: Dictionary) -> void:
	profile["association"] = {
		"legacy_device_key": RcInput.key_for(id, info),
		"guid": str(info.get("guid", "")),
		"vendor_id": int(info.get("vendor_id", 0)),
		"product_id": int(info.get("product_id", 0)),
	}
	var serial_number: Variant = info.get("serial_number", "")
	if typeof(serial_number) == TYPE_STRING and not serial_number.is_empty():
		profile.association["serial_number"] = serial_number
