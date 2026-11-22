# R7 research witness. Uses synthetic device/key callbacks through unchanged production input, controller and session code.
# Observes the baseline; passing this probe does not mean the observed behavior is repaired.
extends SceneTree

const Session = preload("res://sim/multirotor/session.gd")
const FC = preload("res://physics/multirotor/flight_controller.gd")
const Rates = preload("res://physics/multirotor/rates.gd")
const PilotInput = preload("res://input/multirotor_input.gd")
const Profile = preload("res://input/controller_profile.gd")
const RB = preload("res://physics/rigid_body.gd")
const DT = 1.0 / 240.0

var checks := 0
var fails := 0
var axes: Dictionary = {}
var keys: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

func check(label: String, ok: bool, detail: String = "") -> void:
	checks += 1
	if not ok: fails += 1
	print("%s %s %s" % ["ok" if ok else "FAIL", label, detail])

func cli(expo: int) -> String:
	var text := "# Betaflight / STM32F405 (S405) 4.5.2 Apr 4 2025 / 18:22:18 (024f8e13d) MSP API: 1.46\nrateprofile 0\nset rates_type = BETAFLIGHT\n"
	for axis in ["roll", "pitch", "yaw"]:
		text += "set %s_rc_rate = 100\nset %s_srate = 0\nset %s_expo = %d\nset %s_rate_limit = 1998\n" % [axis, axis, axis, expo if axis == "roll" else 0, axis]
	return text

func run_case(expo: int, stick: float) -> Dictionary:
	axes = {}
	keys = {}
	var imported: Dictionary = Rates.import_cli(cli(expo))
	if not imported.ok:
		return {ok = false, error = imported.errors}
	var prep: Dictionary = Rates.prepare(imported.profile)
	var direct: float = Rates.setpoint_dps(prep.prepared, 0, stick)
	var inp := PilotInput.new()
	inp.read_keys = func() -> Dictionary: return keys.duplicate()
	inp.read_axis = func(_id: int, axis: int) -> float: return float(axes.get(axis, 0.0))
	inp.read_button = func(_id: int, _button: int) -> bool: return false
	inp.radio.confirmed_gamepad_connection = func(_id: int) -> bool: return true
	var profile: Dictionary = Profile.defaults("gamepad", "mode2")
	inp.connect_device(7, {name = "Synthetic pad", known = true}, profile)
	# Full-range option is pilot-selectable; the source reports that option to the session.
	inp.cycle_throttle_limit()
	inp.cycle_throttle_limit()
	var s := Session.new()
	root.add_child(s)
	if not s.prepare({}, {rates = imported.profile, throttle_policy = inp.throttle_policy(), throttle_limit = inp.throttle_limit(),
			source_generation = inp.source_generation}):
		var message: String = s.load_error
		s.queue_free()
		return {ok = false, error = message}
	s.resume()
	var sample: Dictionary = inp.sample(DT, true)
	var ok: bool = s.tick_once(sample.pilot)
	keys = {arm = true, mode = true} # Angle -> Acro; arm at zero throttle
	sample = inp.sample(DT, true)
	ok = s.tick_once(sample.pilot) and ok
	keys = {}
	axes[1] = -1.0 # gamepad Mode 2 throttle up (inverted axis)
	for i in 240:
		sample = inp.sample(DT, true)
		if not s.tick_once(sample.pilot):
			ok = false
			break
	axes[1] = 0.0
	var dz: float = float(profile.roll.deadzone)
	axes[2] = signf(stick) * (dz + absf(stick) * (1.0 - dz))
	for i in 240:
		sample = inp.sample(DT, true)
		if not s.tick_once(sample.pilot):
			ok = false
			break
	var answer := {ok = ok and s.fault_reason.is_empty() and s.crash.is_empty() and s.sim.modes[FC.MODE_MOTOR] == FC.MOTOR_ARMED,
		import_ok = imported.ok, validation_ok = Rates.validate(imported.profile).ok,
		data_id = s.source_sha256, profile_id = prep.prepared.identity, tick = s.sim.tick, mode = s.sim.modes[FC.MODE_FLIGHT],
		pilot = sample.pilot, direct_dps = direct, setpoint_dps = rad_to_deg(s.sim.aux[FC.AUX_SETPOINT]),
		body_rate_dps = rad_to_deg(s.sim.state[RB.RATE]), altitude = -s.sim.state[RB.POS + 2]}
	s.queue_free()
	return answer

func _run() -> void:
	var zero := run_case(0, 0.5)
	var hundred := run_case(100, 0.5)
	var bad_positive := run_case(200, 0.5)
	var bad_negative := run_case(200, -0.5)
	print("R7_RATES ", JSON.stringify({case_name = "zero", result = zero}, "", true, true))
	print("R7_RATES ", JSON.stringify({case_name = "hundred", result = hundred}, "", true, true))
	print("R7_RATES ", JSON.stringify({case_name = "bad_positive", result = bad_positive}, "", true, true))
	print("R7_RATES ", JSON.stringify({case_name = "bad_negative", result = bad_negative}, "", true, true))
	check("importer and stock pad sessions accept all four profiles/tapes", zero.ok and hundred.ok and bad_positive.ok and bad_negative.ok
		and zero.import_ok and hundred.import_ok and bad_positive.import_ok and bad_positive.validation_ok)
	check("verified synthetic gamepad supplies +0.5 and -0.5 pre-expo in Acro", absf(bad_positive.pilot[0] - 0.5) < 1e-12
		and absf(bad_negative.pilot[0] + 0.5) < 1e-12 and bad_positive.mode == FC.FLIGHT_ACRO and bad_negative.mode == FC.FLIGHT_ACRO)
	check("expo 0 positive half stick yields +100 deg/s", absf(zero.direct_dps - 100.0) < 1e-9 and absf(zero.setpoint_dps - 100.0) < 1e-6 and zero.body_rate_dps > 0.0)
	check("expo 100 positive half stick yields +12.5 deg/s", absf(hundred.direct_dps - 12.5) < 1e-9 and absf(hundred.setpoint_dps - 12.5) < 1e-6 and hundred.body_rate_dps > 0.0)
	check("expo 200 positive half stick yields -75 deg/s", absf(bad_positive.direct_dps + 75.0) < 1e-9 and absf(bad_positive.setpoint_dps + 75.0) < 1e-6 and bad_positive.body_rate_dps < 0.0)
	check("expo 200 negative half stick yields +75 deg/s", absf(bad_negative.direct_dps - 75.0) < 1e-9 and absf(bad_negative.setpoint_dps - 75.0) < 1e-6 and bad_negative.body_rate_dps > 0.0)
	var curve: Dictionary = Rates.prepare(Rates.import_cli(cli(200)).profile)
	check("expo 200 positive full stick gives +200 deg/s (reversal is partial only)", absf(Rates.setpoint_dps(curve.prepared, 0, 1.0) - 200.0) < 1e-9)
	var invalid_actual: Dictionary = Rates.default_profile()
	invalid_actual.axes.roll.expo = 200
	check("ACTUAL expo 200 is already refused", not Rates.validate(invalid_actual).ok)
	check("incomplete CLI profile still refuses", not Rates.import_cli(cli(200).replace("set roll_srate = 0\n", "")).ok)
	print("R7 rates: %d checks, %d failed" % [checks, fails])
	quit(1 if fails else 0)
