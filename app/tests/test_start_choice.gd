# UI-06a: explicit runway selection survives resets, crash recovery and hot reload; failures never become air starts.
# Run: godot --headless --path . --script res://tests/test_start_choice.gd
extends SceneTree

const Session := preload("res://sim/flight_session.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const RB := preload("res://physics/rigid_body.gd")
const Recorder := preload("res://sim/recorder.gd")
const GroundStart := preload("res://physics/ground_start.gd")

var _checks: int = 0
var _failures: int = 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL ", label, "  ", detail)


func _field() -> Dictionary:
	var result: Dictionary = FieldLoader.load_from()
	_check("default field loads", result.ok)
	return result.get("field", {})


func _session(choice: String = Session.START_AIRBORNE, aircraft_path: String = "") -> Node:
	var session: Node = Session.new()
	session.start_choice = choice
	session.input_enabled = false
	session.setup(aircraft_path if not aircraft_path.is_empty() else Catalog.entry(Catalog.DEFAULT_ID).data)
	root.add_child(session)
	return session


func _array_matches(encoded: String, values: PackedFloat64Array, tolerance: float = 1e-14) -> bool:
	var decoded: Variant = JSON.parse_string(encoded)
	if not decoded is Array or decoded.size() != values.size():
		return false
	for index in values.size():
		if absf(float(decoded[index]) - values[index]) > tolerance:
			return false
	return true


func _initialize() -> void:
	var field: Dictionary = _field()
	if field.is_empty():
		quit(1)
		return
	var session: Node = _session(Session.START_RUNWAY)
	_check("explicit runway start fails closed before a field is loaded", not session.is_flyable()
		and session.sim.paused and not session.start_error.is_empty() and session.start_choice == Session.START_RUNWAY,
		session.start_error)
	_check("validated field is accepted", session.set_field(field))
	session.reset()
	_check("first selected runway start succeeds", session.start_error.is_empty() and session.is_flyable()
		and not session.sim.paused and session.sim.tick == 0)
	var launch_state: PackedFloat64Array = session.sim.state.duplicate()
	var launch_aux: PackedFloat64Array = session.sim.aux.slice(0, Session.AUX_LAYOUT.size())
	var launch_full_aux: PackedFloat64Array = session.sim.aux.duplicate()
	var launch_anchors: PackedFloat64Array = session.sim.aux.slice(Session.AUX_ANCHORS, Session.AUX_ANCHORS + 9)
	var launch_meta: Dictionary = session.trace_meta()
	_check("launch header records runway selection and actual threshold", launch_meta.selected_start_choice == "runway"
		and launch_meta.launch_choice == "runway" and launch_meta.launch_kind == "runway_threshold"
		and launch_meta.launch_field_id == "default" and launch_meta.launch_error == "")
	_check("launch header preserves exact initial state and sampled auxiliaries",
		_array_matches(launch_meta.launch_state, launch_state) and _array_matches(launch_meta.launch_aux, launch_aux)
		and _array_matches(launch_meta.launch_ground_anchors, launch_anchors)
		and launch_meta.launch_engine_running == "true")
	_check("runway reset idles the engine at closed throttle with stuck wheels",
		session.engine_running and session.sim.inputs[3] == 0.0 and launch_aux[0] > 0.0
		and session.sim.aux[6] == 1.0 and session.sim.aux[9] == 1.0 and session.sim.aux[12] == 1.0)

	# A later T recording keeps its own current tick/aux snapshot while retaining the actual launch pose.
	for _tick in 12:
		session.sim.step()
	session.sim.state[RB.POS] += 1.25
	var recorder: RefCounted = Recorder.new(session.sim)
	recorder.start(session.trace_meta())
	var recording_meta: Dictionary = recorder.trace.meta
	var recorded_launch: Variant = JSON.parse_string(recording_meta.launch_state)
	_check("recording start remains distinct from launch metadata", recording_meta.recording_start_tick == 12
		and _array_matches(recording_meta.recording_start_aux, session.sim.aux.slice(0, Session.AUX_LAYOUT.size()))
		and _array_matches(recording_meta.launch_ground_anchors, launch_anchors)
		and absf(float(recorded_launch[RB.POS]) - recorder.trace.value(0, "north_m")) > 1.0)
	_check("trace row starts from the recording-time position", absf(recorder.trace.value(0, "north_m") - session.sim.state[RB.POS]) < 1e-12)
	recorder.detach()

	# Explicit reset is the pause-menu Restart contract; it reconstructs equilibrium and anchors from the choice.
	session.hold("menu")
	session.reset()
	_check("reset preserves the named pause hold", session.sim.paused and session.holds.has("menu")
		and session.sim.tick == 0 and session.sim.state == launch_state and session.sim.aux == launch_full_aux)
	session.release("menu")
	session.resume()
	_check("release and Continue explicitly resume the reset flight", not session.sim.paused and session.is_flyable())
	session.reset()
	_check("pause Restart reconstructs the same runway state and anchors exactly",
		session.start_error.is_empty() and session.sim.tick == 0 and session.sim.state == launch_state
		and session.sim.aux == launch_full_aux
		and session.trace_meta().launch_choice == "runway")
	var restart_aux: PackedFloat64Array = session.sim.aux.duplicate()
	session.crash = { ticks_left = 1, why = "UI-06a test" }
	session.sim.set_paused(true)
	session._physics_process(0.0)
	_check("automatic crash recovery restarts the selected runway start",
		session.crash.is_empty() and session.start_error.is_empty() and session.sim.tick == 0
		and session.sim.state == launch_state and session.sim.aux == restart_aux and not session.sim.paused)

	# The manual input path remains live from the selected runway start.
	session.input_enabled = true
	session.read_raw = func() -> Dictionary: return { roll = 0.0, pitch = 1.0, yaw = 0.0, throttle = 1.0 }
	session._physics_process(session.sim.dt())
	_check("manual input advances controls and raises throttle from runway idle",
		session.commands.pitch > 0.0 and session.commands.throttle > 0.0 and session.sim.inputs[3] > 0.0)
	session.input_enabled = false
	session.reset()

	# A valid hot reload must rebuild the runway support state; corrupting the loaded file must retain the active tick.
	var source_path: String = Catalog.entry(Catalog.DEFAULT_ID).data
	var source: String = FileAccess.get_file_as_string(source_path)
	var modified: String = source.replace("Physics data only; visual geometry", "Physics data only; UI-06a reload fixture; visual geometry")
	var reload_path: String = "user://ui06a-valid-%d.json" % OS.get_process_id()
	var output: FileAccess = FileAccess.open(reload_path, FileAccess.WRITE)
	_check("valid reload fixture opens", output != null)
	if output != null:
		output.store_string(modified)
		output.close()
	var old_anchor_north: float = session.sim.aux[Session.AUX_ANCHORS]
	session.sim.aux[Session.AUX_ANCHORS] += 20.0
	var stale_anchor_north: float = session.sim.aux[Session.AUX_ANCHORS]
	session.aircraft_path = reload_path
	session.hold("menu")
	var valid_reload: String = session.reload()
	_check("valid runway reload rebuilds threshold and wheel anchors", valid_reload.begins_with("aircraft reloaded: runway")
		and session.start_error.is_empty() and session.sim.tick == 0 and session.sim.state == launch_state
		and stale_anchor_north != session.sim.aux[Session.AUX_ANCHORS]
		and session.sim.aux[Session.AUX_ANCHORS] == launch_full_aux[Session.AUX_ANCHORS],
		"result=%s, error=%s, tick=%d, state=%s, anchor=%.9f expected=%.9f old=%.9f" % [valid_reload,
		session.start_error, session.sim.tick, str(session.sim.state == launch_state), session.sim.aux[Session.AUX_ANCHORS],
		launch_full_aux[Session.AUX_ANCHORS], old_anchor_north])
	_check("valid reload preserves a named pause hold", session.sim.paused and session.holds.has("menu"))
	session.release("menu")
	session.resume()
	var retained: Dictionary = session.sim.checkpoint()
	var retained_meta: Dictionary = session.trace_meta()
	output = FileAccess.open(reload_path, FileAccess.WRITE)
	_check("invalid reload fixture opens", output != null)
	if output != null:
		output.store_string("{}")
		output.close()
	var invalid_reload: String = session.reload()
	var after_invalid_meta: Dictionary = session.trace_meta()
	_check("invalid runway reload reports failure", invalid_reload.begins_with("reload failed"), invalid_reload)
	_check("invalid reload transaction retains exact active flight and launch metadata",
		session.sim.checkpoint() == retained and after_invalid_meta.aircraft_input_sha256 == retained_meta.aircraft_input_sha256
		and after_invalid_meta.launch_state == retained_meta.launch_state and after_invalid_meta.launch_choice == "runway")
	_check("invalid reload leaves the runway flight flyable", session.is_flyable() and not session.sim.paused)
	var reload_recorder: RefCounted = Recorder.new(session.sim)
	reload_recorder.start(session.trace_meta())
	session.resetting.connect(func() -> void: reload_recorder.recording = false)
	session.aircraft_path = Catalog.entry("gp-extra-300s-60").data
	var unsupported_reload: String = session.reload()
	_check("valid but unsupported runway reload is rejected before closing the recorder",
		unsupported_reload.begins_with("reload failed") and reload_recorder.recording
		and session.sim.checkpoint() == retained and session.is_flyable(), unsupported_reload)
	reload_recorder.detach()
	session.aircraft_path = source_path
	_check("valid Stik reload succeeds after a refused candidate", session.reload().begins_with("aircraft reloaded: runway")
		and session.is_flyable())
	DirAccess.remove_absolute(ProjectSettings.globalize_path(reload_path))

	# Missing runway and failed equilibrium are explicit, parked failures; restoring valid inputs retries cleanly.
	var saved_field: Dictionary = session._runway_field.duplicate(true)
	var surfaces: Array = session._runway_field.surfaces.duplicate(true)
	var no_runway: Array = []
	for surface in surfaces:
		if surface.get("type", "") != "runway":
			no_runway.append(surface)
	session._runway_field.surfaces = no_runway
	session.reset()
	_check("field without a runway fails closed with a visible reason", session.start_error.contains("no runway")
		and session.sim.paused and not session.is_flyable() and not session.engine_running
		and session.trace_meta().launch_choice == "failed")
	session._runway_field = saved_field
	session.sim.gravity = 0.0
	session.reset()
	_check("failed equilibrium input fails closed instead of launching airborne", session.start_error.contains("positive gravity")
		and session.sim.paused and not session.is_flyable() and not session.engine_running)
	session.sim.gravity = 9.80665
	session.reset()
	_check("valid retry after explicit runway failures succeeds", session.start_error.is_empty()
		and session.is_flyable() and session.sim.state == launch_state)

	var unsupported: Node = _session(Session.START_RUNWAY, Catalog.entry("gp-extra-300s-60").data)
	_check("unsupported aircraft field loads", unsupported.set_field(field))
	unsupported.reset()
	_check("unsupported aircraft is refused without an airborne fallback",
		unsupported.start_error.contains("supported only") and unsupported.sim.paused
		and not unsupported.is_flyable() and unsupported.start_choice == Session.START_RUNWAY
		and unsupported.sim.state[RB.VEL] == 0.0 and not unsupported.engine_running)

	var alternate: Dictionary = field.duplicate(true)
	alternate.id = "another-field"
	var unsupported_field: Node = _session(Session.START_RUNWAY)
	_check("alternate field surface table loads", unsupported_field.set_field(alternate))
	unsupported_field.reset()
	_check("unsupported field is refused with an explicit reason", unsupported_field.start_error.contains("field 'default'")
		and unsupported_field.sim.paused and not unsupported_field.is_flyable())

	# The old one-shot helper stays available to existing test/capture callers and does not persist a choice.
	var legacy: Node = _session()
	_check("legacy field loads", legacy.set_field(field))
	var start_spot: Dictionary = GroundStart.threshold(field)
	_check("legacy one-shot runway helper still starts", legacy.reset_on_runway(start_spot.north, start_spot.east, start_spot.heading)
		and legacy.trace_meta().launch_choice == "runway" and legacy.start_choice == Session.START_AIRBORNE)
	legacy.reset()
	_check("legacy helper leaves ordinary reset airborne", legacy.trace_meta().launch_choice == "airborne"
		and legacy.sim.state == legacy.start.state)
	_check("legacy failed helper still restores its airborne start",
		not legacy.reset_on_runway(NAN, start_spot.east, start_spot.heading) and legacy.is_flyable()
		and legacy.start_error.is_empty() and legacy.sim.state == legacy.start.state)

	session.free()
	unsupported.free()
	unsupported_field.free()
	legacy.free()
	print("UI-06a: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)
