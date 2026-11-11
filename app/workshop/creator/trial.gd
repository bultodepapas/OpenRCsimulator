extends RefCounted
## Frozen Aircraft Creator trial and its start check (AC-09).
##
## `freeze` turns an accepted candidate, its admitted source and placement into the frozen record
## Main and the root flight bridge consume. Nothing is published and no preference changes: an
## unsaved candidate may fly. `check_start` runs the same start transaction a live flight uses on
## a disposable session. Its `ok` means "assessed"; `available` means the requested start
## committed without substitution. A committed scratch reset never publishes a live trial.

const R := preload("res://workshop/creator/result.gd")
const CreatorBytes := preload("res://workshop/creator/bytes.gd")
const AcceptedCandidate := preload("res://workshop/creator/accepted_candidate.gd")
const InspectedSource := preload("res://workshop/creator/inspected_source.gd")
const Placement := preload("res://workshop/creator/placement.gd")
const RecordLoader := preload("res://workshop/creator/record_loader.gd")
const Session := preload("res://sim/flight_session.gd")
const AircraftData := preload("res://physics/aircraft_data.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const Weather := preload("res://physics/wind_config.gd")
const RB := preload("res://physics/rigid_body.gd")

const FORMAT := "openrc-creator-trial v1"
const CHECK_FORMAT := "openrc-creator-start-check v1"
const VEHICLE := "creator"
const START_CHOICES: PackedStringArray = [Session.START_AIRBORNE, Session.START_HAND_LAUNCH]
## Hands-off flight after a hand launch that must stay clear of the ground for the start to be offered.
const CLIMB_OUT_SECONDS := 3.0
const CLIMB_OUT_MIN_HEIGHT_M := 0.5
const MAX_CHECK_USEC := 16_000_000
## Constant text so the host can translate it; keep its duration in step with CLIMB_OUT_SECONDS.
const CLIMB_OUT_REFUSAL := "A standard hand throw would not climb away: the aircraft touched the ground or lost control within 3 seconds. Reduce weight, move the balance point forward or use the Airborne start."


## True for the payload the Creator screen emits when the player asks for a test flight.
static func is_request(payload: Dictionary) -> bool:
	return payload.has("creator_candidate")


static func is_trial(trial: Dictionary) -> bool:
	return str(trial.get("vehicle", "")) == VEHICLE


## Freezes a test-flight request: {creator_candidate, creator_source, creator_placement, creator_name}.
## Returns the frozen-trial dictionary: {ok, errors, vehicle, data, scale, raw_bytes, identity, creator}.
## The candidate must be the object the compiler returned: a dictionary claiming success is refused.
static func freeze(payload: Dictionary) -> Dictionary:
	var candidate: Variant = payload.get("creator_candidate")
	if not (candidate is Object) or (candidate as Object).get_script() != AcceptedCandidate:
		return _refused("The aircraft was not accepted by the compiler.")
	var source: Variant = payload.get("creator_source")
	if not (source is Object) or (source as Object).get_script() != InspectedSource or not (source as InspectedSource).is_admitted():
		return _refused("The model source was not admitted.")
	var placement: Variant = payload.get("creator_placement")
	if typeof(placement) != TYPE_DICTIONARY:
		return _refused("The model placement is missing.")
	var placed: Dictionary = Placement.resolve(placement)
	if not placed.ok:
		return _refused("The model orientation, size or datum is not confirmed.")
	var accepted: AcceptedCandidate = candidate
	var raw_bytes: PackedByteArray = accepted.raw_bytes()
	var raw_sha256: String = CreatorBytes.sha256(raw_bytes)
	var aircraft_id: String = accepted.aircraft_id()
	# The model that flies is loaded here from the exact bytes, not taken from the candidate object:
	# whatever the object holds, the trial is bound to what these bytes mean.
	var data: Dictionary = RecordLoader.load_bytes(raw_bytes, aircraft_id)
	if raw_bytes.is_empty() or raw_sha256 != accepted.raw_sha256() or not data.get("ok", false) \
			or typeof(data.get("model")) != TYPE_DICTIONARY or str(data.model.get("id", "")) != aircraft_id \
			or typeof(data.get("input_identity")) != TYPE_DICTIONARY \
			or str(data.input_identity.get("format", "")) != AircraftData.FORMAT \
			or str(data.input_identity.get("sha256", "")) != raw_sha256:
		return _refused("The compiled aircraft does not match its exact bytes.")
	var pinned := {
		"format": FORMAT, "aircraft_id": aircraft_id, "raw_sha256": raw_sha256,
		"definition_sha256": accepted.definition_sha256(), "source_sha256": (source as InspectedSource).sha256(),
		"placement": _placement_pins(placed.value),
		"qualification": accepted.qualification(),
	}
	var trial_id: String = _trial_id(pinned)
	if trial_id.is_empty():
		return _refused("The trial identity could not be written.")
	var identity: Dictionary = pinned.duplicate(true)
	# The digest of the pinned payload names the trial; it is not part of what it hashes.
	identity["trial_id"] = trial_id
	identity["experimental"] = true
	return {
		"ok": true, "errors": PackedStringArray(), "vehicle": VEHICLE,
		"data": data, "scale": 1.0, "raw_bytes": raw_bytes, "identity": identity,
		"creator": {"source": source, "placement": (placement as Dictionary).duplicate(true),
			"name": str(payload.get("creator_name", ""))},
		# What Pause shows: an unsaved aircraft under test, by its name. Display only, not identity.
		"display_context": {"state": "unsaved", "name": str(payload.get("creator_name", ""))},
	}


## Re-checks a frozen trial before it is used: it may have been copied, edited or deserialized.
## Nothing in the dictionary is taken on trust: the model is reloaded from the exact bytes and must
## equal the one carried, and the placement and trial id are derived again. GDScript cannot make a
## dictionary immutable, so every consumer that acts on a trial calls this first.
static func verify(trial: Dictionary) -> Dictionary:
	if not is_trial(trial) or not trial.get("ok", false):
		return _refused("This is not a frozen Creator trial.")
	var identity: Variant = trial.get("identity")
	var data: Variant = trial.get("data")
	var bytes: Variant = trial.get("raw_bytes")
	var creator: Variant = trial.get("creator")
	if typeof(identity) != TYPE_DICTIONARY or typeof(data) != TYPE_DICTIONARY or typeof(creator) != TYPE_DICTIONARY \
			or typeof(bytes) != TYPE_PACKED_BYTE_ARRAY or (bytes as PackedByteArray).is_empty():
		return _refused("The frozen trial is missing its identity, data, source or exact bytes.")
	if str(identity.get("format", "")) != FORMAT or not data.get("ok", false) or typeof(data.get("model")) != TYPE_DICTIONARY:
		return _refused("The frozen trial has an unsupported identity or an invalid model.")
	var raw_sha256: String = CreatorBytes.sha256(bytes)
	if str(identity.get("raw_sha256", "")) != raw_sha256 or typeof(data.get("input_identity")) != TYPE_DICTIONARY \
			or str(data.input_identity.get("sha256", "")) != raw_sha256 \
			or str(data.input_identity.get("format", "")) != AircraftData.FORMAT:
		return _refused("The frozen aircraft bytes do not match the trial identity.")
	var aircraft_id: String = str(data.model.get("id", ""))
	if aircraft_id.is_empty() or aircraft_id != str(identity.get("aircraft_id", "")):
		return _refused("The frozen model does not match the trial identity.")
	var source: Variant = creator.get("source")
	if not (source is Object) or (source as Object).get_script() != InspectedSource \
			or (source as InspectedSource).sha256() != str(identity.get("source_sha256", "")):
		return _refused("The frozen model source does not match the trial identity.")
	var reloaded: Dictionary = RecordLoader.load_bytes(bytes, aircraft_id)
	if not reloaded.get("ok", false) or reloaded.model != data.model:
		return _refused("The frozen model is not what its exact bytes load to.")
	var placement: Variant = creator.get("placement")
	var placed: Dictionary = Placement.resolve(placement) if typeof(placement) == TYPE_DICTIONARY else {"ok": false}
	if not placed.ok or _placement_pins(placed.value) != identity.get("placement"):
		return _refused("The frozen model placement does not match the trial identity.")
	var pinned: Dictionary = (identity as Dictionary).duplicate(true)
	pinned.erase("trial_id")
	pinned.erase("experimental")
	if str(identity.get("trial_id", "")).is_empty() or str(identity.get("trial_id", "")) != _trial_id(pinned):
		return _refused("The frozen trial identity does not match its content.")
	return {"ok": true, "errors": PackedStringArray(), "aircraft_id": aircraft_id}


static func _placement_pins(resolved: Dictionary) -> Dictionary:
	return {"rows": resolved.rows, "unit_scale": float(resolved.unit_scale), "datum": resolved.datum}


## "creator-" plus the first 24 hex digits of the SHA-256 of the pinned payload, or "" on failure.
static func _trial_id(pinned: Dictionary) -> String:
	var written: Dictionary = CreatorBytes.encode(pinned)
	return "creator-" + str(written.value.sha256).substr(0, 24) if written.ok else ""


## Assesses one start for the exact frozen trial, field and weather.
## Returns {ok, available, reason, start_choice, field_id, diagnostics, duration_ms}.
static func check_start(trial: Dictionary, normalized_field: Dictionary, weather_config: Dictionary,
		start_choice: String) -> Dictionary:
	var started_usec: int = Time.get_ticks_usec()
	var field_id: String = str(normalized_field.get("id", ""))
	var checked: Dictionary = verify(trial)
	if not checked.ok:
		return _failure(str(checked.errors[0]), start_choice, field_id, started_usec)
	if start_choice not in START_CHOICES:
		return _failure("This start is not available for a Creator aircraft without landing gear.", start_choice, field_id, started_usec)
	if str(normalized_field.get("format", "")) != FieldLoader.FORMAT or field_id.is_empty():
		return _failure("The selected field is not a normalized field definition.", start_choice, field_id, started_usec)
	var weather: Dictionary = Weather.validate(weather_config)
	if not weather.get("ok", false):
		return _failure("The weather configuration is invalid.", start_choice, field_id, started_usec)
	var scene_tree: SceneTree = Engine.get_main_loop() as SceneTree
	if scene_tree == null or scene_tree.root == null:
		return _failure("The start check needs a running scene tree.", start_choice, field_id, started_usec)
	var aircraft_id: String = str(checked.aircraft_id)
	var session: Node = Session.new()
	session.physics_enabled = false
	session.input_enabled = false
	session.crash_auto_restart = false
	session.start_choice = start_choice
	session.trim_throttle = Session.CRUISE_TRIM_THROTTLE
	session.setup("workshop://" + str(trial.identity.trial_id), aircraft_id, (trial.data as Dictionary).duplicate(true))
	if not session.aircraft.get("ok", false):
		var load_reason: String = str(session.aircraft.get("errors", ["The frozen aircraft could not be prepared."])[0])
		session.free()
		return _failure(load_reason, start_choice, field_id, started_usec)
	if not session.set_field(normalized_field):
		var field_reason: String = str(session.surface_error)
		session.free()
		return _failure("The selected field could not be installed: " + field_reason, start_choice, field_id, started_usec)
	if not session.setup_weather(weather.config):
		var weather_reason: String = str(session.weather_error)
		session.free()
		return _failure("The weather could not be installed: " + weather_reason, start_choice, field_id, started_usec)
	session.external_controller_selection = true
	scene_tree.root.add_child(session)
	session.start_choice = start_choice
	session.reset()
	var committed: bool = session.is_flyable() and str(session.start_error).is_empty() and session.sim != null and session.sim.tick == 0
	var trace: Dictionary = session.trace_meta() if committed else {}
	var reason: String = str(session.start_error)
	var available: bool = committed and str(trace.get("selected_start_choice", "")) == start_choice
	if available and start_choice == Session.START_HAND_LAUNCH:
		available = str(trace.get("launch_choice", "")) == Session.START_HAND_LAUNCH \
			and str(trace.get("launch_kind", "")) == "hand_launch_release" and str(trace.get("launch_field_id", "")) == field_id
	elif available:
		available = str(trace.get("launch_choice", "")) == "airborne" and str(trace.get("launch_kind", "")) == "trimmed_airborne"
	if not available and reason.is_empty():
		reason = "The requested start did not commit."
	var diagnostics := {
		"format": CHECK_FORMAT, "aircraft_id": aircraft_id, "trial_id": str(trial.identity.trial_id),
		"raw_sha256": str(trial.identity.raw_sha256), "start_choice": start_choice,
		"launch_choice": str(trace.get("launch_choice", "unknown")), "launch_kind": str(trace.get("launch_kind", "unknown")),
		"physical_reset_committed": committed, "root_trial_published": false,
	}
	if available and start_choice == Session.START_HAND_LAUNCH:
		var climb: Dictionary = _climb_out(session)
		diagnostics["climb_out"] = climb
		if not climb.clear:
			available = false
			reason = CLIMB_OUT_REFUSAL
	session.free()
	var elapsed_usec: int = Time.get_ticks_usec() - started_usec
	if elapsed_usec > MAX_CHECK_USEC:
		available = false
		reason = "The start check exceeded its time budget."
	return {"ok": true, "available": available, "reason": reason, "start_choice": start_choice, "field_id": field_id,
		"diagnostics": diagnostics, "duration_ms": float(elapsed_usec) / 1000.0}


## Hands-off continuation of a committed hand launch on the scratch session, in the product
## tick order. It only decides whether the throw is offered; it is not a handling assessment.
static func _climb_out(session: Node) -> Dictionary:
	var start_down: float = session.sim.state[RB.POS + 2]
	var release_north: float = session.sim.state[RB.POS]
	var release_east: float = session.sim.state[RB.POS + 1]
	var terrain: PackedFloat64Array = session.environment.terrain(release_north, release_east)
	var ground: float = float(terrain[0]) if not terrain.is_empty() and is_finite(terrain[0]) else -start_down - Session.HAND_LAUNCH_RELEASE_HEIGHT_M
	var min_height: float = INF
	var ticks: int = int(CLIMB_OUT_SECONDS * 240.0)
	# The start was assessed with stepping disabled; the continuation needs the session's tick gate open.
	session.physics_enabled = true
	var flown := 0
	for _tick: int in ticks:
		if not session._session_after_input():
			break
		session.sim.step()
		flown += 1
		min_height = minf(min_height, -session.sim.state[RB.POS + 2] - ground)
	var clear: bool = flown == ticks and session.crash.is_empty() and str(session.sim.fault_reason).is_empty() \
		and is_finite(min_height) and min_height > CLIMB_OUT_MIN_HEIGHT_M
	return {"clear": clear, "ticks": flown, "min_height_m": min_height if is_finite(min_height) else -1.0,
		"final_height_m": -session.sim.state[RB.POS + 2] - ground}


static func _refused(reason: String) -> Dictionary:
	return {"ok": false, "errors": PackedStringArray([reason])}


static func _failure(reason: String, start_choice: String, field_id: String, started_usec: int) -> Dictionary:
	return {"ok": false, "available": false, "reason": reason, "start_choice": start_choice, "field_id": field_id,
		"diagnostics": {"format": CHECK_FORMAT}, "duration_ms": float(Time.get_ticks_usec() - started_usec) / 1000.0}
