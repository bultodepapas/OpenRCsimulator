extends SceneTree
const GS = preload("res://physics/ground_start.gd")
const AD = preload("res://physics/aircraft_data.gd")
const FieldLoader = preload("res://data/field_loader.gd")
const Surfaces = preload("res://physics/ground_surfaces.gd")
const Scenarios = preload("res://sim/scenarios.gd")

func _initialize() -> void:
	var model: Dictionary = AD.load_file(Scenarios.AIRCRAFT).model
	var field: Dictionary = FieldLoader.load_from().field
	var surfaces: PackedFloat64Array = Surfaces.build(Surfaces.load_table().table, field).rects
	var args: Array = [model, surfaces, 15.0, -47.0, PI / 2.0,
		{elevator = 0.0, aileron_left = 0.0, aileron_right = 0.0, rudder = 0.0}, 0.0, 1e160, 1.225, 9.80665]
	var result: Dictionary = GS.solve.callv(args)
	print("OVERFLOW_PROBE ", JSON.stringify({ok = result.get("ok"), status = result.get("status"),
		iterations = result.get("iterations"), residual = result.get("residual"), scaled_residual = result.get("scaled_residual"),
		message = result.get("message"), diagnostics = result.get("diagnostics", {})}))
	quit()
