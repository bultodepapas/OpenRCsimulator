extends "res://tests/avanti_pullup_base.gd"

const AD := preload("res://physics/aircraft_data.gd")
const KeyboardInput := preload("res://input/keyboard.gd")
var checks := 0
var failures := 0

func check(label: String, valid: bool) -> void:
	checks += 1
	if not valid:
		failures += 1
		printerr("FAIL ", label)

func _initialize() -> void:
	for rate in [120, 240, 480]:
		var x := 0.0
		for i in rate / 2:
			x = Commands.keyboard_pitch(x, 1.0, 1.0 / rate, 1.0, 0.25)
		check("half stick after half second at %d Hz" % rate, absf(x - 0.5) < 1e-12)
		for i in rate / 2:
			x = Commands.keyboard_pitch(x, 1.0, 1.0 / rate, 1.0, 0.25)
		check("full travel retained at %d Hz" % rate, absf(x - 1.0) < 1e-12)
		for i in rate / 4:
			x = Commands.keyboard_pitch(x, 0.0, 1.0 / rate, 1.0, 0.25)
		check("release unloads in quarter second at %d Hz" % rate, absf(x) < 1e-12)
	check("reversal centers first, then builds opposite input", absf(Commands.keyboard_pitch(0.4, -1.0, 0.3, 1.0, 0.25) + 0.2) < 1e-12)
	check("signed symmetry", absf(Commands.keyboard_pitch(-0.4, 1.0, 0.3, 1.0, 0.25) - 0.2) < 1e-12)
	check("partial return stops exactly at target", Commands.keyboard_pitch(0.4, 0.2, 0.3, 1.0, 0.25) == 0.2)
	var c := {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.5}
	var raw_input := {roll = 1.0, pitch = 1.0, yaw = 1.0, throttle = 1.0}
	var old: Dictionary = Commands.step_commands(c, raw_input, 0.25)
	var revised: Dictionary = Commands.step_commands(c, raw_input, 0.25, {pitch_press_time = 1.0, pitch_release_time = 0.25})
	check("legacy/full command path retained", old.pitch == 1.0)
	check("only pitch virtual-stick rate changes", revised.pitch == 0.25 and revised.roll == old.roll and revised.yaw == old.yaw and revised.throttle == old.throttle)
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/aircraft/sebart_avanti_s_a200.json"))
	check("new aircraft schema loads", AD.validate_and_derive(source).ok)
	for bad in [0.0, -0.1, 6.0, "1.0", null]:
		var invalid := source.duplicate(true)
		invalid.controls.keyboard.pitch_press_time.value = bad
		check("invalid keyboard time refused", not AD.validate_and_derive(invalid).ok)
	var missing := source.duplicate(true)
	missing.controls.keyboard.erase("pitch_release_time")
	check("partial keyboard response refused", not AD.validate_and_derive(missing).ok)
	var unit := source.duplicate(true)
	unit.controls.keyboard.pitch_press_time.unit = "deg"
	check("incorrect response units refused", not AD.validate_and_derive(unit).ok)
	var unknown := source.duplicate(true)
	unknown.controls.keyboard.press_rate = unknown.controls.keyboard.pitch_press_time
	check("unknown keyboard field refused", not AD.validate_and_derive(unknown).ok)
	var no_rates := source.duplicate(true)
	no_rates.controls.erase("rates")
	check("response requires declared normal rates", not AD.validate_and_derive(no_rates).ok)
	# Same physical airframe: ordinary key taps recover; a held endpoint can still exceed critical AoA.
	for speed in [29.0, 45.0, 60.0]:
		var recovery := run_case(speed, -1.0)
		check("key pulses recover 45-degree dive at %.0f m/s" % speed, recovery.completed and recovery.recovered_s > 0.0 and recovery.recovered_s < 3.0)
		check("recovery remains attached at %.0f m/s" % speed, recovery.peak_stall_weight < 0.1)
	var tap := run_case(45.0, 0.5)
	check("half-second pull no longer over-rotates into stall", tap.completed and tap.peak_alpha_deg < 9.0 and tap.peak_stall_weight < 0.1)
	var held := run_case(45.0, 2.0)
	check("two-second over-pull crosses the model stall onset while held",
		held.completed and held.first_stall_s > 0.0 and held.first_stall_s < 2.0 and held.peak_stall_weight >= 0.5)
	# VAL-AUD-R02 changes the response, not keyboard authority. After the one-second
	# virtual-stick ramp, two more seconds at the endpoint still cause deep separation.
	# Keep the original >0.9 criterion and require the event before command release.
	var sustained := run_case(45.0, 3.0)
	check("sustained endpoint reaches deep model separation before release",
		sustained.completed and sustained.peak_stall_weight > 0.9
			and sustained.first_deep_separation_s > 0.0 and sustained.first_deep_separation_s < 3.0)
	# Session sampling activates it only for keyboard normal mode; full profile remains the documented override.
	var session := Flight.new()
	session.setup("res://data/aircraft/sebart_avanti_s_a200.json", "sebart-avanti-s-a200-p100rx")
	root.add_child(session)
	session.read_raw = func() -> Dictionary: return {roll = 0.0, pitch = 1.0, yaw = 0.0, throttle = 0.0}
	for profile in ["full", "normal"]:
		session.rate_profile = profile
		session.reset()
		for i in 60: session._physics_process(session.sim.dt())
		check("keyboard sampler respects %s profile" % profile, absf(session.commands.pitch - (1.0 if profile == "full" else 0.25)) < 1e-12)
		session.reset()
		check("reset centers virtual stick and retains solved trim", session.commands.pitch == 0.0 and session.trims.pitch == session.start.pitch_command)
	session.read_raw = func() -> Dictionary: return KeyboardInput.read_raw()
	var down := InputEventKey.new()
	down.keycode = KEY_DOWN
	down.physical_keycode = KEY_DOWN
	down.pressed = true
	Input.parse_input_event(down)
	Input.flush_buffered_events()
	session._physics_process(session.sim.dt())
	check("physical Down key enters gradual pitch sampler", session.raw.pitch == 1.0 and absf(session.commands.pitch - session.sim.dt()) < 1e-12)
	var released := down.duplicate()
	released.pressed = false
	Input.parse_input_event(released)
	Input.flush_buffered_events()
	session._physics_process(session.sim.dt())
	check("physical key release unloads virtual stick", session.raw.pitch == 0.0 and session.commands.pitch == 0.0)
	session.free()
	print("AV-17-R1 keyboard and dive recovery: %d checks, %d failed" % [checks, failures])
	quit(0 if failures == 0 else 1)
