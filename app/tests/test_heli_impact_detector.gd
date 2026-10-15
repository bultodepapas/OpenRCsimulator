extends SceneTree

const FieldLoader := preload("res://data/field_loader.gd")
const RotorcraftData := preload("res://physics/rotorcraft_data.gd")
const GroundStart := preload("res://physics/rotorcraft/ground_start.gd")
const GroundSurfaces := preload("res://physics/ground_surfaces.gd")
const Terrain := preload("res://physics/ground_terrain.gd")
const M := preload("res://physics/math3d.gd")
const Detector := preload("res://physics/rotorcraft/impact_detector.gd")

var _checks: int = 0
var _failures: int = 0


func _check(label: String, condition: bool, detail: String = "") -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _evaluate(previous: PackedFloat64Array, current: PackedFloat64Array,
		context: Dictionary, skids: Dictionary, surfaces: PackedFloat64Array,
		continuous: PackedFloat64Array, phase: PackedFloat64Array, prepared: Dictionary) -> Dictionary:
	return Detector.evaluate(previous, current, continuous, context, skids, surfaces, phase, {}, prepared)


func _set_attitude(state: PackedFloat64Array, q: PackedFloat64Array) -> void:
	for index: int in 4:
		state[6 + index] = q[index]


func _contact_bracket(state: PackedFloat64Array, depth_at_reference: float) -> Array[PackedFloat64Array]:
	var previous: PackedFloat64Array = state.duplicate()
	var current: PackedFloat64Array = state.duplicate()
	previous[2] = 1.0 - depth_at_reference - 0.002
	current[2] = previous[2] + 0.004
	current[5] = 1.0
	return [previous, current]


func _initialize() -> void:
	_run()


func _run() -> void:
	var field_result: Dictionary = FieldLoader.load_from()
	var aircraft_result: Dictionary = RotorcraftData.load_file("res://data/aircraft/xcell_60_research.json")
	_check("field and measured rotorcraft load", bool(field_result.get("ok", false)) and bool(aircraft_result.get("ok", false)))
	if not bool(field_result.get("ok", false)) or not bool(aircraft_result.get("ok", false)):
		quit(1)
		return
	var field: Dictionary = field_result.field
	var aircraft: Dictionary = aircraft_result
	var start: Dictionary = GroundStart.resolve(field, aircraft)
	_check("static pad state resolves", bool(start.get("ok", false)), str(start.get("reason", "")))
	if not bool(start.get("ok", false)):
		quit(1)
		return
	var context: Dictionary = aircraft.context
	var skids: Dictionary = aircraft.skids
	var table: Dictionary = GroundSurfaces.load_table()
	var built: Dictionary = GroundSurfaces.build(table.table, field)
	var surfaces: PackedFloat64Array = built.rects
	var rest: PackedFloat64Array = start.state.duplicate()
	var continuous := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	var phase := PackedFloat64Array([0.0, 0.0])
	var prepared: Dictionary = Detector.prepare(context, skids)
	_check("prepared probe cache is valid", bool(prepared.get("ok", false)) and prepared.probes.size() >= 50)
	if not bool(prepared.get("ok", false)):
		quit(1)
		return

	var rest_result: Dictionary = _evaluate(rest, rest, context, skids, surfaces, continuous, phase, prepared)
	_check("ground rest produces no crash", bool(rest_result.get("ok", false)) and rest_result.impact.is_empty(), str(rest_result))
	var soft: PackedFloat64Array = rest.duplicate()
	soft[2] += 0.02
	var soft_result: Dictionary = _evaluate(rest, soft, context, skids, surfaces, continuous, phase, prepared)
	_check("sub-4 cm skid travel remains a soft contact", bool(soft_result.get("ok", false)) and soft_result.impact.is_empty(), str(soft_result))

	var hard: PackedFloat64Array = rest.duplicate()
	hard[2] += 0.06
	hard[5] = 2.0
	var hard_result: Dictionary = _evaluate(rest, hard, context, skids, surfaces, continuous, phase, prepared)
	_check("hard skid compression creates a terminal report", bool(hard_result.get("ok", false)) and not hard_result.impact.is_empty(), str(hard_result))
	if not hard_result.impact.is_empty():
		var impact: Dictionary = hard_result.impact
		_check("hard landing identifies a physical airframe component", str(impact.component) in [
			"skid_1", "skid_2", "skid_3", "skid_4", "fuselage", "tail_boom", "tail_fin",
			"main_rotor", "tail_rotor"], str(impact.component))
		_check("impact report contains body and contact kinematics",
			impact.body is PackedFloat64Array and impact.point_body_frd is PackedFloat64Array
			and impact.point_world_ned is PackedFloat64Array and impact.normal_world_ned is PackedFloat64Array
			and impact.velocity_world_ned is PackedFloat64Array and impact.point_velocity_world_ned is PackedFloat64Array
			and impact.body_angular_velocity is PackedFloat64Array, str(impact.keys()))
		_check("impact report contains physical grading and string surface",
			impact.effective_mass_kg > 0.0 and impact.normal_speed_mps > 0.0 and impact.normal_energy_j > 0.0
			and impact.surface is String and impact.has("surface_detail"), str(impact))
		_check("terrain detail records sampled local height and normal source",
			impact.surface_detail.get("kind", "") == "terrain" and impact.surface_detail.has("height_up_m"),
			str(impact.surface_detail))

	var sweep_end: PackedFloat64Array = rest.duplicate()
	sweep_end[2] += 0.12
	sweep_end[5] = 3.0
	var sweep_result: Dictionary = _evaluate(rest, sweep_end, context, skids, surfaces, continuous, phase, prepared)
	_check("fast body sweep finds an intermediate hard landing", bool(sweep_result.get("ok", false))
		and not sweep_result.impact.is_empty() and sweep_result.impact.time_fraction > 0.0
		and sweep_result.impact.time_fraction < 1.0, str(sweep_result))

	var bad_state: PackedFloat64Array = rest.duplicate()
	bad_state[6] = 2.0
	var malformed: Dictionary = _evaluate(rest, bad_state, context, skids, surfaces, continuous, phase, prepared)
	_check("malformed attitude returns an error without fake crash", not bool(malformed.get("ok", true))
		and malformed.get("impact", {}) is Dictionary and malformed.impact.is_empty(), str(malformed))
	var bad_surfaces := PackedFloat64Array([1.0])
	malformed = _evaluate(rest, rest, context, skids, bad_surfaces, continuous, phase, prepared)
	_check("malformed terrain table returns an error without fake crash", not bool(malformed.get("ok", true))
		and malformed.get("impact", {}) is Dictionary and malformed.impact.is_empty(), str(malformed))
	var stale_cache: Dictionary = prepared.duplicate(true)
	stale_cache.source_skids[0] += 0.01
	malformed = _evaluate(rest, rest, context, skids, surfaces, continuous, phase, stale_cache)
	_check("cache tied to another contact layout fails closed", not bool(malformed.get("ok", true))
		and malformed.impact.is_empty(), str(malformed))
	var corrupt_reach: Dictionary = prepared.duplicate(true)
	corrupt_reach.hull_reach_m += 0.1
	malformed = _evaluate(rest, rest, context, skids, surfaces, continuous, phase, corrupt_reach)
	_check("mutable prepared reach cache is revalidated", not bool(malformed.get("ok", true))
		and malformed.impact.is_empty(), str(malformed))

	_test_rotor_and_rollover(context, skids, surfaces, rest, phase)
	_test_rotor_scenery(context, skids, surfaces, rest)
	print("HELI impact detector: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)


func _test_rotor_and_rollover(context: Dictionary, skids: Dictionary, surfaces: PackedFloat64Array,
		base: PackedFloat64Array, phase: PackedFloat64Array) -> void:
	var max_height: float = Terrain.max_height_validated(surfaces)
	var yaw: float = M.q_to_euler(base.slice(6, 10))[0]

	var main_context: Dictionary = context.duplicate(true)
	main_context.tail_model.tail_to_main_speed_ratio = 0.01
	var main_prepared: Dictionary = Detector.prepare(main_context, skids)
	var main_continuous := PackedFloat64Array([100.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	var main_reference: PackedFloat64Array = base.duplicate()
	_set_attitude(main_reference, M.q_from_euler(yaw, -PI / 2.0, 0.0))
	main_reference[2] = 1.0
	var main_speed: float = main_continuous[0] * float(main_context.main_model.rotation_sense)
	var main_support: Dictionary = Detector._measure_rotor(main_reference, main_continuous,
		main_context.main_model, true, phase, surfaces, main_speed, max_height)
	var main_bracket: Array[PackedFloat64Array] = _contact_bracket(main_reference, float(main_support.depth_m))
	var main_result: Dictionary = _evaluate(main_bracket[0], main_bracket[1], main_context, skids,
		surfaces, main_continuous, phase, main_prepared)
	_check("full rotating main-disc contact is detected", bool(main_result.get("ok", false))
		and str(main_result.get("impact", {}).get("component", "")) == "main_rotor",
		"support=%s impact=%s" % [str(main_support), str(main_result.get("impact", {}))])

	var tail_context: Dictionary = context.duplicate(true)
	var tail_prepared: Dictionary = Detector.prepare(tail_context, skids)
	var tail_continuous := PackedFloat64Array([168.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	var tail_reference: PackedFloat64Array = base.duplicate()
	_set_attitude(tail_reference, M.q_from_euler(yaw, 0.4, PI))
	# Match the authored crash fixture: 0.65 m CG height, 0.4 rad pitch, inverted roll.
	tail_reference[2] = -0.65
	var tail_speed: float = tail_continuous[0] * float(tail_context.tail_model.tail_to_main_speed_ratio) \
		* float(tail_context.tail_model.rotation_sense)
	var tail_support: Dictionary = Detector._measure_rotor(tail_reference, tail_continuous,
		tail_context.tail_model, false, phase, surfaces, tail_speed, max_height)
	var tail_previous: PackedFloat64Array = tail_reference.duplicate()
	var tail_current: PackedFloat64Array = tail_reference.duplicate()
	tail_current[2] += 0.15
	tail_current[5] = 2.5
	var tail_result: Dictionary = _evaluate(tail_previous, tail_current, tail_context, skids,
		surfaces, tail_continuous, phase, tail_prepared)
	_check("rotating tail-disc contact is detected", bool(tail_result.get("ok", false))
		and str(tail_result.get("impact", {}).get("component", "")) == "tail_rotor",
		"support=%s impact=%s" % [str(tail_support), str(tail_result.get("impact", {}))])

	var rollover_context: Dictionary = context.duplicate(true)
	rollover_context.main_model.rotor_radius_m = 0.001
	rollover_context.tail_model.tail_rotor_radius_m = 0.001
	# Move the test-only rotor hubs clear of this inverted pose so the fuselage proxy is isolated.
	rollover_context.main_model.hub_z_m = 2.0
	rollover_context.tail_model.hub_height_above_cg_m = -2.0
	var rollover_prepared: Dictionary = Detector.prepare(rollover_context, skids)
	var rollover_reference: PackedFloat64Array = base.duplicate()
	_set_attitude(rollover_reference, M.q_from_euler(yaw, 0.0, PI))
	rollover_reference[2] = 1.0
	var max_fuselage_depth: float = -INF
	for probe: Dictionary in rollover_prepared.probes:
		if str(probe.component) != "fuselage":
			continue
		var measured: Dictionary = Detector._measure_body_probe(rollover_reference, probe, surfaces, max_height)
		max_fuselage_depth = maxf(max_fuselage_depth, float(measured.depth_m))
	var fuselage_bracket: Array[PackedFloat64Array] = _contact_bracket(rollover_reference, max_fuselage_depth)
	var rollover_result: Dictionary = _evaluate(fuselage_bracket[0], fuselage_bracket[1], rollover_context,
		skids, surfaces, PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0]), phase, rollover_prepared)
	_check("inverted fuselage collision is separated from skid and rotor contact",
		bool(rollover_result.get("ok", false)) and str(rollover_result.get("impact", {}).get("component", "")) == "fuselage",
		str(rollover_result.get("impact", {})))


func _test_rotor_scenery(context: Dictionary, skids: Dictionary, surfaces: PackedFloat64Array,
		base: PackedFloat64Array) -> void:
	var scene_context: Dictionary = context.duplicate(true)
	scene_context.main_model.hub_z_m = -2.0
	scene_context.main_model.blade_chord_m = 0.0
	scene_context.tail_model.tail_rotor_radius_m = 0.001
	var prepared: Dictionary = Detector.prepare(scene_context, skids)
	_check("rotor scenery cache remains valid", bool(prepared.get("ok", false)), str(prepared.get("error", "")))
	if not bool(prepared.get("ok", false)):
		return
	var state: PackedFloat64Array = base.duplicate()
	_set_attitude(state, M.q_from_euler(0.0, 0.0, 0.0))
	state[0] = 5.0
	state[1] = 5.0
	state[2] = -10.0
	var rotor_center: PackedFloat64Array = PackedFloat64Array([
		state[0] + float(scene_context.main_model.hub_x_m),
		state[1] + float(scene_context.main_model.hub_y_m),
		state[2] + float(scene_context.main_model.hub_z_m),
	])
	var radius: float = float(scene_context.main_model.rotor_radius_m) * 0.9
	var gap_angle: float = PI / (2.0 * 32.0)
	var gap_point: PackedFloat64Array = PackedFloat64Array([
		rotor_center[0] + radius * cos(gap_angle),
		rotor_center[1] - radius * sin(gap_angle), rotor_center[2],
	])
	var high_world: Dictionary = _capsule_world(gap_point, "fence_between_spokes")
	var high_gate: Dictionary = Detector._scenery_candidate_gate(state, state, high_world, prepared, scene_context)
	_check("shared scenery broadphase routes rotor-only obstacles without hull work",
		high_gate.body.is_empty() and not high_gate.rotors.is_empty(), str(high_gate))
	var high_continuous := PackedFloat64Array([168.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	var phase := PackedFloat64Array([0.0, 0.0])
	var high_result: Dictionary = Detector.evaluate(state, state, high_continuous,
		scene_context, skids, surfaces, phase, high_world, prepared)
	var high_impact: Dictionary = high_result.get("impact", {})
	_check("rotating disc envelope catches an obstacle between spokes", bool(high_result.get("ok", false))
		and str(high_impact.get("component", "")) == "main_rotor"
		and str(high_impact.get("obstacle_kind", "")) == "fence", str(high_impact))
	if not high_impact.is_empty():
		_check("rotor scenery keeps aircraft part separate from obstacle and labels padding",
			high_impact.get("surface") is String and high_impact.get("aircraft_part", "") == "main_rotor_blade"
			and high_impact.get("obstacle_id", "") == "fence_between_spokes"
			and high_impact.get("conservative_envelope", false)
			and high_impact.get("rotor_spoke_count", 0) == 32
			and high_impact.get("rotor_angular_gap_bound_m", 0.0) > 0.0
			and high_impact.get("rotor_clearance_padding_m", 0.0) >= high_impact.rotor_angular_gap_bound_m,
			str(high_impact))

	var slow_world: Dictionary = _capsule_world(PackedFloat64Array([
		rotor_center[0], rotor_center[1] - radius * 0.8, rotor_center[2],
	]), "stationary_off_blade")
	var stopped := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	var stopped_result: Dictionary = Detector.evaluate(state, state, stopped,
		scene_context, skids, surfaces, phase, slow_world, prepared)
	_check("stopped blade phase does not become a full disc", bool(stopped_result.get("ok", false))
		and stopped_result.get("impact", {}).is_empty(), str(stopped_result.get("impact", {})))

	var on_blade_world: Dictionary = _capsule_world(PackedFloat64Array([
		rotor_center[0] + radius * 0.8, rotor_center[1] + 0.01, rotor_center[2],
	]), "stationary_on_blade")
	state[4] = 2.0
	var on_blade_result: Dictionary = Detector.evaluate(state, state, stopped,
		scene_context, skids, surfaces, phase, on_blade_world, prepared)
	_check("stopped blade still contacts scenery along its tick-end phase",
		bool(on_blade_result.get("ok", false))
		and str(on_blade_result.get("impact", {}).get("component", "")) == "main_rotor"
		and str(on_blade_result.get("impact", {}).get("rotor_phase_model", "")).begins_with("phase_at_tick_end"),
		str(on_blade_result.get("impact", {})))

	var empty_world: Dictionary = {"format": "openrc-collision-world v1", "cell_size_m": 32.0,
		"proxies": [], "bins": {}, "tick": 0, "damage": {}}
	var empty_result: Dictionary = Detector.evaluate(state, state, stopped,
		scene_context, skids, surfaces, phase, empty_world, prepared)
	_check("empty scenery bins return without a false rotor impact",
		bool(empty_result.get("ok", false)) and empty_result.get("impact", {}).is_empty(), str(empty_result))
	var distant_world: Dictionary = _capsule_world(PackedFloat64Array([500.0, 500.0, 500.0]), "distant_fence")
	var distant_gate: Dictionary = Detector._scenery_candidate_gate(state, state,
		distant_world, prepared, scene_context)
	_check("shared scenery broadphase rejects distant proxies before probe sweeps",
		distant_gate.body.is_empty() and distant_gate.rotors.is_empty(), str(distant_gate))


func _capsule_world(point: PackedFloat64Array, obstacle_id: String) -> Dictionary:
	var radius: float = 0.005
	var half_length: float = 0.02
	var bounds := PackedFloat64Array([point[0] - radius, point[0] + radius,
		point[1] - radius, point[1] + radius,
		point[2] - radius - half_length, point[2] + radius + half_length])
	var proxy: Dictionary = {"id": obstacle_id, "kind": "fence", "part": "post",
		"shape": "capsule", "response_class": "hard_terminal", "north": point[0],
		"east": point[1], "down": point[2], "radius": radius, "half_length": half_length,
		"half_x": 0.0, "half_down": 0.0, "half_z": 0.0, "sin_heading": 0.0,
		"cos_heading": 1.0, "bounds_north_min": bounds[0], "bounds_north_max": bounds[1],
		"bounds_east_min": bounds[2], "bounds_east_max": bounds[3],
		"bounds_down_min": bounds[4], "bounds_down_max": bounds[5]}
	var min_n: int = floori(bounds[0] / 32.0)
	var max_n: int = floori(bounds[1] / 32.0)
	var min_e: int = floori(bounds[2] / 32.0)
	var max_e: int = floori(bounds[3] / 32.0)
	var min_d: int = floori(bounds[4] / 32.0)
	var max_d: int = floori(bounds[5] / 32.0)
	var bins: Dictionary = {}
	for n_cell: int in range(min_n, max_n + 1):
		for e_cell: int in range(min_e, max_e + 1):
			for d_cell: int in range(min_d, max_d + 1):
				bins["%d,%d,%d" % [n_cell, e_cell, d_cell]] = PackedInt64Array([0])
	return {"format": "openrc-collision-world v1", "cell_size_m": 32.0,
		"proxies": [proxy], "bins": bins, "tick": 0, "damage": {}}
