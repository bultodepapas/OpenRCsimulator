extends Node
## Interactive-only bridge. Enumeration never transfers ownership; profile writes are explicit in Controls.
const Registry := preload("res://input/controller_registry.gd")
const Store := preload("res://input/controller_profile_store.gd")
const Profile := preload("res://input/controller_profile.gd")
const RcInput := preload("res://input/rc_input.gd")
const Calibration := preload("res://input/rc_calibration.gd")

signal flight_selection_changed
signal ui_selection_changed(id: int)
signal continuity_lost

var registry = Registry.new()
var store = Store.new()
var enumerate_devices: Callable = observed_devices
var session: Node
var _refreshing := false
var _profiles: Dictionary = {} # connection generation -> explicit selection, never a persistent device ID
var _elapsed := 0.0
var _last_process_ms := 0


func _init() -> void:
	registry.selection_changed.connect(_selection_changed)


func _ready() -> void:
	Input.joy_connection_changed.connect(_connection_changed)
	refresh()
	_last_process_ms = Time.get_ticks_msec()


func _process(delta: float) -> void:
	var now := Time.get_ticks_msec()
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
	_refreshing = true
	registry.update_devices(enumerate_devices.call())
	_refreshing = false


func _connection_changed(id: int, connected: bool) -> void:
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
		for field in ["vendor_id", "product_id"]:
			info[field] = int(info.get(field, 0))
		if RcInput.looks_like_radio(str(info.name)):
			info["kind"] = "radio"
		devices.append(info)
	return devices


func attach_session(target: Node, initial_start := true) -> void:
	session = target
	if not is_instance_valid(session): return
	session.external_controller_selection = true
	session.persist_controller_profile = save_calibration
	session.persist_full_controller_profile = save_profile_and_apply
	var id: int = registry.selected_device_id("flight")
	# A fresh keyboard flight retains its declared launch state.
	if id >= 0:
		session.apply_controller_selection(id, registry.device_for_id(id), profile_for_device(id), initial_start)


func select_devices(flight_id: int, ui_id: int) -> bool:
	# Check both before making either selection; UI navigation is never assigned to an RC transmitter.
	for id: int in [flight_id, ui_id]:
		if id >= 0 and not registry.device_for_id(id).get("connected", false): return false
	if ui_id >= 0 and not is_ui_gamepad(ui_id): return false
	var previous: int = registry.selected_device_id("flight")
	registry.select_device("ui", ui_id)
	registry.select_device("flight", flight_id)
	# Explicit re-apply also acknowledges lost continuity and the deliberate keyboard fallback.
	if previous == flight_id and is_instance_valid(session) and session._controller_lost:
		_selection_changed("flight", flight_id)
	return true


func is_ui_gamepad(id: int) -> bool:
	var info: Dictionary = registry.device_for_id(id)
	if not bool(info.get("connected", false)) or info.get("kind", "") == "radio" or RcInput.looks_like_radio(str(info.get("name", ""))):
		return false
	if bool(info.get("known", false)) and info.get("kind", "") == "gamepad": return true
	# Unknown hardware needs a saved, unambiguous user declaration before it may drive menus.
	var saved: Dictionary = store.match_profile(info, registry.get_devices())
	return saved.get("kind", "") == "gamepad" and bool(saved.get("configured", false)) and Profile.validate(saved).ok


func profile_for_device(id: int) -> Dictionary:
	var info: Dictionary = registry.device_for_id(id)
	if not info.get("connected", false): return {}
	var key := "%d:%d" % [id, registry.connection_generation(id)]
	if _profiles.has(key): return _profiles[key].duplicate(true)
	var profile: Dictionary = store.match_profile(info, registry.get_devices())
	if profile.is_empty() and not store.profiles_for_device(info).is_empty(): return {}
	if profile.is_empty():
		var legacy: Dictionary = Calibration.load_profile(store.legacy_path, RcInput.key_for(id, info))
		if not legacy.is_empty():
			if info.get("known", false) and info.get("kind", "") == "gamepad": return {}
			profile = Profile.upgrade_legacy(legacy, {"legacy_device_key": RcInput.key_for(id, info)})
	if profile.is_empty() and info.get("known", false) and info.get("kind", "") == "gamepad":
		profile = Profile.defaults()
	# Known RC names retain their historical mapping and low-throttle gate. Unknown sticks stay unconfigured.
	if profile.is_empty() and info.get("kind", "") == "radio":
		profile = Profile.defaults("radio", "radio_custom")
	if not profile.is_empty(): _profiles[key] = profile.duplicate(true)
	return profile


func apply_profile(profile: Dictionary, device_id := -1) -> bool:
	var id: int = registry.selected_device_id("flight") if device_id < 0 else device_id
	if id < 0 or not registry.device_for_id(id).get("connected", false) or not Profile.validate(profile).ok: return false
	_profiles["%d:%d" % [id, registry.connection_generation(id)]] = profile.duplicate(true)
	if registry.selected_device_id("flight") == id: _selection_changed("flight", id)
	return true


func _selection_changed(role: String, id: int) -> void:
	if role == "ui":
		ui_selection_changed.emit(id)
		return
	if is_instance_valid(session):
		if _refreshing:
			session.controller_disconnected()
			continuity_lost.emit()
		else:
			session.apply_controller_selection(id, registry.device_for_id(id), profile_for_device(id), false)
	flight_selection_changed.emit()


func save_calibration(legacy_profile: Dictionary) -> Dictionary:
	var id: int = registry.selected_device_id("flight")
	var previous: Dictionary = profile_for_device(id)
	if id < 0 or previous.get("kind", "") != "radio":
		return {"ok": false, "error": "Select a radio profile before calibration."}
	var profile: Dictionary = Profile.upgrade_legacy(legacy_profile)
	if profile.is_empty(): return {"ok": false, "error": "Invalid calibration."}
	for key in ["profile_id", "name", "actions", "presentation"]:
		profile[key] = previous[key]
	return save_profile_and_apply(profile)


func save_profile_and_apply(candidate: Dictionary) -> Dictionary:
	var id: int = registry.selected_device_id("flight")
	var previous: Dictionary = profile_for_device(id)
	var profile: Dictionary = Profile.upgrade_legacy(candidate)
	if id < 0 or previous.is_empty() or profile.is_empty() or profile.kind != previous.kind:
		return {"ok": false, "error": "Invalid controller profile or changed device role."}
	var info: Dictionary = registry.device_for_id(id)
	profile.association = {"legacy_device_key": RcInput.key_for(id, info), "guid": info.guid,
		"vendor_id": info.vendor_id, "product_id": info.product_id}
	if not str(info.get("serial_number", "")).is_empty(): profile.association["serial_number"] = info.serial_number
	var saved: Dictionary = store.save_profile(profile)
	if saved.ok: apply_profile(saved.profile, id)
	return saved
