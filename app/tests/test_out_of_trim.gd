# D6-TRIM-01: natural out-of-trim airframes. Configuration, airframe draws, the session's rigging offsets (the trims
# never move), first-flight and every-flight persistence, rollback, rudder trim, exact checkpoint replay, preferences
# and the next-flight dialog's draft.
extends SceneTree

const Flight := preload("res://sim/flight_session.gd")
const OutOfTrim := preload("res://sim/out_of_trim.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const Commands := preload("res://input/commands.gd")
const Aero := preload("res://physics/aero.gd")
const RB := preload("res://physics/rigid_body.gd")
const Preferences := preload("res://app_state/preferences.gd")
const VisualCheckpoint := preload("res://app_state/visual_checkpoint.gd")
const TrimPracticeMenu := preload("res://ui/trim_practice_menu.gd")

const STIK := "jensen-das-ugly-stik-60"
const X8 := "moonrunner-x99"
const PREFS := "user://test_out_of_trim_settings.cfg"

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame # the dialog's Range nodes signal only inside a running tree
	_test_config()
	_test_draws_and_offsets()
	_test_disabled_is_unchanged()
	_test_every_flight()
	_test_first_flight_persistence()
	_test_refused_restart_rolls_back()
	_test_rudder_trim()
	_test_checkpoint_replay()
	_test_preferences()
	_test_menu_draft()
	print("Out-of-trim airframes: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _check(label: String, ok: bool, detail: Variant = "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s: %s" % [label, str(detail)])


func _config(enabled: bool, intensity: int, mode: String) -> Dictionary:
	return {"enabled": enabled, "intensity_percent": intensity, "mode": mode}


func _new_flight(id: String) -> Node:
	var flight: Node = Flight.new()
	flight.setup(str(Catalog.entry(id).get("data", "")), id)
	flight.input_enabled = true
	return flight


func _start_trims(flight: Node) -> PackedFloat64Array:
	return PackedFloat64Array([float(flight.start.roll_command), float(flight.start.pitch_command),
		float(flight.start.get("yaw_command", 0.0))])


func _trims(flight: Node) -> PackedFloat64Array:
	return PackedFloat64Array([float(flight.trims.roll), float(flight.trims.pitch), float(flight.trims.yaw)])


func _near(a: PackedFloat64Array, b: PackedFloat64Array, tolerance := 1.0e-12) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if absf(a[i] - b[i]) > tolerance:
			return false
	return true


func _step(flight: Node, ticks: int) -> void:
	for _tick in ticks:
		flight.sim.inputs = flight._inputs()
		flight.sim.step()


func _test_config() -> void:
	var defaults: Dictionary = OutOfTrim.defaults()
	_check("defaults are off, 50 % and first flight only", defaults == _config(false, 50, OutOfTrim.MODE_FIRST_FLIGHT), defaults)
	_check("defaults validate", OutOfTrim.validate(defaults).ok)
	_check("every flight at 100 % validates", OutOfTrim.validate(_config(true, 100, OutOfTrim.MODE_EVERY_FLIGHT)).ok)
	_check("a non-object is refused", not OutOfTrim.validate([true, 50]).ok)
	var missing := defaults.duplicate()
	missing.erase("mode")
	_check("a missing key is refused", not OutOfTrim.validate(missing).ok)
	var extra := defaults.duplicate()
	extra.seed = 4
	_check("an unknown key is refused", not OutOfTrim.validate(extra).ok)
	_check("a fractional intensity is refused", not OutOfTrim.validate({"enabled": true, "intensity_percent": 50.0, "mode": "first_flight"}).ok)
	_check("intensity above 100 % is refused", not OutOfTrim.validate(_config(true, 101, OutOfTrim.MODE_FIRST_FLIGHT)).ok)
	_check("negative intensity is refused", not OutOfTrim.validate(_config(true, -1, OutOfTrim.MODE_FIRST_FLIGHT)).ok)
	_check("an unknown mode is refused", not OutOfTrim.validate(_config(true, 40, "sometimes")).ok)
	_check("a non-boolean switch is refused", not OutOfTrim.validate({"enabled": 1, "intensity_percent": 40, "mode": "every_flight"}).ok)


func _test_draws_and_offsets() -> void:
	_check("the same seed and index give the same airframe", OutOfTrim.draw(7, 0) == OutOfTrim.draw(7, 0))
	_check("the next index gives another airframe", OutOfTrim.draw(7, 0) != OutOfTrim.draw(7, 1))
	_check("another seed gives another airframe", OutOfTrim.draw(7, 0) != OutOfTrim.draw(8, 0))
	var bounded := true
	var signs := [{}, {}, {}]
	var magnitude_sum := 0.0
	var count := 0
	for seed_value in 50:
		for index in 4:
			var unit: PackedFloat64Array = OutOfTrim.draw(seed_value, index)
			for axis in 3:
				bounded = bounded and absf(unit[axis]) >= OutOfTrim.MIN_FRACTION and absf(unit[axis]) <= 1.0
				signs[axis][signf(unit[axis])] = true
				magnitude_sum += absf(unit[axis])
				count += 1
	_check("every draw lies within the minimum fraction and the full scale", bounded)
	_check("each axis is drawn with both signs", signs.all(func(seen: Dictionary) -> bool: return seen.has(1.0) and seen.has(-1.0)))
	var mean: float = magnitude_sum / count
	_check("draws cluster near the middle of the range", mean > 0.55 and mean < 0.70, mean)
	var throws := {aileron = 20.0, elevator = 20.0, rudder = 25.0}
	var full: PackedFloat64Array = OutOfTrim.offsets(PackedFloat64Array([1.0, -1.0, 1.0]), 100, throws)
	_check("full scale converts degrees to each axis' throw units", _near(full,
		PackedFloat64Array([OutOfTrim.FULL_SCALE_DEG[0] / 20.0, -OutOfTrim.FULL_SCALE_DEG[1] / 20.0, OutOfTrim.FULL_SCALE_DEG[2] / 25.0])), full)
	var half: PackedFloat64Array = OutOfTrim.offsets(PackedFloat64Array([1.0, -1.0, 1.0]), 50, throws)
	_check("intensity scales the offsets linearly", _near(half, PackedFloat64Array([full[0] * 0.5, full[1] * 0.5, full[2] * 0.5])), half)
	_check("0 % is perfectly trimmed", OutOfTrim.is_zero(OutOfTrim.offsets(PackedFloat64Array([1.0, 1.0, 1.0]), 0, throws)))
	var elevon: PackedFloat64Array = OutOfTrim.offsets(PackedFloat64Array([1.0, 1.0, 1.0]), 100, {aileron = 23.0, elevator = 19.0, elevon = 27.0})
	_check("an elevon aircraft has no yaw offset to trim", elevon[2] == 0.0 and elevon[0] != 0.0 and elevon[1] != 0.0, elevon)
	var tiny: PackedFloat64Array = OutOfTrim.offsets(PackedFloat64Array([1.0, -1.0, 1.0]), 100, {aileron = 1.0, elevator = 1.0, rudder = 1.0})
	_check("tiny throws stay within a replayable offset", tiny == PackedFloat64Array([OutOfTrim.MAX_OFFSET, -OutOfTrim.MAX_OFFSET, OutOfTrim.MAX_OFFSET])
		and OutOfTrim.valid_offsets(tiny), tiny)
	_check("zero offsets are not a carried airframe", not OutOfTrim.valid_offsets(PackedFloat64Array([0.0, 0.0, 0.0])))
	_check("small offsets are a valid airframe", OutOfTrim.valid_offsets(PackedFloat64Array([0.01, -0.02, 0.0])))
	_check("non-finite offsets are refused", not OutOfTrim.valid_offsets(PackedFloat64Array([NAN, 0.0, 0.0])))
	_check("offsets beyond a rigging error are refused", not OutOfTrim.valid_offsets(PackedFloat64Array([0.3, 0.0, 0.0])))
	_check("offsets of the wrong size are refused", not OutOfTrim.valid_offsets(PackedFloat64Array([0.01, 0.0])))
	var record := {unit = PackedFloat64Array([0.5, -0.5, 0.5]), intensity_percent = 60, pilot_trim = PackedFloat64Array([0.0, 0.01, 0.0])}
	_check("a record at the same intensity is carried", not OutOfTrim.carried_record(record, _config(true, 60, "first_flight")).is_empty())
	_check("a record at another intensity rigs a new airframe", OutOfTrim.carried_record(record, _config(true, 70, "first_flight")).is_empty())


func _test_disabled_is_unchanged() -> void:
	var baseline: Node = _new_flight(STIK)
	var configured: Node = _new_flight(STIK)
	_check("disabled settings are accepted", configured.setup_out_of_trim(OutOfTrim.defaults(), 0, {}, STIK), configured.out_of_trim_error)
	_check("disabled settings stay inactive", not configured.out_of_trim_active() and not configured.out_of_trim_status().active)
	baseline.reset()
	configured.reset()
	_check("disabled restart keeps the solved start trim", _trims(configured) == _start_trims(configured))
	_step(baseline, 24)
	_step(configured, 24)
	_check("disabled settings fly the historical physics bit for bit", var_to_bytes(configured.checkpoint()) == var_to_bytes(baseline.checkpoint()))
	_check("disabled settings keep the historical checkpoint format", configured.checkpoint().get("format") != Flight.OUT_OF_TRIM_CHECKPOINT_FORMAT)
	_check("disabled settings add no trace metadata", not configured.trace_meta().has("airframe_trim_offset"))
	baseline.free()
	configured.free()


func _test_every_flight() -> void:
	var flight: Node = _new_flight(STIK)
	var baseline: Node = _new_flight(STIK)
	_check("every-flight settings configure at tick zero",
		flight.setup_out_of_trim(_config(true, 100, OutOfTrim.MODE_EVERY_FLIGHT), 11, {}, STIK), flight.out_of_trim_error)
	_check("the airframe is rigged at the next reset, not before", OutOfTrim.is_zero(flight._airframe_offset))
	flight.reset()
	baseline.reset()
	var throws: Dictionary = flight.throws_deg()
	var first: PackedFloat64Array = flight._airframe_offset.duplicate()
	_check("the first flight flies the first airframe of its seed", first == OutOfTrim.offsets(OutOfTrim.draw(11, 0), 100, throws), first)
	_check("the trims are never moved for the pilot", _trims(flight) == _start_trims(flight))
	var aux: PackedFloat64Array = flight.sim.aux
	var expected: Dictionary = Aero.deflections_from_surfaces(Commands.surface_deflections_deg({roll = aux[Flight.AUX_SERVO] + first[0],
		pitch = aux[Flight.AUX_SERVO + 1] + first[1], yaw = aux[Flight.AUX_SERVO + 2] + first[2]}, throws))
	_check("the aerodynamics see servo positions plus the rigging offsets", flight._deflections(aux) == expected)
	_check("the rendered surfaces stay at the servo positions", flight.surface_angles_deg() == baseline.surface_angles_deg())
	_step(flight, 240)
	_step(baseline, 240)
	var drift := 0.0
	for i in 4:
		drift = maxf(drift, absf(flight.sim.state[RB.ATT + i] - baseline.sim.state[RB.ATT + i]))
	_check("one second hands-off departs from the trimmed baseline", drift > 1.0e-3, drift)
	_check("trace metadata names the airframe", flight.trace_meta().has("airframe_trim_offset") and flight.trace_meta().has("out_of_trim"))
	_check("aileron trim press is accepted", flight.adjust_aileron_trim(0.02))
	flight.reset()
	_check("a restart rigs a new airframe", flight._airframe_offset == OutOfTrim.offsets(OutOfTrim.draw(11, 1), 100, throws) and flight._airframe_offset != first)
	_check("a restart returns the trims to the starting trim", _trims(flight) == _start_trims(flight))
	flight.crash = {speed = 20.0, sink = 5.0, ticks_left = 1, why = "test", impact = null}
	flight.crash_auto_restart = true
	flight._session_after_input()
	_check("a crash restart rigs yet another airframe", flight._airframe_offset == OutOfTrim.offsets(OutOfTrim.draw(11, 2), 100, throws))
	flight.free()
	baseline.free()


func _test_first_flight_persistence() -> void:
	var registry := {}
	var config := _config(true, 60, OutOfTrim.MODE_FIRST_FLIGHT)
	var flight: Node = _new_flight(STIK)
	_check("first-flight settings configure", flight.setup_out_of_trim(config, 5, registry, STIK), flight.out_of_trim_error)
	flight.reset()
	var throws: Dictionary = flight.throws_deg()
	var airframe: PackedFloat64Array = flight._airframe_offset.duplicate()
	_check("the first flight flies the seed's airframe", airframe == OutOfTrim.offsets(OutOfTrim.draw(5, 0), 60, throws))
	_check("the session registry keeps the airframe", registry.has(STIK) and registry[STIK].unit == OutOfTrim.draw(5, 0) and registry[STIK].intensity_percent == 60)
	_check("the starting trims are untouched", _trims(flight) == _start_trims(flight))
	_check("aileron trim", flight.adjust_aileron_trim(-0.02))
	_check("elevator trim", flight.adjust_elevator_trim(0.3))
	_check("rudder trim", flight.adjust_rudder_trim(0.01))
	var pilot := PackedFloat64Array([-0.02, 0.3 / float(throws.elevator), 0.01])
	_check("the registry follows the pilot's trim", _near(registry[STIK].pilot_trim, pilot, 1.0e-9), registry[STIK].pilot_trim)
	var trimmed: PackedFloat64Array = _trims(flight)
	flight.reset()
	_check("a restart keeps the same airframe", flight._airframe_offset == airframe)
	_check("a restart keeps the pilot's trims", _near(_trims(flight), trimmed, 1.0e-12), [_trims(flight), trimmed])
	flight.crash = {speed = 20.0, sink = 5.0, ticks_left = 1, why = "test", impact = null}
	flight.crash_auto_restart = true
	flight._session_after_input()
	_check("a crash restart keeps the airframe and the trims", flight._airframe_offset == airframe and _near(_trims(flight), trimmed, 1.0e-12))
	var reload_note: String = flight.reload()
	_check("F5 reload keeps the airframe and the pilot's trims", reload_note.begins_with("aircraft reloaded")
		and flight._airframe_offset == airframe and _near(_trims(flight), trimmed, 1.0e-12), reload_note)
	_check("F5 reload keeps the pilot's trim in the registry", _near(registry[STIK].pilot_trim, pilot, 1.0e-9), registry[STIK].pilot_trim)
	flight.free()
	var again: Node = _new_flight(STIK)
	_check("the next flight of the session configures", again.setup_out_of_trim(config, 99, registry, STIK), again.out_of_trim_error)
	again.reset()
	_check("the next flight flies the same airframe", again._airframe_offset == airframe)
	_check("the next flight starts with the pilot's trims", _near(_trims(again), trimmed, 1.0e-12), [_trims(again), trimmed])
	again.free()
	var other: Node = _new_flight(STIK)
	other.setup_out_of_trim(_config(true, 80, OutOfTrim.MODE_FIRST_FLIGHT), 99, registry, STIK)
	other.reset()
	_check("a changed intensity rigs a new airframe", other._airframe_offset == OutOfTrim.offsets(OutOfTrim.draw(99, 0), 80, throws))
	_check("a new airframe starts from the starting trim", _trims(other) == _start_trims(other))
	_check("the registry now holds the new airframe", registry[STIK].intensity_percent == 80)
	other.free()
	var every: Node = _new_flight(STIK)
	var before: Dictionary = registry.duplicate(true)
	every.setup_out_of_trim(_config(true, 80, OutOfTrim.MODE_EVERY_FLIGHT), 3, registry, STIK)
	every.reset()
	_check("every flight ignores the remembered airframe", every._airframe_offset == OutOfTrim.offsets(OutOfTrim.draw(3, 0), 80, throws))
	_check("every flight leaves the registry alone", registry == before)
	every.free()


func _test_refused_restart_rolls_back() -> void:
	var flight: Node = _new_flight(STIK)
	flight.setup_out_of_trim(_config(true, 100, OutOfTrim.MODE_EVERY_FLIGHT), 21, {}, STIK)
	flight.reset()
	var airframe: PackedFloat64Array = flight._airframe_offset.duplicate()
	var drawn: int = int(flight._out_of_trim.drawn)
	flight.start_choice = "no-such-start"
	flight.reset()
	_check("a refused restart keeps the flying airframe", flight._airframe_offset == airframe)
	_check("a refused restart does not consume an airframe draw", int(flight._out_of_trim.drawn) == drawn)
	flight.free()


func _test_rudder_trim() -> void:
	var stik: Node = _new_flight(STIK)
	var yaw: float = float(stik.trims.yaw)
	_check("the Stik accepts rudder trim", stik.adjust_rudder_trim(0.005) and is_equal_approx(float(stik.trims.yaw), yaw + 0.005))
	stik.input_enabled = false
	_check("rudder trim follows the same input gate", not stik.adjust_rudder_trim(0.005))
	stik.free()
	var wing: Node = _new_flight(X8)
	_check("the X8 flying wing has no rudder to trim", wing.is_flyable() and not wing.adjust_rudder_trim(0.005))
	wing.setup_out_of_trim(_config(true, 100, OutOfTrim.MODE_EVERY_FLIGHT), 4, {}, X8)
	wing.reset()
	_check("the X8 airframe has roll and pitch tendencies only", wing._airframe_offset[2] == 0.0 and wing._airframe_offset[0] != 0.0 and wing._airframe_offset[1] != 0.0, wing._airframe_offset)
	wing.free()


func _test_checkpoint_replay() -> void:
	var source: Node = _new_flight(STIK)
	source.setup_out_of_trim(_config(true, 100, OutOfTrim.MODE_EVERY_FLIGHT), 3, {}, STIK)
	source.reset()
	_step(source, 30)
	var saved: Dictionary = source.checkpoint()
	_check("an out-of-trim airframe wraps the checkpoint", saved.get("format") == Flight.OUT_OF_TRIM_CHECKPOINT_FORMAT
		and saved.get("airframe_trim_offset") == source._airframe_offset and saved.get("airframe_physics_format") is String, saved.get("format"))
	var replica: Node = _new_flight(STIK)
	_check("a session without the feature restores the airframe", replica.restore_checkpoint(saved) and replica._airframe_offset == source._airframe_offset)
	for _tick in 120:
		var inputs := PackedFloat64Array([0.05, -0.02, 0.01, 0.5])
		source.sim.inputs = inputs.duplicate()
		replica.sim.inputs = inputs.duplicate()
		source.sim.step()
		replica.sim.step()
	_check("the restored airframe replays exactly", var_to_bytes(source.checkpoint()) == var_to_bytes(replica.checkpoint()))
	replica.reset()
	_check("a session without the feature restarts with a true airframe", OutOfTrim.is_zero(replica._airframe_offset)
		and replica.checkpoint().get("format") != Flight.OUT_OF_TRIM_CHECKPOINT_FORMAT and not replica.trace_meta().has("airframe_trim_offset"))
	var zero := saved.duplicate(true)
	zero.airframe_trim_offset = PackedFloat64Array([0.0, 0.0, 0.0])
	_check("a zero airframe offset never wraps a checkpoint", not _new_restore(zero))
	var nested := saved.duplicate(true)
	nested.airframe_physics_format = Flight.OUT_OF_TRIM_CHECKPOINT_FORMAT
	_check("a nested airframe layer is refused", not _new_restore(nested))
	var stray: Dictionary = saved.duplicate(true)
	stray.format = stray.airframe_physics_format
	stray.erase("airframe_physics_format")
	_check("an airframe offset outside its layer is refused", not _new_restore(stray))
	var visual: Dictionary = VisualCheckpoint.read(saved, "test-field")
	_check("visual checkpoints accept the airframe layer", visual.get("ok", false), visual.get("errors", []))
	_check("visual checkpoints refuse a malformed airframe layer", not VisualCheckpoint.read(zero, "test-field").get("ok", false))
	source.free()
	replica.free()


func _new_restore(candidate: Dictionary) -> bool:
	var flight: Node = _new_flight(STIK)
	var restored: bool = flight.restore_checkpoint(candidate)
	flight.free()
	return restored


func _test_preferences() -> void:
	var path: String = ProjectSettings.globalize_path(PREFS)
	DirAccess.remove_absolute(path)
	_check("fresh preferences keep trim practice off", Preferences.load_from(PREFS).out_of_trim_config == OutOfTrim.defaults())
	var prefs: Dictionary = Preferences.load_from(PREFS)
	prefs.out_of_trim_config = _config(true, 80, OutOfTrim.MODE_EVERY_FLIGHT)
	_check("trim practice saves", Preferences.save_to(PREFS, prefs) == OK)
	_check("trim practice round-trips", Preferences.load_from(PREFS).out_of_trim_config == prefs.out_of_trim_config)
	prefs.out_of_trim_config = _config(true, 101, OutOfTrim.MODE_EVERY_FLIGHT)
	_check("invalid trim practice is never saved", Preferences.save_to(PREFS, prefs) == ERR_INVALID_DATA)
	var cfg := ConfigFile.new()
	cfg.load(PREFS)
	cfg.set_value("trim_practice", "config", {"enabled": "yes"})
	cfg.save(PREFS)
	var recovered: Dictionary = Preferences.load_from(PREFS)
	_check("a damaged trim practice entry recovers to the defaults", recovered.out_of_trim_config == OutOfTrim.defaults()
		and "trim practice" in str(recovered.note), recovered.note)
	DirAccess.remove_absolute(path)


func _test_menu_draft() -> void:
	var menu: CanvasLayer = TrimPracticeMenu.new(_config(false, 30, OutOfTrim.MODE_EVERY_FLIGHT))
	root.add_child(menu)
	_check("the dialog opens on the saved choice", menu.get_draft_config() == _config(false, 30, OutOfTrim.MODE_EVERY_FLIGHT))
	_check("intensity and persistence rest while trim practice is off", not menu.intensity_slider.editable
		and menu.first_flight_check.disabled and menu.every_flight_check.disabled)
	menu.enabled_check.button_pressed = true
	_check("enabling wakes the intensity and persistence", menu.intensity_slider.editable and not menu.every_flight_check.disabled)
	menu.intensity_slider.value = 75.0
	_check("slider and percentage stay together", int(menu.intensity_spin.value) == 75)
	menu.first_flight_check.button_pressed = true
	_check("the persistence choices are exclusive", not menu.every_flight_check.button_pressed)
	var emitted: Array = []
	menu.applied.connect(func(config: Dictionary) -> void: emitted.append(config))
	menu._on_apply()
	_check("Apply hands over the draft", emitted.size() == 1 and emitted[0] == _config(true, 75, OutOfTrim.MODE_FIRST_FLIGHT), emitted)
	menu.free()
