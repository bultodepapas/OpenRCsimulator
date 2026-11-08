extends SceneTree

const Data = preload("res://physics/rotorcraft_data.gd")
const Trim = preload("res://physics/rotorcraft/trim.gd")
const Flight = preload("res://physics/rotorcraft/flight_dynamics.gd")
const Electronics = preload("res://physics/rotorcraft/electronics.gd")
const M = preload("res://physics/math3d.gd")

var checks: int = 0
var failures: int = 0


func check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", label)


func close(label: String, actual: float, expected: float, tolerance: float = 1.0e-8) -> void:
	check(label, is_finite(actual) and absf(actual - expected) <= tolerance * maxf(1.0, absf(expected)))


func _initialize() -> void:
	var position: PackedFloat64Array = M.v3(12.0, 4.0, -3.0)
	var wind: PackedFloat64Array = M.v3(0.0, 0.0, 0.0)
	var hx: Dictionary = Data.load_file("res://data/aircraft/hx700_electric_3d_experimental.json")
	check("HX laboratory model loads with body-rate controller", hx.ok and hx.controller_law == Electronics.BODY_RATE_LAW
		and hx.release_gate.state == "laboratory_only" and not hx.release_gate.flight_qualified)
	if hx.ok:
		var rejected: Dictionary = Trim.solve_hover(hx.context, 0.0, position, wind, {"flight_mode": "3d"})
		check("HX trim refuses unsupported body-rate result before solving", not rejected.ok
			and rejected.iterations == 0 and rejected.message.contains("body-rate")
			and rejected.state.is_empty() and rejected.sticks.is_empty() and not rejected.has("trim"))
		var invalid: Dictionary = Trim.solve_hover(hx.context, NAN, position, wind, {"flight_mode": "3d"})
		check("invalid trim inputs remain separately refused", not invalid.ok and invalid.message == "invalid hover-trim arguments")
	var trainer: Dictionary = Data.load_file("res://data/aircraft/xcell_60_research.json")
	check("playable reference has the trainer law", trainer.ok and trainer.controller_law == Electronics.TRAINER_LAW)
	if trainer.ok:
		for mode: String in ["normal", "idle_up"]:
			_round_trip(trainer.context, mode, position, wind)
	print("HELI H07 hover trim contract: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)


func _round_trip(context: Dictionary, mode: String, position: PackedFloat64Array, wind: PackedFloat64Array) -> void:
	var result: Dictionary = Trim.solve_hover(context, 0.0, position, wind, {"flight_mode": mode})
	check(mode + " trainer hover converges", result.ok)
	if not result.ok:
		print(mode, " trim refused: ", result.get("message", "unknown"))
		return
	var neutral: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0, result.sticks[3]])
	for trainer_enabled: bool in [false, true]:
		var label: String = mode + (" trainer" if trainer_enabled else " direct")
		var evaluation: Dictionary = Flight.evaluate(result.state, context, neutral, mode,
			trainer_enabled, false, wind, true, PackedFloat64Array(), result.trim)
		check(label + " consumes returned neutral sticks and trim", evaluation.ok)
		if not evaluation.ok:
			continue
		for index: int in range(6):
			close(label + " aerodynamic wrench " + str(index),
				evaluation.aerodynamic_loads[index], result.evaluation.aerodynamic_loads[index])
		for key: String in ["collective_75_rad", "cyclic_forward_rad", "cyclic_right_rad", "tail_collective_rad"]:
			close(label + " single application of " + key,
				float(evaluation.controls[key]), float(result.evaluation.controls[key]))
		close(label + " shaft derivative", evaluation.derivative[0], result.evaluation.derivative[0])
		for index: int in range(1, 4):
			close(label + " flap/inflow derivative " + str(index), evaluation.derivative[index], result.evaluation.derivative[index])
		var step: Dictionary = Flight.rk4_step_at(result.state, 0.0, 1.0 / 240.0, context,
			neutral, mode, trainer_enabled, false, wind, false, PackedFloat64Array(), result.trim)
		check(label + " accepts a subsequent integration step", step.ok and step.state.size() == Flight.STATE_SIZE)
