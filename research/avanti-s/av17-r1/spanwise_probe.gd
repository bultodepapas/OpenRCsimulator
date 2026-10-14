extends SceneTree

const Flight := preload("res://sim/flight_session.gd")
const Air := preload("res://physics/air_data.gd")
const Aero := preload("res://physics/aero.gd")
const AircraftData := preload("res://physics/aircraft_data.gd")
const M := preload("res://physics/math3d.gd")
const Trim := preload("res://physics/trim.gd")
const DATA_PATH := "res://data/aircraft/sebart_avanti_s_a200.json"

func _initialize() -> void:
	var flight := Flight.new()
	flight.setup(DATA_PATH, "sebart-avanti-s-a200-p100rx")
	root.add_child(flight)
	flight.set_physics_process(false)
	flight.sim.set_physics_process(false)
	var model: Dictionary = flight.aircraft.model
	var no_twist_model: Dictionary = model.duplicate(true)
	no_twist_model.surfaces.station_incidence = PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	var ref: Dictionary = raw.reference
	var chords := PackedFloat64Array([float(ref.root_chord.value), float(ref.tip_chord.value)])
	var area := float(ref.wing_area.value)
	var span := float(ref.wing_span.value)
	assert(AircraftData._induced_map(no_twist_model.envelope, no_twist_model.surfaces,
		no_twist_model.aero, area, span, chords))
	var rho: float = flight.air_density()
	var deflections: Dictionary = Aero.deflections_from_surfaces(flight.surface_angles_deg())
	print("spanwise static strips; 45 m/s; neutral; 500 m; compare accepted twist with zero-twist model copy rederived through _induced_map")
	print("case alpha_deg y_m geometric_deg effective_deg CL stall_weight")
	for alpha_deg in [0.0, 8.0, 9.2, 10.34, 12.0, 14.34]:
		var state: PackedFloat64Array = Trim.state_for(45.0, deg_to_rad(alpha_deg), 0.0, 0.0, M.v3(0.0, 0.0, -500.0))
		var air: Dictionary = Air.compute(state, M.v3(0.0, 0.0, 0.0), rho)
		for pair in [["accepted_twist", model], ["zero_twist", no_twist_model]]:
			var rows: Array = Aero.wing_strip_loads(state, air, deflections, pair[1], rho)
			print("%s %.2f meanCL %.4f" % [pair[0], alpha_deg, mean_cl(rows)])
			for row in rows:
				print("%s %.2f %.4f %.3f %.3f %.4f %.4f" % [pair[0], alpha_deg, row.y_m,
					rad_to_deg(row.alpha_geometric_rad), rad_to_deg(row.alpha_effective_rad), row.cl, row.stall_weight])
	flight.free()
	quit()

func mean_cl(rows: Array) -> float:
	var total := 0.0
	for row in rows:
		total += row.cl
	return total / float(rows.size()) if not rows.is_empty() else 0.0
