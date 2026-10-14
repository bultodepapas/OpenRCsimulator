extends SceneTree

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const GS := preload("res://physics/ground_start.gd")
const Dynamics := preload("res://physics/dynamics.gd")
const GroundTerrain := preload("res://physics/ground_terrain.gd")
const GroundEffect := preload("res://physics/ground_effect.gd")
const Ground := preload("res://physics/ground_contact.gd")
const RetractableGear := preload("res://physics/retractable_gear.gd")
const Air := preload("res://physics/air_data.gd")
const AD := preload("res://physics/aircraft_data.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const Surfaces := preload("res://physics/ground_surfaces.gd")
const Aero := preload("res://physics/aero.gd")
const Commands := preload("res://input/commands.gd")
const Propulsion := preload("res://physics/propulsion.gd")
const G := 9.80665
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
	var speeds: Array[float] = [0.0, 0.5, 1.0, 1.5, 2.0]
	for label: String in AIRCRAFT:
		for speed: float in speeds:
			_run_case(label, AIRCRAFT[label], field, surfaces_result.rects, spot, speed)
	quit(0)

func _run_case(label: String, path: String, field: Dictionary, surfaces: PackedFloat64Array,
		spot: Dictionary, speed: float) -> void:
	var loaded: Dictionary = AD.load_file(path)
	if not loaded.ok:
		printerr("aircraft load failed %s: %s" % [label, str(loaded.errors)])
		return
	var model: Dictionary = loaded.model
	var gear: Dictionary = model.landing_gear
	var rho := 1.225
	var deflections: Dictionary = Aero.deflections_from_surfaces(
		Commands.surface_deflections_deg(Commands.neutral_commands(), model.controls.throw_deg))
	var rpm: float = 0.0 if Propulsion.is_glow(model.propulsion) else Propulsion.steady_rpm(
		0.0, 0.0, model.propulsion, rho, 1.0)
	var wheel_profile: Dictionary = model.get("wheel_profile", {})
	var enhanced: bool = wheel_profile.get("status") == "applied" and not gear.contacts.is_empty()
	var wind := PackedFloat64Array([-speed, 0.0, 0.0]) # from 000°, transport toward south; default runway is eastbound.
	var inv: PackedFloat64Array = RB.inertia_inverse(model.inertia)
	var free := PackedFloat64Array()
	free.resize(gear.contacts.size() * Ground.ANCHOR_STRIDE)
	var support_pose: Dictionary = GS._aft_tricycle_support_pose(gear.contacts)
	var lowest := 0.0
	if support_pose.is_empty():
		for contact: Dictionary in gear.contacts:
			lowest = maxf(lowest, float(contact.position[2]))
	else:
		lowest = maxf(0.0, float(support_pose.support_down))
	var pose := PackedFloat64Array([float(spot.north), float(spot.east),
		-(lowest - float(gear.static_sag)), 0.0, 0.0, float(spot.heading)])
	if not support_pose.is_empty():
		pose[3] = float(support_pose.roll)
		pose[4] = float(support_pose.pitch)
	var rest_evals := [0]
	var rest_last := [PackedFloat64Array()]
	var rest_sets := {}
	var rest_fn := func(x: PackedFloat64Array) -> PackedFloat64Array:
		rest_evals[0] += 1
		var p := PackedFloat64Array([float(spot.north), float(spot.east), x[0], x[1], x[2], float(spot.heading)])
		var state: PackedFloat64Array = GS._state(p)
		var accel: PackedFloat64Array = GS._accelerations(state, model, inv, gear, surfaces, deflections,
			0.0, 0.0, rho, G, free, false, wind, enhanced)
		var q: PackedFloat64Array = GS._quat(p)
		var lin: PackedFloat64Array = M.q_rotate(q, M.v3(accel[0], accel[1], accel[2]))
		var ang: PackedFloat64Array = M.q_rotate(q, M.v3(accel[3], accel[4], accel[5]))
		rest_last[0] = PackedFloat64Array([lin[2], ang[0], ang[1]])
		var active: PackedFloat64Array = Ground.anchor_step(state, gear, 0.0, surfaces, free, enhanced)
		var signature := ""
		for i in gear.contacts.size(): signature += str(active[i * Ground.ANCHOR_STRIDE + 2])
		rest_sets[signature] = int(rest_sets.get(signature, 0)) + 1
		return rest_last[0]
	var rest: Dictionary = GS._newton(rest_fn, PackedFloat64Array([pose[2], pose[3], pose[4]]))
	var anchors := PackedFloat64Array()
	var state := PackedFloat64Array()
	var idle_evals := [0]
	var idle_last := [PackedFloat64Array()]
	var idle_sets := {}
	var idle: Dictionary = {ok = false, iterations = 0, residual = INF, x = pose.duplicate()}
	if rest.ok:
		pose[2] = rest.x[0]
		pose[3] = rest.x[1]
		pose[4] = rest.x[2]
		var rest_state: PackedFloat64Array = GS._state(pose)
		anchors = Ground.anchor_step(rest_state, gear, 0.0, surfaces, free, enhanced)
		var idle_fn := func(x: PackedFloat64Array) -> PackedFloat64Array:
			idle_evals[0] += 1
			var candidate: PackedFloat64Array = GS._state(x)
			idle_last[0] = GS._accelerations(candidate, model, inv, gear, surfaces, deflections,
				0.0, rpm, rho, G, anchors, true, wind, enhanced)
			var active: PackedFloat64Array = Ground.anchor_step(candidate, gear, 0.0, surfaces, anchors, enhanced)
			var signature := ""
			for i in gear.contacts.size(): signature += str(active[i * Ground.ANCHOR_STRIDE + 2])
			idle_sets[signature] = int(idle_sets.get(signature, 0)) + 1
			return idle_last[0]
		idle = GS._newton(idle_fn, pose)
		state = GS._state(idle.x)
	var anchor_after := PackedFloat64Array()
	if not anchors.is_empty(): anchor_after = Ground.anchor_step(state, gear, 0.0, surfaces, anchors, enhanced)
	var compressions := PackedFloat64Array()
	var ground_loads := PackedFloat64Array()
	var hold_gap := INF
	if not state.is_empty() and not anchors.is_empty():
		compressions = Ground.compressions(state, gear)
		var wheel_speeds := PackedFloat64Array()
		if enhanced: wheel_speeds.resize(gear.contacts.size())
		ground_loads = Ground.loads(state, gear, 0.0, surfaces, anchors, wheel_speeds)
		var agrees := anchor_after == anchors
		hold_gap = 0.0 if agrees else 1.0
	var initial_pose := PackedFloat64Array([float(spot.north), float(spot.east),
		-(lowest - float(gear.static_sag)), 0.0, 0.0, float(spot.heading)])
	if not support_pose.is_empty():
		initial_pose[3] = float(support_pose.roll)
		initial_pose[4] = float(support_pose.pitch)
	var row := {
		"aircraft": label,
		"aircraft_id": str(model.get("id", "")),
		"wind_from_deg": 0,
		"wind_mps": speed,
		"wind_ned_mps": Array(wind),
		"rpm": rpm,
		"rho_kg_m3": rho,
		"enhanced_wheels": enhanced,
		"stage1_ok": rest.ok,
		"stage1_iterations": rest.iterations,
		"stage1_solver_residual_linf": rest.residual,
		"stage1_residual_world_down_north_east_rad": Array(rest_last[0]),
		"stage1_evaluations": rest_evals[0],
		"stage1_active_set_histogram": rest_sets,
		"stage1_initial_pose_ned_roll_pitch_yaw": Array(initial_pose),
		"stage1_pose_ned_roll_pitch_yaw": Array(PackedFloat64Array([pose[0], pose[1], pose[2], pose[3], pose[4], pose[5]])),
		"stage2_ok": idle.ok,
		"stage2_iterations": idle.iterations,
		"stage2_solver_residual_linf": idle.residual,
		"stage2_residual_body_accels_mps2_radps2": Array(idle_last[0]),
		"stage2_evaluations": idle_evals[0],
		"stage2_active_set_histogram": idle_sets,
		"stage2_candidate_pose_ned_roll_pitch_yaw": Array(PackedFloat64Array([idle.x[0], idle.x[1], idle.x[2], idle.x[3], idle.x[4], idle.x[5]])),
		"anchor_exact_match": not anchor_after.is_empty() and anchor_after == anchors,
		"compression_m": Array(compressions),
		"ground_load_body_N_Nm": Array(ground_loads),
		"total_residual_evaluations": rest_evals[0] + idle_evals[0],
		"solve_ok": rest.ok and idle.ok and not anchors.is_empty() and anchor_after == anchors,
	}
	print(JSON.stringify(row, "", false, true))
