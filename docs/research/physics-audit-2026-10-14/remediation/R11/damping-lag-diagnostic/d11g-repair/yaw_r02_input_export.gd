extends SceneTree

const AD := preload("res://physics/aircraft_data.gd")
const Aero := preload("res://physics/aero.gd")

const AIRCRAFT := "res://data/aircraft/jensen_ugly_stik_60.json"


func _initialize() -> void:
	var loaded: Dictionary = AD.load_file(AIRCRAFT)
	if not bool(loaded.get("ok", false)):
		push_error("aircraft load failed: %s" % str(loaded.get("errors", [])))
		quit(2)
		return
	var model: Dictionary = loaded.model
	var report := {
		"aircraft_id": model.id,
		"law": Aero.LOADS_LAW,
		"aircraft_input": loaded.input_identity,
		"aero_source_sha256": FileAccess.get_sha256("res://physics/aero.gd"),
		"geometry": {
			"area_m2": model.reference.S,
			"span_m": model.reference.b,
			"mean_chord_m": model.reference.c,
			"station_y_m": model.envelope.station_ys,
			"strip_cl0": model.envelope.strip_cl0,
			"induced_map_E": model.envelope.induced_map,
			"strip_slope_per_rad": model.envelope.strip_slope,
		},
		"aero": {
			"CL0_whole_aircraft": model.aero.CL0,
			"CD0": model.aero.CD0,
			"k_induced_whole_aircraft": model.aero.k_induced,
			"CL_minD": model.aero.CL_minD,
			"a1_attached_rad": model.envelope.a1,
			"n1_attached_rad": model.envelope.n1,
			"wing_polar": model.envelope.get("wing_polar", {}),
		},
	}
	print("D11G_JSON=" + JSON.stringify(report, "", true, true))
	quit(0)
