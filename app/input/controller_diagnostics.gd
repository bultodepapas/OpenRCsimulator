extends RefCounted
## Shareable, allowlisted controller evidence. This does not measure compatibility or latency.

const BuildInfo := preload("res://app_state/build_info.gd")
const ReportData := preload("res://input/input_report_data.gd")
const Profile := preload("res://input/controller_profile.gd")
const Actions := preload("res://input/controller_actions.gd")
const RadioMenu := preload("res://input/radio_menu.gd")
const FORMAT := "openrc-controller-diagnostics v1"
const LOCK_SUFFIX := ".openrc-controller-diagnostics-lock"
const CHANNELS := ["roll", "pitch", "yaw", "throttle"]
const ACTIVITY_CAPABILITIES := ["gear", "smoke", "flaps", "rates", "helicopter"]
const TRANSPORTS := ["usb", "bluetooth", "wireless", "wired"]
const LAYOUTS := ["classic", "advanced", "gamepad", "joystick", "unknown"]


## `observations` is one InputReportData.snapshot() device, optionally extended
## with activity_capabilities from the current flight and optional current_samples
## {raw_axes: Array or PackedFloat64Array, observed: Array[bool] or PackedByteArray},
## each exactly ten entries. The caller marks only events from this connection.
## Missing values remain
## unknown; a profile or an engine mapping does not prove a physical capability.
## Arbitrary device/profile strings and identifiers are omitted unless requested.
static func build(info: Dictionary, profile: Dictionary, observations: Dictionary = {}, include_identifiers: bool = false) -> Dictionary:
	var build_info: Dictionary = BuildInfo.current()
	var engine: Dictionary = Engine.get_version_info()
	var capability_context := _activity_context(observations)
	var valid_profile := not profile.is_empty() and _safe_to_validate(profile) and bool(Profile.validate(profile).get("ok", false))
	var result := {
		"format": FORMAT,
		"build": _build_identity(build_info),
		"engine": {"version": str(engine.get("string", "")), "hash": str(engine.get("hash", ""))},
		"os": {"name": OS.get_name(), "version": OS.get_version()},
		"privacy": {"identifiers_included": include_identifiers},
		"device": _device(info, include_identifiers),
		"profile": _profile(profile, valid_profile, capability_context, include_identifiers),
		"observations": _observations(observations, profile, valid_profile),
	}
	return result


## BuildInfo uses StringName keys in memory; emit ordinary JSON keys while
## retaining every reported source/export identity field and parsed component.
static func _build_identity(info: Dictionary) -> Dictionary:
	var parsed: Dictionary = info.get("parsed", {})
	var result := {}
	for key: String in ["source", "describe", "commit", "dirty", "commit_date", "version", "label", "godot"]:
		result[key] = info.get(key)
	result["parsed"] = {}
	for key: String in ["tag", "base", "prerelease", "after", "sha", "dirty", "semver"]:
		result.parsed[key] = parsed.get(key)
	return result


static func _device(info: Dictionary, include_identifiers: bool) -> Dictionary:
	var result := {
		"connected": _bool_or_null(info.get("connected")),
		"kind": _enum_or_null(info.get("kind"), ["gamepad", "radio", "joystick"]),
		"known_mapping": _bool_or_null(info.get("known")),
		"vendor_id": ReportData.usb_id(info.get("vendor_id")),
		"product_id": ReportData.usb_id(info.get("product_id")),
		"backend": _enum_or_null(info.get("backend"), ["sdl", "sdl3", "directinput", "xinput"]),
		"transport": _reported_enum(info, "transport", TRANSPORTS),
		"layout": _reported_enum(info, "layout", LAYOUTS),
		"firmware": {"status": "not_exposed" if not info.has("firmware") or info.get("firmware") == null else "redacted", "value": null},
		"physical_axis_count": {"status": "not_exposed", "value": null},
		"physical_button_count": {"status": "not_exposed", "value": null},
		"vibration_supported": _bool_or_null(info.get("vibration_supported")),
	}
	if include_identifiers:
		result["identifiers"] = {
			"name": _identifier(info.get("name")),
			"raw_name": _identifier(info.get("raw_name")),
			"guid": _identifier(info.get("guid")),
			"serial_number": _identifier(info.get("serial_number")),
			"transport_raw": _identifier(info.get("transport")),
			"layout_raw": _identifier(info.get("layout")),
			"firmware": _identifier(info.get("firmware")),
		}
	return result


static func _reported_enum(info: Dictionary, key: String, allowed: Array) -> Dictionary:
	var raw: Variant = info.get(key)
	var value: Variant = _enum_or_null(raw, allowed)
	var missing: bool = not info.has(key) or raw == null or (typeof(raw) == TYPE_STRING and raw.is_empty())
	return {"status": "not_exposed" if missing else ("reported" if value != null else "unrecognized"), "value": value}


static func _profile(profile: Dictionary, valid: bool, capabilities: Dictionary, include_identifiers: bool) -> Dictionary:
	var result := {
		"status": "not_provided" if profile.is_empty() else ("valid" if valid else ("unconfigured" if profile.get("configured") == false else "invalid")),
		"schema_version": _nonnegative_int(profile.get("schema_version")),
		"preset_revision": _nonnegative_int(profile.get("preset_revision")),
		"kind": _enum_or_null(profile.get("kind"), ["gamepad", "radio", "joystick"]),
		"preset": _enum_or_null(profile.get("preset"), ["mode1", "mode2", "trigger_absolute", "radio_custom", "jeti_mode2", "unconfigured"]),
		"configured": _bool_or_null(profile.get("configured")),
		"throttle_mode": _enum_or_null(profile.get("throttle_mode"), ["stick_rate", "trigger_absolute", "radio_absolute"]),
		"throttle_rate": _finite_number(profile.get("throttle_rate")),
		"idle_threshold": _finite_number(profile.get("idle_threshold")),
		"neutral_duration_ms": _nonnegative_int(profile.get("neutral_duration_ms")),
		"require_release": _bool_or_null(profile.get("require_release")),
		"channels": {},
		"auxiliary": {},
		"radio_menu": _radio_menu(profile),
		"effective_actions": {"status": "not_available", "activity_capabilities": capabilities, "bindings": {}},
	}
	for name: String in CHANNELS:
		result.channels[name] = _channel(profile.get(name))
	if valid:
		var auxiliary: Variant = profile.get("aux", {})
		if auxiliary is Dictionary:
			for name: String in Actions.AUX_CHANNEL_IDS:
				if auxiliary.has(name):
					result.auxiliary[name] = _aux_binding(auxiliary[name], include_identifiers)
		var effective := Actions.effective_bindings(profile, capabilities.values)
		for definition: Dictionary in Actions.ACTIONS:
			var name: String = definition.id
			var binding: Variant = effective.get(name)
			if Actions.valid_binding(binding):
				result.effective_actions.bindings[name] = _action_binding(binding)
		result.effective_actions.status = "resolved" if capabilities.status == "provided" else "without_activity_capabilities"
	if include_identifiers:
		var association: Variant = profile.get("association", {})
		if not association is Dictionary:
			association = {}
		result["identifiers"] = {
			"profile_id": _identifier(profile.get("profile_id")), "profile_name": _identifier(profile.get("name")),
			"association_guid": _identifier(association.get("guid")),
			"association_serial_number": _identifier(association.get("serial_number")),
			"legacy_device_key": _identifier(association.get("legacy_device_key"), 1024),
		}
	return result


## Verification is a stored mapping/action match, not proof of current connection,
## active menu ownership, fresh center evidence, or a completed physical journey.
## Do not expose either fingerprint: it contains device association identifiers.
static func _radio_menu(profile: Dictionary) -> Dictionary:
	var nav: Variant = profile.get("ui_navigation")
	var result := {"status": "disabled", "horizontal": null, "vertical": null}
	if nav == null: return result
	if not nav is Dictionary or typeof(nav.get("enabled")) != TYPE_BOOL:
		result.status = "stale"
		return result
	if not nav.enabled: return result
	result.status = "verified" if _safe_to_validate(profile) and RadioMenu.is_verified(profile) else "stale"
	result.horizontal = _enum_or_null(nav.get("horizontal"), ["roll", "pitch", "yaw"])
	result.vertical = _enum_or_null(nav.get("vertical"), ["roll", "pitch", "yaw"])
	return result


## Menu fingerprinting expects a dictionary association; reject malformed data
## before calling the shared validator. No private tree content is published.
static func _safe_to_validate(profile: Dictionary) -> bool:
	if not _json_value(profile, 0): return false
	var nav: Variant = profile.get("ui_navigation")
	if nav is Dictionary and nav.get("enabled") == true and typeof(profile.get("association", {})) != TYPE_DICTIONARY:
		return false
	return true


static func _activity_context(observations: Dictionary) -> Dictionary:
	var supplied: Variant = observations.get("activity_capabilities")
	var values := {}
	if supplied is Dictionary:
		for key: String in ACTIVITY_CAPABILITIES:
			if typeof(supplied.get(key)) == TYPE_BOOL:
				values[key] = supplied[key]
	return {"status": "provided" if supplied is Dictionary else "not_provided", "values": values}


static func _channel(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {"status": "not_provided"}
	return {
		"status": "reported", "axis": _nonnegative_int(value.get("axis")),
		"invert": _bool_or_null(value.get("invert")),
		"range_kind": _enum_or_null(value.get("range_kind"), ["centered", "absolute"]),
		"min": _finite_number(value.get("min")), "center": _finite_number(value.get("center")),
		"max": _finite_number(value.get("max")), "deadzone": _finite_number(value.get("deadzone")),
		"expo": _finite_number(value.get("expo")),
	}


## Never copy the binding dictionary: it may contain arbitrary extensions or labels.
static func _action_binding(binding: Dictionary) -> Dictionary:
	var result := {"type": binding.type}
	match binding.type:
		"key":
			for field: String in ["keycode", "physical_keycode"]:
				if binding.has(field): result[field] = _nonnegative_int(binding[field])
			for field: String in ["ctrl", "alt", "shift", "meta"]:
				if binding.has(field): result[field] = _bool_or_null(binding[field])
		"button":
			result["button"] = _nonnegative_int(binding.get("button"))
		"axis":
			result["axis"] = _nonnegative_int(binding.get("axis"))
			result["sign"] = int(binding.get("sign", binding.get("direction", 0)))
			result["threshold"] = _finite_number(binding.get("threshold", 0.65))
			for field: String in ["off", "on"]:
				if binding.has(field): result[field] = _finite_number(binding[field])
			if binding.has("invert"): result["invert"] = _bool_or_null(binding.invert)
	return result


static func _aux_binding(binding: Variant, include_identifiers: bool) -> Dictionary:
	if not binding is Dictionary:
		return {"type": null}
	var kind: Variant = _enum_or_null(binding.get("type"), ["axis", "button", "switch"])
	var result := {"type": kind}
	match kind:
		"axis":
			result["axis"] = _nonnegative_int(binding.get("axis"))
			result["off"] = _finite_number(binding.get("off"))
			result["on"] = _finite_number(binding.get("on"))
			result["invert"] = _bool_or_null(binding.get("invert"))
		"button":
			result["button"] = _nonnegative_int(binding.get("button"))
			result["mode"] = _enum_or_null(binding.get("mode"), ["level", "toggle_edge"])
		"switch":
			var buttons: Array = []
			if binding.get("buttons") is Array:
				for index in mini(binding.buttons.size(), 3): buttons.append(_nonnegative_int(binding.buttons[index]))
			result["buttons"] = buttons
			result["invert"] = _bool_or_null(binding.get("invert"))
			if include_identifiers: result["label"] = _identifier(binding.get("label"))
	return result


static func _observations(data: Dictionary, profile: Dictionary, valid_profile: bool) -> Dictionary:
	var axes: Array[Dictionary] = []
	var seen_axes := {}
	for axis in ReportData.AXES:
		axes.append({"axis": axis, "status": "unobserved", "events": 0, "min": null, "max": null})
	var raw_axes: Variant = data.get("axes")
	if raw_axes is Array:
		for position in mini(raw_axes.size(), ReportData.AXES):
			var row: Variant = raw_axes[position]
			if not row is Dictionary or typeof(row.get("axis")) != TYPE_INT or row.axis < 0 or row.axis >= ReportData.AXES:
				continue
			if seen_axes.has(row.axis):
				axes[row.axis] = {"axis": row.axis, "status": "invalid", "events": null, "min": null, "max": null}
				continue
			seen_axes[row.axis] = true
			var count: Variant = _nonnegative_int(row.get("events"))
			if count == null:
				axes[row.axis] = {"axis": row.axis, "status": "invalid", "events": null, "min": null, "max": null}
				continue
			if count == 0: continue
			var lo: Variant = _unit_number(row.get("min"))
			var hi: Variant = _unit_number(row.get("max"))
			if lo == null or hi == null or lo > hi:
				axes[row.axis] = {"axis": row.axis, "status": "invalid", "events": count, "min": null, "max": null}
				continue
			axes[row.axis] = {"axis": row.axis, "status": "observed", "events": count, "min": lo, "max": hi}
	var buttons: Array[Dictionary] = []
	var raw_buttons: Variant = data.get("buttons")
	if raw_buttons is Array:
		for index in mini(raw_buttons.size(), ReportData.MAX_TRACKED_BUTTONS):
			var row: Variant = raw_buttons[index]
			if not row is Dictionary: continue
			var button: Variant = _nonnegative_int(row.get("button"))
			var events: Variant = _nonnegative_int(row.get("events"))
			if button == null or events == null or events == 0: continue
			buttons.append({"button": button, "events": events, "press_events": _nonnegative_int(row.get("press_events")),
				"release_events": _nonnegative_int(row.get("release_events")), "pressed": _bool_or_null(row.get("pressed"))})
	buttons.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.button < b.button)
	return {
		"status": "provided" if raw_axes is Array or raw_buttons is Array else ("invalid" if data.has("axes") or data.has("buttons") else "not_started"),
		"axes": axes,
		"buttons": buttons,
		"button_events": _nonnegative_int(data.get("button_events")),
		"untracked_button_events": _nonnegative_int(data.get("untracked_button_events")),
		"current_samples": _current_samples(data.get("current_samples"), profile, valid_profile),
		"semantics": "Godot mapped input events only. Unobserved controls are not evidence of absence or physical capability.",
	}


## The raw values are the most recent individual axis events provided by the
## caller, without an age or simultaneity claim. Never infer an unseen zero.
static func _current_samples(value: Variant, profile: Dictionary, valid_profile: bool) -> Dictionary:
	var axes: Array[Dictionary] = []
	var samples_provided := value != null
	var sample_dict := value is Dictionary
	var raw_values: Variant = value.get("raw_axes") if sample_dict else null
	var seen: Variant = value.get("observed") if sample_dict else null
	var shape_ok: bool = (raw_values is Array or raw_values is PackedFloat64Array or raw_values is PackedFloat32Array) \
		and (seen is Array or seen is PackedByteArray) and raw_values.size() == ReportData.AXES and seen.size() == ReportData.AXES
	for axis in ReportData.AXES:
		var state := "unobserved" if not samples_provided else "invalid"
		var raw: Variant = null
		if shape_ok:
			var mask_value: Variant = seen[axis]
			var valid_mask: bool = typeof(mask_value) == TYPE_BOOL or (seen is PackedByteArray and mask_value in [0, 1])
			if valid_mask and not bool(mask_value):
				state = "unobserved"
			elif valid_mask:
				raw = _unit_number(raw_values[axis])
				state = "observed" if raw != null else "invalid"
		axes.append({"axis": axis, "status": state, "raw": raw})
	var channels := {}
	for channel_name: String in CHANNELS:
		var channel: Variant = profile.get(channel_name)
		var axis: Variant = _nonnegative_int(channel.get("axis")) if channel is Dictionary else null
		var sample := {"axis": axis, "status": "not_available", "raw": null, "normalized": null}
		if axis != null and axis < ReportData.AXES:
			var axis_sample: Dictionary = axes[axis]
			sample.status = axis_sample.status
			if axis_sample.status == "observed":
				sample.raw = axis_sample.raw
				if valid_profile:
					sample.normalized = Profile.channel_value(float(axis_sample.raw), channel_name, profile)
				else:
					sample.status = "invalid_profile"
		if channel_name == "throttle" and profile.get("throttle_mode") == "stick_rate":
			sample["meaning"] = "rate_input_not_accumulated_throttle"
		channels[channel_name] = sample
	return {
		"status": "not_provided" if not samples_provided else ("provided" if shape_ok else "invalid"),
		"axes": axes, "channels": channels,
		"semantics": "Last observed values per axis, not necessarily simultaneous; age and current connection freshness are not established by this report.",
	}


static func _enum_or_null(value: Variant, allowed: Array) -> Variant:
	if typeof(value) != TYPE_STRING: return null
	var normalized: String = value.strip_edges().to_lower()
	if allowed.has(normalized): return normalized
	return null


static func _identifier(value: Variant, limit: int = 256) -> Variant:
	return value.substr(0, limit) if typeof(value) == TYPE_STRING and not value.is_empty() else null


static func _bool_or_null(value: Variant) -> Variant:
	return value if typeof(value) == TYPE_BOOL else null


static func _nonnegative_int(value: Variant) -> Variant:
	return value if typeof(value) == TYPE_INT and value >= 0 and value <= 2147483647 else null


static func _finite_number(value: Variant) -> Variant:
	return value if typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) else null


static func _unit_number(value: Variant) -> Variant:
	return value if typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) >= -1.0 and float(value) <= 1.0 else null


## Cooperating OpenRC writers reserve a same-directory lock and reject existing
## paths (including symlinks). Godot has no exclusive-create mode: an unrelated
## process can race the final open. The engine also exposes no fclose/fflush
## result or fsync. Readback detects ordinary write failures, not power loss.
static func write_new(path: String, report: Dictionary) -> Error:
	if path.strip_edges().is_empty() or report.get("format") != FORMAT or not _json_value(report, 0):
		return ERR_INVALID_PARAMETER
	var absolute := ProjectSettings.globalize_path(path).simplify_path()
	var parent := DirAccess.open(absolute.get_base_dir())
	if parent == null or absolute.get_file().is_empty(): return ERR_CANT_OPEN
	var lock := absolute + LOCK_SUFFIX
	var reserved := DirAccess.make_dir_absolute(lock)
	if reserved != OK: return reserved
	var result: Error = OK
	var name := absolute.get_file()
	if parent.file_exists(name) or parent.dir_exists(name) or parent.is_link(name):
		result = ERR_ALREADY_EXISTS
	else:
		var encoded := JSON.stringify(report, "\t") + "\n"
		var file := FileAccess.open(absolute, FileAccess.WRITE)
		if file == null:
			result = FileAccess.get_open_error()
		else:
			if not file.store_string(encoded): result = ERR_FILE_CANT_WRITE
			file.flush()
			if result == OK and file.get_error() != OK: result = file.get_error()
			file.close()
			if result == OK and file.get_error() != OK: result = file.get_error()
			if result == OK:
				var expected := encoded.to_utf8_buffer()
				var readback := FileAccess.open(absolute, FileAccess.READ)
				if readback == null:
					result = FileAccess.get_open_error()
				else:
					if readback.get_length() != expected.size() or readback.get_buffer(expected.size()) != expected:
						result = ERR_FILE_CORRUPT
					readback.close()
	var release := DirAccess.remove_absolute(lock)
	return release if result == OK and release != OK else result


static func _json_value(value: Variant, depth: int) -> bool:
	if depth > 16: return false
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT: return true
		TYPE_STRING: return value.length() <= 4096
		TYPE_FLOAT: return is_finite(value)
		TYPE_ARRAY:
			if value.size() > 4096: return false
			for item in value:
				if not _json_value(item, depth + 1): return false
			return true
		TYPE_DICTIONARY:
			if value.size() > 4096: return false
			for key in value:
				if typeof(key) != TYPE_STRING or not _json_value(value[key], depth + 1): return false
			return true
	return false
