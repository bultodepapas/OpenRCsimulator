extends SceneTree

const AircraftData := preload("res://physics/aircraft_data.gd")
const Propulsion := preload("res://physics/propulsion.gd")
const Trim := preload("res://physics/trim.gd")

const TURBO_PACK_PATH := "res://data/aircraft/battery/turbo_lumber_evolution_4s_pack.json"
const G := 9.80665
const RHO := 1.225

var _checks := 0
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var loaded: Dictionary = AircraftData.load_file(TURBO_PACK_PATH)
	_check("Turbo Lumber pack data loads", loaded.get("ok", false), str(loaded.get("errors", [])))
	if not loaded.get("ok", false):
		_finish()
		return
	var model: Dictionary = loaded.model
	_check("Turbo Lumber pack uses electric propulsion", Propulsion.is_electric(model.get("propulsion", {})))
	var speed: float = float(model.get("start_speed", 15.0))
	var base_x := PackedFloat64Array([0.05, -0.05, 0.5, 0.0, 0.0, 0.0])
	var base: Dictionary = Trim._evaluate_electric(base_x, "level", speed, model, G, RHO)
	_check("base level electric equilibrium succeeds", base.get("ok", false), str(base.get("message", "")))
	if not base.get("ok", false):
		_finish()
		return
	_check("base RPM is finite", is_finite(float(base.get("rpm", NAN))))
	var generic: Dictionary = Trim._evaluate(base_x, "level", speed, model, G, RHO, 1.0)
	_check("generic electric evaluation exposes the RPM it already computed",
		generic.has("rpm") and float(generic.rpm) == float(base.rpm))

	for axis: int in [1, 4, 5]:
		var perturbed_x: PackedFloat64Array = base_x.duplicate()
		perturbed_x[axis] += 1e-7 * maxf(1.0, absf(base_x[axis]))
		_check("control axis %d leaves steady inputs unchanged" % axis,
			Trim._same_electric_steady_point_inputs(base_x, perturbed_x, "level"))
		var reference: Dictionary = Trim._evaluate_electric(perturbed_x, "level", speed, model, G, RHO)
		var reused: Dictionary = Trim._evaluate_electric_perturbation(
			base_x, perturbed_x, base, "level", speed, model, G, RHO)
		_check("control axis %d reuse is byte-identical to a fresh solve" % axis,
			var_to_bytes(reused) == var_to_bytes(reference))

	var alpha_x: PackedFloat64Array = base_x.duplicate()
	alpha_x[0] += 0.1
	_check("alpha change requires a fresh steady point",
		not Trim._same_electric_steady_point_inputs(base_x, alpha_x, "level"))
	var alpha_reference: Dictionary = Trim._evaluate_electric(alpha_x, "level", speed, model, G, RHO)
	var alpha_actual: Dictionary = Trim._evaluate_electric_perturbation(
		base_x, alpha_x, base, "level", speed, model, G, RHO)
	var alpha_stale: Dictionary = Trim._evaluate_electric(alpha_x, "level", speed, model, G, RHO, float(base.rpm))
	_check("alpha change follows the fresh evaluation", var_to_bytes(alpha_actual) == var_to_bytes(alpha_reference))
	_check("alpha change differs from forcing the previous RPM", var_to_bytes(alpha_reference) != var_to_bytes(alpha_stale))

	var duty_x: PackedFloat64Array = base_x.duplicate()
	duty_x[2] += 0.05
	_check("duty change requires a fresh steady point",
		not Trim._same_electric_steady_point_inputs(base_x, duty_x, "level"))
	var duty_reference: Dictionary = Trim._evaluate_electric(duty_x, "level", speed, model, G, RHO)
	var duty_actual: Dictionary = Trim._evaluate_electric_perturbation(
		base_x, duty_x, base, "level", speed, model, G, RHO)
	var duty_stale: Dictionary = Trim._evaluate_electric(duty_x, "level", speed, model, G, RHO, float(base.rpm))
	_check("duty change follows the fresh evaluation", var_to_bytes(duty_actual) == var_to_bytes(duty_reference))
	_check("duty change differs from forcing the previous RPM", var_to_bytes(duty_reference) != var_to_bytes(duty_stale))
	_check("reused evaluation retains finite six-axis derivatives",
		reused_derivatives_are_finite(base_x, model, speed))
	_finish()


func reused_derivatives_are_finite(base_x: PackedFloat64Array, model: Dictionary, speed: float) -> bool:
	var base: Dictionary = Trim._evaluate_electric(base_x, "level", speed, model, G, RHO)
	var perturbed_x: PackedFloat64Array = base_x.duplicate()
	perturbed_x[4] += 1e-7
	var evaluation: Dictionary = Trim._evaluate_electric_perturbation(
		base_x, perturbed_x, base, "level", speed, model, G, RHO)
	var residual: PackedFloat64Array = Trim._residual_from_evaluation(evaluation)
	if residual.size() != 6:
		return false
	for value: float in residual:
		if not is_finite(value):
			return false
	return true


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	if ok:
		print("ok    " + label)
		return
	_failures += 1
	printerr("FAIL  " + label + (" — " + detail if not detail.is_empty() else ""))


func _finish() -> void:
	print("Electric trim RPM reuse fixture: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
