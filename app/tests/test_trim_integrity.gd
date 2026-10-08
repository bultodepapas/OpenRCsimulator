# D4-R2: reject false numerical convergence without changing valid flight trims.
extends SceneTree

const AD = preload("res://physics/aircraft_data.gd")
const Trim = preload("res://physics/trim.gd")
const Scenarios = preload("res://sim/scenarios.gd")
const Modes = preload("res://physics/flight_modes.gd")
const G: float = 9.80665
const RESULT_KEYS: Array[String] = ["ok", "message", "mode", "V", "alpha", "beta", "gamma", "throttle",
	"thrust", "rpm", "elevator", "aileron", "rudder", "pitch_command", "roll_command", "yaw_command",
	"state", "residual", "iterations"]
var checks: int = 0
var failures: int = 0


func check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
		printerr("FAIL ", label)


func refused(label: String, result: Dictionary) -> void:
	check(label + " refuses with reason", not result.ok and not result.message.is_empty())
	for key in RESULT_KEYS:
		check(label + " retains " + key, result.has(key))


func finite_result(result: Dictionary) -> bool:
	for value in result.values():
		if typeof(value) == TYPE_FLOAT and not is_finite(value):
			return false
	for value in result.state:
		if not is_finite(value):
			return false
	return true


func trim_contract() -> void:
	var model: Dictionary = AD.load_file(Scenarios.AIRCRAFT).model
	var model_before: PackedByteArray = var_to_bytes(model)
	var throws: Dictionary = model.controls.throw_rad
	var control: Dictionary = Trim.solve("level", 15.0, model, G, throws)
	check("positive control converges and is finite", control.ok and finite_result(control) and control.residual < 1e-8)
	for bad in [NAN, INF, -INF]:
		refused("invalid speed " + str(bad), Trim.solve("level", bad, model, G, throws))
		refused("invalid gravity " + str(bad), Trim.solve("level", 15.0, model, bad, throws))
	# Finite speed still overflows dynamic pressure; finite-input screening alone is insufficient.
	refused("finite overflowing speed", Trim.solve("level", 1e160, model, G, throws))
	for bad in [0.0, -1.0]:
		refused("nonpositive speed", Trim.solve("level", bad, model, G, throws))
	refused("negative gravity", Trim.solve("level", 15.0, model, -1.0, throws))
	refused("unsupported mode", Trim.solve("hover", 15.0, model, G, throws))
	for axis in ["elevator", "aileron", "rudder"]:
		for bad in [NAN, INF, 0.0, -1.0, "0.2", true]:
			var limits: Dictionary = throws.duplicate()
			limits[axis] = bad
			refused("invalid throw " + axis, Trim.solve("level", 15.0, model, G, limits))
		var missing: Dictionary = throws.duplicate()
		missing.erase(axis)
		refused("missing throw " + axis, Trim.solve("level", 15.0, model, G, missing))
	var poisoned: Dictionary = model.duplicate(true)
	poisoned.aero.Cm0 = NAN
	refused("nonfinite model residual", Trim.solve("level", 15.0, poisoned, G, throws))
	check("level scenario propagates refusal", not Scenarios.trimmed_level_across_view(model, NAN, throws).ok)
	check("glide scenario propagates refusal", not Scenarios.trimmed_glide_across_view(model, NAN, throws).ok)
	check("modal analysis does not linearize a false trim", not Modes.analyze(model, 15.0, NAN).ok)
	var impossible: Dictionary = Trim.solve("level", 5.0, model, G, throws)
	check("physical nonconvergence still reports failure", not impossible.ok and not impossible.message.is_empty())
	check("failed solves do not mutate the model", var_to_bytes(model) == model_before)
	check("valid result repeats exactly after failures", var_to_bytes(Trim.solve("level", 15.0, model, G, throws)) == var_to_bytes(control))


func linear_contract() -> void:
	var matrix: Array = [PackedFloat64Array([0.0, 2.0]), PackedFloat64Array([3.0, 1.0])]
	var rhs: PackedFloat64Array = PackedFloat64Array([4.0, 5.0])
	var before: PackedByteArray = var_to_bytes([matrix, rhs])
	check("pivoting known answer", Trim.solve_linear(matrix, rhs) == PackedFloat64Array([1.0, 2.0]))
	check("linear solver keeps inputs detached", var_to_bytes([matrix, rhs]) == before)
	for bad in [NAN, INF, -INF]:
		for row in 2:
			for col in 2:
				var a: Array = matrix.duplicate(true)
				a[row][col] = bad
				check("nonfinite matrix entry", Trim.solve_linear(a, rhs).is_empty())
			var b: PackedFloat64Array = rhs.duplicate()
			b[row] = bad
			check("nonfinite RHS entry", Trim.solve_linear(matrix, b).is_empty())
	for bad in [[], [PackedFloat64Array([1, 2])], [PackedFloat64Array([1]), PackedFloat64Array([2])],
			[PackedFloat64Array([1, 2, 3]), PackedFloat64Array([2, 1, 3])],
			[PackedFloat64Array([1, 2]), PackedFloat64Array([2, 1]), PackedFloat64Array([1, 2])],
			[[1.0, 2.0], [2.0, 1.0]], [null, null]]:
		check("malformed square matrix", Trim.solve_linear(bad, rhs).is_empty())
	check("empty system refused", Trim.solve_linear([], PackedFloat64Array()).is_empty())
	check("singular system refused", Trim.solve_linear([PackedFloat64Array([1, 2]), PackedFloat64Array([2, 4])], rhs).is_empty())
	check("elimination overflow refused", Trim.solve_linear([PackedFloat64Array([1e308, 1e308]), PackedFloat64Array([-1e308, 1e308])], rhs).is_empty())
	check("RHS elimination overflow refused", Trim.solve_linear([PackedFloat64Array([1, 0]), PackedFloat64Array([-1, 1])], PackedFloat64Array([1e308, 1e308])).is_empty())
	check("back substitution overflow refused", Trim.solve_linear([PackedFloat64Array([1e-13])], PackedFloat64Array([1e308])).is_empty())
	check("back substitution accumulation overflow refused", Trim.solve_linear([PackedFloat64Array([1, 1e308]), PackedFloat64Array([0, 1])], PackedFloat64Array([-1e308, 2])).is_empty())


func _initialize() -> void:
	# --repro keeps the baseline run bounded: its old unsupported-mode assert would stop execution.
	if "--repro" in OS.get_cmdline_user_args():
		var model: Dictionary = AD.load_file(Scenarios.AIRCRAFT).model
		check("valid baseline control", Trim.solve("level", 15.0, model, G, model.controls.throw_rad).ok)
		refused("NaN gravity", Trim.solve("level", 15.0, model, NAN, model.controls.throw_rad))
		check("NaN linear RHS", Trim.solve_linear([PackedFloat64Array([1.0])], PackedFloat64Array([NAN])).is_empty())
	else:
		trim_contract()
		linear_contract()
	print("D4-R2 trim integrity: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)
