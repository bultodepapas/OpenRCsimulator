extends SceneTree

const Flight := preload("res://main.gd")
const Session := preload("res://sim/flight_session.gd")
const Profile := preload("res://input/controller_profile.gd")
const Rig := preload("res://render/camera/camera_rig.gd")
const Smoke := preload("res://render/smoke/exhaust.gd")
var checks := 0
var failures := 0

func check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
		printerr("FAIL ", label)

func _initialize() -> void:
	var flight := Flight.new()
	var session := Session.new()
	session.physics_enabled = false
	session.input_enabled = false
	session.setup()
	session.sim.set_paused(false)
	session.radio.connect_device(42, {"known": true, "name": "Synthetic Xbox"}, Profile.defaults())
	flight.session = session
	var camera := Camera3D.new()
	flight._rig = Rig.new(camera, 1.5)
	for view in ["chase", "orbit", "pilot"]:
		check("direct camera " + view, flight.controller_action("camera_" + view) and flight._rig.view == view)
	flight.controller_action("camera_previous")
	check("previous wraps camera list", flight._rig.view == "closeup")
	flight.controller_action("camera_cycle")
	check("next retains existing cycle", flight._rig.view == "pilot")
	flight.controller_action("camera_zoom_in")
	check("zoom in reaches real camera rig", flight._rig.pilot_zoom < 1.0)
	flight.controller_action("camera_zoom_out")
	check("zoom out restores reciprocal step", is_equal_approx(flight._rig.pilot_zoom, 1.0))
	flight.controller_action("camera_auto_zoom")
	check("auto zoom toggles real camera policy", not flight._rig.auto_zoom)
	flight.controller_action("camera_zoom_in")
	flight.controller_action("view_reset")
	check("view reset still works", flight._rig.pilot_zoom == 1.0)
	flight._night_kit = Node3D.new()
	flight._night_kit.set_meta("mode", "all")
	flight.controller_action("lights_cycle")
	check("lights use existing night kit modes", flight._night_kit.get_meta("mode") == "nav")
	flight.controller_action("lights_cycle")
	check("second lights action selects off", flight._night_kit.get_meta("mode") == "off")

	var before_inputs: PackedFloat64Array = session.sim.inputs.duplicate()
	var before_state: PackedFloat64Array = session.sim.state.duplicate()
	var before_aux: PackedFloat64Array = session.sim.aux.duplicate()
	flight.controller_action("flaps_cycle")
	check("flap request exposes intermediate position", session.radio.auxiliary_amount("flaps") == 0.5)
	check("flap notice declares missing physics", flight._note.contains("50%") and flight._note.contains("not simulated"))
	flight.controller_action("gear_toggle")
	check("fixed landing gear is explained without creating an AUX request", session.radio.auxiliary_amount("gear") == 0.0 and flight._note.contains("fixed"))
	check("requests do not pretend to alter aircraft physics", session.sim.inputs == before_inputs and session.sim.state == before_state and session.sim.aux == before_aux)
	flight.controller_action("smoke_toggle")
	check("missing smoke is explained without changing pump", session.radio.smoke_amount() == 0.0 and flight._note.contains("not available"))
	flight._smoke = Smoke.new()
	flight._smoke._anchor = {"pump": false}
	flight.controller_action("smoke_toggle")
	check("exhaust without pump cannot enable smoke", session.radio.smoke_amount() == 0.0)
	flight._smoke._anchor = {"pump": true}
	flight.controller_action("smoke_toggle")
	check("supported smoke toggle reaches pump request", session.radio.smoke_amount() == 1.0)
	session.sim.set_paused(true)
	flight.controller_action("smoke_toggle")
	flight.controller_action("flaps_cycle")
	check("paused semantic actions do not queue", session.radio.smoke_amount() == 1.0 and session.radio.auxiliary_amount("flaps") == 0.5)
	session.hold("test menu")
	check("actual session hold clears auxiliary requests", session.radio.smoke_amount() == 0.0 and session.radio.auxiliary_amount("flaps") == 0.0)
	check("unknown semantic action is refused", not flight.controller_action("unimplemented_action"))
	session.release("test menu")
	session.radio.connect_device(42, {"known": false, "name": "EdgeTX synthetic"}, Profile.defaults("radio", "radio_custom"))
	session.radio.auxiliary_action("smoke_toggle")
	check("radio calibration immediately clears active AUX", session.start_calibration() and session.radio.smoke_amount() == 0.0)
	session._poll_controller()
	check("calibration polling cannot re-enable AUX", not session.radio.auxiliary_action("smoke_toggle") and session.radio.smoke_amount() == 0.0)
	session.cancel_calibration()
	var gear_session := Session.new()
	gear_session.physics_enabled = false
	gear_session.input_enabled = false
	gear_session.setup("res://data/aircraft/sebart_avanti_s_a200.json", "sebart-avanti-s-a200-p100rx")
	gear_session.sim.set_paused(false)
	flight.session = gear_session
	check("Avanti gear controller action deploys the gear", flight.controller_action("gear_toggle") and bool(gear_session.gear_state().target_down))
	var target_before_pause: bool = bool(gear_session.gear_state().target_down)
	check("brake test fixture accepts a held demand", gear_session.set_wheel_brake(1.0))
	gear_session.sim.set_paused(true)
	flight.controller_action("gear_toggle")
	check("paused gear action does not queue", bool(gear_session.gear_state().target_down) == target_before_pause)
	var brake_release := InputEventKey.new()
	brake_release.physical_keycode = KEY_B
	brake_release.pressed = false
	flight._input(brake_release)
	check("B key release clears wheel braking during pause", float(gear_session.gear_state().brake) == 0.0)
	flight._smoke.free()
	flight._night_kit.free()
	flight.free()
	camera.free()
	session.free()
	gear_session.free()
	print("controller flight actions: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
