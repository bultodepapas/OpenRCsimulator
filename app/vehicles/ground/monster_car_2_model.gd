## Render boundary for the supplied Monster Car 2 Blender rig and GLB.
## Suspension/linkages are sampled from the authored rig bake; physics state is read-only.
extends RefCounted

const Frames = preload("res://render/frames.gd")
const SCENE := "res://assets/vehicles/monster-car-2/monster_truck_nitro_1.glb"
const RIG_MANIFEST := "res://assets/vehicles/monster-car-2/visual_rig.json"
const RIG_BINARY := "res://assets/vehicles/monster-car-2/visual_rig.bin"
const VEHICLE_DATA := "res://data/vehicles/ground/monster_car_2.json"
const DATUM_HEIGHT_M := 0.087
const ART_BASIS := Basis(Vector3.UP, PI / 2.0)
const CORNERS := ["FL", "FR", "RL", "RR"]
const STATE_TRAVEL_START := 13
const STATE_WHEEL_ANGLE_START := 25
const STEER_STATE_INDEX := 29
const ENGINE_PHASE_KEY := "engine_phase_rad"
const TRAVEL_INPUT_NAMES := ["h_FL", "h_FR", "h_RL", "h_RR"]


class TrackSampler extends RefCounted:
	var axis_names := PackedStringArray()
	var low_values := PackedFloat64Array()
	var steps := PackedFloat64Array()
	var counts := PackedInt32Array()
	var low_indices := PackedInt32Array()
	var high_indices := PackedInt32Array()
	var fractions := PackedFloat64Array()
	var offset := 0
	var correction := Transform3D.IDENTITY
	var values := PackedFloat32Array()


static func build() -> Dictionary:
	var packed := load(SCENE) as PackedScene
	if packed == null:
		return {"ok": false, "error": "Monster Car 2 GLB resource is unavailable"}
	var manifest_file := FileAccess.open(RIG_MANIFEST, FileAccess.READ)
	if manifest_file == null:
		return {"ok": false, "error": "Monster Car 2 authored visual manifest is unavailable"}
	var manifest_value: Variant = JSON.parse_string(manifest_file.get_as_text())
	manifest_file.close()
	if typeof(manifest_value) != TYPE_DICTIONARY or manifest_value.get("schema", "") != "openrc-monster-car-2-visual-rig-v1":
		return {"ok": false, "error": "Monster Car 2 visual manifest has an unsupported schema"}
	var manifest: Dictionary = manifest_value
	var binary_file := FileAccess.open(RIG_BINARY, FileAccess.READ)
	if binary_file == null:
		return {"ok": false, "error": "Monster Car 2 authored visual bake is unavailable"}
	var rig_bytes := binary_file.get_buffer(binary_file.get_length())
	binary_file.close()
	if rig_bytes.is_empty():
		return {"ok": false, "error": "Monster Car 2 authored visual bake is empty"}
	var bundle_error := _validate_bundle(manifest, rig_bytes)
	if not bundle_error.is_empty():
		return {"ok": false, "error": bundle_error}

	var imported := packed.instantiate() as Node3D
	if imported == null:
		return {"ok": false, "error": "Monster Car 2 GLB did not instantiate as Node3D"}
	var imported_nodes := {}
	var mesh_nodes := {}
	var error := _collect(imported, imported_nodes, mesh_nodes)
	if not error.is_empty():
		imported.free()
		return {"ok": false, "error": error}
	for player in _find_animation_players(imported):
		player.stop()
		player.active = false

	var nodes := {}
	var binding_error := _bind_aliases(imported_nodes, nodes)
	if not binding_error.is_empty():
		imported.free()
		return {"ok": false, "error": binding_error}
	var bindings: Dictionary = manifest.get("bindings", {})
	var body_nodes: Array[MeshInstance3D] = []
	for name: String in bindings.get("body_nodes", []):
		var body_node: Variant = mesh_nodes.get(name)
		if not body_node is MeshInstance3D:
			imported.free()
			return {"ok": false, "error": "Missing authored body mesh binding: " + name}
		body_nodes.append(body_node as MeshInstance3D)
	var headlight_nodes := _mesh_bindings(bindings.get("headlight_nodes", []), mesh_nodes)
	var brake_light_nodes := _mesh_bindings(bindings.get("brake_light_nodes", []), mesh_nodes)
	if headlight_nodes.is_empty() or brake_light_nodes.is_empty():
		imported.free()
		return {"ok": false, "error": "Monster Car 2 authored lamp bindings are incomplete"}
	var track_nodes: Dictionary = manifest.get("tracks", {})
	for name: String in track_nodes:
		if name.begins_with("@wheel_"):
			continue
		if not mesh_nodes.has(name):
			imported.free()
			return {"ok": false, "error": "Missing authored transform track node: " + name}
		if mesh_nodes[name].get_parent() != imported:
			imported.free()
			return {"ok": false, "error": "Monster Car 2 GLB is no longer flattened at: " + name}
	for corner in CORNERS:
		var wheel_group: Dictionary = bindings.get("wheel_groups", {}).get(corner, {})
		if not track_nodes.has(str(wheel_group.get("pivot_track", ""))):
			imported.free()
			return {"ok": false, "error": "Missing authored wheel pivot track for " + corner}
		for name: String in wheel_group.get("mesh_nodes", []):
			if not mesh_nodes.has(name):
				imported.free()
				return {"ok": false, "error": "Missing authored wheel assembly mesh: " + name}
	var engine_nodes: Array[MeshInstance3D] = _mesh_bindings(bindings.get("engine_nodes", []), mesh_nodes)
	if engine_nodes.is_empty() or not _matrix_is_valid(bindings.get("engine_pivot_gltf", [])):
		imported.free()
		return {"ok": false, "error": "Monster Car 2 authored engine rotation bindings are incomplete"}

	var root := Node3D.new()
	root.name = "MonsterCar2Visual"
	var art := Node3D.new()
	art.name = "AuthoredCoordinates"
	art.transform = Transform3D(ART_BASIS, Vector3(0.0, -DATUM_HEIGHT_M, 0.0))
	root.add_child(art)
	art.add_child(imported)
	var base_transforms := {}
	for name: String in mesh_nodes:
		base_transforms[name] = (mesh_nodes[name] as MeshInstance3D).transform
	var draw_tracks: Array[Dictionary] = []
	for name: String in track_nodes:
		if name.begins_with("@wheel_"):
			continue
		draw_tracks.append({
			"mesh": mesh_nodes[name] as MeshInstance3D,
			"sampler": _compile_track(track_nodes[name]),
		})
	var draw_wheel_groups: Array[Dictionary] = []
	var wheel_groups: Dictionary = bindings.get("wheel_groups", {})
	for corner in CORNERS:
		var group: Dictionary = wheel_groups.get(corner, {})
		var pivot_track := str(group.get("pivot_track", ""))
		var draw_meshes: Array[Dictionary] = []
		for name_value in group.get("mesh_nodes", []):
			var name := str(name_value)
			draw_meshes.append({
				"mesh": mesh_nodes[name] as MeshInstance3D,
				"animated": track_nodes.has(name),
				"base": base_transforms[name],
			})
		draw_wheel_groups.append({
			"sampler": _compile_track(track_nodes[pivot_track]),
			"spin_sign": float(group.get("spin_sign", 1.0)),
			"meshes": draw_meshes,
		})
	var draw_engine_nodes: Array[Dictionary] = []
	for engine_mesh: MeshInstance3D in engine_nodes:
		var name := str(engine_mesh.name)
		draw_engine_nodes.append({
			"mesh": engine_mesh,
			"animated": track_nodes.has(name),
			"base": base_transforms[name],
			"bell": name == "Campana_Embrague",
		})
	var engine_pivot := _transform_from_floats(bindings.engine_pivot_gltf)
	var headlight_positions: Array[Vector3] = []
	for raw_position: Array in bindings.get("headlight_positions", []):
		if raw_position.size() != 3:
			root.free()
			return {"ok": false, "error": "Monster Car 2 headlight position metadata is malformed"}
		headlight_positions.append(Vector3(float(raw_position[0]), float(raw_position[1]), float(raw_position[2])))
	if headlight_positions.size() != 2:
		root.free()
		return {"ok": false, "error": "Monster Car 2 needs two authored headlight positions"}
	var exhaust_position_values: Array = bindings.get("exhaust_position", [])
	var exhaust_direction_values: Array = bindings.get("exhaust_direction", [])
	if exhaust_position_values.size() != 3 or exhaust_direction_values.size() != 3:
		root.free()
		return {"ok": false, "error": "Monster Car 2 exhaust position metadata is malformed"}
	var cg_source := _source_cg_offsets()
	var visual := {
		"ok": true,
		"error": "",
		"root": root,
		"nodes": nodes,
		"travel_outside_art": false,
		"body_nodes": body_nodes,
		"headlight_nodes": headlight_nodes,
		"brake_light_nodes": brake_light_nodes,
		"headlight_positions": headlight_positions,
		"exhaust_position": Vector3(float(exhaust_position_values[0]), float(exhaust_position_values[1]), float(exhaust_position_values[2])),
		"exhaust_direction": Vector3(float(exhaust_direction_values[0]), float(exhaust_direction_values[1]), float(exhaust_direction_values[2])).normalized(),
		"damage_basis": ART_BASIS,
		"_default_cg_right": cg_source.x,
		"_default_cg_forward": cg_source.y,
		ENGINE_PHASE_KEY: 0.0,
		"_manifest": manifest,
		"_rig_bytes": rig_bytes,
		"_mesh_nodes": mesh_nodes,
		"_imported": imported,
		"_base_transforms": base_transforms,
		"_animated_names": track_nodes,
		"_engine_pivot": engine_pivot,
		"_engine_pivot_inverse": engine_pivot.affine_inverse(),
		"_draw_tracks": draw_tracks,
		"_draw_wheel_groups": draw_wheel_groups,
		"_draw_engine_nodes": draw_engine_nodes,
		"_draw_inputs": {"h_FL": 0.0, "h_FR": 0.0, "h_RL": 0.0, "h_RR": 0.0, "steer": 0.0},
	}
	return visual


static func _bind_aliases(imported_nodes: Dictionary, aliases: Dictionary) -> String:
	var required := {
		"Body": "Carroceria_Casco",
		"Bumper_F": "Parachoques_Del.001",
		"Bumper_R": "Parachoques_Tras.001",
		"FL_WheelMesh": "Llanta_Del_Izq",
		"FR_WheelMesh": "Llanta_Del_Der",
		"RL_WheelMesh": "Llanta_Tras_Izq",
		"RR_WheelMesh": "Llanta_Tras_Der",
	}
	for alias: String in required:
		var source_name: String = required[alias]
		var node: Variant = imported_nodes.get(source_name)
		if not node is MeshInstance3D:
			return "Missing Monster Car 2 binding %s (%s)" % [alias, source_name]
		aliases[alias] = node
	return ""


static func _collect(node: Node, nodes: Dictionary, meshes: Dictionary) -> String:
	if node is CollisionObject3D or node is CollisionShape3D:
		return "Monster Car 2 render asset must not own simulation: " + str(node.name)
	var imported_name := str(node.name)
	var source_name := _restore_blender_suffix(imported_name)
	if node is Node3D and not nodes.has(imported_name):
		nodes[imported_name] = node
		if not source_name.is_empty():
			nodes[source_name] = node
	if node is MeshInstance3D:
		if meshes.has(imported_name):
			return "Duplicate Monster Car 2 mesh binding: " + imported_name
		meshes[imported_name] = node
		if not source_name.is_empty():
			meshes[source_name] = node
	for child in node.get_children():
		var error := _collect(child, nodes, meshes)
		if not error.is_empty():
			return error
	return ""


static func _restore_blender_suffix(imported_name: String) -> String:
	var separator := imported_name.rfind("_")
	if separator <= 0:
		return ""
	var suffix := imported_name.substr(separator + 1)
	if suffix.length() != 3 or not suffix.is_valid_int():
		return ""
	return imported_name.substr(0, separator) + "." + suffix


static func _find_animation_players(node: Node) -> Array[AnimationPlayer]:
	var result: Array[AnimationPlayer] = []
	if node is AnimationPlayer:
		result.append(node as AnimationPlayer)
	for child in node.get_children():
		result.append_array(_find_animation_players(child))
	return result


static func _mesh_bindings(names: Array, mesh_nodes: Dictionary) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	for name: String in names:
		var value: Variant = mesh_nodes.get(name)
		if value is MeshInstance3D:
			result.append(value as MeshInstance3D)
	return result


static func _source_cg_offsets() -> Vector2:
	var file := FileAccess.open(VEHICLE_DATA, FileAccess.READ)
	if file == null:
		return Vector2.ZERO
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("parameters"):
		return Vector2.ZERO
	var parameters: Dictionary = parsed.parameters
	var right: Dictionary = parameters.get("cg_right_from_datum_m", {})
	var forward: Dictionary = parameters.get("cg_forward_from_datum_m", {})
	return Vector2(float(right.get("value", 0.0)), float(forward.get("value", 0.0)))


static func _validate_bundle(manifest: Dictionary, bytes: PackedByteArray) -> String:
	var expected_hash := str(manifest.get("binary_sha256", "")).to_lower()
	if expected_hash.is_empty() or _sha256(bytes) != expected_hash:
		return "Monster Car 2 visual bake SHA-256 does not match its manifest"
	# In source builds, verify the supplied file bytes directly. Exported PCKs
	# remap this path to Godot's imported scene resource, which is not the GLB.
	var raw_glb_path := ProjectSettings.globalize_path(SCENE)
	if FileAccess.file_exists(raw_glb_path):
		var glb_bytes := FileAccess.get_file_as_bytes(raw_glb_path)
		if glb_bytes.is_empty() or _sha256(glb_bytes) != str(manifest.get("source_glb_sha256", "")).to_lower():
			return "Monster Car 2 GLB SHA-256 does not match its visual manifest"
	var tracks: Dictionary = manifest.get("tracks", {})
	if tracks.is_empty():
		return "Monster Car 2 visual manifest has no authored transform tracks"
	for name: String in tracks:
		var track: Dictionary = tracks[name]
		var axes: Array = track.get("axes", [])
		var ranges: Array = track.get("ranges", [])
		if axes.size() != ranges.size() or axes.size() > 4 or not _matrix_is_valid(track.get("correction", [])):
			return "Malformed Monster Car 2 transform track: " + name
		var sample_count := 1
		for axis_index in ranges.size():
			var axis_name := str(axes[axis_index])
			if axis_name not in ["h_FL", "h_FR", "h_RL", "h_RR", "steer"]:
				return "Unknown Monster Car 2 track input in: " + name
			var range_values: Array = ranges[axis_index]
			if range_values.size() != 4:
				return "Malformed Monster Car 2 track range in: " + name
			var low := float(range_values[0])
			var high := float(range_values[1])
			var step := float(range_values[2])
			var count := int(range_values[3])
			if not is_finite(low) or not is_finite(high) or not is_finite(step) or count < 1 or high < low:
				return "Invalid Monster Car 2 track range in: " + name
			if count > 1 and step <= 0.0:
				return "Invalid Monster Car 2 track step in: " + name
			sample_count *= count
		var float_count := int(track.get("float_count", -1))
		var offset := int(track.get("offset", -1))
		if float_count != sample_count * 12 or offset < 0 or offset + float_count * 4 > bytes.size():
			return "Monster Car 2 track bounds/count mismatch: " + name
		for value_index in float_count:
			if not is_finite(bytes.decode_float(offset + value_index * 4)):
				return "Non-finite Monster Car 2 transform sample: " + name
	var steer_map: Array = manifest.get("steer_inverse_map", [])
	if steer_map.size() < 2:
		return "Monster Car 2 visual manifest has no steering transfer table"
	var previous_angle := -INF
	var previous_control := -INF
	for row: Dictionary in steer_map:
		var angle := float(row.get("wheel_angle_rad", NAN))
		var control := float(row.get("control_rad", NAN))
		if not is_finite(angle) or not is_finite(control) or angle <= previous_angle or control <= previous_control:
			return "Monster Car 2 steering transfer table is invalid"
		previous_angle = angle
		previous_control = control
	return ""


static func _sha256(bytes: PackedByteArray) -> String:
	var hashing := HashingContext.new()
	if hashing.start(HashingContext.HASH_SHA256) != OK or hashing.update(bytes) != OK:
		return ""
	return hashing.finish().hex_encode()


## Render-only poses. The received state is never mutated; physics may stop outside the art table.
static func draw(visual: Dictionary, state: PackedFloat64Array, cg_height_m: float) -> bool:
	if state.size() < 31 or not bool(visual.get("ok", false)) or not is_finite(cg_height_m):
		return false
	for value in state:
		if not is_finite(value):
			return false
	var root: Node3D = visual.get("root") as Node3D
	if root == null:
		return false
	var rotation := Frames.quat_to_render(state.slice(6, 10))
	var position := Frames.ned_to_render([state[0], state[1], state[2]])
	var default_right := float(visual.get("_default_cg_right", 0.0))
	var default_forward := float(visual.get("_default_cg_forward", 0.0))
	var default_cg_offset := Vector3(default_right, cg_height_m, -default_forward)
	var cg_offset: Variant = visual.get("cg_offset", default_cg_offset)
	if not cg_offset is Vector3 or not is_finite(cg_offset.x) or not is_finite(cg_offset.y) or not is_finite(cg_offset.z):
		return false
	root.transform = Frames.root_transform(rotation, position, cg_offset as Vector3)

	var inputs: Dictionary = visual.get("_draw_inputs", {})
	if inputs.is_empty():
		return false
	var outside := false
	for corner_index in CORNERS.size():
		var authored_travel := clampf(state[STATE_TRAVEL_START + corner_index], -0.044, 0.036)
		inputs[TRAVEL_INPUT_NAMES[corner_index]] = authored_travel
		outside = outside or absf(authored_travel - state[STATE_TRAVEL_START + corner_index]) > 0.000001
	var manifest: Dictionary = visual.get("_manifest", {})
	var steer_map: Array = manifest.get("steer_inverse_map", [])
	var requested_source_wheel_angle := -state[STEER_STATE_INDEX]
	var authored_steer := _inverse_steer_map(steer_map, requested_source_wheel_angle)
	inputs["steer"] = authored_steer
	var source_angle_limit := clampf(requested_source_wheel_angle,
		float(steer_map[0].wheel_angle_rad), float(steer_map[steer_map.size() - 1].wheel_angle_rad))
	outside = outside or absf(source_angle_limit - requested_source_wheel_angle) > 0.000001
	visual.travel_outside_art = outside

	var rig_bytes: PackedByteArray = visual.get("_rig_bytes", PackedByteArray())
	for track_item: Dictionary in visual.get("_draw_tracks", []):
		var mesh: MeshInstance3D = track_item.get("mesh") as MeshInstance3D
		var transform_value: Variant = _sample_compiled_track(track_item.get("sampler") as TrackSampler, rig_bytes, inputs)
		if not transform_value is Transform3D:
			return false
		mesh.transform = transform_value

	var draw_wheel_groups: Array = visual.get("_draw_wheel_groups", [])
	for corner_index in CORNERS.size():
		var group: Dictionary = draw_wheel_groups[corner_index]
		var pivot_value: Variant = _sample_compiled_track(group.get("sampler") as TrackSampler, rig_bytes, inputs)
		if not pivot_value is Transform3D:
			return false
		var pivot: Transform3D = pivot_value
		var spin_sign := float(group.spin_sign)
		var angle := spin_sign * state[STATE_WHEEL_ANGLE_START + corner_index]
		var wheel_spin := pivot * Transform3D(Basis(Vector3.FORWARD, angle), Vector3.ZERO) * pivot.affine_inverse()
		for mesh_item: Dictionary in group.meshes:
			var wheel_mesh := mesh_item.mesh as MeshInstance3D
			var base: Transform3D = wheel_mesh.transform if mesh_item.animated else mesh_item.base
			wheel_mesh.transform = wheel_spin * base

	var engine_phase := float(visual.get(ENGINE_PHASE_KEY, 0.0))
	if not is_finite(engine_phase):
		return false
	var engine_pivot: Transform3D = visual.get("_engine_pivot", Transform3D.IDENTITY)
	var engine_pivot_inverse: Transform3D = visual["_engine_pivot_inverse"]
	var engine_spin := engine_pivot * Transform3D(Basis(Vector3.FORWARD, engine_phase), Vector3.ZERO) * engine_pivot_inverse
	# The authored bell shares the crank pivot but belongs to the transmission
	# output. At idle it stays still while the flywheel rotates inside it.
	var bell_phase := 0.0
	for corner_index in 4: bell_phase += state[STATE_WHEEL_ANGLE_START + corner_index] * 0.25
	bell_phase *= float(visual.get("gear_ratio", 0.0))
	var bell_spin := engine_pivot * Transform3D(Basis(Vector3.FORWARD, fposmod(bell_phase, TAU)), Vector3.ZERO) * engine_pivot.affine_inverse()
	for engine_item: Dictionary in visual.get("_draw_engine_nodes", []):
		var engine_mesh := engine_item.mesh as MeshInstance3D
		var base: Transform3D = engine_mesh.transform if engine_item.animated else engine_item.base
		engine_mesh.transform = (bell_spin if engine_item.bell else engine_spin) * base
	return true


static func _compile_track(track: Dictionary) -> TrackSampler:
	var sampler := TrackSampler.new()
	var axes: Array = track.get("axes", [])
	var ranges: Array = track.get("ranges", [])
	sampler.axis_names.resize(axes.size())
	sampler.low_values.resize(axes.size())
	sampler.steps.resize(axes.size())
	sampler.counts.resize(axes.size())
	sampler.low_indices.resize(axes.size())
	sampler.high_indices.resize(axes.size())
	sampler.fractions.resize(axes.size())
	for axis_index in axes.size():
		var range_values: Array = ranges[axis_index]
		sampler.axis_names[axis_index] = str(axes[axis_index])
		sampler.low_values[axis_index] = float(range_values[0])
		sampler.steps[axis_index] = float(range_values[2])
		sampler.counts[axis_index] = int(range_values[3])
	sampler.offset = int(track.get("offset", 0))
	sampler.correction = _transform_from_floats(track.get("correction", []))
	sampler.values.resize(12)
	return sampler


static func _sample_compiled_track(sampler: TrackSampler, bytes: PackedByteArray, inputs: Dictionary) -> Variant:
	if sampler == null or bytes.is_empty():
		return null
	var axis_count := sampler.axis_names.size()
	sampler.values.fill(0.0)
	for axis_index in axis_count:
		var count := sampler.counts[axis_index]
		if count < 1:
			return null
		if count == 1:
			sampler.low_indices[axis_index] = 0
			sampler.high_indices[axis_index] = 0
			sampler.fractions[axis_index] = 0.0
			continue
		var value := float(inputs.get(sampler.axis_names[axis_index], 0.0))
		var grid_position := clampf(
			(value - sampler.low_values[axis_index]) / sampler.steps[axis_index],
			0.0,
			float(count - 1),
		)
		var lower := int(floor(grid_position))
		var upper := mini(lower + 1, count - 1)
		sampler.low_indices[axis_index] = lower
		sampler.high_indices[axis_index] = upper
		sampler.fractions[axis_index] = grid_position - float(lower)
	for mask in (1 << axis_count):
		var weight := 1.0
		var flat_index := 0
		for axis_index in axis_count:
			var choose_upper := (mask & (1 << axis_index)) != 0
			var sample_index := sampler.high_indices[axis_index] if choose_upper else sampler.low_indices[axis_index]
			weight *= sampler.fractions[axis_index] if choose_upper else 1.0 - sampler.fractions[axis_index]
			flat_index = flat_index * sampler.counts[axis_index] + sample_index
		if weight <= 0.0:
			continue
		var sample_offset := sampler.offset + flat_index * 12 * 4
		if sample_offset < 0 or sample_offset + 48 > bytes.size():
			return null
		for component in 12:
			sampler.values[component] += bytes.decode_float(sample_offset + component * 4) * weight
	return sampler.correction * _transform_from_floats(sampler.values)


static func _inverse_steer_map(steer_map: Array, wheel_angle_rad: float) -> float:
	if steer_map.size() < 2:
		return 0.0
	if wheel_angle_rad <= float(steer_map[0].wheel_angle_rad):
		return float(steer_map[0].control_rad)
	if wheel_angle_rad >= float(steer_map[steer_map.size() - 1].wheel_angle_rad):
		return float(steer_map[steer_map.size() - 1].control_rad)
	for index in range(steer_map.size() - 1):
		var lower: Dictionary = steer_map[index]
		var upper: Dictionary = steer_map[index + 1]
		if wheel_angle_rad <= float(upper.wheel_angle_rad):
			var fraction := (wheel_angle_rad - float(lower.wheel_angle_rad)) / (float(upper.wheel_angle_rad) - float(lower.wheel_angle_rad))
			return lerpf(float(lower.control_rad), float(upper.control_rad), fraction)
	return 0.0


static func _matrix_is_valid(values: Variant) -> bool:
	if typeof(values) != TYPE_ARRAY or values.size() != 12:
		return false
	for value in values:
		if not is_finite(float(value)):
			return false
	return true


static func _transform_from_floats(values: Array) -> Transform3D:
	var basis := Basis(
		Vector3(float(values[0]), float(values[1]), float(values[2])),
		Vector3(float(values[3]), float(values[4]), float(values[5])),
		Vector3(float(values[6]), float(values[7]), float(values[8])),
	)
	return Transform3D(basis, Vector3(float(values[9]), float(values[10]), float(values[11])))
