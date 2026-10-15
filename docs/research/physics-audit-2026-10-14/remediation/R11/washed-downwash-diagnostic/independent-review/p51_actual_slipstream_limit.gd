extends SceneTree
const AD := preload("res://physics/aircraft_data.gd")
const Air := preload("res://physics/air_data.gd")
const Aero := preload("res://physics/aero.gd")
const Propulsion := preload("res://physics/propulsion.gd")
const Slipstream := preload("res://physics/slipstream.gd")
const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const RHO := 1.225
const AIRCRAFT_PATH := "res://data/aircraft/p51d_mustang_120.json"
const ALPHAS_DEG := [-5.0, 0.0, 5.0]
const SPEEDS := [0.0, 1.0, 0.01, 0.000001, 0.00000001]

func _initialize() -> void:
	var loaded: Dictionary = AD.load_file(AIRCRAFT_PATH)
	if not loaded.get("ok", false):
		printerr("P51_WASH_ERROR " + str(loaded.get("errors", [])))
		quit(2)
		return
	var model: Dictionary = loaded.model
	var prop: Dictionary = model.propulsion
	if prop.get("slipstream", {}).is_empty():
		printerr("P51_WASH_ERROR catalog has no slipstream")
		quit(2)
		return
	var rpm: float = float(prop.max_rpm)
	var d := {elevator = 0.0, rudder = 0.0, aileron_left = 0.0, aileron_right = 0.0}
	var rates := M.v3(0.0, 0.0, 0.0)
	var rows: Array[Dictionary] = []
	var helper_worst := 0.0
	var immersed_count := 0
	var zero_rows: Dictionary = {}
	for alpha_deg: float in ALPHAS_DEG:
		var alpha: float = deg_to_rad(alpha_deg)
		for speed: float in SPEEDS:
			var state := PackedFloat64Array([0.0, 0.0, -100.0, speed * cos(alpha), 0.0,
				speed * sin(alpha), 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
			var air: Dictionary = Air.compute(state, M.v3(0.0, 0.0, 0.0), RHO)
			var source: float = Aero.wing_wake_velocity(state, air, d, model)
			var shaft: PackedFloat64Array = Propulsion.thrust_torque(air.v_air, rpm, prop, RHO)
			var wake: Dictionary = Slipstream.wake(air.v_air, shaft[0], shaft[1], prop, RHO)
			var loads: PackedFloat64Array = Slipstream.loads(state, air, d, model, rpm, RHO)
			var helper := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
			var immersed := 0
			for piece: Dictionary in prop.slipstream.pieces:
				var im: Dictionary = Slipstream.immersion(piece, wake, prop.slipstream.hub, prop,
					air.v_air, air.V, model)
				if float(im.area) <= 0.0:
					continue
				immersed += 1
				var extra: PackedFloat64Array = M.sub(M.scale(Propulsion.axis(prop), float(wake.dv)), im.swirl)
				var increment: PackedFloat64Array = Aero.tail_surface_increment(air.v_air, rates, d, model,
					str(piece.surface), float(im.area), im.shift, extra, RHO, source)
				for k: int in 6:
					helper[k] += increment[k]
			var helper_error := 0.0
			for k: int in 6:
				helper_error = maxf(helper_error, absf(loads[k] - helper[k]))
			helper_worst = maxf(helper_worst, helper_error)
			immersed_count += immersed
			var row := {"alpha_deg": alpha_deg, "speed_mps": speed, "wing_wake_mps": source,
				"rpm": rpm, "static_thrust_n": shaft[0], "wake_dv_mps": wake.dv,
				"immersed_pieces": immersed, "slipstream_loads": loads,
				"helper_composition_loads": helper, "helper_max_abs_error": helper_error}
			rows.append(row)
			if speed == 0.0:
				zero_rows[str(alpha_deg)] = loads
			else:
				var exact: PackedFloat64Array = zero_rows.get(str(alpha_deg), PackedFloat64Array())
				# SPEEDS lists zero first, so the reference is available here.
				row["force_delta_vs_zero_n"] = M.sqrt_((loads[0] - exact[0]) * (loads[0] - exact[0])
					+ (loads[1] - exact[1]) * (loads[1] - exact[1])
					+ (loads[2] - exact[2]) * (loads[2] - exact[2]))
				row["pitch_delta_vs_zero_nm"] = loads[4] - exact[4]
	var report := {"aircraft_id": model.id, "source_file": AIRCRAFT_PATH, "rho_kg_m3": RHO,
		"rpm_from_catalog_max_rpm": rpm, "prop_slipstream_has_edge_fraction": prop.slipstream.has("edge_fraction"),
		"prop_slipstream_piece_count": prop.slipstream.pieces.size(), "total_immersed_piece_samples": immersed_count,
		"max_abs_actual_vs_public_helper_error": helper_worst,
		"zero_flow_loads_by_alpha": zero_rows, "rows": rows}
	print("P51_WASH_ACTUAL " + JSON.stringify(report))
	quit(0)
