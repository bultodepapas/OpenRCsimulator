extends SceneTree
# P51-26: relative error of the slipstream yaw per sideslip for 1, 2, 4 and 64 subdivisions per swirl segment against 256.
const T = preload("res://tests/test_slipstream_sidewash.gd")
const AD = preload("res://physics/aircraft_data.gd")
const Air = preload("res://physics/air_data.gd")
const Propulsion = preload("res://physics/propulsion.gd")
const M = preload("res://physics/math3d.gd")
func _initialize() -> void:
	var model: Dictionary = AD.load_file("res://data/aircraft/p51d_mustang_120.json").model
	var step := deg_to_rad(0.5)
	for V: float in [18.0, 22.0, 25.7, 28.6, 35.0, 45.0]:
		var s0 := T._state(V, deg_to_rad(4.0), 0.0)
		var air0 := Air.compute(s0, M.v3(0, 0, 0), 1.225)
		var rpm := Propulsion.steady_rpm(0.6, M.dot(air0.v_air, Propulsion.axis(model.propulsion)), model.propulsion, 1.225, 1.0)
		var sp := T._state(V, deg_to_rad(4.0), step)
		var sm := T._state(V, deg_to_rad(4.0), -step)
		var ref := T._yaw(model, sp, sm, rpm, 256)
		var line := "V %4.1f" % V
		for n in [1, 2, 4, 64]:
			line += "  n%d %+.4f" % [n, (T._yaw(model, sp, sm, rpm, n) - ref) / absf(ref)]
		print(line)
	quit(0)
