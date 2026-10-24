## FUEL-10: the accepted finite-fuel sample reaches the Flight Data row and reserve warning/audio path.
## Run: godot --headless --path . --audio-driver Dummy --script res://tests/test_overlay_fuel_flight.gd
extends SceneTree

const Flight := preload("res://sim/flight_session.gd")
const OverlayManager := preload("res://render/overlays/overlay_manager.gd")
const GLOW := "res://data/aircraft/stik_glow_61fx_2t.json"

var _checks := 0
var _failed := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	if not ok:
		_failed += 1
		printerr("FAIL %s %s" % [label, detail])


func _initialize() -> void:
	TranslationServer.set_locale("en")
	await process_frame
	var session: Node = Flight.new()
	session.input_enabled = false
	session.setup(GLOW)
	session.reset()
	var manager: CanvasLayer = OverlayManager.new({}, "en")
	root.add_child(manager)
	await process_frame
	var warnings: Array = []
	manager.fuel_reserve_warning_requested.connect(func(sample: Dictionary) -> void: warnings.append(sample))
	var initial: Dictionary = session.mass_properties()
	_check("the production session provides a finite accepted tank sample",
		initial.get("ok", false) and initial.get("finite_fuel", false) and initial.get("tick", -1) == session.sim.tick
		and is_equal_approx(initial.get("time_s", NAN), session.sim.time()), str(initial))
	var snapshot: Dictionary = OverlayManager.snapshot(session, {}, 1.5, false, 0.0)
	_check("the production snapshot forwards the exact same mass sample", snapshot.get("mass_sample", {}) == initial)
	manager.refresh_numbers(snapshot)
	var expected := "%d mL · %d %%" % [roundi(float(initial.volume_ml)), roundi(float(initial.fill_fraction) * 100.0)]
	_check("real finite-fuel aircraft displays accepted volume and fill", manager.frames.flight.values.fuel.visible
		and manager.frames.flight.values.fuel.text == expected, manager.frames.flight.values.fuel.text)
	_check("real tank reserve basis appears in the row tooltip", manager.frames.flight.values.fuel.get_parent()
		.get_child(manager.frames.flight.values.fuel.get_index() - 1).tooltip_text.contains("reserve"))
	manager.set_preset("instruments")
	manager.refresh_numbers(snapshot)
	_check("player fuel widget reads the production sample rather than fixture-only keys",
		manager.frames.fuel.value_label.text == str(roundi(float(initial.fill_fraction) * 100.0))
		and manager.frames.fuel.left_value.text == String.num(float(initial.volume_ml), 0) + " mL"
		and manager.frames.fuel.right_value.text == String.num(float(initial.fuel_remaining_kg) * 1000.0, 0) + " g")
	_check("engine widget reads production RPM", manager.frames.engine.value_label.text == str(roundi(snapshot.rpm)))
	var original_roll: float = session.trims.roll
	snapshot.trims.roll = 0.123
	_check("snapshot trim values are detached from the flight session", session.trims.roll == original_roll)
	var tanks: Array = session.aircraft.model.get("fuel_system", {}).get("tanks", [])
	_check("fixture has one authored finite tank", tanks.size() == 1)
	if tanks.size() == 1:
		var tank: Dictionary = tanks[0]
		var reserve: float = float(tank.get("reserve_kg", float(tank.unusable_kg) + 0.1 * float(tank.capacity_kg)))
		session.sim.continuous[1] = reserve + 0.001
		session.sim.set_paused(false)
		var above: Dictionary = OverlayManager.snapshot(session, {}, 1.5, false, 0.0)
		manager.refresh_numbers(above)
		session.sim.continuous[1] = reserve - 0.001
		var below: Dictionary = OverlayManager.snapshot(session, {}, 1.5, false, 0.0)
		manager.refresh_numbers(below)
		_check("production sample at reserve raises the estimated reserve chip",
			below.mass_sample.low_fuel and below.mass_sample.reserve_estimated
			and manager.frames.warnings.codes.has("fuel_reserve_estimated"))
		_check("production crossing emits exactly one semantic cue carrying the accepted sample",
			warnings.size() == 1 and warnings[0] == below.mass_sample)
		_check("production path plays the existing warning asset on Master",
			manager.get("_fuel_warning_player").playing and manager.get("_fuel_warning_player").bus == &"Master")
	var warning_player: AudioStreamPlayer = manager.get("_fuel_warning_player")
	var warning_playback: AudioStreamPlayback = warning_player.get_stream_playback()
	var warning_playback_ref: WeakRef = weakref(warning_playback) if warning_playback != null else null
	warning_playback = null
	session.free()
	manager.queue_free()
	await process_frame
	# AudioServer releases the playback after the removed player is observed by its mix thread.
	if warning_playback_ref != null:
		var release_deadline_msec := Time.get_ticks_msec() + 500
		while warning_playback_ref.get_ref() != null and Time.get_ticks_msec() < release_deadline_msec:
			await create_timer(0.02).timeout
		_check("warning playback is released after overlay teardown", warning_playback_ref.get_ref() == null,
			"AudioServer retained the playback after the bounded drain")
	print("overlay fuel flight: %d checks, %d failed" % [_checks, _failed])
	quit(1 if _failed else 0)
