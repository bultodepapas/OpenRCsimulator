# VAL-3 offline adapter: read current model/mode code; never change app data or simulation state on disk.
extends SceneTree

const Aircraft = preload("res://physics/aircraft_data.gd")
const Modes = preload("res://physics/flight_modes.gd")
const ModeTests = preload("res://tests/test_modes.gd")
const RHO: float = 1.225
const G: float = 9.80665


func fail(message: String) -> void:
	printerr("VAL-3: ", message)
	quit(1)


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 2:
		fail("expected request.json and output.json")
		return
	var request: Variant = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	if not request is Dictionary or not request.get("cases") is Array:
		fail("invalid request")
		return
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/aircraft/jensen_ugly_stik_60.json"))
	var scale: float = float(request.get("clp_scale", 1.0))
	if not is_finite(scale) or scale <= 0:
		fail("invalid Clp scale")
		return
	raw.aero.coefficients.Clp.value *= scale # in-memory mutation probe only; normal requests use 1.
	var data: Dictionary = Aircraft.validate_and_derive(raw)
	if not data.ok:
		fail(str(data.errors))
		return
	var model: Dictionary = data.model
	var output: Dictionary = {format = "openrc-modal-samples v1", godot = Engine.get_version_info().string,
		clp_scale = scale, model_id = model.id, mass_kg = model.mass_kg,
		span_m = model.reference.b, chord_m = model.reference.c, area_m2 = model.reference.S,
		warnings = data.warnings, cases = {}, regression_15_mps = {}}
	for case: Dictionary in request.cases:
		var speed: float = float(case.get("speed_mps", 0.0))
		if case.method == "same_cl":
			speed = sqrt(2.0 * float(model.mass_kg) * G / (RHO * float(model.reference.S) * float(case.reference_cl)))
		if not is_finite(speed) or speed <= 0:
			fail("invalid comparison speed")
			return
		var modes: Dictionary = Modes.analyze(model, speed)
		if not modes.ok:
			fail(str(modes.message))
			return
		output.cases[case.id] = {speed_mps = speed, lift_coefficient = 2.0 * float(model.mass_kg) * G / (RHO * speed * speed * float(model.reference.S)),
			sp_wn = TAU * modes.short_period.f_hz, sp_zeta = modes.short_period.zeta,
			roll_rate = 1.0 / modes.roll_tau, dr_wn = TAU * modes.dutch_roll.f_hz, dr_zeta = modes.dutch_roll.zeta,
			trim = {alpha_rad = modes.trim.alpha, throttle = modes.trim.throttle},
			projection_note = modes.projection_note}
	# This is a software regression check, separate from comparisons with other airframes.
	if scale == 1.0:
		var baseline: Dictionary = Modes.analyze(model, 15.0)
		if not baseline.ok:
			fail(str(baseline.message))
			return
		var actual: Array = [baseline.short_period.f_hz, baseline.short_period.zeta, baseline.phugoid.f_hz,
			baseline.phugoid.zeta, baseline.roll_tau, baseline.dutch_roll.f_hz, baseline.dutch_roll.zeta,
			-1.0 / baseline.spiral_tau, baseline.downwash_lag_root]
		var expected: Array = ModeTests.BANDS[15.0]
		for index: int in expected.size():
			if not is_finite(actual[index]) or absf(actual[index] - expected[index]) > ModeTests.TOL * absf(expected[index]):
				fail("15 m/s mode regression mismatch at index %d" % index)
				return
		output.regression_15_mps = {actual = actual, expected = expected, relative_tolerance = ModeTests.TOL}
	var file: FileAccess = FileAccess.open(args[1], FileAccess.WRITE)
	if file == null:
		fail("cannot open output")
		return
	file.store_string(JSON.stringify(output, "\t", true, true) + "\n")
	file.flush()
	var error: Error = file.get_error()
	file.close()
	if error != OK:
		fail("cannot write output")
		return
	quit(0)
