## R04 bounded-solver magnitude and force/moment balance probe.
## Run against an isolated app source copy with the pinned Godot 4.7.2 binary.
extends SceneTree

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const GS := preload("res://physics/ground_start.gd")
const Dynamics := preload("res://physics/dynamics.gd")
const Ground := preload("res://physics/ground_contact.gd")
const GroundTerrain := preload("res://physics/ground_terrain.gd")
const GroundEffect := preload("res://physics/ground_effect.gd")
const RetractableGear := preload("res://physics/retractable_gear.gd")
const Air := preload("res://physics/air_data.gd")
const AD := preload("res://physics/aircraft_data.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const Surfaces := preload("res://physics/ground_surfaces.gd")
const Aero := preload("res://physics/aero.gd")
const Commands := preload("res://input/commands.gd")
const Propulsion := preload("res://physics/propulsion.gd")

const G_NOMINAL := 9.80665
const RHO_NOMINAL := 1.225
const AIRCRAFT := {
	"Stik": "res://data/aircraft/jensen_ugly_stik_60.json",
	"Jet": "res://data/aircraft/sebart_avanti_s_a200.json",
}

func _initialize() -> void:
	var field_result: Dictionary = FieldLoader.load_from()
	var table_result: Dictionary = Surfaces.load_table()
	if not field_result.ok or not table_result.ok:
		printerr("setup failed: field=%s surfaces=%s" % [str(field_result), str(table_result)])
		quit(2)
		return
	var field: Dictionary = field_result.field
	var surfaces_result: Dictionary = Surfaces.build(table_result.table, field)
	var spot: Dictionary = GS.threshold(field)
	if not surfaces_result.ok or not spot.ok:
		printerr("geometry setup failed: %s %s" % [str(surfaces_result), str(spot)])
		quit(2)
		return
	var invalid_model: Dictionary = {}
	for label: String in AIRCRAFT:
		var loaded: Dictionary = AD.load_file(AIRCRAFT[label])
		if not loaded.ok:
			printerr("aircraft load failed %s: %s" % [label, str(loaded.errors)])
			continue
		invalid_model = loaded.model
		for speed: float in [0.0, 0.5, 1.0, 1.5, 2.0]:
			_run_case(label, loaded.model, surfaces_result.rects, spot, speed, 0.0, G_NOMINAL, RHO_NOMINAL, "magnitude")
		for condition: Dictionary in [
			{"speed": 2.0, "from_deg": 0.0, "g": 9.0, "rho": 0.8, "tag": "low_g_low_density"},
			{"speed": 2.0, "from_deg": 0.0, "g": 10.5, "rho": 1.4, "tag": "high_g_high_density"},
			{"speed": 2.0, "from_deg": 0.0, "g": G_NOMINAL, "rho": 0.0, "tag": "zero_density_limit"},
		]:
			_run_case(label, loaded.model, surfaces_result.rects, spot, condition.speed, condition.from_deg,
				condition.g, condition.rho, condition.tag)
		_run_case(label, loaded.model, surfaces_result.rects, spot, 20.0, 0.0, G_NOMINAL, RHO_NOMINAL, "extreme_unresolved")
	_run_invalid(invalid_model)
	quit(0)


func _run_case(label: String, model: Dictionary, surfaces: PackedFloat64Array, spot: Dictionary,
		speed: float, from_deg: float, gravity: float, density: float, tag: String) -> void:
	var gear: Dictionary = model.landing_gear
	var neutral: Dictionary = Commands.neutral_commands()
	var surface_angles: Dictionary = Commands.surface_deflections_deg(neutral, model.controls.throw_deg)
	var deflections: Dictionary = Aero.deflections_from_surfaces(surface_angles)
	var rpm: float = 0.0 if Propulsion.is_glow(model.propulsion) else Propulsion.steady_rpm(
		0.0, 0.0, model.propulsion, density, 1.0)
	var wheel_profile: Dictionary = model.get("wheel_profile", {})
	var enhanced: bool = wheel_profile.get("status") == "applied" and not gear.contacts.is_empty()
	var from_rad := deg_to_rad(from_deg)
	var wind := PackedFloat64Array([-speed * cos(from_rad), -speed * sin(from_rad), 0.0])
	var result: Dictionary = GS.solve(model, surfaces, spot.north, spot.east, spot.heading,
		deflections, 0.0, rpm, density, gravity, wind, enhanced)
	var solve_diagnostics: Dictionary = result.get("diagnostics", {})
	var row := {"case": tag, "aircraft": label, "model_id": str(model.get("id", "")),
		"wind_from_deg": from_deg, "wind_speed_mps": speed, "wind_ned_mps": Array(wind),
		"gravity_mps2": gravity, "density_kg_m3": density, "rpm": rpm, "enhanced_wheels": enhanced,
		"ok": result.get("ok", false), "status": result.get("status", "unknown"),
		"message": str(result.get("message", "")), "iterations": result.get("iterations", -1),
		"residual_linf_accel": result.get("residual", INF), "scaled_residual_linf": result.get("scaled_residual", INF),
		"solver_diagnostics": {"length_scale_m": solve_diagnostics.get("length_scale_m", NAN),
			"length_scale_definition": solve_diagnostics.get("length_scale_definition", ""),
			"total_residual_evaluations": solve_diagnostics.get("total_residual_evaluations", -1),
			"residual_evaluation_budget": solve_diagnostics.get("residual_evaluation_budget", -1),
			"stage1": _stage_record(solve_diagnostics.get("stage1", {})),
			"stage2": _stage_record(solve_diagnostics.get("stage2", {}))}}
	if result.get("ok", false):
		var state: PackedFloat64Array = result.state
		var anchors: PackedFloat64Array = result.anchors
		var q := PackedFloat64Array([state[RB.ATT], state[RB.ATT + 1], state[RB.ATT + 2], state[RB.ATT + 3]])
		var q_conjugate := PackedFloat64Array([q[0], -q[1], -q[2], -q[3]])
		var ground_up: float = GroundTerrain.sample_validated(state[RB.POS], state[RB.POS + 1], surfaces)[0] \
			if GroundEffect.enabled(model) else NAN
		var aircraft_loads: PackedFloat64Array = Dynamics.loads(state, model, deflections, rpm, density, wind,
			NAN, PackedFloat64Array(), ground_up)
		if RetractableGear.enabled(gear):
			var gear_drag: PackedFloat64Array = RetractableGear.drag_loads(state, Air.compute(state, wind, density).v_air,
				gear, 1.0, density)
			for i in gear_drag.size(): aircraft_loads[i] += gear_drag[i]
		var wheel_speeds := PackedFloat64Array()
		if enhanced: wheel_speeds.resize(gear.contacts.size())
		var gear_loads: PackedFloat64Array = Ground.loads(state, gear, 0.0, surfaces, anchors, wheel_speeds)
		var weight_body := M.q_rotate(q_conjugate, M.v3(0.0, 0.0, float(model.mass_kg) * gravity))
		var total_force := PackedFloat64Array([weight_body[0], weight_body[1], weight_body[2]])
		var total_moment := PackedFloat64Array([0.0, 0.0, 0.0])
		for axis in 3:
			total_force[axis] += aircraft_loads[axis] + (gear_loads[axis] if gear_loads.size() == 6 else 0.0)
			total_moment[axis] += aircraft_loads[axis + 3] + (gear_loads[axis + 3] if gear_loads.size() == 6 else 0.0)
		var external_force := PackedFloat64Array()
		external_force.resize(3)
		for axis in 3:
			external_force[axis] = aircraft_loads[axis] + (gear_loads[axis] if gear_loads.size() == 6 else 0.0)
		var rotor_h := Dynamics.rotor_momentum(model, rpm)
		var derivative := RB.derivative(state, model.mass_kg, model.inertia, RB.inertia_inverse(model.inertia),
			external_force,
			PackedFloat64Array([total_moment[0], total_moment[1], total_moment[2]]), gravity, rotor_h)
		var reconstructed_force := PackedFloat64Array([model.mass_kg * derivative[RB.VEL],
			model.mass_kg * derivative[RB.VEL + 1], model.mass_kg * derivative[RB.VEL + 2]])
		var alpha := PackedFloat64Array([derivative[RB.RATE], derivative[RB.RATE + 1], derivative[RB.RATE + 2]])
		var reconstructed_moment := RB.inertia_mul(model.inertia, alpha)
		var force_closure := M.sub(reconstructed_force, total_force)
		var moment_closure := M.sub(reconstructed_moment, total_moment)
		var compressions := Ground.compressions(state, gear)
		var anchor_after := Ground.anchor_step(state, gear, 0.0, surfaces, anchors, enhanced)
		var diagnostics: Dictionary = result.get("diagnostics", {})
		row["final_pose_ned"] = PackedFloat64Array([state[RB.POS], state[RB.POS + 1], state[RB.POS + 2]])
		row["achieved_minus_requested_ned_yaw"] = diagnostics.get("achieved_minus_requested", PackedFloat64Array())
		row["compressions_m"] = Array(compressions)
		row["anchors_persist"] = anchor_after == anchors
		row["support_contacts"] = diagnostics.get("contact_summary", [])
		row["force_residual_n"] = Array(total_force)
		row["moment_residual_nm"] = Array(total_moment)
		row["force_reconstruction_difference_n"] = Array(force_closure)
		row["moment_reconstruction_difference_nm"] = Array(moment_closure)
		row["force_residual_linf_n"] = GS._norm(total_force)
		row["moment_residual_linf_nm"] = GS._norm(total_moment)
		row["residual_evaluations"] = diagnostics.get("total_residual_evaluations", -1)
	print(JSON.stringify(row, "", false, true))


func _stage_record(stage: Dictionary) -> Dictionary:
	return {"stage": stage.get("stage", ""), "reason": stage.get("reason", ""),
		"iterations": stage.get("iterations", 0), "evaluations": stage.get("evaluations", 0),
		"final_residual": stage.get("final_residual", PackedFloat64Array()),
		"final_scaled_residual": stage.get("final_scaled_residual", PackedFloat64Array()),
		"accepted_step_count": stage.get("accepted_steps", []).size(),
		"finite_difference_scaled_steps": stage.get("finite_difference_steps_used", PackedFloat64Array()),
		"active_set_stencil_rejections": stage.get("active_set_stencil_rejections", 0),
		"one_sided_columns": stage.get("one_sided_columns", 0),
		"max_derivative_step_relative_difference": stage.get("max_derivative_step_relative_difference", 0.0),
		"pivot_ratio_proxy": stage.get("pivot_ratio_proxy", 0.0),
		"final_contact_state": stage.get("final_contact_state", {})}


func _run_invalid(model: Dictionary) -> void:
	if model.is_empty(): return
	var field: Dictionary = FieldLoader.load_from().field
	var table: Dictionary = Surfaces.load_table().table
	var surfaces: PackedFloat64Array = Surfaces.build(table, field).rects
	var spot: Dictionary = GS.threshold(field)
	var neutral := Commands.neutral_commands()
	var d: Dictionary = Aero.deflections_from_surfaces(Commands.surface_deflections_deg(neutral, model.controls.throw_deg))
	var result: Dictionary = GS.solve(model, surfaces, NAN, float(spot.east), float(spot.heading), d,
		0.0, 0.0, RHO_NOMINAL, G_NOMINAL)
	print(JSON.stringify({"case":"invalid_input","aircraft":str(model.get("id","")),"ok":result.get("ok"),
		"status":result.get("status"),"message":result.get("message"),"iterations":result.get("iterations"),
		"state_size":result.get("state",PackedFloat64Array()).size(),"diagnostics":result.get("diagnostics",{})},"",false,true))
