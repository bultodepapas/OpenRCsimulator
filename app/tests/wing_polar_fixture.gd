# Synthetic verification/sensitivity fixture, NOT a measured or recommended Ugly Stik polar.
extends RefCounted

const AD := preload("res://physics/aircraft_data.gd")
const PATH := "res://data/aircraft/jensen_ugly_stik_60.json"


static func raw(retention := 0.7) -> Dictionary:
	var result: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	var model: Dictionary = AD.validate_and_derive(result).model
	var env: Dictionary = model.envelope
	var slope: float = float(env.strip_slope)*AD._row_mean(env.induced_map, env.station_ys.size())
	var offset := 0.0
	for value: float in env.strip_cl0:
		offset += value / float(env.strip_cl0.size())
	var cd0: float = model.aero.CD0
	var cd90: float = env.CD90
	var polar := {method = "tabulated-wing-v1", basis = "finite-wing-strip-reference"}
	for side in [1.0, -1.0]:
		var peak: float = side*offset+slope*deg_to_rad(13.0)
		var samples := [
			8.0, side*offset+slope*deg_to_rad(8.0), cd0, 1.0,
			10.0, side*offset+slope*deg_to_rad(10.0), cd0, 1.0,
			14.0, peak, cd0+0.04, 0.85,
			25.0, peak*retention, cd0+0.22, 0.4,
			45.0, cd90*0.5, cd0+cd90*0.5, 0.0,
			70.0, cd90*0.32, cd0+cd90*0.88, 0.0,
			90.0, 0.0, cd0+cd90, 0.0,
		]
		polar["positive" if side > 0.0 else "negative"] = {value = samples,
			unit = "deg, 1, 1, 1", kind = "estimated",
			source = "D8b-R2 synthetic sensitivity fixture; arbitrary post-peak retention %.2f; NOT matched Jensen measurements or calibrated flight data" % retention}
	result.aero.wing_polar = polar
	return result
