## HELI impact contact candidates. Pure float64 simulation-space code; it does not resolve forces.
extends RefCounted

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const Terrain := preload("res://physics/ground_terrain.gd")
const GroundContact := preload("res://physics/ground_contact.gd")
const EffectiveMass := preload("res://physics/effective_mass.gd")
const SceneryCollision := preload("res://sim/scenery_collision.gd")

const SKID_TERMINAL_TRAVEL_M := 0.04
const SWEEP_SPACING_M := 0.05
const MAX_SWEEP_STEPS := 8192
const SWEEP_REFINE_STEPS := 24
const FULL_DISC_SPEED_RAD_S := 20.0
const ROTOR_SCENE_FULL_DISC_SPOKES := 32
const ROTOR_SCENE_HALF_TICK_SWEEP_M := SWEEP_SPACING_M * 0.5
const GEOMETRY_EPSILON := 1.0e-10
const WORLD_FORMAT := "openrc-collision-world v1"

# The Carenado and Botalon_Carbono AABBs are measured in the reviewed HX-700 GLB
# source audit (research/helicopter/assets/hx700_binding_candidate.json and
# docs/research/helicopter/HELI-25/README.md). Convert source XYZ (+X nose,
# +Y left, +Z up) to the builder's CG-relative FRD frame. These are estimated
# collision probes only; they do not describe material strength or mass.
const HX_CG_UP_M := 0.110
const HX_FUSELAGE_FORWARD_MIN_M := -0.10311
const HX_FUSELAGE_FORWARD_MAX_M := 0.38699999
const HX_FUSELAGE_HALF_WIDTH_M := 0.08359559
const HX_FUSELAGE_DOWN_MIN_M := HX_CG_UP_M - 0.28827199
const HX_FUSELAGE_DOWN_MAX_M := HX_CG_UP_M - 0.09539336
const HX_BOOM_FORWARD_MIN_M := -0.92400002
const HX_BOOM_FORWARD_MAX_M := -0.11
const HX_BOOM_CENTER_DOWN_M := HX_CG_UP_M - 0.197
const HX_BOOM_RADIUS_M := 0.014
const HX_FIN_FORWARD_MIN_M := -0.9948523
const HX_FIN_FORWARD_MAX_M := -0.92011452
const HX_FIN_HALF_WIDTH_M := 0.00125
const HX_FIN_DOWN_MIN_M := HX_CG_UP_M - 0.26189071
const HX_FIN_DOWN_MAX_M := HX_CG_UP_M - 0.02917617


## Builds the immutable probe/hull cache once when a rotorcraft session is prepared.
## Keep the returned dictionary unchanged for subsequent calls to evaluate().
static func prepare(context: Dictionary, skids: Dictionary) -> Dictionary:
	var invalid: String = _geometry_input_error(context, skids)
	if not invalid.is_empty():
		return {"ok": false, "error": invalid}
	var probes: Array[Dictionary] = _body_probes(skids.points_body_frd_m)
	var main: Dictionary = context.main_model
	var tail: Dictionary = context.tail_model
	var hull := PackedFloat64Array()
	for probe: Dictionary in probes:
		hull.append_array(probe.point)
	return {"ok": true, "version": 1, "probes": probes, "hull": hull,
		"hull_reach_m": _maximum_probe_reach(probes), "max_reach_m": _maximum_reach(probes, main, tail),
		"source_skids": skids.points_body_frd_m.duplicate(),
		"source_main_geometry": _main_geometry(main), "source_tail_geometry": _tail_geometry(tail)}


## Returns {ok, impact, error}. An empty impact means no terminal contact this tick.
## `continuous` is the rotorcraft's six-value coupled state prefix (optionally followed by
## skid memory); `phase` is the signed main/tail shaft phase in radians at the end of the tick.
## `prepared` is the cache returned by prepare(); omitting it remains valid but rebuilds geometry.
static func evaluate(previous_body: PackedFloat64Array, body: PackedFloat64Array,
		continuous: PackedFloat64Array, context: Dictionary, skids: Dictionary,
		surfaces: PackedFloat64Array, phase: PackedFloat64Array = PackedFloat64Array(),
		world: Dictionary = {}, prepared: Dictionary = {}) -> Dictionary:
	var invalid: String = _input_error(previous_body, body, continuous, context, skids, surfaces, phase, world)
	if not invalid.is_empty():
		return {"ok": false, "impact": {}, "error": invalid}
	if prepared.is_empty():
		prepared = prepare(context, skids)
	if not bool(prepared.get("ok", false)):
		return {"ok": false, "impact": {}, "error": str(prepared.get("error", "invalid prepared impact geometry"))}
	invalid = _prepared_error(prepared, context, skids)
	if not invalid.is_empty():
		return {"ok": false, "impact": {}, "error": invalid}
	var mass: float = float(context.mass_kg)
	var rotor_speeds: PackedFloat64Array = _rotor_speeds(continuous, context.main_model, context.tail_model)
	var max_height: float = Terrain.max_height_validated(surfaces)
	var sweep: Dictionary = _sweep_plan(previous_body, body, float(prepared.max_reach_m), max_height)
	if not bool(sweep.get("ok", false)):
		return {"ok": false, "impact": {}, "error": str(sweep.get("error", "invalid sweep"))}
	if not bool(sweep.terrain_possible) and world.is_empty():
		return {"ok": true, "impact": {}, "error": ""}
	var probes: Array[Dictionary] = prepared.probes
	var best: Dictionary = {}
	if bool(sweep.terrain_possible):
		best = _terrain_contact(previous_body, body, continuous, context, skids,
			surfaces, phase, probes, int(sweep.steps), rotor_speeds, max_height)
		if not best.is_empty() and not bool(best.get("ok", true)):
			return {"ok": false, "impact": {}, "error": str(best.get("error", "terrain sampling failed"))}
	if not world.is_empty():
		var nearby: Dictionary = _scenery_candidate_gate(previous_body, body, world, prepared, context)
		var body_candidates: Array[int] = nearby.body
		var rotor_candidates: Array[int] = nearby.rotors
		if not body_candidates.is_empty():
			var scenery: Dictionary = _first_scenery_contact(previous_body, body, world, context, prepared,
				rotor_speeds, best)
			if not scenery.is_empty() and float(scenery.time_fraction) < float(best.get("time_fraction", INF)):
				best = scenery
		if not rotor_candidates.is_empty():
			var rotor_scenery: Dictionary = _first_rotor_scenery_contact(previous_body, body, continuous,
				context, phase, world, prepared, int(sweep.steps), rotor_speeds, best, rotor_candidates)
			if not rotor_scenery.is_empty() and float(rotor_scenery.time_fraction) < float(best.get("time_fraction", INF)):
				best = rotor_scenery
	return {"ok": true, "impact": best, "error": ""}


static func _geometry_input_error(context: Dictionary, skids: Dictionary) -> String:
	if not context.has_all(["main_model", "tail_model"]):
		return "rotorcraft context is missing rotor models"
	if not context.main_model is Dictionary or not context.tail_model is Dictionary:
		return "rotor models must be dictionaries"
	for model_value: Variant in [context.main_model, context.tail_model]:
		var blade_chord: Variant = model_value.get("blade_chord_m", 0.0)
		if not _finite_number(blade_chord) or float(blade_chord) < 0.0:
			return "rotor blade chord must be finite and non-negative"
	for key: String in ["hub_x_m", "hub_y_m", "hub_z_m", "rotor_radius_m", "rotation_sense"]:
		if not _finite_number(context.main_model.get(key, NAN)):
			return "main rotor model is missing finite %s" % key
	if context.main_model.rotor_radius_m <= 0.0:
		return "main rotor radius must be positive"
	for key: String in ["hub_distance_aft_m", "hub_height_above_cg_m", "tail_rotor_radius_m",
			"tail_to_main_speed_ratio", "rotation_sense"]:
		if not _finite_number(context.tail_model.get(key, NAN)):
			return "tail rotor model is missing finite %s" % key
	if context.tail_model.tail_rotor_radius_m <= 0.0 or context.tail_model.tail_to_main_speed_ratio <= 0.0:
		return "tail rotor radius and gearing must be positive"
	if not skids.has("points_body_frd_m") or not skids.points_body_frd_m is PackedFloat64Array \
			or skids.points_body_frd_m.size() != 12 or not _finite(skids.points_body_frd_m):
		return "skids must contain four finite CG-relative FRD contact points"
	return ""


static func _main_geometry(model: Dictionary) -> PackedFloat64Array:
	return PackedFloat64Array([float(model.get("hub_x_m", NAN)), float(model.get("hub_y_m", NAN)),
		float(model.get("hub_z_m", NAN)), float(model.get("rotor_radius_m", NAN)),
		float(model.get("blade_chord_m", 0.0)), float(model.get("rotation_sense", NAN))])


static func _tail_geometry(model: Dictionary) -> PackedFloat64Array:
	return PackedFloat64Array([float(model.get("hub_distance_aft_m", NAN)),
		float(model.get("hub_height_above_cg_m", NAN)), float(model.get("tail_rotor_radius_m", NAN)),
		float(model.get("blade_chord_m", 0.0)), float(model.get("tail_to_main_speed_ratio", NAN)),
		float(model.get("rotation_sense", NAN))])


static func _prepared_error(prepared: Dictionary, context: Dictionary, skids: Dictionary) -> String:
	if int(prepared.get("version", 0)) != 1 or not prepared.get("probes") is Array \
			or not prepared.get("hull") is PackedFloat64Array or prepared.hull.is_empty() \
			or prepared.hull.size() % 3 != 0 or not _finite(prepared.hull) \
		or not _finite_number(prepared.get("hull_reach_m", NAN)) or float(prepared.hull_reach_m) <= 0.0 \
			or not _finite_number(prepared.get("max_reach_m", NAN)) or float(prepared.max_reach_m) <= 0.0:
		return "prepared impact geometry cache is malformed"
	if not _same_packed(prepared.get("source_skids", PackedFloat64Array()), skids.points_body_frd_m) \
			or not _same_packed(prepared.get("source_main_geometry", PackedFloat64Array()), _main_geometry(context.main_model)) \
			or not _same_packed(prepared.get("source_tail_geometry", PackedFloat64Array()), _tail_geometry(context.tail_model)):
		return "prepared impact geometry does not match the rotorcraft context"
	var probes: Array = prepared.probes
	if probes.size() != prepared.hull.size() / 3:
		return "prepared impact probe and hull counts differ"
	var hull_reach: float = 0.0
	for index: int in probes.size():
		if not probes[index] is Dictionary or not probes[index].get("point") is PackedFloat64Array \
				or probes[index].point.size() != 3 or not _finite(probes[index].point) \
				or not probes[index].get("component", "") is String \
				or not probes[index].get("part", "") is String \
				or not probes[index].get("method", "") is String \
				or not _finite_number(probes[index].get("threshold_m", NAN)):
			return "prepared impact probe is malformed"
		for axis: int in 3:
			if probes[index].point[axis] != prepared.hull[index * 3 + axis]:
				return "prepared impact hull does not match its probes"
		hull_reach = maxf(hull_reach, M.norm(probes[index].point))
	if not is_equal_approx(hull_reach, float(prepared.hull_reach_m)):
		return "prepared impact hull reach does not match its probes"
	var expected_max_reach: float = maxf(hull_reach,
		M.norm(M.v3(float(context.main_model.hub_x_m), float(context.main_model.hub_y_m),
			float(context.main_model.hub_z_m))) + float(context.main_model.rotor_radius_m))
	expected_max_reach = maxf(expected_max_reach,
		M.norm(M.v3(-float(context.tail_model.hub_distance_aft_m), 0.0,
			-float(context.tail_model.hub_height_above_cg_m))) + float(context.tail_model.tail_rotor_radius_m))
	if not is_equal_approx(expected_max_reach, float(prepared.max_reach_m)):
		return "prepared impact maximum reach does not match its geometry"
	return ""


static func _same_packed(a: Variant, b: PackedFloat64Array) -> bool:
	if not a is PackedFloat64Array or a.size() != b.size():
		return false
	for index: int in b.size():
		if a[index] != b[index]:
			return false
	return true


static func _input_error(previous_body: PackedFloat64Array, body: PackedFloat64Array,
		continuous: PackedFloat64Array, context: Dictionary, skids: Dictionary,
		surfaces: PackedFloat64Array, phase: PackedFloat64Array, world: Dictionary) -> String:
	if not _body_is_valid(previous_body) or not _body_is_valid(body):
		return "body states must be finite normalized 13-value float64 rigid-body states"
	if continuous.size() < 3 or not _finite(continuous):
		return "continuous state must contain finite rotor speed and two main-flap values"
	if not Terrain.is_valid_surface_table(surfaces):
		return "terrain surface table is malformed"
	if not phase.is_empty() and (phase.size() != 2 or not _finite(phase)):
		return "shaft phase must be empty or contain two finite signed angles"
	if not context.has_all(["mass_kg", "inertia_body_kg_m2", "main_model", "tail_model"]):
		return "rotorcraft context is missing mass, inertia or rotor models"
	if typeof(context.mass_kg) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(context.mass_kg)) \
			or float(context.mass_kg) <= 0.0:
		return "rotorcraft mass must be finite and positive"
	if not context.inertia_body_kg_m2 is PackedFloat64Array or context.inertia_body_kg_m2.size() != 6:
		return "body inertia must be a six-value float64 tensor"
	if not _finite(context.inertia_body_kg_m2) or context.inertia_body_kg_m2[0] <= 0.0 \
			or context.inertia_body_kg_m2[1] <= 0.0 or context.inertia_body_kg_m2[2] <= 0.0:
		return "body inertia must be finite with positive diagonal values"
	if not context.main_model is Dictionary or not context.tail_model is Dictionary:
		return "rotor models must be dictionaries"
	for key: String in ["rotor_radius_m", "hub_x_m", "hub_y_m", "hub_z_m", "rotation_sense"]:
		if not _finite_number(context.main_model.get(key, NAN)):
			return "main rotor model is missing finite %s" % key
	if context.main_model.rotor_radius_m <= 0.0:
		return "main rotor radius must be positive"
	for key: String in ["tail_rotor_radius_m", "hub_distance_aft_m", "hub_height_above_cg_m",
			"tail_to_main_speed_ratio", "rotation_sense"]:
		if not _finite_number(context.tail_model.get(key, NAN)):
			return "tail rotor model is missing finite %s" % key
	if context.tail_model.tail_rotor_radius_m <= 0.0 or context.tail_model.tail_to_main_speed_ratio <= 0.0:
		return "tail rotor radius and gearing must be positive"
	if not skids.has("points_body_frd_m") or not skids.points_body_frd_m is PackedFloat64Array \
			or skids.points_body_frd_m.size() != 12 or not _finite(skids.points_body_frd_m):
		return "skids must contain four finite CG-relative FRD contact points"
	if not world.is_empty() and not _world_is_valid(world):
		return "scenery collision world has an invalid scalar inventory header"
	return ""


static func _body_is_valid(state: PackedFloat64Array) -> bool:
	if state.size() != RB.SIZE or not _finite(state):
		return false
	var qnorm2: float = state[6] * state[6] + state[7] * state[7] + state[8] * state[8] + state[9] * state[9]
	return is_finite(qnorm2) and absf(qnorm2 - 1.0) <= 1.0e-9


static func _world_is_valid(world: Dictionary) -> bool:
	return str(world.get("format", "")) == WORLD_FORMAT and world.get("proxies") is Array \
		and world.get("bins") is Dictionary and _finite_number(world.get("cell_size_m", NAN)) \
		and float(world.cell_size_m) == 32.0


static func _body_probes(skid_points: PackedFloat64Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index: int in 4:
		result.append({"point": skid_points.slice(index * 3, index * 3 + 3),
			"component": "skid_%d" % (index + 1), "part": "landing_skid", "threshold_m": SKID_TERMINAL_TRAVEL_M,
			"method": "four_point_skid_travel"})
	for x: float in [HX_FUSELAGE_FORWARD_MIN_M, HX_FUSELAGE_FORWARD_MAX_M]:
		for y: float in [-HX_FUSELAGE_HALF_WIDTH_M, HX_FUSELAGE_HALF_WIDTH_M]:
			for z: float in [HX_FUSELAGE_DOWN_MIN_M, HX_FUSELAGE_DOWN_MAX_M]:
				result.append({"point": M.v3(x, y, z), "component": "fuselage", "part": "fuselage_bounds",
					"threshold_m": 0.0, "method": "measured_hx_carenado_aabb_probe"})
	for station: int in 9:
		var x: float = lerpf(HX_BOOM_FORWARD_MIN_M, HX_BOOM_FORWARD_MAX_M, float(station) / 8.0)
		for radial: PackedFloat64Array in [M.v3(0.0, -HX_BOOM_RADIUS_M, 0.0),
			M.v3(0.0, HX_BOOM_RADIUS_M, 0.0), M.v3(0.0, 0.0, -HX_BOOM_RADIUS_M),
			M.v3(0.0, 0.0, HX_BOOM_RADIUS_M)]:
			result.append({"point": M.v3(x, radial[1], HX_BOOM_CENTER_DOWN_M + radial[2]),
				"component": "tail_boom", "part": "boom_tube_bounds", "threshold_m": 0.0,
				"method": "measured_hx_boom_aabb_cylinder_proxy"})
	for x: float in [HX_FIN_FORWARD_MIN_M, HX_FIN_FORWARD_MAX_M]:
		for y: float in [-HX_FIN_HALF_WIDTH_M, HX_FIN_HALF_WIDTH_M]:
			for z: float in [HX_FIN_DOWN_MIN_M, HX_FIN_DOWN_MAX_M]:
				result.append({"point": M.v3(x, y, z), "component": "tail_fin", "part": "vertical_fin_bounds",
					"threshold_m": 0.0, "method": "measured_hx_fin_aabb_probe"})
	return result


static func _maximum_reach(probes: Array[Dictionary], main: Dictionary, tail: Dictionary) -> float:
	var reach: float = 0.0
	for probe: Dictionary in probes:
		reach = maxf(reach, M.norm(probe.point))
	reach = maxf(reach, M.norm(M.v3(main.hub_x_m, main.hub_y_m, main.hub_z_m)) + main.rotor_radius_m)
	reach = maxf(reach, M.norm(M.v3(-tail.hub_distance_aft_m, 0.0, -tail.hub_height_above_cg_m))
		+ tail.tail_rotor_radius_m)
	return reach


static func _maximum_probe_reach(probes: Array[Dictionary]) -> float:
	var reach: float = 0.0
	for probe: Dictionary in probes:
		reach = maxf(reach, M.norm(probe.point))
	return reach


static func _sweep_plan(previous: PackedFloat64Array, current: PackedFloat64Array,
		max_reach: float, max_height: float) -> Dictionary:
	var position_delta: PackedFloat64Array = M.sub(current.slice(0, 3), previous.slice(0, 3))
	var q0: PackedFloat64Array = previous.slice(RB.ATT, RB.ATT + 4)
	var q1: PackedFloat64Array = current.slice(RB.ATT, RB.ATT + 4)
	var qdot: float = absf(q0[0] * q1[0] + q0[1] * q1[1] + q0[2] * q1[2] + q0[3] * q1[3])
	var angle: float = 2.0 * M.acos_(clampf(qdot, -1.0, 1.0))
	var path_length: float = M.norm(position_delta) + angle * max_reach
	var steps: int = maxi(1, ceili(path_length / SWEEP_SPACING_M))
	if steps > MAX_SWEEP_STEPS:
		return {"ok": false, "error": "body sweep exceeds the bounded 0.05 m contact sampling budget"}
	var terrain_possible: bool = maxf(previous[RB.POS + 2], current[RB.POS + 2]) + max_reach + max_height > 0.0
	return {"ok": true, "steps": steps, "terrain_possible": terrain_possible}


static func _terrain_contact(previous: PackedFloat64Array, current: PackedFloat64Array,
		continuous: PackedFloat64Array, context: Dictionary, skids: Dictionary,
		surfaces: PackedFloat64Array, phase: PackedFloat64Array, probes: Array[Dictionary],
		steps: int, rotor_speeds: PackedFloat64Array, max_height: float) -> Dictionary:
	var best: Dictionary = {}
	var main_state: PackedFloat64Array = SceneryCollision.state_at_fraction(previous, current, 0.0)
	var old_probe_measures: Array[Dictionary] = []
	for probe: Dictionary in probes:
		old_probe_measures.append(_measure_body_probe(main_state, probe, surfaces, max_height))
	var old_main: Dictionary = _measure_rotor(main_state, continuous, context.main_model, true,
		phase, surfaces, rotor_speeds[0], max_height)
	var old_tail: Dictionary = _measure_rotor(main_state, continuous, context.tail_model, false,
		phase, surfaces, rotor_speeds[1], max_height)
	if not bool(old_main.get("ok", false)) or not bool(old_tail.get("ok", false)):
		return {"ok": false, "error": "rotor terrain sample failed at the start of the body sweep"}
	for step: int in range(steps + 1):
		if step == 0:
			continue
		var fraction: float = float(step) / float(steps)
		var state: PackedFloat64Array = SceneryCollision.state_at_fraction(previous, current, fraction)
		for probe_index: int in probes.size():
			var probe: Dictionary = probes[probe_index]
			var measured: Dictionary = _measure_body_probe(state, probe, surfaces, max_height)
			if not bool(measured.get("ok", false)):
				return {"ok": false, "error": str(measured.get("error", "terrain probe failed"))}
			var old_depth: float = float(old_probe_measures[probe_index].depth_m)
			if _crossed_limit(old_depth, float(measured.depth_m),
					float(probe.threshold_m)):
				var previous_fraction: float = fraction - 1.0 / float(steps)
				var at: float = previous_fraction if old_depth > float(probe.threshold_m) else _refine_probe(previous, current, probe, surfaces,
					max_height, previous_fraction, fraction)
				var contact_state: PackedFloat64Array = SceneryCollision.state_at_fraction(previous, current, at)
				var contact: Dictionary = _measure_body_probe(contact_state, probe, surfaces, max_height)
				var event: Dictionary = _make_terrain_impact(contact_state, contact, probe, at,
					context, rotor_speeds, {})
				if _precedes(event, best):
					best = event
			old_probe_measures[probe_index] = measured
		var main_measure: Dictionary = _measure_rotor(state, continuous, context.main_model, true,
			phase, surfaces, rotor_speeds[0], max_height)
		if not bool(main_measure.get("ok", false)):
			return {"ok": false, "error": str(main_measure.get("error", "main rotor terrain sample failed"))}
		var old_main_depth: float = float(old_main.depth_m)
		if _crossed_limit(old_main_depth, float(main_measure.depth_m), 0.0):
			var previous_fraction: float = fraction - 1.0 / float(steps)
			var at: float = previous_fraction if old_main_depth > 0.0 else _refine_rotor(previous, current, continuous, context.main_model, true,
				phase, surfaces, rotor_speeds[0], max_height, previous_fraction, fraction)
			var contact_state: PackedFloat64Array = SceneryCollision.state_at_fraction(previous, current, at)
			var contact: Dictionary = _measure_rotor(contact_state, continuous, context.main_model, true,
				phase, surfaces, rotor_speeds[0], max_height)
			var event: Dictionary = _make_terrain_impact(contact_state, contact, {}, at,
				context, rotor_speeds, contact.get("rotor", {}))
			if _precedes(event, best):
				best = event
		old_main = main_measure
		var tail_measure: Dictionary = _measure_rotor(state, continuous, context.tail_model, false,
			phase, surfaces, rotor_speeds[1], max_height)
		if not bool(tail_measure.get("ok", false)):
			return {"ok": false, "error": str(tail_measure.get("error", "tail rotor terrain sample failed"))}
		var old_tail_depth: float = float(old_tail.depth_m)
		if _crossed_limit(old_tail_depth, float(tail_measure.depth_m), 0.0):
			var previous_fraction: float = fraction - 1.0 / float(steps)
			var at: float = previous_fraction if old_tail_depth > 0.0 else _refine_rotor(previous, current, continuous, context.tail_model, false,
				phase, surfaces, rotor_speeds[1], max_height, previous_fraction, fraction)
			var contact_state: PackedFloat64Array = SceneryCollision.state_at_fraction(previous, current, at)
			var contact: Dictionary = _measure_rotor(contact_state, continuous, context.tail_model, false,
				phase, surfaces, rotor_speeds[1], max_height)
			var event: Dictionary = _make_terrain_impact(contact_state, contact, {}, at,
				context, rotor_speeds, contact.get("rotor", {}))
			if _precedes(event, best):
				best = event
		old_tail = tail_measure
	return best


static func _measure_body_probe(state: PackedFloat64Array, probe: Dictionary,
		surfaces: PackedFloat64Array, max_height: float) -> Dictionary:
	var down: float = _point_down_without_allocation(state, probe.point)
	if down + max_height <= float(probe.threshold_m):
		return {"ok": true, "possible": false, "depth_m": -INF}
	var q: PackedFloat64Array = state.slice(RB.ATT, RB.ATT + 4)
	var position: PackedFloat64Array = state.slice(RB.POS, RB.POS + 3)
	var offset: PackedFloat64Array = M.q_rotate(q, probe.point)
	var point: PackedFloat64Array = M.add(position, offset)
	return _terrain_sample(point, probe.point, surfaces, max_height, float(probe.threshold_m))


static func _point_down_without_allocation(state: PackedFloat64Array, body_point: PackedFloat64Array) -> float:
	var w: float = state[RB.ATT]
	var x: float = state[RB.ATT + 1]
	var y: float = state[RB.ATT + 2]
	var z: float = state[RB.ATT + 3]
	var down_x: float = 2.0 * (x * z - w * y)
	var down_y: float = 2.0 * (y * z + w * x)
	var down_z: float = 1.0 - 2.0 * (x * x + y * y)
	return state[RB.POS + 2] + down_x * body_point[0] + down_y * body_point[1] \
		+ down_z * body_point[2]


static func _measure_rotor(state: PackedFloat64Array, continuous: PackedFloat64Array,
		model: Dictionary, main_rotor: bool, phase: PackedFloat64Array,
		surfaces: PackedFloat64Array, signed_omega: float, max_height: float) -> Dictionary:
	var q: PackedFloat64Array = state.slice(RB.ATT, RB.ATT + 4)
	var hub: PackedFloat64Array
	var axis_body: PackedFloat64Array
	var radius: float
	var chord: float = float(model.get("blade_chord_m", 0.0))
	var component: String
	var method: String
	var rotor_index: int = 0 if main_rotor else 1
	if main_rotor:
		hub = M.v3(float(model.hub_x_m), float(model.hub_y_m), float(model.hub_z_m))
		var flap_a: float = float(continuous[1])
		var flap_b: float = float(continuous[2])
		axis_body = M.v3(-M.sin_(flap_a), M.sin_(flap_b), -M.cos_(flap_a) * M.cos_(flap_b))
		radius = float(model.rotor_radius_m)
		component = "main_rotor"
	else:
		hub = M.v3(-float(model.hub_distance_aft_m), 0.0, -float(model.hub_height_above_cg_m))
		axis_body = M.v3(0.0, 1.0, 0.0)
		radius = float(model.tail_rotor_radius_m)
		component = "tail_rotor"
	axis_body = M.scale(axis_body, 1.0 / M.norm(axis_body))
	var center: PackedFloat64Array = M.add(state.slice(RB.POS, RB.POS + 3), M.q_rotate(q, hub))
	var axis_down: float = _point_down_without_allocation(state, axis_body) - state[RB.POS + 2]
	axis_down = clampf(axis_down, -1.0, 1.0)
	var blade_half_chord: float = maxf(chord * 0.5, 0.0)
	var vertical_support_m: float = (radius + blade_half_chord) \
		* sqrt(maxf(0.0, 1.0 - axis_down * axis_down))
	# The whole blade, including stopped-rotor chord, lies inside this vertical support bound.
	# max_height bounds every accepted terrain surface, so safely elevated rotors need no point samples.
	if center[2] + vertical_support_m + max_height <= -1.0e-12:
		var safe_method: String = "analytic_rotating_disc_local_support_v1" \
			if absf(signed_omega) >= FULL_DISC_SPEED_RAD_S \
			else "finite_two_blade_chord_at_tick_end_proxy_v1"
		return {"ok": true, "possible": false, "depth_m": -INF,
			"point_world_ned": center, "point_body_frd": hub,
			"component": component, "method": safe_method,
			"rotating_envelope": absf(signed_omega) >= FULL_DISC_SPEED_RAD_S,
			"rotor_phase_model": "phase_at_tick_end; no_intra_tick_phase_interpolation"}
	if absf(signed_omega) >= FULL_DISC_SPEED_RAD_S:
		method = "analytic_rotating_disc_local_support_v1"
		var down: PackedFloat64Array = M.v3(0.0, 0.0, 1.0)
		var candidate: PackedFloat64Array = center.duplicate()
		var terrain: PackedFloat64Array = PackedFloat64Array()
		var radial_world: PackedFloat64Array = M.v3(0.0, 0.0, 0.0)
		for iteration: int in 4:
			var support_extent_down: float = radius if iteration == 0 else 0.0
			if candidate[2] + support_extent_down + max_height <= 0.0:
				return {"ok": true, "possible": false, "depth_m": -INF,
					"point_world_ned": candidate, "point_body_frd": hub,
					"component": component, "method": method, "rotating_envelope": true}
			terrain = Terrain.sample_validated(candidate[0], candidate[1], surfaces)
			if terrain.size() != 3 or not _finite(terrain):
				return {"ok": false, "error": "terrain sampling failed at rotor support point"}
			var ground_down: PackedFloat64Array = M.v3(terrain[1], terrain[2], 1.0)
			ground_down = M.scale(ground_down, 1.0 / M.norm(ground_down))
			var axis_world: PackedFloat64Array = M.q_rotate(q, axis_body)
			var projection: PackedFloat64Array = M.sub(ground_down,
				M.scale(axis_world, M.dot(ground_down, axis_world)))
			var projection_norm: float = M.norm(projection)
			radial_world = M.v3(0.0, 0.0, 0.0)
			if projection_norm > GEOMETRY_EPSILON:
				radial_world = M.scale(projection, radius / projection_norm)
			candidate = M.add(center, radial_world)
		var point_body: PackedFloat64Array = M.add(hub, M.q_rotate(M.q_conj(q), radial_world))
		var result: Dictionary = _terrain_sample(candidate, point_body, surfaces, max_height)
		result["method"] = method
		result["component"] = component
		result["rotor"] = {"point": point_body, "rotor_axis_body": axis_body, "hub_body": hub,
			"rotor_arm_body": M.sub(point_body, hub), "component": component,
			"speed_ratio": 1.0 if main_rotor else float(model.tail_to_main_speed_ratio)}
		result["rotating_envelope"] = true
		return result
	method = "finite_two_blade_chord_at_tick_end_proxy_v1"
	var reference: PackedFloat64Array = M.v3(1.0, 0.0, 0.0)
	var basis_u: PackedFloat64Array = M.sub(reference, M.scale(axis_body, M.dot(reference, axis_body)))
	if M.norm(basis_u) <= GEOMETRY_EPSILON:
		reference = M.v3(0.0, 0.0, 1.0)
		basis_u = M.sub(reference, M.scale(axis_body, M.dot(reference, axis_body)))
	basis_u = M.scale(basis_u, 1.0 / M.norm(basis_u))
	var basis_v: PackedFloat64Array = M.cross(axis_body, basis_u)
	var angle: float = phase[rotor_index] if phase.size() == 2 else 0.0
	var best: Dictionary = {}
	for blade: int in 2:
		var blade_angle: float = angle + float(blade) * PI
		var radial: PackedFloat64Array = M.add(M.scale(basis_u, M.cos_(blade_angle)),
			M.scale(basis_v, M.sin_(blade_angle)))
		var chord_axis: PackedFloat64Array = M.cross(axis_body, radial)
		for radius_at: float in [0.0, radius]:
			for chord_sign: float in [-1.0, 1.0]:
				var blade_arm: PackedFloat64Array = M.add(M.scale(radial, radius_at),
					M.scale(chord_axis, chord_sign * blade_half_chord))
				var point_body: PackedFloat64Array = M.add(hub, blade_arm)
				if _point_down_without_allocation(state, point_body) + max_height <= 0.0:
					continue
				var point_world: PackedFloat64Array = M.add(state.slice(RB.POS, RB.POS + 3), M.q_rotate(q, point_body))
				var measured: Dictionary = _terrain_sample(point_world, point_body, surfaces, max_height)
				if not bool(measured.get("ok", true)):
					return measured
				measured["method"] = method
				measured["component"] = component
				measured["rotor"] = {"point": point_body, "rotor_axis_body": axis_body,
					"hub_body": hub, "rotor_arm_body": blade_arm, "component": component,
					"speed_ratio": 1.0 if main_rotor else float(model.tail_to_main_speed_ratio)}
				measured["rotating_envelope"] = false
				measured["rotor_phase_model"] = "phase_at_tick_end; no_intra_tick_phase_interpolation"
				if best.is_empty() or float(measured.depth_m) > float(best.depth_m):
					best = measured
	if best.is_empty():
		best = {"ok": true, "possible": false, "depth_m": -INF,
			"point_world_ned": center, "point_body_frd": hub}
	return best


static func _terrain_sample(point_world: PackedFloat64Array, point_body: PackedFloat64Array,
		surfaces: PackedFloat64Array, max_height: float, threshold: float = 0.0) -> Dictionary:
	if point_world[2] + max_height <= threshold:
		return {"ok": true, "possible": false, "depth_m": -INF,
			"point_world_ned": point_world, "point_body_frd": point_body}
	var terrain: PackedFloat64Array = Terrain.sample_validated(point_world[0], point_world[1], surfaces)
	if terrain.size() != 3 or not _finite(terrain):
		return {"ok": false, "error": "terrain sample is invalid at a candidate contact point"}
	var normal: PackedFloat64Array = M.v3(-terrain[1], -terrain[2], -1.0)
	normal = M.scale(normal, 1.0 / M.norm(normal))
	var surface_index: int = GroundContact.surface_at(surfaces, point_world[0], point_world[1]) if not surfaces.is_empty() else -1
	var rolling_factor: float = float(surfaces[surface_index + 5]) if surface_index >= 0 else Terrain.ROLLING_ROUGH
	return {"ok": true, "depth_m": point_world[2] + terrain[0], "point_world_ned": point_world,
		"point_body_frd": point_body, "normal_world_ned": normal,
		"terrain": terrain, "surface": _surface_id(rolling_factor),
		"surface_detail": {"kind": "terrain", "row": floori(float(surface_index) / float(Terrain.SURFACE_STRIDE)) if surface_index >= 0 else -1,
			"height_up_m": terrain[0], "slope_north": terrain[1], "slope_east": terrain[2]}}


static func _surface_id(rolling_factor: float) -> String:
	if rolling_factor == Terrain.ROLLING_RUNWAY:
		return "runway"
	if rolling_factor == Terrain.ROLLING_ROTORPAD:
		return "rotorpad"
	if rolling_factor == Terrain.ROLLING_MOWN:
		return "mown"
	return "rough"


static func _crossed_limit(old_depth: float, new_depth: float, limit: float) -> bool:
	if limit > 0.0:
		return (old_depth > limit and new_depth > limit) or (old_depth <= limit and new_depth > limit)
	return (old_depth > 0.0) or (old_depth <= 0.0 and new_depth > 0.0)


static func _refine_probe(previous: PackedFloat64Array, current: PackedFloat64Array,
		probe: Dictionary, surfaces: PackedFloat64Array, max_height: float, low: float, high: float) -> float:
	for _iteration: int in SWEEP_REFINE_STEPS:
		var middle: float = 0.5 * (low + high)
		var state: PackedFloat64Array = SceneryCollision.state_at_fraction(previous, current, middle)
		var measured: Dictionary = _measure_body_probe(state, probe, surfaces, max_height)
		if float(measured.depth_m) > float(probe.threshold_m):
			high = middle
		else:
			low = middle
	return high


static func _refine_rotor(previous: PackedFloat64Array, current: PackedFloat64Array,
		continuous: PackedFloat64Array, model: Dictionary, main_rotor: bool,
		phase: PackedFloat64Array, surfaces: PackedFloat64Array, signed_omega: float, max_height: float,
		low: float, high: float) -> float:
	for _iteration: int in SWEEP_REFINE_STEPS:
		var middle: float = 0.5 * (low + high)
		var state: PackedFloat64Array = SceneryCollision.state_at_fraction(previous, current, middle)
		var measured: Dictionary = _measure_rotor(state, continuous, model, main_rotor,
			phase, surfaces, signed_omega, max_height)
		if float(measured.depth_m) > 0.0:
			high = middle
		else:
			low = middle
	return high


static func _make_terrain_impact(state: PackedFloat64Array, measured: Dictionary,
		probe: Dictionary, fraction: float, context: Dictionary,
		rotor_speeds: PackedFloat64Array, rotor_data: Dictionary = {}) -> Dictionary:
	if not bool(measured.get("ok", false)):
		return {"ok": false, "error": str(measured.get("error", "invalid terrain contact"))}
	var component: String = str(probe.get("component", measured.get("component", "")))
	var reason: String = _reason_for(component)
	var contact: Dictionary = _impact_kinematics(state, measured.point_body_frd, measured.point_world_ned,
		measured.normal_world_ned, context, rotor_speeds, rotor_data)
	contact.merge({"component": component, "reason": reason, "body": state.duplicate(),
		"point_body_frd": measured.point_body_frd.duplicate(), "point_world_ned": measured.point_world_ned.duplicate(),
		"normal_world_ned": measured.normal_world_ned.duplicate(), "surface": str(measured.surface),
		"surface_detail": measured.get("surface_detail", {}),
		"time_fraction": fraction, "penetration_m": maxf(0.0, float(measured.depth_m)),
		"contact_method": str(probe.get("method", measured.get("method", "terrain_probe"))),
		"estimated_proxy": component in ["fuselage", "tail_boom", "tail_fin"],
		"conservative_envelope": bool(measured.get("rotating_envelope", false)),
		"rotor_phase_model": str(measured.get("rotor_phase_model", ""))}, true)
	contact["point_body_frd_m"] = measured.point_body_frd.duplicate()
	return contact


static func _impact_kinematics(state: PackedFloat64Array, point_body: PackedFloat64Array,
		point_world: PackedFloat64Array, normal_world: PackedFloat64Array,
		context: Dictionary, rotor_speeds: PackedFloat64Array,
		rotor_data: Dictionary = {}) -> Dictionary:
	var q: PackedFloat64Array = state.slice(RB.ATT, RB.ATT + 4)
	var velocity_cg: PackedFloat64Array = M.q_rotate(q, state.slice(RB.VEL, RB.VEL + 3))
	var omega_body: PackedFloat64Array = state.slice(RB.RATE, RB.RATE + 3)
	var velocity_body: PackedFloat64Array = M.add(state.slice(RB.VEL, RB.VEL + 3), M.cross(omega_body, point_body))
	if not rotor_data.is_empty():
		var axis_body: PackedFloat64Array = rotor_data.rotor_axis_body
		var arm_body: PackedFloat64Array = rotor_data.rotor_arm_body
		var signed_omega: float = rotor_speeds[0] if str(rotor_data.component) == "main_rotor" else rotor_speeds[1]
		# `rotor_speeds` are signed about their physical FRD shaft axes; rotor arm is relative to hub.
		velocity_body = M.add(velocity_body, M.scale(M.cross(axis_body, arm_body), signed_omega))
	var velocity_point: PackedFloat64Array = M.q_rotate(q, velocity_body)
	var normal_component: float = M.dot(velocity_point, normal_world)
	var normal_speed: float = maxf(0.0, -normal_component)
	var tangent: PackedFloat64Array = M.sub(velocity_point, M.scale(normal_world, normal_component))
	var effective_mass: float = EffectiveMass.at_point(q, point_body, normal_world,
		float(context.mass_kg), context.inertia_body_kg_m2)
	if not rotor_data.is_empty() and effective_mass > 0.0:
		var shaft_mobility: float = _rotor_shaft_inverse_mobility(q, normal_world, rotor_data, context)
		var inverse_mass: float = 1.0 / effective_mass + shaft_mobility
		if is_finite(inverse_mass) and inverse_mass > 0.0:
			effective_mass = 1.0 / inverse_mass
	return {"velocity_world_ned": velocity_cg, "point_velocity_world_ned": velocity_point,
		"body_angular_velocity": omega_body, "normal_speed_mps": normal_speed,
		"tangent_speed_mps": M.norm(tangent), "effective_mass_kg": effective_mass,
		"normal_energy_j": 0.5 * effective_mass * normal_speed * normal_speed,
		"main_omega_rad_s": rotor_speeds[0], "tail_omega_rad_s": rotor_speeds[1]}


static func _rotor_shaft_inverse_mobility(q: PackedFloat64Array, normal_world: PackedFloat64Array,
		rotor_data: Dictionary, context: Dictionary) -> float:
	var elements: Variant = context.get("shaft_elements", [])
	if not elements is Array or elements.is_empty():
		return 0.0
	var inertia_about_main: float = 0.0
	for element_value: Variant in elements:
		if not element_value is Dictionary:
			return 0.0
		var shaft_inertia: Variant = element_value.get("inertia_kg_m2", NAN)
		var ratio: Variant = element_value.get("speed_ratio", NAN)
		if not _finite_number(shaft_inertia) or float(shaft_inertia) <= 0.0 \
				or not _finite_number(ratio) or float(ratio) <= 0.0:
			return 0.0
		inertia_about_main += float(shaft_inertia) * float(ratio) * float(ratio)
	if inertia_about_main <= 0.0:
		return 0.0
	var axis_world: PackedFloat64Array = M.q_rotate(q, rotor_data.rotor_axis_body)
	var arm_world: PackedFloat64Array = M.q_rotate(q, rotor_data.rotor_arm_body)
	var point_velocity_per_main_rad_s: PackedFloat64Array = M.scale(
		M.cross(axis_world, arm_world), float(rotor_data.speed_ratio))
	var generalized_lever: float = M.dot(normal_world, point_velocity_per_main_rad_s)
	return generalized_lever * generalized_lever / inertia_about_main


static func _first_scenery_contact(previous: PackedFloat64Array, current: PackedFloat64Array,
		world: Dictionary, context: Dictionary, prepared: Dictionary,
		rotor_speeds: PackedFloat64Array, terrain_best: Dictionary) -> Dictionary:
	var probes: Array[Dictionary] = prepared.probes
	var events: Array[SceneryCollision.Event] = SceneryCollision.contacts(previous, current, prepared.hull,
		world, int(world.get("tick", 0)), float(context.mass_kg), context.inertia_body_kg_m2,
		world.get("damage", {}))
	for event: SceneryCollision.Event in events:
		if event == null or not event.terminal or not event.has_kinematics:
			continue
		if float(event.time_fraction) >= float(terrain_best.get("time_fraction", INF)):
			continue
		var contact_state: PackedFloat64Array = event.contact_state()
		var q: PackedFloat64Array = contact_state.slice(RB.ATT, RB.ATT + 4)
		var velocity_cg: PackedFloat64Array = M.q_rotate(q, contact_state.slice(RB.VEL, RB.VEL + 3))
		var tangent: PackedFloat64Array = M.sub(event.velocity_ned,
			M.scale(event.normal_ned, M.dot(event.velocity_ned, event.normal_ned)))
		if event.point_index < 0 or event.point_index >= probes.size():
			continue
		var aircraft_probe: Dictionary = probes[event.point_index]
		var component: String = str(aircraft_probe.get("component", ""))
		if component.is_empty():
			continue
		return {"component": component, "reason": event.description(), "body": contact_state,
			"point_body_frd": event.body_point.duplicate(), "point_world_ned": event.point_ned.duplicate(),
			"normal_world_ned": event.normal_ned.duplicate(), "velocity_world_ned": velocity_cg,
			"point_velocity_world_ned": event.velocity_ned.duplicate(),
			"body_angular_velocity": contact_state.slice(RB.RATE, RB.RATE + 3),
			"normal_speed_mps": event.normal_speed_mps, "tangent_speed_mps": M.norm(tangent),
			"effective_mass_kg": event.effective_mass_kg, "normal_energy_j": event.impact_energy_j,
			"surface": str(event.obstacle_kind) if not str(event.obstacle_kind).is_empty() else "scenery",
			"surface_detail": {"kind": event.obstacle_kind, "id": event.obstacle_id,
				"part": event.obstacle_part, "aircraft_part": str(aircraft_probe.get("part", ""))},
			"obstacle_kind": event.obstacle_kind, "obstacle_id": event.obstacle_id,
			"obstacle_part": event.obstacle_part,
			"aircraft_part": str(aircraft_probe.get("part", "")),
			"main_omega_rad_s": rotor_speeds[0], "tail_omega_rad_s": rotor_speeds[1],
			"time_fraction": event.time_fraction, "penetration_m": 0.0,
			"contact_method": "swept_static_scenery_proxy_v1", "estimated_proxy": true,
			"conservative_envelope": false}
	return {}


## One bin query gates both the hull and rotor tests. In particular, skip SceneryCollision.contacts()
## when no proxy overlaps the swept hull AABB; that routine otherwise builds all probe sweeps even
## when its broadphase has no overlapping proxies.
static func _scenery_candidate_gate(previous: PackedFloat64Array, current: PackedFloat64Array,
		world: Dictionary, prepared: Dictionary, context: Dictionary) -> Dictionary:
	var hull_reach: float = float(prepared.hull_reach_m)
	var q_start: PackedFloat64Array = previous.slice(RB.ATT, RB.ATT + 4)
	var q_end: PackedFloat64Array = current.slice(RB.ATT, RB.ATT + 4)
	var hull_padding: float = SceneryCollision._rotational_chord_padding(q_start, q_end, hull_reach)
	var body_reach: float = hull_reach + hull_padding
	var max_rotor_radius: float = maxf(float(context.main_model.rotor_radius_m),
		float(context.tail_model.tail_rotor_radius_m))
	var max_chord_half: float = maxf(float(context.main_model.get("blade_chord_m", 0.0)),
		float(context.tail_model.get("blade_chord_m", 0.0))) * 0.5
	var rotor_padding: float = max_chord_half \
		+ max_rotor_radius * M.sin_(PI / (2.0 * float(ROTOR_SCENE_FULL_DISC_SPOKES))) \
		+ ROTOR_SCENE_HALF_TICK_SWEEP_M
	var rotor_reach: float = float(prepared.max_reach_m) + rotor_padding
	var union_reach: float = maxf(body_reach, rotor_reach)
	var min_n: float = minf(previous[RB.POS], current[RB.POS]) - union_reach
	var max_n: float = maxf(previous[RB.POS], current[RB.POS]) + union_reach
	var min_e: float = minf(previous[RB.POS + 1], current[RB.POS + 1]) - union_reach
	var max_e: float = maxf(previous[RB.POS + 1], current[RB.POS + 1]) + union_reach
	var min_d: float = minf(previous[RB.POS + 2], current[RB.POS + 2]) - union_reach
	var max_d: float = maxf(previous[RB.POS + 2], current[RB.POS + 2]) + union_reach
	var candidates: Array[int] = SceneryCollision._candidate_indices(world, min_n, max_n,
		min_e, max_e, min_d, max_d)
	candidates = SceneryCollision._active_candidate_indices(world, candidates, world.get("damage", {}))
	var body_candidates: Array[int] = []
	var rotor_candidates: Array[int] = []
	var body_min_n: float = minf(previous[RB.POS], current[RB.POS]) - body_reach
	var body_max_n: float = maxf(previous[RB.POS], current[RB.POS]) + body_reach
	var body_min_e: float = minf(previous[RB.POS + 1], current[RB.POS + 1]) - body_reach
	var body_max_e: float = maxf(previous[RB.POS + 1], current[RB.POS + 1]) + body_reach
	var body_min_d: float = minf(previous[RB.POS + 2], current[RB.POS + 2]) - body_reach
	var body_max_d: float = maxf(previous[RB.POS + 2], current[RB.POS + 2]) + body_reach
	var rotor_min_n: float = minf(previous[RB.POS], current[RB.POS]) - rotor_reach
	var rotor_max_n: float = maxf(previous[RB.POS], current[RB.POS]) + rotor_reach
	var rotor_min_e: float = minf(previous[RB.POS + 1], current[RB.POS + 1]) - rotor_reach
	var rotor_max_e: float = maxf(previous[RB.POS + 1], current[RB.POS + 1]) + rotor_reach
	var rotor_min_d: float = minf(previous[RB.POS + 2], current[RB.POS + 2]) - rotor_reach
	var rotor_max_d: float = maxf(previous[RB.POS + 2], current[RB.POS + 2]) + rotor_reach
	for proxy_index: int in candidates:
		var proxy: Dictionary = world.proxies[proxy_index]
		if SceneryCollision._aabb_overlap(proxy, body_min_n, body_max_n, body_min_e,
			body_max_e, body_min_d, body_max_d):
			body_candidates.append(proxy_index)
		if SceneryCollision._aabb_overlap(proxy, rotor_min_n, rotor_max_n, rotor_min_e,
			rotor_max_e, rotor_min_d, rotor_max_d):
			rotor_candidates.append(proxy_index)
	return {"body": body_candidates, "rotors": rotor_candidates}


## Sweeps rotor blade segments against nearby static scenery without adding them to the body hull.
## At high RPM, 32 diameter spokes cover the full swept disc; the proxy is inflated by the
## half-angle chord bound, half blade chord, and half the body-sweep spacing. Low RPM uses only
## the current phase diameter, so a stopped blade does not become a full circular disc.
static func _first_rotor_scenery_contact(previous: PackedFloat64Array, current: PackedFloat64Array,
		continuous: PackedFloat64Array, context: Dictionary, phase: PackedFloat64Array,
		world: Dictionary, prepared: Dictionary, steps: int, rotor_speeds: PackedFloat64Array,
		incumbent: Dictionary, shared_candidates: Array[int] = []) -> Dictionary:
	if int(steps) < 1 or int(steps) > MAX_SWEEP_STEPS:
		return {}
	if float(incumbent.get("time_fraction", INF)) <= 0.0:
		return {}
	var max_chord_half: float = maxf(float(context.main_model.get("blade_chord_m", 0.0)),
		float(context.tail_model.get("blade_chord_m", 0.0))) * 0.5
	var max_rotor_radius: float = maxf(float(context.main_model.rotor_radius_m),
		float(context.tail_model.tail_rotor_radius_m))
	var broad_padding: float = max_chord_half \
		+ max_rotor_radius * M.sin_(PI / (2.0 * float(ROTOR_SCENE_FULL_DISC_SPOKES))) \
		+ ROTOR_SCENE_HALF_TICK_SWEEP_M
	var reach: float = float(prepared.max_reach_m) + broad_padding
	var min_n: float = minf(previous[RB.POS], current[RB.POS]) - reach
	var max_n: float = maxf(previous[RB.POS], current[RB.POS]) + reach
	var min_e: float = minf(previous[RB.POS + 1], current[RB.POS + 1]) - reach
	var max_e: float = maxf(previous[RB.POS + 1], current[RB.POS + 1]) + reach
	var min_d: float = minf(previous[RB.POS + 2], current[RB.POS + 2]) - reach
	var max_d: float = maxf(previous[RB.POS + 2], current[RB.POS + 2]) + reach
	var candidates: Array[int] = shared_candidates
	if candidates.is_empty():
		candidates = SceneryCollision._candidate_indices(world,
			min_n, max_n, min_e, max_e, min_d, max_d)
		candidates = SceneryCollision._active_candidate_indices(world, candidates, world.get("damage", {}))
	if candidates.is_empty():
		return {}
	var overlapping: Array[int] = []
	for proxy_index: int in candidates:
		if SceneryCollision._aabb_overlap(world.proxies[proxy_index], min_n, max_n,
			min_e, max_e, min_d, max_d):
			overlapping.append(proxy_index)
	if overlapping.is_empty():
		return {}
	var best: Dictionary = {}
	var rotor_models: Array[Dictionary] = [context.main_model, context.tail_model]
	var sample_steps: int = 0 if _same_packed(previous, current) else steps
	for step: int in range(sample_steps + 1):
		var fraction: float = 0.0 if sample_steps == 0 else float(step) / float(sample_steps)
		if fraction >= float(incumbent.get("time_fraction", INF)) \
			or fraction > float(best.get("time_fraction", INF)):
			break
		var state: PackedFloat64Array = SceneryCollision.state_at_fraction(previous, current, fraction)
		for rotor_index: int in 2:
			var main_rotor: bool = rotor_index == 0
			var model: Dictionary = rotor_models[rotor_index]
			var signed_omega: float = rotor_speeds[rotor_index]
			var descriptor: Dictionary = _rotor_scene_descriptor(state, continuous, model, main_rotor,
				phase, signed_omega)
			var radius: float = float(descriptor.radius_m)
			var rotor_min_n: float = float(descriptor.center_world_ned[0]) - radius - float(descriptor.padding_m)
			var rotor_max_n: float = float(descriptor.center_world_ned[0]) + radius + float(descriptor.padding_m)
			var rotor_min_e: float = float(descriptor.center_world_ned[1]) - radius - float(descriptor.padding_m)
			var rotor_max_e: float = float(descriptor.center_world_ned[1]) + radius + float(descriptor.padding_m)
			var rotor_min_d: float = float(descriptor.center_world_ned[2]) - radius - float(descriptor.padding_m)
			var rotor_max_d: float = float(descriptor.center_world_ned[2]) + radius + float(descriptor.padding_m)
			for proxy_index: int in overlapping:
				var proxy: Dictionary = world.proxies[proxy_index]
				if not SceneryCollision._aabb_overlap(proxy, rotor_min_n, rotor_max_n,
					rotor_min_e, rotor_max_e, rotor_min_d, rotor_max_d):
					continue
				for spoke: Dictionary in descriptor.spokes:
					var hit: Dictionary = SceneryCollision._segment_proxy(spoke.a_world_ned,
						spoke.b_world_ned, proxy, float(descriptor.padding_m))
					if not bool(hit.get("hit", false)):
						continue
					var event: Dictionary = _make_rotor_scenery_impact(state, descriptor, spoke,
						proxy, hit, context, rotor_speeds, fraction)
					if not event.is_empty() and _precedes(event, best):
						best = event
	return best


static func _rotor_scene_descriptor(state: PackedFloat64Array, continuous: PackedFloat64Array,
		model: Dictionary, main_rotor: bool, phase: PackedFloat64Array, signed_omega: float) -> Dictionary:
	var q: PackedFloat64Array = state.slice(RB.ATT, RB.ATT + 4)
	var hub_body: PackedFloat64Array
	var axis_body: PackedFloat64Array
	var radius: float
	var component: String
	var rotor_index: int = 0 if main_rotor else 1
	if main_rotor:
		hub_body = M.v3(float(model.hub_x_m), float(model.hub_y_m), float(model.hub_z_m))
		var flap_a: float = float(continuous[1])
		var flap_b: float = float(continuous[2])
		axis_body = M.v3(-M.sin_(flap_a), M.sin_(flap_b), -M.cos_(flap_a) * M.cos_(flap_b))
		radius = float(model.rotor_radius_m)
		component = "main_rotor"
	else:
		hub_body = M.v3(-float(model.hub_distance_aft_m), 0.0, -float(model.hub_height_above_cg_m))
		axis_body = M.v3(0.0, 1.0, 0.0)
		radius = float(model.tail_rotor_radius_m)
		component = "tail_rotor"
	axis_body = M.scale(axis_body, 1.0 / M.norm(axis_body))
	var reference: PackedFloat64Array = M.v3(1.0, 0.0, 0.0)
	var basis_u: PackedFloat64Array = M.sub(reference, M.scale(axis_body, M.dot(reference, axis_body)))
	if M.norm(basis_u) <= GEOMETRY_EPSILON:
		reference = M.v3(0.0, 0.0, 1.0)
		basis_u = M.sub(reference, M.scale(axis_body, M.dot(reference, axis_body)))
	basis_u = M.scale(basis_u, 1.0 / M.norm(basis_u))
	var basis_v: PackedFloat64Array = M.cross(axis_body, basis_u)
	var center: PackedFloat64Array = M.add(state.slice(RB.POS, RB.POS + 3), M.q_rotate(q, hub_body))
	var full_disc: bool = absf(signed_omega) >= FULL_DISC_SPEED_RAD_S
	var angular_padding: float = radius * M.sin_(PI / (2.0 * float(ROTOR_SCENE_FULL_DISC_SPOKES))) \
		if full_disc else 0.0
	var chord_half: float = maxf(float(model.get("blade_chord_m", 0.0)), 0.0) * 0.5
	var padding: float = angular_padding + chord_half + ROTOR_SCENE_HALF_TICK_SWEEP_M
	var spokes: Array[Dictionary] = []
	var angle_at_end: float = phase[rotor_index] if phase.size() == 2 else 0.0
	var spoke_count: int = ROTOR_SCENE_FULL_DISC_SPOKES if full_disc else 1
	for spoke_index: int in spoke_count:
		var angle: float = angle_at_end if not full_disc else PI * float(spoke_index) / float(spoke_count)
		var radial_body: PackedFloat64Array = M.add(M.scale(basis_u, M.cos_(angle)),
			M.scale(basis_v, M.sin_(angle)))
		var offset_body: PackedFloat64Array = M.scale(radial_body, radius)
		var a_body: PackedFloat64Array = M.sub(hub_body, offset_body)
		var b_body: PackedFloat64Array = M.add(hub_body, offset_body)
		spokes.append({"a_world_ned": M.add(state.slice(RB.POS, RB.POS + 3), M.q_rotate(q, a_body)),
			"b_world_ned": M.add(state.slice(RB.POS, RB.POS + 3), M.q_rotate(q, b_body)),
			"radial_body": radial_body, "half_length_m": radius, "index": spoke_index})
	return {"component": component, "hub_body": hub_body, "axis_body": axis_body,
		"center_world_ned": center, "radius_m": radius, "padding_m": padding,
		"angular_padding_m": angular_padding, "chord_half_m": chord_half,
		"full_disc_envelope": full_disc, "spoke_count": spoke_count,
		"rotor_index": rotor_index, "speed_ratio": 1.0 if main_rotor else float(model.tail_to_main_speed_ratio),
		"method": "swept_rotor_disc_32_spoke_conservative_envelope_v1" if full_disc \
			else "finite_rotor_blade_phase_at_tick_end_v1", "spokes": spokes}


static func _make_rotor_scenery_impact(state: PackedFloat64Array, descriptor: Dictionary,
		spoke: Dictionary, proxy: Dictionary, hit: Dictionary, context: Dictionary,
		rotor_speeds: PackedFloat64Array, fraction: float) -> Dictionary:
	var segment_fraction: float = clampf(float(hit.get("fraction", 0.5)), 0.0, 1.0)
	var radial_distance: float = (2.0 * segment_fraction - 1.0) * float(spoke.half_length_m)
	var point_body: PackedFloat64Array = M.add(descriptor.hub_body,
		M.scale(spoke.radial_body, radial_distance))
	var q: PackedFloat64Array = state.slice(RB.ATT, RB.ATT + 4)
	var point_world: PackedFloat64Array = M.add(state.slice(RB.POS, RB.POS + 3), M.q_rotate(q, point_body))
	var normal_world: PackedFloat64Array = hit.get("normal", PackedFloat64Array())
	if normal_world.size() != 3 or M.norm(normal_world) <= GEOMETRY_EPSILON:
		return {}
	normal_world = M.scale(normal_world, 1.0 / M.norm(normal_world))
	var rotor_data: Dictionary = {"component": descriptor.component,
		"rotor_axis_body": descriptor.axis_body,
		"rotor_arm_body": M.sub(point_body, descriptor.hub_body),
		"speed_ratio": descriptor.speed_ratio}
	var kinematics: Dictionary = _impact_kinematics(state, point_body, point_world,
		normal_world, context, rotor_speeds, rotor_data)
	var normal_speed: float = float(kinematics.normal_speed_mps)
	if normal_speed <= 0.0 or not SceneryCollision._is_terminal_response(
		str(proxy.get("response_class", "hard_terminal")), normal_speed):
		return {}
	var normal_component: float = M.dot(kinematics.point_velocity_world_ned, normal_world)
	var tangent: PackedFloat64Array = M.sub(kinematics.point_velocity_world_ned,
		M.scale(normal_world, normal_component))
	var component: String = str(descriptor.component)
	var kind: String = str(proxy.get("kind", "scenery"))
	var obstacle_id: String = str(proxy.get("id", ""))
	var obstacle_part: String = str(proxy.get("part", ""))
	return {"component": component, "reason": "%s scenery impact (%s)" % [component.replace("_", " "), obstacle_id],
		"body": state.duplicate(), "point_body_frd": point_body, "point_body_frd_m": point_body.duplicate(),
		"point_world_ned": point_world, "normal_world_ned": normal_world,
		"velocity_world_ned": kinematics.velocity_world_ned,
		"point_velocity_world_ned": kinematics.point_velocity_world_ned,
		"body_angular_velocity": kinematics.body_angular_velocity,
		"normal_speed_mps": normal_speed, "tangent_speed_mps": M.norm(tangent),
		"effective_mass_kg": kinematics.effective_mass_kg, "normal_energy_j": kinematics.normal_energy_j,
		"main_omega_rad_s": rotor_speeds[0], "tail_omega_rad_s": rotor_speeds[1],
		"surface": kind, "surface_detail": {"kind": kind, "id": obstacle_id,
			"part": obstacle_part, "aircraft_part": "%s_blade" % component},
		"obstacle_kind": kind, "obstacle_id": obstacle_id, "obstacle_part": obstacle_part,
		"aircraft_part": "%s_blade" % component, "time_fraction": fraction,
		"penetration_m": 0.0, "contact_method": descriptor.method,
		"estimated_proxy": true, "conservative_envelope": true,
		"rotor_angular_envelope": bool(descriptor.full_disc_envelope),
		"rotor_phase_model": "full_disc_spatial_envelope; phase_window_unavailable" \
			if bool(descriptor.full_disc_envelope) else "phase_at_tick_end; no_intra_tick_phase_interpolation",
		"rotor_spoke_count": descriptor.spoke_count, "rotor_clearance_padding_m": descriptor.padding_m,
		"rotor_angular_gap_bound_m": descriptor.angular_padding_m,
		"rotor_blade_half_chord_m": descriptor.chord_half_m,
		"sweep_half_step_bound_m": ROTOR_SCENE_HALF_TICK_SWEEP_M}


static func _rotor_speeds(continuous: PackedFloat64Array, main: Dictionary,
		tail: Dictionary) -> PackedFloat64Array:
	return PackedFloat64Array([float(continuous[0]) * float(main.rotation_sense),
		float(continuous[0]) * float(tail.tail_to_main_speed_ratio) * float(tail.rotation_sense)])


static func _reason_for(component: String) -> String:
	match component:
		"main_rotor": return "main rotor ground strike"
		"tail_rotor": return "tail rotor ground strike"
		"fuselage": return "fuselage ground strike"
		"tail_boom": return "tail boom ground strike"
		"tail_fin": return "tail fin ground strike"
		_: return "hard landing: skid travel exceeded"


static func _precedes(candidate: Dictionary, incumbent: Dictionary) -> bool:
	return not candidate.is_empty() and (incumbent.is_empty()
		or float(candidate.get("time_fraction", INF)) < float(incumbent.get("time_fraction", INF)))


static func _finite_number(value: Variant) -> bool:
	return typeof(value) in [TYPE_FLOAT, TYPE_INT] and is_finite(float(value))


static func _finite(values: PackedFloat64Array) -> bool:
	for value: float in values:
		if not is_finite(value):
			return false
	return true
