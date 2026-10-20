## AE-11: qualify a selected frozen aircraft start against the selected environment.
class_name WorkshopStartQualification
extends RefCounted

const Session := preload("res://sim/flight_session.gd")
const AircraftData := preload("res://physics/aircraft_data.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const Weather := preload("res://physics/wind_config.gd")

const MAX_QUALIFICATION_USEC := 16_000_000
const RESULT_FORMAT := "openrc-aircraft-start-qualification-v1"
const START_CHOICES := [Session.START_AIRBORNE, Session.START_RUNWAY, Session.START_HALF_POWER]


## Runs the same selected start transaction FlightSession uses for a live flight.
## `ok` says the supplied frozen trial and settings were assessed; `available` says the
## requested start was committed without fallback. A physical refusal is not malformed input.
static func qualify(frozen_trial: Dictionary, normalized_field: Dictionary, weather_config: Dictionary,
		start_choice: String) -> Dictionary:
	var started_usec: int = Time.get_ticks_usec()
	var checked_trial: Dictionary = _validate_frozen_trial(frozen_trial)
	if not checked_trial.get("ok", false):
		return _failure(str(checked_trial.get("reason", "frozen trial identity is invalid")), start_choice,
			str(normalized_field.get("id", "")), started_usec, {"trial_errors": checked_trial.get("errors", [])})
	if not START_CHOICES.has(start_choice):
		return _failure("unsupported start choice '%s'" % start_choice, start_choice,
			str(normalized_field.get("id", "")), started_usec)
	if not _normalized_field_shape_valid(normalized_field):
		return _failure("selected field is not a normalized field definition", start_choice,
			str(normalized_field.get("id", "")), started_usec)
	var checked_weather: Dictionary = Weather.validate(weather_config)
	if not checked_weather.get("ok", false):
		return _failure("weather configuration is invalid: %s" % "; ".join(checked_weather.get("errors", [])),
			start_choice, str(normalized_field.get("id", "")), started_usec)

	var trial_data: Dictionary = frozen_trial.data.duplicate(true)
	var aircraft_id: String = str(checked_trial.aircraft_id)
	var field_id: String = str(normalized_field.get("id", ""))
	var session = Session.new()
	session.physics_enabled = false
	session.input_enabled = false
	session.crash_auto_restart = false
	session.start_choice = start_choice
	session.setup("workshop://" + aircraft_id, aircraft_id, trial_data)
	if not session.aircraft.get("ok", false):
		var load_reason: String = str(session.aircraft.get("errors", ["frozen aircraft could not be prepared"])[0])
		session.free()
		return _failure(load_reason, start_choice, field_id, started_usec,
			{"aircraft_id": aircraft_id, "model_sha256": checked_trial.model_sha256})
	if not session.set_field(normalized_field):
		var field_reason: String = str(session.surface_error)
		session.free()
		return _failure("selected field could not be installed: " + field_reason, start_choice,
			field_id, started_usec, {"aircraft_id": aircraft_id})
	if not session.setup_weather(checked_weather.config):
		var weather_reason: String = str(session.weather_error)
		session.free()
		return _failure("weather could not be installed: " + weather_reason, start_choice,
			field_id, started_usec, {"aircraft_id": aircraft_id})
	var scene_tree: SceneTree = Engine.get_main_loop() as SceneTree
	if scene_tree == null or scene_tree.root == null:
		session.free()
		return _failure("aircraft start qualification requires an active SceneTree", start_choice,
			field_id, started_usec, {"aircraft_id": aircraft_id})
	session.external_controller_selection = true
	scene_tree.root.add_child(session)
	session.start_choice = start_choice
	var original_field: Dictionary = normalized_field.duplicate(true)
	session.reset()
	var trace: Dictionary = session.trace_meta() if session.is_flyable() and str(session.start_error).is_empty() \
		else session._launch_metadata.duplicate(true)
	var outcome: Dictionary = session.runway_start_outcome.duplicate(true)
	var reason: String = str(session.start_error)
	var available: bool = _committed_requested_start(session, trace, outcome, start_choice, field_id)
	if not available and reason.is_empty():
		reason = "FlightSession did not commit the requested %s start." % start_choice
	var elapsed_usec: int = Time.get_ticks_usec() - started_usec
	var diagnostics: Dictionary = {
		"format": RESULT_FORMAT,
		"aircraft_id": aircraft_id,
		"model_sha256": checked_trial.model_sha256,
		"resolved_sha256": checked_trial.resolved_sha256,
		"start_choice": start_choice,
		"launch_choice": str(trace.get("launch_choice", "unknown")),
		"launch_kind": str(trace.get("launch_kind", "unknown")),
		"launch_field_id": str(trace.get("launch_field_id", "")),
		"runway_status": str(outcome.get("status", "not_attempted")),
		"runway_iterations": int(outcome.get("iterations", 0)),
		"runway_residual": float(outcome.get("residual", NAN)),
		"runway_scaled_residual": float(outcome.get("scaled_residual", NAN)),
		"runway_diagnostics": outcome.get("diagnostics", {}),
		"gear_contact_count": session.aircraft.get("model", {}).get("landing_gear", {}).get("contacts", []).size(),
		"stiction_anchor_count": session.anchor_count(),
		"wheel_count": session.wheel_count(),
		"tick": int(session.sim.tick) if session.sim != null else -1,
		"field_unchanged": normalized_field == original_field,
		"runtime_budget_usec": MAX_QUALIFICATION_USEC,
	}
	session.free()
	if elapsed_usec > MAX_QUALIFICATION_USEC:
		available = false
		reason = "start qualification exceeded the 16-second assessment budget"
		diagnostics.timed_out = true
	else:
		diagnostics.timed_out = false
	return {
		"ok": true,
		"available": available,
		"reason": reason,
		"start_choice": start_choice,
		"field_id": field_id,
		"diagnostics": diagnostics,
		"duration_ms": float(elapsed_usec) / 1000.0,
	}


static func _validate_frozen_trial(frozen_trial: Dictionary) -> Dictionary:
	if typeof(frozen_trial) != TYPE_DICTIONARY or not frozen_trial.get("ok", false):
		return _invalid_trial("frozen trial is not an accepted Trial.freeze result")
	var identity: Variant = frozen_trial.get("identity", null)
	var data: Variant = frozen_trial.get("data", null)
	var bytes: Variant = frozen_trial.get("raw_bytes", null)
	if typeof(identity) != TYPE_DICTIONARY or typeof(data) != TYPE_DICTIONARY \
			or typeof(bytes) != TYPE_PACKED_BYTE_ARRAY or bytes.is_empty():
		return _invalid_trial("frozen trial is missing identity, data, or exact source bytes")
	if identity.get("format", "") != "openrc-aircraft-trial v1" or not data.get("ok", false) \
			or typeof(data.get("model", null)) != TYPE_DICTIONARY:
		return _invalid_trial("frozen trial has an unsupported identity or invalid compiled model")
	var resolved_sha: String = _sha(bytes)
	if identity.get("resolved_sha256", "") != resolved_sha:
		return _invalid_trial("frozen trial resolved-source hash does not match its source bytes")
	var input_identity: Variant = data.get("input_identity", null)
	if typeof(input_identity) != TYPE_DICTIONARY or input_identity.get("format", "") != AircraftData.FORMAT \
			or input_identity.get("sha256", "") != resolved_sha:
		return _invalid_trial("compiled aircraft input identity does not match the frozen source bytes")
	var model: Dictionary = data.model
	var aircraft_id: String = str(model.get("id", ""))
	if aircraft_id.is_empty() or aircraft_id != str(identity.get("trial_id", "")) \
			or not aircraft_id.begins_with("workshop-"):
		return _invalid_trial("compiled model ID does not match the frozen trial identity")
	var parser := JSON.new()
	var raw_bytes: PackedByteArray = bytes
	if raw_bytes.get_string_from_utf8().to_utf8_buffer() != raw_bytes \
			or parser.parse(raw_bytes.get_string_from_utf8()) != OK or typeof(parser.data) != TYPE_DICTIONARY \
			or str(parser.data.get("id", "")) != aircraft_id:
		return _invalid_trial("frozen source bytes do not contain the compiled model ID")
	var model_sha: String = _sha(var_to_bytes(model))
	if identity.get("resolved_model_sha256", "") != model_sha:
		return _invalid_trial("frozen model hash does not match the compiled model")
	return {"ok": true, "aircraft_id": aircraft_id, "resolved_sha256": resolved_sha,
		"model_sha256": model_sha, "errors": PackedStringArray()}


static func _normalized_field_shape_valid(field: Dictionary) -> bool:
	if field.get("format", "") != FieldLoader.FORMAT:
		return false
	if typeof(field.get("id", null)) != TYPE_STRING or str(field.id).is_empty():
		return false
	if typeof(field.get("runway", null)) != TYPE_STRING or typeof(field.get("surfaces", null)) != TYPE_ARRAY:
		return false
	return true


static func _committed_requested_start(session: Node, trace: Dictionary, outcome: Dictionary,
		start_choice: String, field_id: String) -> bool:
	if not session.is_flyable() or not str(session.start_error).is_empty() or session.sim == null or session.sim.tick != 0:
		return false
	var selected: String = str(trace.get("selected_start_choice", ""))
	if selected != start_choice:
		return false
	if start_choice == Session.START_RUNWAY:
		return bool(outcome.get("ok", false)) and str(trace.get("launch_choice", "")) == "runway" \
			and str(trace.get("launch_kind", "")) == "runway_threshold" \
			and str(trace.get("launch_field_id", "")) == field_id
	if start_choice == Session.START_HALF_POWER:
		return str(trace.get("launch_choice", "")) == "airborne" \
			and str(trace.get("launch_kind", "")) == "trimmed_airborne"
	return str(trace.get("launch_choice", "")) == "airborne" \
		and str(trace.get("launch_kind", "")) == "trimmed_airborne"


static func _failure(reason: String, start_choice: String, field_id: String, started_usec: int,
		diagnostics: Dictionary = {}) -> Dictionary:
	return {
		"ok": false,
		"available": false,
		"reason": reason,
		"start_choice": start_choice,
		"field_id": field_id,
		"diagnostics": {"format": RESULT_FORMAT}.merged(diagnostics, true),
		"duration_ms": float(Time.get_ticks_usec() - started_usec) / 1000.0,
	}


static func _invalid_trial(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "errors": PackedStringArray([reason])}


static func _sha(bytes: PackedByteArray) -> String:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(bytes)
	return hashing.finish().hex_encode()
