# E3b2/R04: bounded, dimensionless runway equilibrium search. Pure; 64-bit floats only; no session mutation.
# Stage 1 solves the engine-off support pose. Stage 2 solves all six idle accelerations while retaining the exact
# support anchors. Uniform wind is part of both residual functions, so zero body speed does not imply zero airspeed.
extends RefCounted
const FixedDatum := preload("res://physics/fixed_datum_body.gd")

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const Dynamics := preload("res://physics/dynamics.gd")
const GroundTerrain := preload("res://physics/ground_terrain.gd")
const GroundEffect := preload("res://physics/ground_effect.gd")
const Ground := preload("res://physics/ground_contact.gd")
const GroundWheels := preload("res://physics/ground_wheels.gd")
const RetractableGear := preload("res://physics/retractable_gear.gd")
const Air := preload("res://physics/air_data.gd")
const WindFlow := preload("res://physics/wind_aircraft_flow.gd")

## Residual accelerations (m/s², rad/s²) below which the pose counts as solved.
const TOLERANCE := 1e-11
const MAX_ITERATIONS := 40
## Central-difference step for the Jacobian (m and rad).
const STEP := 1e-6
const SCALED_TOLERANCE := 1e-9
const MAX_STAGE_ITERATIONS := 64
const MAX_BACKTRACK_TRIALS := 8
const MAX_RESIDUAL_EVALUATIONS := 4096
const FD_STEP_SCALED := 1e-5
const FD_MAX_SHRINKS := 5
const PIVOT_RELATIVE_FLOOR := 1e-12
const MAX_HORIZONTAL_START_SHIFT := 0.010
const MAX_HEADING_START_SHIFT := 0.0017453292519943296 # 0.1 degree
## E3b2 default line-up: the CG this far inside the runway's end (m, estimated: a few metres, so the tail is on it).
const LINEUP := 3.0


## The start spot at a runway end, facing along the runway. `field` is a loaded field (FieldLoader); east_bound starts
## at the west end heading east. Returns { ok, north, east, heading (rad, 0 = north, π/2 = east), message }.
static func threshold(field: Dictionary, east_bound := true, lineup := LINEUP) -> Dictionary:
	for s in field.get("surfaces", []):
		if s.get("type", "") == "runway":
			var half: float = float(s.length_east_west) / 2.0
			var center_east: float = s.center_east
			return { ok = true, north = float(s.center_north), east = center_east - half + lineup if east_bound else center_east + half - lineup,
				heading = PI / 2.0 if east_bound else -PI / 2.0, message = "" }
	return { ok = false, north = 0.0, east = 0.0, heading = 0.0, message = "field has no runway" }


## Solve the start. model: AircraftData model with stiction gear; surfaces: the field's surface table; d: aerodynamic
## deflections (radians, Aero convention); steer: the rudder servo position (nose wheel); rpm: the idling engine.
## Returns a pure start candidate plus bounded numerical/contact diagnostics. Failure results publish no partial state.
## Optional candidate_air_at_state(state, rho) must return a matching R2 stage Air receipt on every residual query;
## unsupported or malformed local-flow samples refuse the solve. Omitting it preserves the uniform-wind path.
static func solve(model: Dictionary, surfaces: PackedFloat64Array, north: float, east: float, heading: float,
		d: Dictionary, steer: float, rpm: float, rho: float, g: float,
		wind_ned: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0]), enhanced := false,
		environment_at_state: Callable = Callable(), candidate_air_at_state: Callable = Callable()) -> Dictionary:
	if wind_ned.size() != 3:
		return _fail("runway start needs three NED wind components")
	for value: float in wind_ned:
		if not is_finite(value):
			return _fail("runway start needs finite NED wind")
	for value in [north, east, heading, steer, rpm, rho, g]:
		if not is_finite(value):
			return _fail("runway start needs finite position, heading, controls, rpm, density and gravity")
	if rpm < 0.0 or rho < 0.0 or g <= 0.0:
		return _fail("runway start needs nonnegative rpm/density and positive gravity")
	for axis in ["elevator", "aileron_left", "aileron_right", "rudder"]:
		var angle: Variant = d.get(axis)
		if (typeof(angle) != TYPE_FLOAT and typeof(angle) != TYPE_INT) or not is_finite(angle):
			return _fail("runway start needs a finite " + axis + " deflection")
	var gear: Dictionary = model.get("landing_gear", {})
	if gear.is_empty() or not gear.has("breakaway_factor"):
		return _fail("runway start needs landing gear with stiction data (breakaway_factor)")
	var inv := RB.inertia_inverse(model.inertia)
	var free := PackedFloat64Array()
	free.resize(gear.contacts.size() * Ground.ANCHOR_STRIDE)
	var length_scale := _characteristic_length(gear)
	var budget := {"evaluations": 0, "feasibility_checks": 0, "max_evaluations": MAX_RESIDUAL_EVALUATIONS}
	var environment_stats := {"queries": 0, "minimum_rho_kgm3": INF, "maximum_rho_kgm3": -INF}
	var environment_error := [""]
	var candidate_air_stats := {"queries": 0}
	var candidate_air_error := [""]
	# Stage 1 starts from the existing contact-plane seed.
	var lowest := 0.0 # deepest contact below the CG (body z, down)
	var support_pose: Dictionary = _aft_tricycle_support_pose(gear.contacts)
	if support_pose.is_empty():
		# Keep the established seed for nose-wheel aircraft and geometries without a three-point support plane.
		for c in gear.contacts:
			lowest = maxf(lowest, float(c.position[2]))
	else:
		lowest = maxf(0.0, float(support_pose.support_down))
	var pose := PackedFloat64Array([north, east, -(lowest - float(gear.static_sag)), 0.0, 0.0, heading])
	if not support_pose.is_empty():
		pose[3] = float(support_pose.roll)
		pose[4] = float(support_pose.pitch)
	var seed_q := _quat(pose)
	var rest_state_at: Callable = func(x: PackedFloat64Array) -> PackedFloat64Array:
		var local_rotation := _rotation_increment(PackedFloat64Array([x[1], x[2], 0.0]))
		var q := M.q_normalized(M.q_mul(seed_q, local_rotation))
		return _state_with_quaternion(north, east, x[0], q)
	var rest_residual: Callable = func(x: PackedFloat64Array) -> PackedFloat64Array:
		var state: PackedFloat64Array = rest_state_at.call(x)
		var local_environment := _environment_density(environment_at_state, state, rho, environment_stats)
		if not local_environment.ok:
			environment_error[0] = str(local_environment.error)
			return PackedFloat64Array([NAN, NAN, NAN])
		var candidate_air: Dictionary = {}
		if candidate_air_at_state.is_valid():
			var air_sample := _candidate_air_sample(candidate_air_at_state, state,
				float(local_environment.rho_kgm3), candidate_air_stats)
			if not air_sample.ok:
				candidate_air_error[0] = str(air_sample.error)
				return PackedFloat64Array([NAN, NAN, NAN])
			candidate_air = air_sample.air
		var a := _accelerations(state, model, inv, gear, surfaces, d, steer, 0.0,
			float(local_environment.rho_kgm3), g, free, false, wind_ned, enhanced, candidate_air)
		var q := PackedFloat64Array([state[RB.ATT], state[RB.ATT + 1], state[RB.ATT + 2], state[RB.ATT + 3]])
		var lin := M.q_rotate(q, M.v3(a[0], a[1], a[2]))
		var ang := M.q_rotate(q, M.v3(a[3], a[4], a[5]))
		return PackedFloat64Array([lin[2], ang[0], ang[1]])
	var rest_feasible: Callable = func(x: PackedFloat64Array) -> Dictionary:
		budget.feasibility_checks = int(budget.feasibility_checks) + 1
		return _contact_feasibility(rest_state_at.call(x), gear, surfaces, PackedFloat64Array(), false, steer, enhanced)
	var rest := _bounded_scaled_newton(rest_residual, PackedFloat64Array([pose[2], 0.0, 0.0]),
		PackedFloat64Array([length_scale, 1.0, 1.0]), PackedFloat64Array([g, g / length_scale, g / length_scale]),
		rest_feasible, budget, "engine_off")
	var diagnostics := {
		"format": "openrc-runway-equilibrium-diagnostics-v1",
		"length_scale_m": length_scale,
		"length_scale_definition": "max_i norm(contact_position_i), floored at 0.1 m",
		"scaled_residual_target": SCALED_TOLERANCE,
		"residual_evaluation_budget": MAX_RESIDUAL_EVALUATIONS,
		"requested_pose_ned_heading": PackedFloat64Array([north, east, heading]),
		"initial_pose_ned_yaw_pitch_roll": PackedFloat64Array([pose[0], pose[1], pose[5], pose[4], pose[3]]),
		"stage1": rest.diagnostics,
		"stage2": {},
		"contact_summary": [],
		"total_residual_evaluations": int(budget.evaluations),
		"feasibility_checks": int(budget.feasibility_checks),
		"environment": _environment_summary(environment_at_state, environment_stats, ""),
	}
	if candidate_air_at_state.is_valid():
		diagnostics["candidate_air"] = _candidate_air_summary(candidate_air_stats, "")
	if not rest.ok:
		diagnostics.total_residual_evaluations = int(budget.evaluations)
		diagnostics.feasibility_checks = int(budget.feasibility_checks)
		diagnostics.environment = _environment_summary(environment_at_state, environment_stats, environment_error[0])
		var rest_reason := "engine-off support pose unresolved: " + str(rest.reason)
		if candidate_air_error[0] != "":
			diagnostics.candidate_air = _candidate_air_summary(candidate_air_stats, candidate_air_error[0])
			rest_reason = "candidate_air_at_state rejected engine-off residual: " + candidate_air_error[0]
		elif environment_error[0] != "":
			rest_reason = "environment_at_state rejected engine-off residual: " + environment_error[0]
		return _start_failure(rest_reason, diagnostics,
			rest.iterations, rest.residual, rest.scaled_residual)
	var rest_state: PackedFloat64Array = rest_state_at.call(rest.x)
	var rest_ypr: PackedFloat64Array = M.q_to_euler(PackedFloat64Array([
		rest_state[RB.ATT], rest_state[RB.ATT + 1], rest_state[RB.ATT + 2], rest_state[RB.ATT + 3]]))
	pose[2] = rest.x[0]
	pose[3] = rest_ypr[2]
	pose[4] = rest_ypr[1]
	pose[5] = rest_ypr[0]
	var anchors := Ground.anchor_step(rest_state, gear, steer, surfaces, free, enhanced)
	for i in gear.contacts.size():
		if anchors[i * Ground.ANCHOR_STRIDE + 2] != 1.0:
			diagnostics.contact_summary = _contact_feasibility(rest_state, gear, surfaces, PackedFloat64Array(), false, steer, enhanced).contacts
			return _start_failure("contact %d did not latch at the engine-off support pose" % i, diagnostics,
				rest.iterations, rest.residual, rest.scaled_residual)
	var rest_q := PackedFloat64Array([rest_state[RB.ATT], rest_state[RB.ATT + 1], rest_state[RB.ATT + 2], rest_state[RB.ATT + 3]])
	var idle_state_at: Callable = func(x: PackedFloat64Array) -> PackedFloat64Array:
		var local_rotation := _rotation_increment(PackedFloat64Array([x[3], x[4], x[5]]))
		var q := M.q_normalized(M.q_mul(rest_q, local_rotation))
		return _state_with_quaternion(north + x[0], east + x[1], rest.x[0] + x[2], q)
	var idle_residual: Callable = func(x: PackedFloat64Array) -> PackedFloat64Array:
		var state: PackedFloat64Array = idle_state_at.call(x)
		var local_environment := _environment_density(environment_at_state, state, rho, environment_stats)
		if not local_environment.ok:
			environment_error[0] = str(local_environment.error)
			return PackedFloat64Array([NAN, NAN, NAN, NAN, NAN, NAN])
		var candidate_air: Dictionary = {}
		if candidate_air_at_state.is_valid():
			var air_sample := _candidate_air_sample(candidate_air_at_state, state,
				float(local_environment.rho_kgm3), candidate_air_stats)
			if not air_sample.ok:
				candidate_air_error[0] = str(air_sample.error)
				return PackedFloat64Array([NAN, NAN, NAN, NAN, NAN, NAN])
			candidate_air = air_sample.air
		return _accelerations(state, model, inv, gear, surfaces, d, steer, rpm,
			float(local_environment.rho_kgm3), g, anchors, true, wind_ned, enhanced, candidate_air)
	var idle_feasible: Callable = func(x: PackedFloat64Array) -> Dictionary:
		var state: PackedFloat64Array = idle_state_at.call(x)
		var horizontal_shift := M.sqrt_(x[0] * x[0] + x[1] * x[1])
		var yaw := M.q_to_euler(PackedFloat64Array([state[RB.ATT], state[RB.ATT + 1], state[RB.ATT + 2], state[RB.ATT + 3]]))[0]
		var heading_shift := wrapf(yaw - heading, -PI, PI)
		var rotation_shift := M.norm(PackedFloat64Array([x[3], x[4], x[5]]))
		budget.feasibility_checks = int(budget.feasibility_checks) + 1
		if horizontal_shift > MAX_HORIZONTAL_START_SHIFT + 1.0e-12:
			return {ok = false, signature = "", contacts = [], reason = "horizontal placement limit exceeded"}
		if absf(heading_shift) > MAX_HEADING_START_SHIFT + 1.0e-12:
			return {ok = false, signature = "", contacts = [], reason = "heading placement limit exceeded"}
		if rotation_shift >= PI:
			return {ok = false, signature = "", contacts = [], reason = "local rotation left the principal rotation chart"}
		var support: Dictionary = _contact_feasibility(state, gear, surfaces, anchors, true, steer, enhanced)
		support["pose_delta"] = PackedFloat64Array([x[0], x[1], x[2], heading_shift])
		return support
	var idle := _bounded_scaled_newton(idle_residual, PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0]),
		PackedFloat64Array([length_scale, length_scale, length_scale, 1.0, 1.0, 1.0]),
		PackedFloat64Array([g, g, g, g / length_scale, g / length_scale, g / length_scale]),
		idle_feasible, budget, "idle")
	diagnostics.stage2 = idle.diagnostics
	diagnostics.total_residual_evaluations = int(budget.evaluations)
	diagnostics.feasibility_checks = int(budget.feasibility_checks)
	diagnostics.environment = _environment_summary(environment_at_state, environment_stats, environment_error[0])
	if candidate_air_at_state.is_valid():
		diagnostics.candidate_air = _candidate_air_summary(candidate_air_stats, candidate_air_error[0])
	if not idle.ok:
		var idle_reason := "idle support pose unresolved: " + str(idle.reason)
		if candidate_air_error[0] != "":
			idle_reason = "candidate_air_at_state rejected idle residual: " + candidate_air_error[0]
		elif environment_error[0] != "":
			idle_reason = "environment_at_state rejected idle residual: " + environment_error[0]
		return _start_failure(idle_reason, diagnostics,
			rest.iterations + idle.iterations, idle.residual, idle.scaled_residual)
	var state: PackedFloat64Array = idle_state_at.call(idle.x)
	if not _finite_size(state, 13) or not _finite_size(rest_state, 13) or not _finite_size(anchors, free.size()):
		return _start_failure("nonfinite runway start state or anchors", diagnostics,
			rest.iterations + idle.iterations, INF, INF)
	if Ground.anchor_step(state, gear, steer, surfaces, anchors, enhanced) != anchors:
		return _start_failure("idle thrust exceeds the wheels' static hold", diagnostics,
			rest.iterations + idle.iterations, idle.residual, idle.scaled_residual)
	var final_contacts: Dictionary = _contact_feasibility(state, gear, surfaces, anchors, true, steer, enhanced)
	diagnostics.contact_summary = final_contacts.contacts
	var final_ypr: PackedFloat64Array = M.q_to_euler(PackedFloat64Array([
		state[RB.ATT], state[RB.ATT + 1], state[RB.ATT + 2], state[RB.ATT + 3]]))
	diagnostics.final_pose_ned_yaw_pitch_roll = PackedFloat64Array([state[RB.POS], state[RB.POS + 1], state[RB.POS + 2],
		final_ypr[0], final_ypr[1], final_ypr[2]])
	diagnostics.achieved_minus_requested = PackedFloat64Array([state[RB.POS] - north, state[RB.POS + 1] - east,
		state[RB.POS + 2] - pose[2], wrapf(final_ypr[0] - heading, -PI, PI)])
	return { ok = true, status = "converged", state = state, anchors = anchors, rest_state = rest_state,
		iterations = rest.iterations + idle.iterations, residual = idle.residual, scaled_residual = idle.scaled_residual,
		diagnostics = diagnostics, message = "" }


## Sample density at the candidate state. An absent callback preserves the legacy scalar-density behavior.
static func _environment_density(environment_at_state: Callable, state: PackedFloat64Array,
		fallback_rho: float, stats: Dictionary) -> Dictionary:
	if not environment_at_state.is_valid():
		return {"ok": true, "rho_kgm3": fallback_rho}
	stats["queries"] = int(stats.get("queries", 0)) + 1
	var sample: Variant = environment_at_state.call(state)
	if typeof(sample) != TYPE_DICTIONARY:
		return {"ok": false, "error": "callback must return an environment Dictionary"}
	var environment: Dictionary = sample
	if not bool(environment.get("ok", false)):
		return {"ok": false, "error": "atmosphere query reported failure: " + str(environment.get("errors", []))}
	var density: Variant = environment.get("rho_kgm3")
	if (typeof(density) != TYPE_FLOAT and typeof(density) != TYPE_INT) \
			or not is_finite(float(density)) or float(density) <= 0.0:
		return {"ok": false, "error": "environment rho_kgm3 must be finite and positive"}
	var local_rho := float(density)
	stats["minimum_rho_kgm3"] = minf(float(stats.get("minimum_rho_kgm3", INF)), local_rho)
	stats["maximum_rho_kgm3"] = maxf(float(stats.get("maximum_rho_kgm3", -INF)), local_rho)
	return {"ok": true, "rho_kgm3": local_rho}


## Candidate mode accepts only a complete R2 stage Air receipt for this exact state and density.
## The callback samples on every residual evaluation; it must not cache or reuse receipts across candidates.
static func _candidate_air_sample(candidate_air_at_state: Callable, state: PackedFloat64Array,
		rho_kgm3: float, stats: Dictionary) -> Dictionary:
	stats["queries"] = int(stats.get("queries", 0)) + 1
	var sample: Variant = candidate_air_at_state.call(state.duplicate(), rho_kgm3)
	if typeof(sample) != TYPE_DICTIONARY:
		return {"ok": false, "error": "callback must return a stage Air Dictionary"}
	var receipt: Dictionary = sample
	if not bool(receipt.get("ok", false)):
		return {"ok": false, "error": "stage Air callback reported failure: " + str(receipt.get("errors", []))}
	var air_value: Variant = receipt.get("air")
	if typeof(air_value) != TYPE_DICTIONARY:
		return {"ok": false, "error": "stage Air callback must include an air Dictionary"}
	var air: Dictionary = air_value
	if air.get("spatial_air_law", "") != WindFlow.STAGE_AIR_LAW or not WindFlow.matches_stage(air, state, rho_kgm3):
		return {"ok": false, "error": "air must be a matching R2 stage receipt for the candidate state and density"}
	var v_air: Variant = air.get("v_air")
	if typeof(v_air) != TYPE_PACKED_FLOAT64_ARRAY or not _finite_size(v_air, 3):
		return {"ok": false, "error": "air.v_air must contain three finite body-frame components"}
	var qbar: Variant = air.get("qbar")
	if (typeof(qbar) != TYPE_FLOAT and typeof(qbar) != TYPE_INT) or not is_finite(float(qbar)) or float(qbar) < 0.0:
		return {"ok": false, "error": "air.qbar must be finite and nonnegative"}
	return {"ok": true, "air": air}


static func _candidate_air_summary(stats: Dictionary, error: String) -> Dictionary:
	return {"source": "candidate_air_at_state", "queries": int(stats.get("queries", 0)), "error": error}


static func _environment_summary(environment_at_state: Callable, stats: Dictionary, error: String) -> Dictionary:
	var uses_callback := environment_at_state.is_valid()
	var minimum_rho := float(stats.get("minimum_rho_kgm3", INF))
	var maximum_rho := float(stats.get("maximum_rho_kgm3", -INF))
	return {
		"source": "state_callback" if uses_callback else "scalar_argument",
		"queries": int(stats.get("queries", 0)),
		"minimum_rho_kgm3": minimum_rho if is_finite(minimum_rho) else null,
		"maximum_rho_kgm3": maximum_rho if is_finite(maximum_rho) else null,
		"error": error,
	}


## Seed an aft third contact from the rigid plane through two lateral main contacts and the aft wheel.
## Nose-wheel aircraft retain the original level seed. Positions are AircraftData body-FRD coordinates.
static func _aft_tricycle_support_pose(contacts: Array) -> Dictionary:
	if contacts.size() != 3:
		return {}
	var positions: Array[PackedFloat64Array] = []
	for contact: Dictionary in contacts:
		var value: Variant = contact.get("position")
		if typeof(value) != TYPE_PACKED_FLOAT64_ARRAY or value.size() != 3:
			return {}
		positions.append(value)
	var pair_a := -1
	var pair_b := -1
	var widest := 0.0
	for i in positions.size():
		for j in range(i + 1, positions.size()):
			var lateral_width: float = absf(positions[i][1] - positions[j][1])
			if lateral_width > widest:
				widest = lateral_width
				pair_a = i
				pair_b = j
	if pair_a < 0 or pair_b < 0:
		return {}
	var aft := 3 - pair_a - pair_b
	var axle_x: float = 0.5 * (positions[pair_a][0] + positions[pair_b][0])
	if positions[aft][0] >= axle_x:
		return {} # The lone contact is ahead of the main axle (a nose wheel).
	var lateral_edge: PackedFloat64Array = M.sub(positions[pair_b], positions[pair_a])
	var aft_edge: PackedFloat64Array = M.sub(positions[aft], positions[pair_a])
	var normal: PackedFloat64Array = M.cross(lateral_edge, aft_edge)
	var normal_length: float = M.norm(normal)
	if not is_finite(normal_length) or normal_length <= 1e-9:
		return {}
	normal = M.scale(normal, 1.0 / normal_length)
	if normal[2] < 0.0:
		normal = M.scale(normal, -1.0)
	if normal[2] <= 1e-6:
		return {}
	var pitch: float = M.atan2_(-normal[0], M.sqrt_(normal[1] * normal[1] + normal[2] * normal[2]))
	var roll: float = M.atan2_(normal[1], normal[2])
	var support_down := -INF
	for position: PackedFloat64Array in positions:
		support_down = maxf(support_down, M.dot(normal, position))
	return { pitch = pitch, roll = roll, support_down = support_down }


## Body accelerations [u̇, v̇, ẇ, ṗ, q̇, ṙ] at state s (zero velocity and rates) from aero, propulsion (when running)
## and the gear with the given anchors.
static func _accelerations(s: PackedFloat64Array, model: Dictionary, inv: PackedFloat64Array, gear: Dictionary,
		surfaces: PackedFloat64Array, d: Dictionary, steer: float, rpm: float, rho: float, g: float,
		anchors: PackedFloat64Array, engine: bool,
		wind_ned: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0]), enhanced := false,
		candidate_air: Dictionary = {}) -> PackedFloat64Array:
	var loads := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	if engine or wind_ned[0] != 0.0 or wind_ned[1] != 0.0 or wind_ned[2] != 0.0 or not candidate_air.is_empty():
		# M5-GE-1: on the runway the session evaluates aero with the terrain height under the CG; the static solve must
		# see the same ground (zero airspeed gives zero aero either way; wind does not).
		var ground_up: float = GroundTerrain.sample_validated(s[RB.POS], s[RB.POS + 1], surfaces)[0] \
			if GroundEffect.enabled(model) else NAN
		if candidate_air.is_empty():
			loads = Dynamics.loads(s, model, d, rpm if engine else 0.0, rho, wind_ned, NAN, PackedFloat64Array(), ground_up)
		else:
			loads = Dynamics.loads_from_air(s, model, d, rpm if engine else 0.0, rho, candidate_air,
				NAN, PackedFloat64Array(), ground_up)
		if RetractableGear.enabled(gear):
			var drag: PackedFloat64Array
			if candidate_air.is_empty():
				drag = RetractableGear.drag_loads(s, Air.compute(s, wind_ned, rho).v_air, gear, 1.0, rho)
			else:
				var ambient_delta: PackedFloat64Array = candidate_air.ambient_delta_body_at.call(gear.retraction.drag_center)
				drag = RetractableGear.drag_loads(s, candidate_air.v_air, gear, 1.0, rho, ambient_delta)
			for i in drag.size(): loads[i] += drag[i]
	var wheels := PackedFloat64Array()
	if enhanced:
		wheels.resize(gear.contacts.size())
	var ground := Ground.loads(s, gear, steer, surfaces, anchors, wheels)
	for i in ground.size():
		loads[i] += ground[i]
	var derivative := RB.derivative(s, model.mass_kg, model.inertia, inv, M.v3(loads[0], loads[1], loads[2]),
		M.v3(loads[3], loads[4], loads[5]), g, Dynamics.rotor_momentum(model, rpm) if engine else PackedFloat64Array())
	if model.has("trim_mass_properties"):
		var properties: Dictionary = model.trim_mass_properties
		var force: PackedFloat64Array = loads.slice(0, 3)
		var moment: PackedFloat64Array = M.sub(loads.slice(3, 6), M.cross(properties.cg_body_m, force))
		derivative = FixedDatum.derivative(s, properties, force, moment, g,
			Dynamics.rotor_momentum(model, rpm) if engine else PackedFloat64Array())
	return PackedFloat64Array([derivative[RB.VEL], derivative[RB.VEL + 1], derivative[RB.VEL + 2],
		derivative[RB.RATE], derivative[RB.RATE + 1], derivative[RB.RATE + 2]])


## Pose [north, east, down, roll, pitch, yaw] → state at rest.
static func _state(p: PackedFloat64Array) -> PackedFloat64Array:
	var q := _quat(p)
	return PackedFloat64Array([p[0], p[1], p[2], 0.0, 0.0, 0.0, q[0], q[1], q[2], q[3], 0.0, 0.0, 0.0])


static func _quat(p: PackedFloat64Array) -> PackedFloat64Array:
	return M.q_from_euler(p[5], p[4], p[3])


## Newton's method with a central-difference Jacobian and partial-pivot elimination.
static func _newton(residual: Callable, x0: PackedFloat64Array) -> Dictionary:
	var x := x0.duplicate()
	var n := x.size()
	var iterations := 0
	if n == 0 or not _finite_size(x, n):
		return { ok = false, x = x, residual = INF, iterations = iterations }
	var r: PackedFloat64Array = residual.call(x)
	var norm := _norm(r) if r.size() == n else INF
	while is_finite(norm) and norm > TOLERANCE and iterations < MAX_ITERATIONS:
		var jacobian := PackedFloat64Array()
		jacobian.resize(n * n)
		for j in n:
			var plus := x.duplicate()
			var minus := x.duplicate()
			plus[j] += STEP
			minus[j] -= STEP
			var rp: PackedFloat64Array = residual.call(plus)
			var rm: PackedFloat64Array = residual.call(minus)
			if not _finite_size(rp, n) or not _finite_size(rm, n):
				return { ok = false, x = x, residual = INF, iterations = iterations }
			for i in n:
				jacobian[i * n + j] = (rp[i] - rm[i]) / (2.0 * STEP)
		var dx := _linear_solve(jacobian, r, n)
		if dx.is_empty():
			break
		for i in n:
			x[i] -= dx[i]
		if not _finite_size(x, n):
			return { ok = false, x = x, residual = INF, iterations = iterations }
		r = residual.call(x)
		norm = _norm(r) if r.size() == n else INF
		iterations += 1
	return { ok = is_finite(norm) and norm <= TOLERANCE, x = x, residual = norm, iterations = iterations }


## Bounded local SO(3) exponential: vector is a body-local rotation increment in radians.
static func _rotation_increment(rotation: PackedFloat64Array) -> PackedFloat64Array:
	if rotation.size() != 3 or not _finite_size(rotation, 3):
		return PackedFloat64Array()
	var angle := M.norm(rotation)
	if not is_finite(angle):
		return PackedFloat64Array()
	if angle < 1.0e-8:
		var a2 := angle * angle
		var q := PackedFloat64Array([1.0 - a2 / 8.0,
			(0.5 - a2 / 48.0) * rotation[0], (0.5 - a2 / 48.0) * rotation[1], (0.5 - a2 / 48.0) * rotation[2]])
		return M.q_normalized(q)
	var half := 0.5 * angle
	var scale := M.sin_(half) / angle
	return PackedFloat64Array([M.cos_(half), rotation[0] * scale, rotation[1] * scale, rotation[2] * scale])


static func _state_with_quaternion(north: float, east: float, down: float, q: PackedFloat64Array) -> PackedFloat64Array:
	if q.size() != 4 or not _finite_size(q, 4):
		return PackedFloat64Array()
	return PackedFloat64Array([north, east, down, 0.0, 0.0, 0.0, q[0], q[1], q[2], q[3], 0.0, 0.0, 0.0])


## Largest contact-arm norm gives a declared aircraft scale; the 0.1 m floor protects tiny fixtures.
static func _characteristic_length(gear: Dictionary) -> float:
	var length := 0.0
	for contact: Dictionary in gear.get("contacts", []):
		var position: Variant = contact.get("position")
		if typeof(position) == TYPE_PACKED_FLOAT64_ARRAY and position.size() == 3 and _finite_size(position, 3):
			length = maxf(length, M.norm(position))
	return maxf(0.1, length)


## Enforce contact travel, positive support, anchor persistence and the modeled static friction envelope.
## `signature` identifies piecewise support/clamp branches for finite-difference and line-search consistency.
static func _contact_feasibility(state: PackedFloat64Array, gear: Dictionary, surfaces: PackedFloat64Array,
		anchors: PackedFloat64Array, require_anchors: bool, steer: float, enhanced: bool) -> Dictionary:
	if not _finite_size(state, 13) or gear.get("contacts", []).is_empty():
		return {ok = false, signature = "", contacts = [], reason = "invalid contact state or gear"}
	var next_anchors := Ground.anchor_step(state, gear, steer, surfaces, anchors, enhanced)
	if next_anchors.size() != anchors.size() or not _finite_size(next_anchors, anchors.size()):
		return {ok = false, signature = "", contacts = [], reason = "anchor evaluation is invalid"}
	if require_anchors and next_anchors != anchors:
		return {ok = false, signature = "", contacts = [], reason = "one or more support anchors released"}
	var contacts: Array = []
	var signature := ""
	var valid := true
	var reason := ""
	for i in gear.contacts.size():
		var contact: Dictionary = gear.contacts[i]
		var frame: Dictionary = GroundWheels.frame(state, contact, steer, surfaces)
		var compression := float(frame.get("compression", NAN))
		var normal_load := float(frame.get("normal_load", NAN))
		var max_compression := float(contact.get("max_compression", INF))
		var heading_ok := bool(frame.get("valid_heading", false))
		var loaded := compression > 0.0 and normal_load > 0.0
		var anchor_index: int = i * Ground.ANCHOR_STRIDE
		var stuck: bool = anchors.size() == gear.contacts.size() * Ground.ANCHOR_STRIDE and anchors[anchor_index + 2] == 1.0
		var next_stuck: bool = next_anchors.size() == gear.contacts.size() * Ground.ANCHOR_STRIDE \
			and next_anchors[anchor_index + 2] == 1.0
		var anchor_dx := 0.0
		var anchor_de := 0.0
		var request_long := 0.0
		var request_side := 0.0
		var hold_limit := 0.0
		var side_limit := 0.0
		var friction_margin := 0.0
		var long_branch := 0
		var side_branch := 0
		var circle_branch := 0
		if stuck and loaded and heading_ok:
			anchor_dx = float(frame.position[0]) - anchors[anchor_index]
			anchor_de = float(frame.position[1]) - anchors[anchor_index + 1]
			var displacement := M.v3(anchor_dx, anchor_de, 0.0)
			request_long = -float(contact.get("anchor_stiffness", 0.0)) * M.dot(displacement, frame.heading)
			request_side = -float(contact.get("anchor_stiffness", 0.0)) * M.dot(displacement, frame.side)
			if enhanced:
				var coeff := GroundWheels.coefficients(gear, contact, surfaces, frame.position)
				side_limit = maxf(0.0, coeff[0] * normal_load)
				hold_limit = maxf(0.0, float(gear.get("breakaway_factor", 1.0)) * coeff[1] * normal_load)
			else:
				var mu := float(gear.get("side_friction", 0.0))
				var rolling := float(gear.get("rolling_resistance", 0.0))
				if not surfaces.is_empty():
					var at := Ground.surface_at(surfaces, frame.position[0], frame.position[1])
					mu *= surfaces[at + 4]
					rolling *= surfaces[at + 5]
				side_limit = maxf(0.0, mu * normal_load)
				hold_limit = maxf(0.0, float(gear.get("breakaway_factor", 1.0)) * rolling * normal_load)
			if absf(request_long) > hold_limit:
				long_branch = 1 if request_long > 0.0 else -1
			if absf(request_side) > side_limit:
				side_branch = 1 if request_side > 0.0 else -1
			var requested_norm := M.sqrt_(request_long * request_long + request_side * request_side)
			friction_margin = side_limit - requested_norm
			if requested_norm > side_limit:
				circle_branch = 1
			elif side_limit > 0.0 and requested_norm >= side_limit * (1.0 - 1.0e-10):
				circle_branch = -1
		var anchor_ok: bool = not require_anchors or next_stuck
		var contact_ok := is_finite(compression) and is_finite(normal_load) and is_finite(max_compression) \
			and compression > 0.0 and normal_load > 0.0 and compression <= max_compression \
			and heading_ok and anchor_ok and absf(request_long) <= hold_limit + 1.0e-10 \
			and absf(request_side) <= side_limit + 1.0e-10 \
			and request_long * request_long + request_side * request_side <= side_limit * side_limit + 1.0e-10
		if not contact_ok:
			valid = false
			if reason.is_empty():
				reason = "contact %d is outside compression/support/anchor friction bounds" % i
		signature += ("1" if loaded else "0") + ("h" if heading_ok else "x") + ("a" if stuck else "s") \
			+ str(long_branch) + "," + str(side_branch) + "," + str(circle_branch) + ";"
		contacts.append({"name": str(contact.get("name", i)), "compression_m": compression,
			"max_compression_m": max_compression, "normal_load_n": normal_load, "loaded": loaded,
			"heading_valid": heading_ok, "anchor_stuck": stuck, "anchor_delta_ned_m": PackedFloat64Array([anchor_dx, anchor_de]),
			"longitudinal_anchor_request_n": request_long, "lateral_anchor_request_n": request_side,
			"longitudinal_hold_limit_n": hold_limit, "lateral_friction_limit_n": side_limit,
			"anchor_friction_margin_n": friction_margin, "next_anchor_stuck": next_stuck})
	return {ok = valid, signature = signature, contacts = contacts, reason = reason}


## Scaled Newton with local linear rotations, branch-aware finite differences, trust clipping and bounded search.
static func _bounded_scaled_newton(residual: Callable, x0: PackedFloat64Array, variable_scales: PackedFloat64Array,
		residual_scales: PackedFloat64Array, feasible: Callable, budget: Dictionary, stage_name: String) -> Dictionary:
	var x := x0.duplicate()
	var n := x.size()
	var details := {"stage": stage_name, "variable_scales": variable_scales.duplicate(),
		"residual_scales": residual_scales.duplicate(), "finite_difference_scaled_step": FD_STEP_SCALED,
		"finite_difference_physical_steps": PackedFloat64Array(), "residual_units": [],
		"scaled_tolerance": SCALED_TOLERANCE, "iteration_limit": MAX_STAGE_ITERATIONS,
		"accepted_steps": [], "active_set_stencil_rejections": 0, "one_sided_columns": 0,
		"max_derivative_step_relative_difference": 0.0, "min_pivot": INF, "max_pivot": 0.0,
		"pivot_ratio_proxy": 0.0, "initial_residual": PackedFloat64Array(), "final_residual": PackedFloat64Array(),
		"initial_scaled_residual": PackedFloat64Array(), "final_scaled_residual": PackedFloat64Array(),
		"initial_contact_state": {}, "final_contact_state": {}, "finite_difference_steps_used": PackedFloat64Array(),
		"evaluations_at_stage_start": int(budget.get("evaluations", 0)), "evaluations": 0,
		"feasibility_checks_at_stage_start": int(budget.get("feasibility_checks", 0)), "iterations": 0,
		"reason": ""}
	for scale in variable_scales:
		details.finite_difference_physical_steps.append(float(scale) * FD_STEP_SCALED)
	for i in residual_scales.size():
		details.residual_units.append("m/s^2" if i < 3 else "rad/s^2")
	if n == 3:
		details.residual_units = ["world_down_m/s^2", "world_north_rad/s^2", "world_east_rad/s^2"]
	if n == 6:
		details.residual_units = ["body_forward_m/s^2", "body_right_m/s^2", "body_down_m/s^2",
			"body_roll_rad/s^2", "body_pitch_rad/s^2", "body_yaw_rad/s^2"]
	if n <= 0 or n != residual_scales.size() or n != variable_scales.size() \
		or not _finite_size(x, n) or not _finite_size(variable_scales, n) or not _finite_size(residual_scales, n):
		return {ok = false, x = x, residual = INF, scaled_residual = INF, iterations = 0,
			reason = "malformed scaled solver inputs", diagnostics = details}
	for scale in variable_scales:
		if scale <= 0.0:
			return {ok = false, x = x, residual = INF, scaled_residual = INF, iterations = 0,
				reason = "nonpositive variable scale", diagnostics = details}
	for scale in residual_scales:
		if scale <= 0.0:
			return {ok = false, x = x, residual = INF, scaled_residual = INF, iterations = 0,
				reason = "nonpositive residual scale", diagnostics = details}
	var current_feasibility: Dictionary = feasible.call(x)
	details.initial_contact_state = current_feasibility
	if not current_feasibility.get("ok", false):
		details.reason = str(current_feasibility.get("reason", "initial pose is outside feasibility bounds"))
		return {ok = false, x = x, residual = INF, scaled_residual = INF, iterations = 0,
			reason = details.reason, diagnostics = details}
	var evaluated := _scaled_residual(residual, x, residual_scales, budget)
	if not evaluated.ok:
		details.reason = str(evaluated.reason)
		return {ok = false, x = x, residual = INF, scaled_residual = INF, iterations = 0,
			reason = details.reason, diagnostics = details}
	var raw: PackedFloat64Array = evaluated.raw
	var scaled: PackedFloat64Array = evaluated.scaled
	var raw_norm := _norm(raw)
	var scaled_norm := _norm(scaled)
	details.initial_residual = raw.duplicate()
	details.initial_scaled_residual = scaled.duplicate()
	var iterations := 0
	while iterations < MAX_STAGE_ITERATIONS:
		if scaled_norm <= SCALED_TOLERANCE and raw_norm <= TOLERANCE:
			details.reason = "converged"
			break
		iterations += 1
		details.iterations = iterations
		var jacobian := PackedFloat64Array()
		jacobian.resize(n * n)
		var derivative_failed := ""
		for column in n:
			var derivative: Dictionary = _scaled_jacobian_column(residual, x, raw, scaled, residual_scales,
				variable_scales, column, current_feasibility, feasible, budget)
			details.active_set_stencil_rejections = int(details.active_set_stencil_rejections) + int(derivative.get("rejections", 0))
			if derivative.get("one_sided", false):
				details.one_sided_columns = int(details.one_sided_columns) + 1
			details.max_derivative_step_relative_difference = maxf(float(details.max_derivative_step_relative_difference),
				float(derivative.get("relative_difference", 0.0)))
			if details.finite_difference_steps_used.size() <= column:
				details.finite_difference_steps_used.append(float(derivative.get("used_scaled_step", 0.0)))
			else:
				details.finite_difference_steps_used[column] = float(derivative.get("used_scaled_step", 0.0))
			if not derivative.get("ok", false):
				derivative_failed = str(derivative.get("reason", "finite-difference stencil unavailable"))
				break
			var values: PackedFloat64Array = derivative.values
			for row in n:
				jacobian[row * n + column] = values[row]
		if not derivative_failed.is_empty():
			details.reason = derivative_failed
			break
		var linear: Dictionary = _bounded_linear_solve(jacobian, scaled, n)
		details.min_pivot = minf(float(details.min_pivot), float(linear.get("min_pivot", INF)))
		details.max_pivot = maxf(float(details.max_pivot), float(linear.get("max_pivot", 0.0)))
		if float(details.min_pivot) < INF and float(details.max_pivot) > 0.0:
			details.pivot_ratio_proxy = float(details.min_pivot) / float(details.max_pivot)
		var direction: PackedFloat64Array = linear.get("step", PackedFloat64Array())
		var method := "newton"
		if direction.size() != n:
			direction = _negative_gradient(jacobian, scaled, n)
			method = "gradient_fallback_rank_rejected"
		if not _finite_size(direction, n) or _norm(direction) <= 1.0e-15:
			details.reason = "rank-deficient Jacobian has no usable descent direction"
			break
		var direction_norm := _norm(direction)
		if direction_norm > 0.05:
			for i in n:
				direction[i] *= 0.05 / direction_norm
		var accepted := false
		var accepted_alpha := 0.0
		var accepted_method := method
		var accepted_x := PackedFloat64Array()
		var accepted_raw := PackedFloat64Array()
		var accepted_scaled := PackedFloat64Array()
		var accepted_feasibility: Dictionary = {}
		var active_set_changed := false
		var previous_active_set := str(current_feasibility.get("signature", ""))
		var attempts := 0
		for group in 2:
			if group == 1:
				direction = _negative_gradient(jacobian, scaled, n)
				method = "gradient_fallback"
				if not _finite_size(direction, n) or _norm(direction) <= 1.0e-15:
					break
				direction_norm = _norm(direction)
				if direction_norm > 0.05:
					for i in n:
						direction[i] *= 0.05 / direction_norm
			for backtrack in 4:
				if attempts >= MAX_BACKTRACK_TRIALS:
					break
				attempts += 1
				var alpha := 1.0 / float(1 << backtrack)
				var trial := x.duplicate()
				for i in n:
					trial[i] += alpha * direction[i] * variable_scales[i]
				var trial_feasibility: Dictionary = feasible.call(trial)
				if not trial_feasibility.get("ok", false):
					continue
				var trial_eval := _scaled_residual(residual, trial, residual_scales, budget)
				if not trial_eval.ok:
					details.reason = str(trial_eval.reason)
					break
				var trial_raw: PackedFloat64Array = trial_eval.raw
				var trial_scaled: PackedFloat64Array = trial_eval.scaled
				if _norm_l2(trial_scaled) < _norm_l2(scaled):
					accepted = true
					accepted_alpha = alpha
					accepted_method = method
					accepted_x = trial
					accepted_raw = trial_raw
					accepted_scaled = trial_scaled
					accepted_feasibility = trial_feasibility
					active_set_changed = trial_feasibility.get("signature", "") != previous_active_set
					break
			if accepted or details.reason == "residual evaluation budget exhausted":
				break
		if not accepted:
			if details.reason.is_empty():
				details.reason = "bounded line search found no feasible descent step"
			break
		x = accepted_x
		raw = accepted_raw
		scaled = accepted_scaled
		current_feasibility = accepted_feasibility
		raw_norm = _norm(raw)
		scaled_norm = _norm(scaled)
		details.accepted_steps.append({"iteration": iterations, "method": accepted_method,
			"alpha": accepted_alpha, "step_scaled_linf": _norm(direction) * accepted_alpha,
			"residual_scaled_l2": _norm_l2(scaled), "residual_scaled_linf": scaled_norm,
			"active_set": current_feasibility.get("signature", ""), "active_set_changed": active_set_changed,
			"previous_active_set": previous_active_set,
			"contact_state": current_feasibility.get("contacts", [])})
	if details.reason.is_empty():
		details.reason = "iteration limit exhausted"
	details.final_residual = raw.duplicate()
	details.final_scaled_residual = scaled.duplicate()
	details.final_contact_state = current_feasibility
	details.evaluations = int(budget.get("evaluations", 0)) - int(details.evaluations_at_stage_start)
	details.feasibility_checks = int(budget.get("feasibility_checks", 0)) - int(details.feasibility_checks_at_stage_start)
	var success: bool = details.reason == "converged"
	return {ok = success, x = x, residual = raw_norm, scaled_residual = scaled_norm,
		iterations = iterations, reason = details.reason, diagnostics = details}


static func _scaled_jacobian_column(residual: Callable, x: PackedFloat64Array, raw: PackedFloat64Array,
		scaled: PackedFloat64Array, residual_scales: PackedFloat64Array, variable_scales: PackedFloat64Array,
		column: int, base_feasibility: Dictionary, feasible: Callable, budget: Dictionary) -> Dictionary:
	var step := FD_STEP_SCALED
	var rejections := 0
	var last: Dictionary = {}
	var max_difference := 0.0
	var one_sided := false
	var used_step := 0.0
	for shrink in range(FD_MAX_SHRINKS + 1):
		var coarse: Dictionary = _difference_column(residual, x, raw, scaled, residual_scales, variable_scales,
			column, step, base_feasibility, feasible, budget)
		var fine: Dictionary = _difference_column(residual, x, raw, scaled, residual_scales, variable_scales,
			column, 0.5 * step, base_feasibility, feasible, budget)
		rejections += int(coarse.get("rejections", 0)) + int(fine.get("rejections", 0))
		if fine.get("ok", false):
			last = fine
			used_step = 0.5 * step
			one_sided = one_sided or bool(fine.get("one_sided", false))
			if coarse.get("ok", false):
				var a: PackedFloat64Array = coarse.values
				var b: PackedFloat64Array = fine.values
				var difference := 0.0
				for i in b.size():
					difference = maxf(difference, absf(a[i] - b[i]) / maxf(1.0, absf(b[i])))
				max_difference = maxf(max_difference, difference)
				if difference <= 0.25:
					break
			else:
				max_difference = maxf(max_difference, 1.0)
		if shrink < FD_MAX_SHRINKS:
			step *= 0.5
	if last.is_empty():
		return {ok = false, rejections = rejections, reason = "no feasible finite-difference stencil for variable %d" % column}
	return {ok = true, values = last.values, rejections = rejections, one_sided = one_sided,
		relative_difference = max_difference, used_scaled_step = used_step}


static func _difference_column(residual: Callable, x: PackedFloat64Array, raw: PackedFloat64Array,
		scaled: PackedFloat64Array, residual_scales: PackedFloat64Array, variable_scales: PackedFloat64Array,
		column: int, step: float, base_feasibility: Dictionary, feasible: Callable, budget: Dictionary) -> Dictionary:
	var plus := x.duplicate()
	var minus := x.duplicate()
	plus[column] += step * variable_scales[column]
	minus[column] -= step * variable_scales[column]
	var plus_feasibility: Dictionary = feasible.call(plus)
	var minus_feasibility: Dictionary = feasible.call(minus)
	var base_signature: Variant = base_feasibility.get("signature", "")
	var plus_ok: bool = plus_feasibility.get("ok", false) and plus_feasibility.get("signature", "") == base_signature
	var minus_ok: bool = minus_feasibility.get("ok", false) and minus_feasibility.get("signature", "") == base_signature
	var rejections := int(not plus_ok) + int(not minus_ok)
	if plus_ok and minus_ok:
		var plus_eval := _scaled_residual(residual, plus, residual_scales, budget)
		var minus_eval := _scaled_residual(residual, minus, residual_scales, budget)
		if not plus_eval.ok or not minus_eval.ok:
			return {ok = false, rejections = rejections, reason = str(plus_eval.get("reason", minus_eval.get("reason", "residual evaluation failed")))}
		var derivative := PackedFloat64Array()
		derivative.resize(x.size())
		for i in x.size():
			derivative[i] = (plus_eval.scaled[i] - minus_eval.scaled[i]) / (2.0 * step)
		return {ok = true, values = derivative, rejections = rejections, one_sided = false}
	if plus_ok or minus_ok:
		var trial := plus if plus_ok else minus
		var trial_eval := _scaled_residual(residual, trial, residual_scales, budget)
		if not trial_eval.ok:
			return {ok = false, rejections = rejections, reason = str(trial_eval.get("reason", "residual evaluation failed"))}
		var sign := 1.0 if plus_ok else -1.0
		var derivative := PackedFloat64Array()
		derivative.resize(x.size())
		for i in x.size():
			derivative[i] = sign * (trial_eval.scaled[i] - scaled[i]) / step
		return {ok = true, values = derivative, rejections = rejections, one_sided = true}
	return {ok = false, rejections = maxf(1, rejections), reason = "contact/friction active-set stencil crossing"}


static func _scaled_residual(residual: Callable, x: PackedFloat64Array, residual_scales: PackedFloat64Array,
		budget: Dictionary) -> Dictionary:
	if int(budget.get("evaluations", 0)) >= int(budget.get("max_evaluations", MAX_RESIDUAL_EVALUATIONS)):
		return {ok = false, reason = "residual evaluation budget exhausted"}
	budget.evaluations = int(budget.get("evaluations", 0)) + 1
	var raw: PackedFloat64Array = residual.call(x)
	if not _finite_size(raw, residual_scales.size()):
		return {ok = false, reason = "nonfinite or malformed residual evaluation"}
	var scaled := PackedFloat64Array()
	scaled.resize(raw.size())
	for i in raw.size():
		scaled[i] = raw[i] / residual_scales[i]
	if not _finite_size(scaled, raw.size()):
		return {ok = false, reason = "nonfinite scaled residual evaluation"}
	return {ok = true, raw = raw, scaled = scaled}


static func _negative_gradient(jacobian: PackedFloat64Array, residual: PackedFloat64Array, n: int) -> PackedFloat64Array:
	var direction := PackedFloat64Array()
	direction.resize(n)
	for column in n:
		for row in n:
			direction[column] -= jacobian[row * n + column] * residual[row]
	return direction


## Partial pivoting with a relative pivot floor. The ratio is a pivot proxy, not a matrix condition number.
static func _bounded_linear_solve(a_in: PackedFloat64Array, b_in: PackedFloat64Array, n: int) -> Dictionary:
	if n <= 0 or a_in.size() != n * n or not _finite_size(a_in, n * n) or not _finite_size(b_in, n):
		return {step = PackedFloat64Array(), min_pivot = INF, max_pivot = 0.0}
	var a := a_in.duplicate()
	var b := b_in.duplicate()
	var matrix_max := 0.0
	for value in a:
		matrix_max = maxf(matrix_max, absf(value))
	if matrix_max <= 0.0:
		return {step = PackedFloat64Array(), min_pivot = 0.0, max_pivot = 0.0}
	var min_pivot := INF
	var max_pivot := 0.0
	for col in n:
		var pivot := col
		for row in range(col + 1, n):
			if absf(a[row * n + col]) > absf(a[pivot * n + col]):
				pivot = row
		var magnitude := absf(a[pivot * n + col])
		if magnitude <= PIVOT_RELATIVE_FLOOR * matrix_max:
			return {step = PackedFloat64Array(), min_pivot = minf(min_pivot, magnitude), max_pivot = maxf(max_pivot, max_pivot)}
		min_pivot = minf(min_pivot, magnitude)
		max_pivot = maxf(max_pivot, magnitude)
		if pivot != col:
			for k in n:
				var temporary := a[col * n + k]
				a[col * n + k] = a[pivot * n + k]
				a[pivot * n + k] = temporary
			var value := b[col]
			b[col] = b[pivot]
			b[pivot] = value
		for row in range(col + 1, n):
			var factor := a[row * n + col] / a[col * n + col]
			if not is_finite(factor):
				return {step = PackedFloat64Array(), min_pivot = min_pivot, max_pivot = max_pivot}
			for k in range(col, n):
				a[row * n + k] -= factor * a[col * n + k]
			b[row] -= factor * b[col]
	var step := PackedFloat64Array()
	step.resize(n)
	for row in range(n - 1, -1, -1):
		var value := -b[row]
		for k in range(row + 1, n):
			value -= a[row * n + k] * step[k]
		step[row] = value / a[row * n + row]
		if not is_finite(step[row]):
			return {step = PackedFloat64Array(), min_pivot = min_pivot, max_pivot = max_pivot}
	return {step = step, min_pivot = min_pivot, max_pivot = max_pivot}


static func _norm_l2(v: PackedFloat64Array) -> float:
	var sum := 0.0
	for value in v:
		if not is_finite(value):
			return INF
		sum += value * value
	return M.sqrt_(sum)


static func _start_failure(message: String, diagnostics: Dictionary, iterations: int, residual: float, scaled_residual: float) -> Dictionary:
	# Preserve the established failure count contract while keeping exact attempted iterations in stage diagnostics.
	diagnostics["total_solver_iterations"] = iterations
	return {ok = false, status = "numerical_unresolved", state = PackedFloat64Array(), anchors = PackedFloat64Array(),
		rest_state = PackedFloat64Array(), iterations = 0, residual = residual,
		scaled_residual = scaled_residual, diagnostics = diagnostics, message = message}


static func _finite_size(values: PackedFloat64Array, size: int) -> bool:
	if values.size() != size:
		return false
	for value in values:
		if not is_finite(value):
			return false
	return true


static func _norm(v: PackedFloat64Array) -> float:
	if v.is_empty():
		return INF
	var worst := 0.0
	for value in v:
		if not is_finite(value):
			return INF
		worst = maxf(worst, absf(value))
	return worst


## Solve A·x = b (A row-major n×n). Empty for malformed, singular or nonfinite systems, including overflow.
static func _linear_solve(a_in: PackedFloat64Array, b_in: PackedFloat64Array, n: int) -> PackedFloat64Array:
	if n <= 0 or n > a_in.size() or a_in.size() != n * n or not _finite_size(a_in, a_in.size()) or not _finite_size(b_in, n):
		return PackedFloat64Array()
	var a := a_in.duplicate()
	var b := b_in.duplicate()
	for col in n:
		var pivot := col
		for row in range(col + 1, n):
			if absf(a[row * n + col]) > absf(a[pivot * n + col]):
				pivot = row
		if absf(a[pivot * n + col]) < 1e-300:
			return PackedFloat64Array()
		if pivot != col:
			for k in n:
				var t := a[col * n + k]
				a[col * n + k] = a[pivot * n + k]
				a[pivot * n + k] = t
			var tb := b[col]
			b[col] = b[pivot]
			b[pivot] = tb
		for row in range(col + 1, n):
			var f := a[row * n + col] / a[col * n + col]
			if not is_finite(f):
				return PackedFloat64Array()
			for k in range(col, n):
				a[row * n + k] -= f * a[col * n + k]
				if not is_finite(a[row * n + k]):
					return PackedFloat64Array()
			b[row] -= f * b[col]
			if not is_finite(b[row]):
				return PackedFloat64Array()
	var x := PackedFloat64Array()
	x.resize(n)
	for row in range(n - 1, -1, -1):
		var acc := b[row]
		for k in range(row + 1, n):
			acc -= a[row * n + k] * x[k]
			if not is_finite(acc):
				return PackedFloat64Array()
		x[row] = acc / a[row * n + row]
		if not is_finite(x[row]):
			return PackedFloat64Array()
	return x


static func _fail(message: String) -> Dictionary:
	return { ok = false, state = PackedFloat64Array(), anchors = PackedFloat64Array(), rest_state = PackedFloat64Array(),
		status = "invalid_input", iterations = 0, residual = INF, scaled_residual = INF, message = message }
