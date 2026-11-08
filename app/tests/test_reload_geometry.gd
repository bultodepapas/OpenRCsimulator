extends SceneTree

const MainScene := preload("res://main.tscn")
const AircraftData := preload("res://physics/aircraft_data.gd")
const Installation := preload("res://physics/glow/installation.gd")
const Shadow := preload("res://render/shadow.gd")
const Frames := preload("res://render/frames.gd")
const AirplaneBuilder := preload("res://render/airplane.gd")
const AIRCRAFT := "res://data/aircraft/gp_extra_300s_60.json"
const INSTALLATION := "res://data/glow/extra_61fx_2t.json"

var _checks := 0
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(label: String, passed: bool, detail := "") -> void:
	_checks += 1
	if not passed:
		_failures += 1
	print(("ok   " if passed else "FAIL ") + label + " " + detail)


func _run() -> void:
	var main: Node = MainScene.instantiate()
	main.set_user_args(PackedStringArray(["--physics-backend=gdscript_reference", "--soundscape=off",
		"--scenery=off", "--birds=off", "--crash-effects=off"]))
	main.set("aircraft_id", "gp-extra-300s-60")
	main.set("start_choice", "airborne")
	main.set("interactive_start", true)
	main.set("accident_reports_enabled", false)
	root.add_child(main)
	var deadline: int = Time.get_ticks_msec() + 45000
	while not main.get("startup_complete") and str(main.get("startup_error")).is_empty() and Time.get_ticks_msec() < deadline:
		await process_frame
	_check("production Extra flight starts", bool(main.get("startup_complete")), str(main.get("startup_error")))
	var session: Node = main.get("session")
	if session == null or not main.get("startup_complete"):
		await _finish(main)
		return
	main.set_process(false)
	session.set_physics_process(false)
	session.sim.set_physics_process(false)
	session.input_enabled = false
	var stock: Dictionary = AircraftData.load_file(AIRCRAFT)
	_check("stock fixture passes the production aircraft loader", stock.get("ok", false))
	var original_diameter: float = stock.model.propulsion.diameter
	var larger: Dictionary = _candidate(stock, original_diameter * 13.0 / 12.0, true)
	_check("coherent larger installation passes the production installation validator", larger.get("ok", false), str(larger.get("errors", [])))
	_check_geometry(main, original_diameter, "startup")
	var orbit: RefCounted = main.get("_rig").orbit
	orbit.distance = 7.25
	orbit.set("_distance", 6.75)
	for candidate: Dictionary in [stock, stock, larger, larger, stock, stock]:
		# Use the production frozen-data boundary, never mutate bundled generated files.
		session.set("_frozen_aircraft", candidate.duplicate(true))
		await _tap_f5()
		_check("F5 actually reloads the candidate", str(main.get("_note")).begins_with("aircraft reloaded:"), str(main.get("_note")))
		_check_geometry(main, candidate.model.propulsion.diameter, "F5")
		_check("diameter-only/no-op F5 preserves orbit goals and interpolation", orbit.distance == 7.25 and orbit.get("_distance") == 6.75)
	var before: Dictionary = session.checkpoint()
	var scale_before: Vector3 = main.get("_airplane").propeller.scale
	var rejected: Dictionary = _candidate(stock, original_diameter * 13.0 / 12.0, false)
	_check("one-sided diameter mismatch is rejected by the installation validator", not rejected.get("ok", true))
	session.set("_frozen_aircraft", rejected)
	await _tap_f5()
	_check("F5 reports the rejected mismatch", str(main.get("_note")).begins_with("reload failed; previous aircraft"), str(main.get("_note")))
	_check("rejected F5 retains accepted physics", var_to_bytes(session.checkpoint()) == var_to_bytes(before))
	_check("rejected F5 retains the solid transform", main.get("_airplane").propeller.scale == scale_before)
	_check_geometry(main, original_diameter, "rejected F5")
	_check("rejected F5 preserves orbit goals and interpolation", orbit.distance == 7.25 and orbit.get("_distance") == 6.75)
	# A committed physical reload cannot be undone by a presentation failure.
	session.set("_frozen_aircraft", larger)
	main.get("_airplane")["_scaled_propeller_visual"] = false
	await _tap_f5()
	_check("presentation failure retains the committed diameter", session.aircraft.model.propulsion.diameter == larger.model.propulsion.diameter)
	_check("presentation failure pauses with an explicit reason", session.sim.paused
		and str(main.get("_note")).contains("could not be displayed")
		and str(main.get("_note")).contains("simulation paused"), str(main.get("_note")))
	session.resume()
	_check("resume cannot bypass the presentation hold", session.sim.paused and not session.can_resume())
	main.get("_airplane")["_scaled_propeller_visual"] = true
	await _tap_f5()
	_check_geometry(main, larger.model.propulsion.diameter, "recovered F5")
	_check("successful sync releases the presentation hold", session.holds.is_empty())
	session.resume()
	_check("recovered flight can resume", not session.sim.paused)
	await _finish(main)


func _candidate(stock: Dictionary, diameter: float, coherent: bool) -> Dictionary:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(AIRCRAFT))
	var installation: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(INSTALLATION))
	var model: Dictionary = stock.model.duplicate(true)
	raw.propulsion.propeller.diameter.value = diameter
	model.propulsion.diameter = diameter
	if coherent:
		installation.propeller.diameter_m.value = diameter
	var installed: Dictionary = Installation.prepare_value(installation, raw, model, JSON.stringify(installation).to_utf8_buffer())
	if not installed.get("ok", false):
		return installed
	var result: Dictionary = stock.duplicate(true)
	result.model = installed.model
	result.input_identity = {format = AircraftData.FORMAT} # no stock file hash for an in-memory candidate
	return result


func _check_geometry(main: Node, diameter: float, label: String) -> void:
	var session: Node = main.get("session")
	var airplane: Dictionary = main.get("_airplane")
	var authored: float = airplane.model_manifest.bindings.rotor.authored_diameter_m
	var ratio: float = diameter / authored
	_check(label + " physical strike radius follows the accepted diameter", is_equal_approx(float(session.get("_prop_disc").radius), diameter * 0.5))
	_check(label + " solid propeller uses absolute authored scaling", is_equal_approx(airplane.propeller.scale.x, ratio)
		and is_equal_approx(airplane.propeller.scale.y, ratio))
	var blur: Node3D = main.get_node_or_null("PropellerBlur")
	_check(label + " production blur exists", blur != null)
	if blur != null:
		for rpm: float in [0.0, 9000.0, 9000.0]:
			blur.update(rpm)
			_check(label + " stopped/spinning/unchanged blur transform follows solid", blur.global_transform.is_equal_approx(airplane.propeller.global_transform))
	var extent: Vector2 = Shadow.model_extent(airplane.root)
	_check(label + " model extents and camera span refresh", main.get("_extent").is_equal_approx(extent)
		and is_equal_approx(float(main.get("_rig").get("_span")), extent.x))
	var datum: Vector2 = AirplaneBuilder.datum("gp-extra-300s-60")
	var cg: Vector3 = Frames.cg_in_model_frame(session.aircraft.model.cg_le, datum.x, datum.y)
	_check(label + " accepted CG reaches presentation", main.get("_cg_model").is_equal_approx(cg))


func _tap_f5() -> void:
	var key := InputEventKey.new()
	key.physical_keycode = KEY_F5
	key.pressed = true
	Input.parse_input_event(key)
	await process_frame
	key = InputEventKey.new()
	key.physical_keycode = KEY_F5
	key.pressed = false
	Input.parse_input_event(key)
	await process_frame


func _finish(main: Node) -> void:
	main.queue_free()
	await process_frame
	await process_frame
	print("Reload geometry: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)
