# HELI-07: finite powerplant proxy, power cap, loss and zero-speed behavior.
extends SceneTree

const Drive = preload("res://physics/rotorcraft/drive.gd")
const Fixture = preload("res://tests/test_heli_flight.gd")
var checks: int = 0
var failures: int = 0


func check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", label)


func close(label: String, actual: float, expected: float, tolerance: float = 1.0e-12) -> void:
	check(label, is_finite(actual) and absf(actual - expected) <= tolerance * maxf(1.0, absf(expected)))


func _initialize() -> void:
	var parameters: Dictionary = Fixture.drive_parameters()
	var prepared: Dictionary = Drive.prepare(parameters)
	check("aircraft drive parameters prepare", prepared.ok)
	if not prepared.ok:
		quit(1)
		return
	var model: Dictionary = prepared.model
	var nominal: Dictionary = Drive.evaluate(model, 167.0, 0.85)
	check("nominal driven state evaluates", nominal.ok)
	close("engine speed follows declared gear ratio", nominal.engine_speed_rad_s, 8.3 * 167.0)
	close("shaft power is delivered torque times engine speed", nominal.engine_power_w,
		nominal.engine_torque_nm * nominal.engine_speed_rad_s)
	close("main power includes gear efficiency", nominal.main_drive_power_w,
		0.9 * nominal.engine_power_w)
	close("main torque includes gear ratio and efficiency", nominal.main_drive_torque_nm,
		0.9 * 8.3 * nominal.engine_torque_nm)
	var ramped: Dictionary = Drive.evaluate(model, 167.0, 0.85, true, false, 0.25)
	check("startup ramp applies after the governor", ramped.ok and ramped.drive_scale == 0.25)
	close("ramp scales delivered engine torque", ramped.engine_torque_nm, 0.25 * nominal.engine_torque_nm)
	close("ramp scales geared main torque", ramped.main_drive_torque_nm, 0.25 * nominal.main_drive_torque_nm)
	var disarmed: Dictionary = Drive.evaluate(model, 0.0, 0.0, true, false, 0.0)
	check("zero ramp suppresses governor startup torque", disarmed.ok and disarmed.engine_torque_nm == 0.0
		and disarmed.main_drive_torque_nm == 0.0)
	var capped_params: Dictionary = parameters.duplicate(true)
	capped_params.engine_power_max_w = 500.0
	var capped_model: Dictionary = Drive.prepare(capped_params).model
	var capped: Dictionary = Drive.evaluate(capped_model, 167.0, 1.0, false)
	check("power limited state evaluates and reports active cap", capped.ok and capped.power_limited)
	close("engine shaft power reaches but does not exceed cap", capped.engine_power_w, 500.0)
	check("engine torque obeys its independent maximum", capped.engine_torque_nm <= capped_model.engine_torque_max_nm)
	var capped_ramp: Dictionary = Drive.evaluate(capped_model, 167.0, 1.0, false, false, 0.5)
	check("soft-start ramp remains downstream of the power cap", capped_ramp.ok and capped_ramp.power_limited)
	close("ramped engine power is half the capped output", capped_ramp.engine_power_w, 250.0)
	var stopped: Dictionary = Drive.evaluate(model, 0.0, 1.0, false)
	check("stopped rotor uses finite startup torque with no omega floor", stopped.ok
		and is_finite(stopped.engine_torque_nm) and stopped.engine_power_w == 0.0)
	close("stopped Coulomb loss cannot reverse the drive", stopped.net_main_torque_nm,
		stopped.main_drive_torque_nm - minf(stopped.main_drive_torque_nm, model.shaft_loss_torque_nm))
	var hold: Dictionary = Drive.evaluate(model, 167.0, 1.0, true, true)
	check("zero-drive hold has an explicit still-lumped proxy label",
		hold.ok and hold.zero_drive_hold_proxy and hold.one_speed_lump_preserved)
	check("hold zeros engine power and drive torque", hold.engine_power_w == 0.0 and hold.main_drive_torque_nm == 0.0)
	close("hold retains declared running shaft losses", hold.net_main_torque_nm, -hold.shaft_loss_torque_nm)
	check("negative rotor speed is refused rather than hidden", not Drive.evaluate(model, -0.01, 1.0).ok)
	var unknown: Dictionary = parameters.duplicate(true)
	unknown["rpm_floor"] = 20.0
	check("undeclared runtime defaults are refused", not Drive.prepare(unknown).ok)
	print("HELI-07 finite drive proxy: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)
