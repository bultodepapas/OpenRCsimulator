# E3b2-R1: compare complete GroundStart results against an identified baseline.
# Run with --headless --path <snapshot>/app --script <absolute path to this file>.
extends SceneTree
const GS = preload("res://physics/ground_start.gd")
const AD = preload("res://physics/aircraft_data.gd")
const FieldLoader = preload("res://data/field_loader.gd")
const Surfaces = preload("res://physics/ground_surfaces.gd")
const FILES: Array[String] = ["jensen_ugly_stik_60", "gp_extra_300s_60", "p51d_mustang_120", "sebart_avanti_s_a200"]
func _initialize() -> void:
	var field: Dictionary = FieldLoader.load_from().field
	var surfaces: PackedFloat64Array = Surfaces.build(Surfaces.load_table().table, field).rects
	var deflections: Dictionary = {elevator=0.0, aileron_left=0.0, aileron_right=0.0, rudder=0.0}
	for aircraft in FILES:
		var loaded: Dictionary = AD.load_file("res://data/aircraft/" + aircraft + ".json")
		if not loaded.ok:
			printerr(loaded.errors)
			quit(1)
			return
		var model: Dictionary = loaded.model
		for heading in [PI/2, -PI/2, 0.0, .6]:
			for rho in [0.0, .9, 1.225]:
				for rpm in [0.0, model.propulsion.idle_rpm]:
					var result: Dictionary = GS.solve(model, surfaces, 15.0, 0.0, heading, deflections, 0.0, rpm, rho, 9.80665)
					print("START ", JSON.stringify({aircraft=aircraft, heading=heading, rho=rho, rpm=rpm,
						ok=result.ok, iterations=result.iterations, message=result.message,
						result_sha256=var_to_bytes(result).hex_encode().sha256_text()}))
	quit(0)
