## Read-only presentation snapshot of the accepted rigid-body and landing-gear contact state.
extends RefCounted

const Frames := preload("res://render/frames.gd")
const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const Ground := preload("res://physics/ground_contact.gd")
const Wheels := preload("res://physics/ground_wheels.gd")
const Terrain := preload("res://physics/ground_terrain.gd")
## GP-19f (2026-10-27): beyond gear reach over the terrain bound, plus this margin and this many
## seconds of travel at the current speed, no wheel can load before the next real rows begin.
const FAR_MARGIN_M := 1.0
const FAR_HORIZON_S := 0.5
const SURFACE_TYPES := ["runway", "rotorpad", "mown", "rough"]
## Authored material identities select existing recordings. This table is an
## audio choice, not a friction/roughness model or an inference from land usage.
const MATERIAL_ROLL_FAMILIES := {
	"maintained_turf": "grass", "mown_grass": "grass", "long_grass": "grass",
	"dry_pavement": "hard", "asphalt": "hard", "concrete": "hard", "gravel": "gravel",
}


## Returns point forces and velocities from the accepted state only; it does not change or advance simulation state.
static func snapshot_contacts(session: Node, _field: Dictionary) -> Array[Dictionary]:
	var contacts_out: Array[Dictionary] = []
	if session == null or not session.has_method("current_landing_gear"):
		return contacts_out
	var sim: Variant = session.get("sim")
	if sim == null:
		return contacts_out
	var state: PackedFloat64Array = sim.state
	var auxiliary: PackedFloat64Array = sim.aux
	if state.size() < RB.SIZE or auxiliary.size() < 4:
		return contacts_out
	var gear: Dictionary = session.call("current_landing_gear", auxiliary)
	var gear_contacts: Array = gear.get("contacts", [])
	if gear_contacts.is_empty():
		return contacts_out
	var ground_surfaces: PackedFloat64Array = session.get("ground_surfaces")	
	var lake_value: Variant = session.get("_lake")
	var lake: Dictionary = lake_value if lake_value is Dictionary else {}
	var steer: float = auxiliary[3]
	var wheel_count: int = int(session.call("wheel_count")) if session.has_method("wheel_count") else 0
	var wheel_index: int = int(session.call("wheel_index")) if session.has_method("wheel_index") else 0
	var anchors_count: int = int(session.call("anchor_count")) if session.has_method("anchor_count") else 0
	var anchors: PackedFloat64Array = auxiliary.slice(4, 4 + anchors_count * Ground.ANCHOR_STRIDE)
	var speeds := PackedFloat64Array()
	if wheel_count > 0 and wheel_index >= 0 and wheel_index + wheel_count <= sim.continuous.size():
		speeds = sim.continuous.slice(wheel_index, wheel_index + wheel_count)
	else:
		wheel_count = 0
	var brake: float = float(sim.inputs[5]) if session.has_method("gear_is_retractable") and bool(session.call("gear_is_retractable")) and sim.inputs.size() > 5 else 0.0
	var attitude := M.quat(state[RB.ATT], state[RB.ATT + 1], state[RB.ATT + 2], state[RB.ATT + 3])
	var base_velocity := M.v3(state[RB.VEL], state[RB.VEL + 1], state[RB.VEL + 2])
	var body_rate := state.slice(RB.RATE, RB.RATE + 3)
	var reference_load: float = maxf(1.0, float(sim.mass) * float(sim.gravity) / float(gear_contacts.size()))
	# Well clear of the ground, every wheel is unloaded and the cues only age their airborne state, so skip the
	# wheel frames, contact law and material queries. Rows resume in full FAR_HORIZON_S before any wheel can load.
	if _clear_of_ground(state, gear, ground_surfaces):
		return _unloaded_rows(gear_contacts, state, attitude, base_velocity, body_rate, reference_load)
	var wheel_evaluation: Dictionary = {}
	if wheel_count > 0:
		wheel_evaluation = Ground.evaluate(state, gear, steer, ground_surfaces, anchors, speeds, brake, true, lake)
	var wheel_diagnostics: Array = wheel_evaluation.get("wheels", [])
	var environment := session.get("environment") as RefCounted
	var time_s: float = sim.time()
	for index: int in range(gear_contacts.size()):
		var contact: Dictionary = gear_contacts[index]
		if not contact.has("position"):
			continue
		var frame: Dictionary = Wheels.frame(state, contact, steer, ground_surfaces, PackedFloat64Array(), true, lake)
		var arm: PackedFloat64Array = contact.position
		var body_point_velocity: PackedFloat64Array = M.add(base_velocity, M.cross(body_rate, arm))
		var point_velocity: PackedFloat64Array = M.q_rotate(attitude, body_point_velocity)
		var normal: PackedFloat64Array = frame.get("normal", PackedFloat64Array([0.0, 0.0, -1.0]))
		var approach_speed: float = maxf(0.0, -M.dot(point_velocity, normal))
		var wheel_diag: Dictionary = wheel_diagnostics[index] if index < wheel_diagnostics.size() else {}
		var force_ned := PackedFloat64Array([0.0, 0.0, 0.0])
		var rim_speed: float = 0.0
		if wheel_count > 0 and not wheel_diag.is_empty():
			var normal_load: float = maxf(0.0, float(wheel_diag.get("normal_load", 0.0)))
			var longitudinal: float = float(wheel_diag.get("longitudinal_force", 0.0))
			var lateral: float = float(wheel_diag.get("lateral_force", 0.0))
			var heading: PackedFloat64Array = frame.get("heading", PackedFloat64Array([0.0, 0.0, 0.0]))
			var side: PackedFloat64Array = frame.get("side", PackedFloat64Array([0.0, 0.0, 0.0]))
			force_ned = M.add(M.scale(normal, normal_load), M.add(M.scale(heading, longitudinal), M.scale(side, lateral)))
			rim_speed = float(wheel_diag.get("rim_speed", 0.0))
		else:
			# Ground.loads only reads nested gear data; isolate the contact list only.
			var single_gear: Dictionary = gear.duplicate()
			single_gear["contacts"] = [contact]
			var one_anchor := PackedFloat64Array()
			if anchors_count > index:
				one_anchor = anchors.slice(index * Ground.ANCHOR_STRIDE, (index + 1) * Ground.ANCHOR_STRIDE)
			var loads: PackedFloat64Array = Ground.loads(state, single_gear, steer, ground_surfaces, one_anchor, PackedFloat64Array(), brake, lake)
			if loads.size() == 6:
				force_ned = M.q_rotate(attitude, M.v3(loads[0], loads[1], loads[2]))
		var normal_force: float = maxf(0.0, M.dot(force_ned, normal))
		var rolling_speed: float = maxf(absf(float(frame.get("long_speed", 0.0))), absf(rim_speed))
		var position_ned: PackedFloat64Array = frame.get("position", PackedFloat64Array([state[0], state[1], state[2]]))
		var identity: String = str(contact.get("name", "gear_%d" % index))
		var audio_surface := surface_observation(environment, position_ned, point_velocity, time_s)
		contacts_out.append({
			id = identity,
			position = Frames.ned_to_render(Array(position_ned)),
			velocity_mps = Frames.ned_to_render(Array(point_velocity)),
			force_n = Frames.ned_to_render(Array(force_ned)),
			surface_normal = Frames.ned_to_render(Array(normal)),
			normal_force_n = normal_force,
			reference_load_n = reference_load,
			compression_m = float(frame.get("compression", 0.0)),
			approach_speed_mps = approach_speed,
			rolling_speed_mps = rolling_speed,
			rim_speed_mps = rim_speed,
			surface = audio_surface.surface,
			material_id = audio_surface.material_id,
			material_resolved = audio_surface.material_resolved,
			surface_audio_fallback = audio_surface.surface_audio_fallback,
			surface_region_id = audio_surface.region_id,
			grounded = normal_force > 0.0,
			roll_enabled = true,
		})
	return contacts_out


## VQ-01c-R1: true when snapshot_contacts() would return unloaded far rows for the accepted state, so no
## wheel can load within FAR_HORIZON_S. Cheap enough to ask on every accepted tick.
static func wheels_clear_of_ground(session: Node) -> bool:
	if session == null or not session.has_method("current_landing_gear"):
		return false
	var sim: Variant = session.get("sim")
	if sim == null or sim.state.size() < RB.SIZE or sim.aux.size() < 4:
		return false
	var gear: Dictionary = session.call("current_landing_gear", sim.aux)
	if gear.get("contacts", []).is_empty():
		return false
	return _clear_of_ground(sim.state, gear, session.get("ground_surfaces"))


static func _clear_of_ground(state: PackedFloat64Array, gear: Dictionary, ground_surfaces: PackedFloat64Array) -> bool:
	return Terrain.is_valid_surface_table(ground_surfaces) and -state[RB.POS + 2] > float(gear.get("reach", INF)) \
		+ Terrain.max_height_validated(ground_surfaces) + FAR_MARGIN_M \
		+ FAR_HORIZON_S * M.norm(M.v3(state[RB.VEL], state[RB.VEL + 1], state[RB.VEL + 2]))


## Rows for wheels that cannot touch this tick: the body pose with flat-ground normal, approach and compression
## (exact on flat ground), no load, and the explicit hard-roll fallback used whenever no material is resolved.
static func _unloaded_rows(gear_contacts: Array, state: PackedFloat64Array, attitude: PackedFloat64Array,
		base_velocity: PackedFloat64Array, body_rate: PackedFloat64Array, reference_load: float) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var origin := M.v3(state[RB.POS], state[RB.POS + 1], state[RB.POS + 2])
	for index: int in range(gear_contacts.size()):
		var contact: Dictionary = gear_contacts[index]
		if not contact.has("position"):
			continue
		var arm: PackedFloat64Array = contact.position
		var point_velocity: PackedFloat64Array = M.q_rotate(attitude, M.add(base_velocity, M.cross(body_rate, arm)))
		var position_ned: PackedFloat64Array = M.add(origin, M.q_rotate(attitude, arm))
		rows.append({
			id = str(contact.get("name", "gear_%d" % index)),
			position = Frames.ned_to_render(Array(position_ned)),
			velocity_mps = Frames.ned_to_render(Array(point_velocity)),
			force_n = Frames.ned_to_render([0.0, 0.0, 0.0]),
			surface_normal = Frames.ned_to_render([0.0, 0.0, -1.0]),
			normal_force_n = 0.0,
			reference_load_n = reference_load,
			compression_m = position_ned[2],
			approach_speed_mps = maxf(0.0, point_velocity[2]),
			rolling_speed_mps = 0.0,
			rim_speed_mps = 0.0,
			surface = "hard",
			material_id = "unspecified",
			material_resolved = false,
			surface_audio_fallback = true,
			surface_region_id = "",
			grounded = false,
			roll_enabled = true,
		})
	return rows


## Read the same solid-support provider used by the accepted session. Unsupported
## or unresolved material uses the existing hard-roll layer as an explicit
## audio fallback; field usage never fabricates a material. Water is not solid bed.
static func surface_observation(environment: RefCounted, position_ned: PackedFloat64Array,
		velocity_ned: PackedFloat64Array, time_s: float) -> Dictionary:
	var result := {surface = "hard", material_id = "unspecified", material_resolved = false,
		surface_audio_fallback = true, region_id = ""}
	if environment == null or not environment.has_method("sample_support"):
		return result
	var sampled: Variant = environment.call("sample_support", position_ned, velocity_ned, time_s)
	if not sampled is Dictionary or typeof(sampled.get("ok")) != TYPE_BOOL or not sampled.ok:
		return result
	if typeof(sampled.get("material_id")) != TYPE_STRING \
		or typeof(sampled.get("material_resolved")) != TYPE_BOOL \
		or typeof(sampled.get("region_id")) != TYPE_STRING:
		return result
	result.material_id = sampled.material_id
	result.material_resolved = sampled.material_resolved
	result.region_id = sampled.region_id
	if sampled.material_resolved and MATERIAL_ROLL_FAMILIES.has(sampled.material_id):
		result.surface = MATERIAL_ROLL_FAMILIES[sampled.material_id]
		result.surface_audio_fallback = false
	return result


## Historical usage-only helper for unmigrated presentation callers. Fixed-wing
## snapshots above use authored material from Environment, never this alias map.
static func surface_name(field: Dictionary, north: float, east: float) -> String:
	for surface_type: String in SURFACE_TYPES:
		for area: Dictionary in field.get("surfaces", []):
			if str(area.get("type", "")) != surface_type:
				continue
			if absf(north - float(area.get("center_north", 0.0))) <= float(area.get("width_north_south", 0.0)) * 0.5 \
				and absf(east - float(area.get("center_east", 0.0))) <= float(area.get("length_east_west", 0.0)) * 0.5:
				return "hard" if surface_type in ["runway", "rotorpad"] else ("grass" if surface_type == "mown" else "gravel")
	return "gravel"
