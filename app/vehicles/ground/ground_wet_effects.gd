## Bounded, render-only water and mud response for the MT8 tires.
## Input telemetry is treated as an accepted read-only snapshot.
extends Node3D

const CORNERS := ["FL", "FR", "RL", "RR"]
const SPLASH_ONE: AudioStreamWAV = preload("res://assets/audio/water/peludo-splash1.wav")
const SPLASH_TWO: AudioStreamWAV = preload("res://assets/audio/water/peludo-splash2.wav")

const DROPS_PER_WHEEL := 8
const DROP_BUDGET_PER_KIND := DROPS_PER_WHEEL * 4
const RING_COUNT_PER_WHEEL := 2
const MAX_FRAME_DELTA_S := 0.1
const DROP_LIFETIME_S := 0.62
const MAX_AUDIO_DISTANCE_M := 18.0
const AUDIO_COOLDOWN_S := 0.9

var audio_enabled := true

var _prepared := false
var _paused := false
var _vehicle_root: Node3D
var _wheel_nodes: Array[MeshInstance3D] = []
var _wheel_radii := PackedFloat32Array()
var _water_droplets: MultiMeshInstance3D
var _water_multimesh: MultiMesh
var _mud_droplets: MultiMeshInstance3D
var _mud_multimesh: MultiMesh
var _rings: Array[MeshInstance3D] = []
var _ring_materials: Array[StandardMaterial3D] = []
var _audio_player: AudioStreamPlayer3D
var _clock_s := 0.0
var _audio_cooldown_s := 0.0
var _audio_pulses := 0
var _water_activity := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
var _mud_activity := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
var _water_active_wheels := 0
var _mud_active_wheels := 0
var _water_instance_cursor := 0
var _mud_instance_cursor := 0


## Bind the four source wheel meshes once. No imported mesh or material is mutated.
func prepare(visual: Dictionary, scene_parent: Node = null) -> bool:
	if _prepared:
		return false
	var root_value: Variant = visual.get("root")
	var nodes_value: Variant = visual.get("nodes")
	if not root_value is Node3D or typeof(nodes_value) != TYPE_DICTIONARY:
		return false
	var checked_wheels: Array[MeshInstance3D] = []
	for corner: String in CORNERS:
		var wheel_value: Variant = nodes_value.get(corner + "_WheelMesh")
		if not wheel_value is MeshInstance3D or (wheel_value as MeshInstance3D).mesh == null:
			return false
		checked_wheels.append(wheel_value as MeshInstance3D)
	_vehicle_root = root_value as Node3D
	_wheel_nodes = checked_wheels
	for wheel: MeshInstance3D in _wheel_nodes:
		var bounds := wheel.get_aabb()
		_wheel_radii.append(clampf(maxf(bounds.size.y, bounds.size.z) * 0.5, 0.035, 0.10))
	if scene_parent != null and get_parent() == null:
		scene_parent.add_child(self)
	_build_pools()
	_prepared = true
	return true


## Animate only from the accepted environment/wheel snapshot and motion telemetry.
## `wheel_water_height_m` is an absolute render-world UP elevation, as in the physics contract.
func update_render(dt: float, telemetry: Dictionary, paused: bool, night_weight: float = 0.0) -> void:
	if not _prepared:
		return
	_paused = paused
	var safe_dt := clampf(dt, 0.0, MAX_FRAME_DELTA_S) if is_finite(dt) else 0.0
	if not paused:
		_clock_s += safe_dt
		_audio_cooldown_s = maxf(0.0, _audio_cooldown_s - safe_dt)
	if _audio_player != null:
		_audio_player.stream_paused = paused
		if not audio_enabled:
			_audio_player.stop()
			_audio_player.stream = null
	if paused:
		return
	if not audio_enabled and _audio_player != null:
		_audio_player.stream = null

	var parsed := _read_render_inputs(telemetry)
	if not bool(parsed.get("ok", false)):
		_clear_activity()
		return
	var environment: Dictionary = parsed.environment
	var contacts: PackedByteArray = parsed.contacts
	var slips: PackedFloat64Array = parsed.slips
	var speed := absf(float(parsed.speed_m_per_s))
	var body_submersion := float(environment.body_submersion)
	var water_depth := float(environment.water_depth_m)
	var motion := clampf((speed - 0.25) / 3.8, 0.0, 1.0) * 0.58
	var safe_night_weight := clampf(night_weight, 0.0, 1.0) if is_finite(night_weight) else 0.0
	_update_pool_bounds()
	var audio_activity := 0.0
	_water_active_wheels = 0
	_mud_active_wheels = 0
	_water_instance_cursor = 0
	_mud_instance_cursor = 0

	for wheel_index: int in 4:
		var wheel: MeshInstance3D = _wheel_nodes[wheel_index]
		var wheel_position := wheel.global_position
		if not _vector3_is_finite(wheel_position):
			_water_activity[wheel_index] = 0.0
			_mud_activity[wheel_index] = 0.0
			_hide_wheel_pool(wheel_index)
			continue
		var slip := absf(float(slips[wheel_index]))
		var movement := maxf(motion, clampf((slip - 0.08) / 1.25, 0.0, 1.0))
		var submersion := float(environment.wheel_submersion[wheel_index])
		var surface_y := float(environment.wheel_water_height_m[wheel_index])
		var local_depth := float(environment.wheel_depth_m[wheel_index])
		var mud_fraction := float(environment.wheel_mud[wheel_index])
		var radius := _wheel_radii[wheel_index]
		var tire_bottom_y := wheel_position.y - radius
		var tire_top_y := wheel_position.y + radius
		var water_surface_intersects_tire := surface_y >= tire_bottom_y - 0.045 \
			and surface_y <= tire_top_y + 0.018
		var exposed_fraction := 1.0 - smoothstep(0.84, 0.98, submersion)
		var wet_fill := maxf(submersion, clampf(local_depth / maxf(radius * 2.0, 0.02), 0.0, 1.0))
		var water_level := movement * wet_fill * exposed_fraction
		if not water_surface_intersects_tire or body_submersion >= 0.99:
			water_level = 0.0
		var mud_submersion := maxf(body_submersion, submersion)
		var mud_exposure := 1.0 - smoothstep(0.45, 0.82, mud_submersion)
		var mud_level := movement * mud_fraction * mud_exposure if contacts[wheel_index] != 0 else 0.0
		_water_activity[wheel_index] = clampf(water_level, 0.0, 1.0)
		_mud_activity[wheel_index] = clampf(mud_level, 0.0, 1.0)
		if _water_activity[wheel_index] > 0.035:
			_water_active_wheels += 1
			audio_activity = maxf(audio_activity, _water_activity[wheel_index])
		if _mud_activity[wheel_index] > 0.035:
			_mud_active_wheels += 1
		_sync_wheel_pool(wheel_index, wheel_position, radius, surface_y, water_depth,
			_water_activity[wheel_index], _mud_activity[wheel_index], safe_night_weight)
	_water_multimesh.visible_instance_count = _water_instance_cursor
	_mud_multimesh.visible_instance_count = _mud_instance_cursor

	if audio_activity >= 0.18 and _audio_cooldown_s <= 0.0:
		_play_splash(audio_activity)


## Reset only this component's pools and voice; the source model remains untouched.
func reset() -> void:
	_clock_s = 0.0
	_audio_cooldown_s = 0.0
	_audio_pulses = 0
	_paused = false
	_clear_activity()
	if _audio_player != null:
		_audio_player.stop()
		_audio_player.stream_paused = false
		_audio_player.stream = null


func diagnostic_snapshot() -> Dictionary:
	return {
		"prepared": _prepared,
		"water_active_wheels": 0 if _paused else _water_active_wheels,
		"mud_active_wheels": 0 if _paused else _mud_active_wheels,
		"water_activity_per_wheel": _water_activity.duplicate(),
		"mud_activity_per_wheel": _mud_activity.duplicate(),
		"water_drop_budget": _water_multimesh.instance_count if _water_multimesh != null else 0,
		"mud_drop_budget": _mud_multimesh.instance_count if _mud_multimesh != null else 0,
		"water_instances_visible": _water_multimesh.visible_instance_count if _water_multimesh != null else 0,
		"mud_instances_visible": _mud_multimesh.visible_instance_count if _mud_multimesh != null else 0,
		"ring_budget": _rings.size(),
		"audio_enabled": audio_enabled,
		"audio_pulses": _audio_pulses,
		"paused": _paused,
		"clock_s": _clock_s,
	}


func _build_pools() -> void:
	var droplet_mesh := SphereMesh.new()
	droplet_mesh.radius = 1.0
	droplet_mesh.height = 2.0
	droplet_mesh.radial_segments = 8
	droplet_mesh.rings = 4
	_water_multimesh = _new_droplet_pool(droplet_mesh)
	_water_droplets = MultiMeshInstance3D.new()
	_water_droplets.name = "WaterDropPool"
	_water_droplets.multimesh = _water_multimesh
	_water_droplets.material_override = _drop_material(Color(0.66, 0.86, 0.9, 0.68))
	_water_droplets.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_water_droplets.custom_aabb = AABB(Vector3(-8.0, -2.0, -8.0), Vector3(16.0, 6.0, 16.0))
	_water_droplets.top_level = true
	add_child(_water_droplets)

	_mud_multimesh = _new_droplet_pool(droplet_mesh)
	_mud_droplets = MultiMeshInstance3D.new()
	_mud_droplets.name = "MudClodPool"
	_mud_droplets.multimesh = _mud_multimesh
	_mud_droplets.material_override = _drop_material(Color(0.27, 0.16, 0.075, 0.86))
	_mud_droplets.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mud_droplets.custom_aabb = AABB(Vector3(-8.0, -2.0, -8.0), Vector3(16.0, 6.0, 16.0))
	_mud_droplets.top_level = true
	add_child(_mud_droplets)

	var ring_mesh := _make_ring_mesh()
	for wheel_index: int in 4:
		for ring_index: int in RING_COUNT_PER_WHEEL:
			var ring := MeshInstance3D.new()
			ring.name = "%sRipple%d" % [CORNERS[wheel_index], ring_index]
			ring.mesh = ring_mesh
			ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			ring.top_level = true
			var material := StandardMaterial3D.new()
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
			material.albedo_color = Color(0.35, 0.68, 0.72, 0.0)
			material.vertex_color_use_as_albedo = true
			material.render_priority = 2
			ring.material_override = material
			ring.visible = false
			add_child(ring)
			_rings.append(ring)
			_ring_materials.append(material)

	_audio_player = AudioStreamPlayer3D.new()
	_audio_player.name = "WetTireSplashVoice"
	_audio_player.max_polyphony = 1
	_audio_player.unit_size = 4.0
	_audio_player.max_distance = MAX_AUDIO_DISTANCE_M
	_audio_player.volume_db = -18.0
	_audio_player.panning_strength = 0.7
	_audio_player.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_audio_player)
	_update_pool_bounds()
	_clear_activity()


func _new_droplet_pool(mesh: Mesh) -> MultiMesh:
	var pool := MultiMesh.new()
	pool.transform_format = MultiMesh.TRANSFORM_3D
	pool.use_colors = true
	pool.mesh = mesh
	pool.instance_count = DROP_BUDGET_PER_KIND
	pool.visible_instance_count = 0
	return pool


func _drop_material(tint: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.vertex_color_use_as_albedo = true
	material.albedo_color = tint
	material.render_priority = 2
	return material


func _make_ring_mesh() -> ArrayMesh:
	const SEGMENTS := 32
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for index: int in SEGMENTS:
		var angle0 := TAU * float(index) / float(SEGMENTS)
		var angle1 := TAU * float(index + 1) / float(SEGMENTS)
		var inner0 := Vector3(cos(angle0) * 0.92, 0.0, sin(angle0) * 0.92)
		var outer0 := Vector3(cos(angle0), 0.0, sin(angle0))
		var inner1 := Vector3(cos(angle1) * 0.92, 0.0, sin(angle1) * 0.92)
		var outer1 := Vector3(cos(angle1), 0.0, sin(angle1))
		var base := vertices.size()
		vertices.append_array(PackedVector3Array([inner0, outer0, inner1, outer1]))
		normals.append_array(PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP]))
		colors.append_array(PackedColorArray([
			Color(1.0, 1.0, 1.0, 0.4), Color(1.0, 1.0, 1.0, 0.0),
			Color(1.0, 1.0, 1.0, 0.4), Color(1.0, 1.0, 1.0, 0.0),
		]))
		indices.append_array(PackedInt32Array([base, base + 2, base + 1, base + 1, base + 2, base + 3]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var ring := ArrayMesh.new()
	ring.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return ring


func _sync_wheel_pool(wheel_index: int, wheel_position: Vector3, radius: float,
		surface_y: float, total_water_depth: float, water_activity: float,
		mud_activity: float, night_weight: float) -> void:
	var vehicle_basis := _vehicle_root.global_basis.orthonormalized()
	var side_axis := _outward_side_vector(wheel_index, 1.0)
	var rear_axis := vehicle_basis * Vector3(0.0, 0.0, 1.0)
	var water_tint := Color(0.72, 0.9, 0.94).lerp(Color(0.4, 0.57, 0.68), clampf(night_weight, 0.0, 1.0))
	var wheel_depth_factor := clampf(total_water_depth / maxf(radius * 5.0, 0.1), 0.0, 1.0)
	for drop_index: int in DROPS_PER_WHEEL:
		var water_slot_visible := drop_index < ceili(water_activity * float(DROPS_PER_WHEEL))
		var water_age := fposmod(_clock_s * 0.93 + float(wheel_index) * 0.17 + float(drop_index) * 0.113, DROP_LIFETIME_S)
		var water_lift := 0.48 + 0.72 * water_activity + 0.12 * wheel_depth_factor
		var water_flight_y := 0.015 + water_lift * water_age - 1.35 * water_age * water_age
		if water_slot_visible and water_activity > 0.02 and water_flight_y > 0.0:
			var water_origin := wheel_position
			water_origin.y = surface_y + 0.012
			var water_fan := side_axis * (0.055 + 0.04 * sin(float(drop_index) * 1.7)) + rear_axis * 0.045
			var water_position := water_origin + water_fan * water_age + Vector3.UP * water_flight_y
			var water_radius := 0.006 + 0.009 * water_activity
			var water_transform := Transform3D(Basis.IDENTITY.scaled(Vector3(water_radius, water_radius * 1.5, water_radius)), water_position)
			_water_multimesh.set_instance_transform(_water_instance_cursor, water_transform)
			_water_multimesh.set_instance_color(_water_instance_cursor, Color(water_tint.r, water_tint.g, water_tint.b,
				(1.0 - water_age / DROP_LIFETIME_S) * water_activity))
			_water_instance_cursor += 1

		var mud_slot_visible := drop_index < ceili(mud_activity * float(DROPS_PER_WHEEL))
		var mud_age := fposmod(_clock_s * 0.74 + float(wheel_index) * 0.21 + float(drop_index) * 0.127 + 0.19, DROP_LIFETIME_S)
		var mud_lift := 0.38 + 0.68 * mud_activity
		var mud_flight_y := 0.012 + mud_lift * mud_age - 1.25 * mud_age * mud_age
		if mud_slot_visible and mud_activity > 0.02 and mud_flight_y > 0.0:
			var mud_origin := wheel_position
			mud_origin.y = wheel_position.y - radius + 0.015
			var mud_fan := side_axis * (0.065 + 0.035 * cos(float(drop_index) * 1.3)) + rear_axis * 0.06
			var mud_position := mud_origin + mud_fan * mud_age + Vector3.UP * mud_flight_y
			var mud_radius := 0.007 + 0.012 * mud_activity
			var mud_transform := Transform3D(Basis.IDENTITY.scaled(Vector3(mud_radius, mud_radius, mud_radius)), mud_position)
			_mud_multimesh.set_instance_transform(_mud_instance_cursor, mud_transform)
			_mud_multimesh.set_instance_color(_mud_instance_cursor, Color(1.0, 1.0, 1.0,
				(1.0 - mud_age / DROP_LIFETIME_S) * mud_activity))
			_mud_instance_cursor += 1

	for ripple_index: int in RING_COUNT_PER_WHEEL:
		var ring_index := wheel_index * RING_COUNT_PER_WHEEL + ripple_index
		if water_activity > 0.035:
			var ring_phase := fposmod(_clock_s * 0.52 + float(wheel_index) * 0.13 + float(ripple_index) * 0.5, 1.0)
			var ring_radius := radius * (1.35 + 2.3 * ring_phase + 0.8 * water_activity)
			var ring := _rings[ring_index]
			ring.global_transform = Transform3D(Basis.IDENTITY.scaled(Vector3(ring_radius, 1.0, ring_radius)),
				Vector3(wheel_position.x, surface_y + 0.008, wheel_position.z))
			var alpha := water_activity * 0.38 * (1.0 - ring_phase)
			_ring_materials[ring_index].albedo_color = Color(0.35, 0.68, 0.72, alpha)
			ring.visible = alpha > 0.008
		else:
			_rings[ring_index].visible = false
			_ring_materials[ring_index].albedo_color = Color(0.35, 0.68, 0.72, 0.0)

	_water_droplets.global_transform = Transform3D.IDENTITY
	_mud_droplets.global_transform = Transform3D.IDENTITY


func _outward_side_vector(wheel_index: int, distance: float) -> Vector3:
	var side_sign := -1.0 if wheel_index in [0, 2] else 1.0
	return _vehicle_root.global_basis.orthonormalized() * Vector3(side_sign * distance, 0.0, 0.0)


func _play_splash(activity: float) -> void:
	if not audio_enabled or _audio_player == null:
		return
	if _vehicle_root != null:
		_audio_player.global_position = _vehicle_root.global_position
	var source := SPLASH_ONE if _audio_pulses % 2 == 0 else SPLASH_TWO
	_audio_player.stream = source.duplicate() as AudioStreamWAV
	_audio_player.volume_db = lerpf(-22.0, -15.0, clampf(activity, 0.0, 1.0))
	_audio_player.stream_paused = false
	_audio_pulses += 1
	_audio_cooldown_s = AUDIO_COOLDOWN_S
	if AudioServer.get_driver_name() != "Dummy":
		_audio_player.play()


func _clear_activity() -> void:
	_water_activity = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	_mud_activity = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	_water_active_wheels = 0
	_mud_active_wheels = 0
	_water_instance_cursor = 0
	_mud_instance_cursor = 0
	if _water_multimesh != null:
		_water_multimesh.visible_instance_count = 0
	if _mud_multimesh != null:
		_mud_multimesh.visible_instance_count = 0
	for ring: MeshInstance3D in _rings:
		ring.visible = false
	for material: StandardMaterial3D in _ring_materials:
		material.albedo_color = Color(0.35, 0.68, 0.72, 0.0)


func _update_pool_bounds() -> void:
	if _vehicle_root == null:
		return
	var center := _vehicle_root.global_position
	if not _vector3_is_finite(center):
		return
	var bounds := AABB(center - Vector3(4.0, 3.0, 4.0), Vector3(8.0, 6.0, 8.0))
	if _water_droplets != null:
		_water_droplets.custom_aabb = bounds
	if _mud_droplets != null:
		_mud_droplets.custom_aabb = bounds


func _hide_wheel_pool(wheel_index: int) -> void:
	for ring_index: int in RING_COUNT_PER_WHEEL:
		var index := wheel_index * RING_COUNT_PER_WHEEL + ring_index
		_rings[index].visible = false
		_ring_materials[index].albedo_color = Color(0.35, 0.68, 0.72, 0.0)


func _read_render_inputs(telemetry: Dictionary) -> Dictionary:
	var environment_value: Variant = telemetry.get("environment")
	if typeof(environment_value) != TYPE_DICTIONARY:
		return {}
	var environment: Dictionary = environment_value
	if environment.get("ok") != true:
		return {}
	for key: String in ["body_submersion", "water_depth_m", "buoyancy_n", "drag_power_w", "power_w"]:
		if not _finite_number(environment.get(key)):
			return {}
	if float(environment.body_submersion) < 0.0 or float(environment.body_submersion) > 1.0 \
			or float(environment.water_depth_m) < 0.0 or float(environment.buoyancy_n) < 0.0 \
			or float(environment.drag_power_w) > 0.0:
		return {}
	var wheel_submersion: Variant = environment.get("wheel_submersion")
	var wheel_water_height: Variant = environment.get("wheel_water_height_m")
	var wheel_depth: Variant = environment.get("wheel_depth_m")
	var wheel_mud: Variant = environment.get("wheel_mud")
	if typeof(wheel_submersion) != TYPE_PACKED_FLOAT64_ARRAY or wheel_submersion.size() != 4 \
			or typeof(wheel_water_height) != TYPE_PACKED_FLOAT64_ARRAY or wheel_water_height.size() != 4 \
			or typeof(wheel_depth) != TYPE_PACKED_FLOAT64_ARRAY or wheel_depth.size() != 4 \
			or typeof(wheel_mud) != TYPE_PACKED_FLOAT64_ARRAY or wheel_mud.size() != 4:
		return {}
	for index: int in 4:
		if not _finite_number(wheel_submersion[index]) or float(wheel_submersion[index]) < 0.0 \
				or float(wheel_submersion[index]) > 1.0 or not _finite_number(wheel_water_height[index]) \
				or not _finite_number(wheel_depth[index]) or float(wheel_depth[index]) < 0.0 \
				or not _finite_number(wheel_mud[index]) or float(wheel_mud[index]) < 0.0 \
				or float(wheel_mud[index]) > 1.0:
			return {}
	var contacts_value: Variant = telemetry.get("wheel_in_contact")
	var slips_value: Variant = telemetry.get("wheel_slip_speed_m_per_s")
	var speed_value: Variant = telemetry.get("speed_m_per_s")
	if typeof(contacts_value) != TYPE_PACKED_BYTE_ARRAY or contacts_value.size() != 4 \
			or typeof(slips_value) != TYPE_PACKED_FLOAT64_ARRAY or slips_value.size() != 4 \
			or not _finite_number(speed_value):
		return {}
	for slip_value: Variant in slips_value:
		if not _finite_number(slip_value):
			return {}
	return {"ok": true, "environment": environment, "contacts": contacts_value,
		"slips": slips_value, "speed_m_per_s": float(speed_value)}


static func _finite_number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))


static func _vector3_is_finite(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)
