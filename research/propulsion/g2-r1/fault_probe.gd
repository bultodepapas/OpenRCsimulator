# G2-R1: the isolated verifier injects a bad internal torque evaluation.
extends SceneTree
const P := preload("res://physics/propulsion.gd")

func _initialize() -> void:
	var prop := { diameter = 1.0, cp = PackedFloat64Array([0.0, 0.01, 1.0, 0.01]),
		shaft = { power_curve = PackedFloat64Array([100.0, 100.0 * TAU / 60.0,
			10000.0, 10000.0 * TAU / 60.0]), friction = PackedFloat64Array([0.0, 0.0]),
			idle_power = 0.5, peak_indicated_power = 2000.0 } }
	var refused := is_nan(P.steady_rpm(1.0, 0.0, prop, 1.0))
	print("G2-R1 internal fault refused: ", refused)
	quit(0 if refused else 1)
