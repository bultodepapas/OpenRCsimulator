## E300-07: final diagnostics and states belong to the accepted Newton iterate, including a refused step.
extends SceneTree

const AD := preload("res://physics/aircraft_data.gd")
const Trim := preload("res://physics/trim.gd")
const G := 9.80665
var checks := 0
var failures := 0


func check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
		printerr("FAIL ", label)


func _initialize() -> void:
	var loaded: Dictionary = AD.load_file("res://data/aircraft/gp_extra_300s_60.json")
	check("Extra loads", loaded.get("ok", false))
	if not loaded.get("ok", false):
		quit(1)
		return
	for stalled in [false, true]:
		var model: Dictionary = loaded.model.duplicate(true)
		if stalled:
			model.propulsion.glow.throttle_idle_offset = 0.3
		var before := var_to_bytes(model)
		for seed in [0.4, 0.75, 0.95]:
			var speed := 17.0 if stalled else 22.0
			var result: Dictionary = Trim._solve_from("level", speed, model, G,
				model.controls.throw_rad, seed, 1.225, 1.0)
			check("expected acceptance/refusal", result.ok == not stalled)
			if stalled:
				check("refusal is the bounded-step failure", result.message.contains("stalled"))
			var x := PackedFloat64Array([result.alpha, result.elevator, result.throttle,
				result.beta, result.aileron, result.rudder])
			# Independently solve the equilibrium at the reported state. This also checks
			# that rejected probes did not lend their RPM to the accepted result.
			var rpm: float = Trim._rpm(result.throttle, result.state, "level", model, 1.225, 1.0)
			check("reported RPM belongs to reported state", var_to_bytes(result.rpm) == var_to_bytes(rpm))
			var residual: PackedFloat64Array = Trim._residual(x, "level", speed, model, G, 1.225, 1.0)
			var recomputed: Dictionary = Trim._result(result.ok, result.message, x, "level", speed,
				residual, result.iterations, model.controls.throw_rad, model, G, 1.225, 1.0)
			check("complete result matches uncached finalization", var_to_bytes(result) == var_to_bytes(recomputed))
		check("model remains unchanged", var_to_bytes(model) == before)
	print("%d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)
