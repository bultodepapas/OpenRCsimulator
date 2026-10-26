# D11-R1: stock conventional wings must retain their authored small-angle aileron authority
# when the load evaluator changes from coefficient derivatives to induced-flow strips.
# These are consistency checks, not measured aircraft handling targets.
extends SceneTree

const AD := preload("res://physics/aircraft_data.gd")
const Aero := preload("res://physics/aero.gd")
const Air := preload("res://physics/air_data.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const RHO := 1.225
const SPEED := 25.0
const STEP := 0.0001
var failures := 0
var checks := 0

func check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
	print(("ok   " if passed else "FAIL ") + label)

func derivative(model: Dictionary, alpha: float, local: bool, side: int) -> float:
	var state := PackedFloat64Array([0, 0, -300, SPEED*cos(alpha), 0, SPEED*sin(alpha), 1, 0, 0, 0, 0, 0, 0])
	var air := Air.compute(state, PackedFloat64Array([0, 0, 0]), RHO)
	var plus := {elevator = 0.0, rudder = 0.0, aileron_right = -STEP if side != 2 else 0.0, aileron_left = STEP if side != 1 else 0.0}
	var minus := {elevator = 0.0, rudder = 0.0, aileron_right = -plus.aileron_right, aileron_left = -plus.aileron_left}
	var lp := Aero._local_loads(state, air, plus, model, RHO) if local else Aero._global_loads(state, air, plus, model, RHO)
	var lm := Aero._local_loads(state, air, minus, model, RHO) if local else Aero._global_loads(state, air, minus, model, RHO)
	return (lp[3] - lm[3]) / (2.0 * STEP * air.qbar * float(model.reference.S) * float(model.reference.b))

func _initialize() -> void:
	for entry in Catalog.airplane_flyable_entries():
		var loaded := AD.load_file(entry.data)
		check("%s loads" % entry.id, loaded.ok)
		if not loaded.ok:
			continue
		var model: Dictionary = loaded.model
		# X8 elevon loading is independently derived from its swept geometry and symmetric lift target.
		if model.surfaces.has("tailless"):
			continue
		for degrees in [0.0, 4.0]:
			for side in 3:
				var global_value := derivative(model, deg_to_rad(degrees), false, side)
				var local_value := derivative(model, deg_to_rad(degrees), true, side)
				check("%s alpha %.0f side %d: roll-control local %.6f / oracle %.6f within 1 %%" % [entry.id, degrees, side, local_value, global_value],
					global_value > 0.0 and absf(local_value / global_value - 1.0) < 0.01)
	print("%d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)
