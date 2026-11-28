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
	var track_value: Variant = session.get("_rc_track")
	var track: Dictionary = track_value if track_value is Dictionary else {}
	var reference_load: float = maxf(1.0, float(sim.mass) * float(sim.gravity) / float(gear_contacts.size()))
	# Well clear of the ground, every wheel is unloaded and the cues only age their airborne state, so skip the
	# wheel frames, contact law and material queries. Rows resume in full FAR_HORIZON_S before any wheel can load.
	# NK-7h: tested before the loaded rows' inputs below, which the unloaded rows never read.
	if _clear_of_ground(state, gear, ground_surfaces, track):
		return _unloaded_rows(gear_contacts, state,
			M.quat(state[RB.ATT], state[RB.ATT + 1], state[RB.ATT + 2], state[RB.ATT + 3]),
			M.v3(state[RB.VEL], state[RB.VEL + 1], state[RB.VEL + 2]), state.slice(RB.RATE, RB.RATE + 3), reference_load)
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
	var wheel_evaluation: Dictionary = {}
	# NK-6o: the session's native stage may answer Ground.evaluate's diagnostics and each wheel's frame for the endpoint
	# it published, with the same values; otherwise they are evaluated here.
	var rows := PackedFloat64Array()
	if wheel_count > 0:
		rows = _native_rows(session, state, steer, anchors, speeds, brake, gear_contacts.size())
		if rows.is_empty():
			wheel_evaluation = Ground.evaluate(state, gear, steer, ground_surfaces, anchors, speeds, brake, true, lake, track)
	var native_rows: bool = rows.size() > 1
	var wheel_diagnostics: Array = wheel_evaluation.get("wheels", [])
	var environment := session.get("environment") as RefCounted
	var time_s: float = sim.time()
	for index: int in range(gear_contacts.size()):
		var contact: Dictionary = gear_contacts[index]
		if not contact.has("position"):
			continue
		var kinematics := _row_kinematics(rows, index, contact, attitude, base_velocity, body_rate) if native_rows \
			else _contact_kinematics(state, contact, steer, ground_surfaces, lake, track, attitude, base_velocity, body_rate)
		var frame: Dictionary = kinematics.frame
		var point_velocity: PackedFloat64Array = kinematics.point_velocity
		var normal: PackedFloat64Array = kinematics.normal
		var approach_speed: float = kinematics.approach_speed
		var wheel_diag: Dictionary = _row_diagnostics(rows, index) if native_rows \
			else (wheel_diagnostics[index] if index < wheel_diagnostics.size() else {})
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
			var loads: PackedFloat64Array = Ground.loads(state, single_gear, steer, ground_surfaces, one_anchor, PackedFloat64Array(), brake, lake, track)
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


## NK-6o: the session's native wheel rows for this observation: [1, n, rows] (n == contacts), [0] where the reference
## has no diagnostics, or empty to evaluate Ground.evaluate here.
static func _native_rows(session: Node, state: PackedFloat64Array, steer: float, anchors: PackedFloat64Array,
		speeds: PackedFloat64Array, brake: float, contacts: int) -> PackedFloat64Array:
	if not session.has_method("published_wheel_rows"):
		return PackedFloat64Array()
	var rows: PackedFloat64Array = session.call("published_wheel_rows", state, steer, anchors, speeds, brake)
	if rows.size() == 1 and rows[0] == 0.0:
		return rows
	if rows.size() == 2 + contacts * WHEEL_ROW_SIZE and rows[0] == 1.0 and int(rows[1]) == contacts:
		return rows
	return PackedFloat64Array()


## Values per native wheel row (nk::kWheelRowSize).
const WHEEL_ROW_SIZE := 18


## Ground.evaluate's diagnostics fields this observation reads, from a native row.
static func _row_diagnostics(rows: PackedFloat64Array, index: int) -> Dictionary:
	var at: int = 2 + index * WHEEL_ROW_SIZE
	return {normal_load = rows[at], longitudinal_force = rows[at + 1], lateral_force = rows[at + 2], rim_speed = rows[at + 3]}


## _contact_kinematics from a native row: the same frame values (Wheels.frame), point velocity and approach speed.
static func _row_kinematics(rows: PackedFloat64Array, index: int, contact: Dictionary, attitude: PackedFloat64Array,
		base_velocity: PackedFloat64Array, body_rate: PackedFloat64Array) -> Dictionary:
	var at: int = 2 + index * WHEEL_ROW_SIZE
	var normal := PackedFloat64Array([rows[at + 8], rows[at + 9], rows[at + 10]])
	var frame := {compression = rows[at + 4], position = PackedFloat64Array([rows[at + 5], rows[at + 6], rows[at + 7]]),
		normal = normal, heading = PackedFloat64Array([rows[at + 11], rows[at + 12], rows[at + 13]]),
		side = PackedFloat64Array([rows[at + 14], rows[at + 15], rows[at + 16]]), long_speed = rows[at + 17]}
	var arm: PackedFloat64Array = contact.position
	var body_point_velocity: PackedFloat64Array = M.add(base_velocity, M.cross(body_rate, arm))
	var point_velocity: PackedFloat64Array = M.q_rotate(attitude, body_point_velocity)
	return {frame = frame, point_velocity = point_velocity, normal = normal,
		approach_speed = maxf(0.0, -M.dot(point_velocity, normal))}


## One row's wheel frame, point velocity (NED), surface normal and approach speed.
static func _contact_kinematics(state: PackedFloat64Array, contact: Dictionary, steer: float,
		ground_surfaces: PackedFloat64Array, lake: Dictionary, track: Dictionary, attitude: PackedFloat64Array,
		base_velocity: PackedFloat64Array, body_rate: PackedFloat64Array) -> Dictionary:
	var frame: Dictionary = Wheels.frame(state, contact, steer, ground_surfaces, PackedFloat64Array(), true, lake, track)
	var arm: PackedFloat64Array = contact.position
	var body_point_velocity: PackedFloat64Array = M.add(base_velocity, M.cross(body_rate, arm))
	var point_velocity: PackedFloat64Array = M.q_rotate(attitude, body_point_velocity)
	var normal: PackedFloat64Array = frame.get("normal", PackedFloat64Array([0.0, 0.0, -1.0]))
	return {frame = frame, point_velocity = point_velocity, normal = normal,
		approach_speed = maxf(0.0, -M.dot(point_velocity, normal))}


## The approach_speed_mps of snapshot_contacts()'s near-ground rows, by the same arithmetic, without loads or
## material queries; `identities` receives the rows' ids in order. Empty where snapshot_contacts() has no near-ground
## rows (no gear or state, or clear of the ground). For FlightAudio's ticks between ground observations.
static func approach_speeds(session: Node, identities: PackedStringArray) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	identities.clear()
	if session == null or not session.has_method("current_landing_gear"):
		return out
	var sim: Variant = session.get("sim")
	if sim == null:
		return out
	var state: PackedFloat64Array = sim.state
	var auxiliary: PackedFloat64Array = sim.aux
	if state.size() < RB.SIZE or auxiliary.size() < 4:
		return out
	var gear: Dictionary = session.call("current_landing_gear", auxiliary)
	var gear_contacts: Array = gear.get("contacts", [])
	var ground_surfaces: PackedFloat64Array = session.get("ground_surfaces")
	var lake_value: Variant = session.get("_lake")
	var lake: Dictionary = lake_value if lake_value is Dictionary else {}
	var track_value: Variant = session.get("_rc_track")
	var track: Dictionary = track_value if track_value is Dictionary else {}
	if gear_contacts.is_empty() or _clear_of_ground(state, gear, ground_surfaces, track):
		return out
	var steer: float = auxiliary[3]
	var attitude := M.quat(state[RB.ATT], state[RB.ATT + 1], state[RB.ATT + 2], state[RB.ATT + 3])
	var base_velocity := M.v3(state[RB.VEL], state[RB.VEL + 1], state[RB.VEL + 2])
	var body_rate := state.slice(RB.RATE, RB.RATE + 3)
	for index: int in range(gear_contacts.size()):
		var contact: Dictionary = gear_contacts[index]
		if not contact.has("position"):
			continue
		identities.append(str(contact.get("name", "gear_%d" % index)))
		out.append(float(_contact_kinematics(state, contact, steer, ground_surfaces, lake, track, attitude, base_velocity,
			body_rate).approach_speed))
	return out


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
	var track_value: Variant = session.get("_rc_track")
	var track: Dictionary = track_value if track_value is Dictionary else {}
	return _clear_of_ground(sim.state, gear, session.get("ground_surfaces"), track)


## NK-7f hook: false builds the airborne rows in GDScript.
static var native_rows_enabled := true
static var _rows_native: Object = null


static func _rows_kernel() -> Object:
	if not native_rows_enabled:
		return null
	if _rows_native == null:
		if not ClassDB.class_exists(&"OpenRCNativeKernel"):
			return null
		var kernel: Object = ClassDB.instantiate(&"OpenRCNativeKernel")
		if kernel == null or not kernel.has_method(&"audio_unloaded_rows"):
			native_rows_enabled = false
			return null
		_rows_native = kernel
	return _rows_native


static func _clear_of_ground(state: PackedFloat64Array, gear: Dictionary, ground_surfaces: PackedFloat64Array,
		track: Dictionary = {}) -> bool:
	return Terrain.is_valid_surface_table(ground_surfaces) and -state[RB.POS + 2] > float(gear.get("reach", INF)) \
		+ Terrain.max_height_validated(ground_surfaces) + Wheels.Track.max_height_m(track) + FAR_MARGIN_M \
		+ FAR_HORIZON_S * M.norm(M.v3(state[RB.VEL], state[RB.VEL + 1], state[RB.VEL + 2]))


## Rows for wheels that cannot touch this tick: the body pose with flat-ground normal, approach and compression
## (exact on flat ground), no load, and the explicit hard-roll fallback used whenever no material is resolved.
static func _unloaded_rows(gear_contacts: Array, state: PackedFloat64Array, attitude: PackedFloat64Array,
		base_velocity: PackedFloat64Array, body_rate: PackedFloat64Array, reference_load: float) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	# NK-7f: the kernel builds the same rows (nk_audio_rows.hpp) from the state; otherwise they are built here.
	var kernel := _rows_kernel()
	if kernel != null:
		var arms := PackedFloat64Array()
		var ids := PackedStringArray()
		var well_formed := true
		for index: int in range(gear_contacts.size()):
			var contact: Dictionary = gear_contacts[index]
			if not contact.has("position"):
				continue
			var arm: PackedFloat64Array = contact.position
			well_formed = well_formed and arm.size() == 3
			arms.append_array(arm)
			ids.append(str(contact.get("name", "gear_%d" % index)))
		if well_formed:
			rows.assign(kernel.audio_unloaded_rows(state, arms, ids, reference_load))
			if rows.size() == ids.size():
				return rows
			rows.clear()
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
