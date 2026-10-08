extends SceneTree
const Data = preload("res://physics/aircraft_data.gd")

func _initialize() -> void:
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/aircraft/jensen_ugly_stik_60.json"))
	for label: String in ["4.0", "0.1", "1e-10", "1e-300"]:
		var slope: float = label.to_float()
		var raw: Dictionary = source.duplicate(true)
		raw.aero.coefficients.CLa.value = slope
		var result: Dictionary = Data.validate_and_derive(raw)
		var env: Dictionary = result.model.get("envelope", {})
		var out: Dictionary = {CLa = label, ok = result.ok, errors = Array(result.errors), angles = {}}
		for key in ["a1", "a2", "n1", "n2"]:
			if env.has(key):
				out.angles[key] = str(env[key])
		print(JSON.stringify(out))
	quit()
