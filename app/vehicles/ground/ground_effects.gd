## Render-only effects for the bundled MT8. Physics values are read-only inputs.
extends Node3D

const CORNERS := ["FL", "FR", "RL", "RR"]
const SMOKE_TEXTURE: Texture2D = preload("res://assets/crash/smoke.png")
const GRIME_SHADER_PATH := "res://vehicles/ground/ground_grime_overlay.gdshader"
const PARTICLES_PER_TIRE := 24
const MAX_GRIME := 0.46
const TIRE_RADIUS_FALLBACK_M := 0.061
const FULL_SHELL_GRIME_OPACITY_GAIN := 1.8

var _prepared := false
var headlights_enabled := true
var _vehicle_root: Node3D
var _authored_lights := {}
var _body_mesh: MeshInstance3D
var _shell_meshes: Array[MeshInstance3D] = []
var _wheel_nodes: Array[Node3D] = []
var _wheel_radii := PackedFloat32Array()
var _emitters: Array[CPUParticles3D] = []
var _dust_levels := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
var _grime_material: ShaderMaterial
var _grime_materials: Array[ShaderMaterial] = []
var _full_shell_grime := false
var _grime_amount := 0.0
var _wet_amount := 0.0
var _paused := false
var _last_headlight_energy := 0.0
var _night_weight := 0.0
var _brake_lights := false
var _reverse_lights := false
var _headlight_lights: Array[SpotLight3D] = []
var _headlight_materials: Array[StandardMaterial3D] = []
var _headlight_lens_colors: Array[Color] = []
var _tail_materials: Array[StandardMaterial3D] = []
var _tail_lens_colors: Array[Color] = []
var _reverse_materials: Array[StandardMaterial3D] = []
var _reverse_lens_colors: Array[Color] = []


## Build all per-instance visuals once. `visual` is the read-only result from mt8_model.build().
func prepare(visual: Dictionary, scene_parent: Node = null) -> bool:
	if _prepared:
		return false
	var root_value: Variant = visual.get("root")
	var nodes_value: Variant = visual.get("nodes")
	if not root_value is Node3D or typeof(nodes_value) != TYPE_DICTIONARY:
		return false
	var checked_wheels: Array[Node3D] = []
	for corner in CORNERS:
		var wheel: Variant = nodes_value.get(corner + "_WheelMesh")
		if not wheel is MeshInstance3D:
			return false
		checked_wheels.append(wheel as Node3D)
	var body_value: Variant = nodes_value.get("Body")
	_vehicle_root = root_value as Node3D
	if visual.has("headlight_positions"):
		_authored_lights = {
			"positions": visual.headlight_positions,
			"heads": visual.get("headlight_nodes", []),
			"tails": visual.get("brake_light_nodes", []),
		}
	_wheel_nodes = checked_wheels
	_body_mesh = body_value as MeshInstance3D if body_value is MeshInstance3D else null
	var authored_body_value: Variant = visual.get("body_nodes", [])
	if typeof(authored_body_value) == TYPE_ARRAY:
		for mesh_value in authored_body_value:
			if mesh_value is MeshInstance3D:
				_append_shell_mesh(mesh_value as MeshInstance3D)
	if _body_mesh != null:
		_append_shell_mesh(_body_mesh)
	_full_shell_grime = _shell_meshes.size() > 1
	if not _build_grime_overlay():
		_vehicle_root = null
		_shell_meshes.clear()
		_wheel_nodes.clear()
		_body_mesh = null
		return false
	_sync_grime_frame()
	if scene_parent != null and get_parent() == null:
		scene_parent.add_child(self)
	_build_dust_emitters()
	_build_vehicle_lights()
	_prepared = true
	return true


## Called by the render loop with accepted telemetry and controls. The road callback receives
## NED north/east in metres; the wheel's render-space position maps to (-z, x).
func update_render(
	simulation_elapsed_since_render: float,
	telemetry: Dictionary,
	last_controls: Dictionary,
	road: Callable,
	paused: bool,
	night_weight: float,
) -> void:
	if not _prepared:
		return
	var dt := clampf(simulation_elapsed_since_render, 0.0, 0.1) if is_finite(simulation_elapsed_since_render) else 0.0
	_paused = paused
	_sync_grime_frame()
	_update_lights(telemetry, last_controls, night_weight)
	if paused:
		for emitter in _emitters:
			emitter.emitting = false
			emitter.speed_scale = 0.0
		return
	for emitter in _emitters:
		emitter.speed_scale = 1.0
	var contacts: Variant = telemetry.get("wheel_in_contact", PackedByteArray())
	var slips: Variant = telemetry.get("wheel_slip_speed_m_per_s", PackedFloat64Array())
	var speed_value: Variant = telemetry.get("speed_m_per_s", 0.0)
	if not road.is_valid() or typeof(contacts) != TYPE_PACKED_BYTE_ARRAY \
			or contacts.size() != 4 or typeof(slips) != TYPE_PACKED_FLOAT64_ARRAY \
			or slips.size() != 4 or typeof(speed_value) not in [TYPE_FLOAT, TYPE_INT] \
			or not is_finite(float(speed_value)):
		_clear_dust_levels()
		return
	for slip_value in slips:
		if not is_finite(float(slip_value)):
			_clear_dust_levels()
			return
	var speed := absf(float(speed_value))
	var environment := _accepted_environment(telemetry)
	var dirt_activity := 0.0
	var distance_soil_activity := 0.0
	var mud_activity := 0.0
	var wet_target := float(environment.get("body_submersion", 0.0))
	var water_wash := wet_target
	var body_wet := wet_target > 0.01
	if not environment.is_empty():
		var environment_submersion: PackedFloat64Array = environment.wheel_submersion
		for i in 4:
			wet_target = maxf(wet_target, float(environment_submersion[i]))
			water_wash = maxf(water_wash, float(environment_submersion[i]))
		body_wet = float(environment.body_submersion) > 0.01
	for i in 4:
		var level := 0.0
		var source := _wheel_nodes[i].global_position
		var sample_value: Variant = {}
		if _vector3_is_finite(source):
			sample_value = road.call(-source.z, source.x)
		var road_water := 0.0
		var road_water_depth := 0.0
		var road_mud := 0.0
		var road_waterline_active := false
		if typeof(sample_value) == TYPE_DICTIONARY:
			var road_sample: Dictionary = sample_value
			var depth_value: Variant = road_sample.get("water_depth_m", 0.0)
			if _finite_number(depth_value) and float(depth_value) >= 0.0:
				road_water_depth = float(depth_value)
			var height_value: Variant = road_sample.get("water_height_m")
			if _finite_number(height_value) and _vector3_is_finite(source):
				var water_height := float(height_value)
				road_waterline_active = road_water_depth > 0.0 \
					and water_height >= source.y - _wheel_radii[i] - 0.045 \
					and water_height <= source.y + _wheel_radii[i] + 0.018
			var mud_value: Variant = road_sample.get("mud_fraction", 0.0)
			if _finite_number(mud_value) and float(mud_value) >= 0.0 and float(mud_value) <= 1.0:
				road_mud = float(mud_value)
		if road_waterline_active:
			road_water = clampf(road_water_depth / 0.04, 0.0, 1.0)
		wet_target = maxf(wet_target, road_water)
		water_wash = maxf(water_wash, road_water)
		var wheel_water := 0.0
		var wheel_mud := road_mud
		if not environment.is_empty():
			var environment_submersion: PackedFloat64Array = environment.wheel_submersion
			var environment_mud: PackedFloat64Array = environment.wheel_mud
			wheel_water = float(environment_submersion[i])
			wheel_mud = maxf(wheel_mud, float(environment_mud[i]))
		wet_target = maxf(wet_target, wheel_water)
		water_wash = maxf(water_wash, wheel_water)
		if contacts[i] != 0:
			var slip_speed := absf(float(slips[i]))
			var over_wet_surface := body_wet or road_waterline_active or wheel_water > 0.01
			var over_mud := wheel_mud > 0.001
			if typeof(sample_value) == TYPE_DICTIONARY:
				var sample: Dictionary = sample_value
				var surface_factor := _surface_dust_factor(str(sample.get("surface_id", "")))
				var ground_height: Variant = sample.get("height_m", source.y - _wheel_radii[i])
				var ground_height_valid := typeof(ground_height) in [TYPE_FLOAT, TYPE_INT] \
					and is_finite(float(ground_height))
				if _full_shell_grime and surface_factor > 0.0 and ground_height_valid \
						and not over_wet_surface and not over_mud:
					distance_soil_activity += surface_factor * maxf(speed, slip_speed)
				if surface_factor > 0.0 and ground_height_valid and not over_wet_surface \
						and not over_mud and (speed >= 0.35 or slip_speed >= 0.12):
					var speed_factor := clampf((speed - 0.35) / 4.5, 0.0, 1.0)
					var slip_factor := clampf((slip_speed - 0.04) / 1.4, 0.0, 1.0)
					level = surface_factor * maxf(speed_factor * 0.45, slip_factor)
					source.y = float(ground_height) + 0.018
					var emitter := _emitters[i]
					emitter.global_transform = Transform3D(_vehicle_root.global_basis.orthonormalized(), source)
					emitter.speed_scale = 0.45 + sqrt(level) * 0.9
					emitter.initial_velocity_max = lerpf(0.5, 1.4, level)
					emitter.scale_amount_max = lerpf(0.45, 0.9, level)
					var dust_tint := Color(1.0, 0.92, 0.81).lerp(Color(0.32, 0.38, 0.54), _night_weight)
					var dust_alpha := 0.8 * sqrt(level) * lerpf(1.0, 0.08, _night_weight)
					emitter.color = Color(dust_tint.r, dust_tint.g, dust_tint.b, dust_alpha)
			if wheel_mud > 0.0 and (speed >= 0.2 or slip_speed >= 0.04):
				var mud_motion := maxf(clampf((speed - 0.2) / 2.8, 0.0, 1.0),
					clampf((slip_speed - 0.03) / 0.9, 0.0, 1.0))
				mud_activity += wheel_mud * mud_motion
		_dust_levels[i] = level
		_emitters[i].emitting = level > 0.015
		dirt_activity += level
	if dt > 0.0:
		if _full_shell_grime and distance_soil_activity > 0.0:
			_grime_amount = minf(MAX_GRIME, _grime_amount + distance_soil_activity * dt * 0.0005)
		elif dirt_activity > 0.0:
			_grime_amount = minf(MAX_GRIME, _grime_amount + dirt_activity * 0.25 * dt * 0.028)
		if mud_activity > 0.0:
			_grime_amount = minf(MAX_GRIME, _grime_amount + mud_activity * 0.25 * dt * 0.08)
		if water_wash > 0.0:
			_grime_amount = maxf(0.0, _grime_amount - water_wash * dt * 0.006)
		var wet_rate := 1.5 if wet_target > _wet_amount else 0.22
		_wet_amount = move_toward(_wet_amount, clampf(wet_target, 0.0, 1.0), wet_rate * dt)
		for material in _grime_materials:
			material.set_shader_parameter("dirt_amount", _grime_amount)
			material.set_shader_parameter("wet_amount", _wet_amount)


## Reset clears only this component's particle buffers and overlay. Body visibility and source
## materials remain untouched.
func reset() -> void:
	if not _prepared:
		return
	clean_vehicle()
	_paused = false
	for emitter in _emitters:
		emitter.speed_scale = 1.0
	_brake_lights = false
	_reverse_lights = false
	_apply_tail_light_state()


## Clean only render-side grime, wet sheen and particle buffers.
func clean_vehicle() -> void:
	if not _prepared:
		return
	_grime_amount = 0.0
	_wet_amount = 0.0
	_sync_grime_frame()
	for material in _grime_materials:
		material.set_shader_parameter("dirt_amount", 0.0)
		material.set_shader_parameter("wet_amount", 0.0)
	_clear_dust_levels()
	for emitter in _emitters:
		emitter.restart()
		emitter.emitting = false
		emitter.speed_scale = 0.0 if _paused else 1.0


## Stable, allocation-light readout for focused tests and capture manifests.
func diagnostic_snapshot() -> Dictionary:
	var effective_levels := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	var active_wheels := 0
	for i in 4:
		if not _paused:
			effective_levels[i] = _dust_levels[i]
		if effective_levels[i] > 0.015:
			active_wheels += 1
	return {
		"prepared": _prepared,
		"dust_emission_levels": effective_levels,
		"dust_active_wheels": active_wheels,
		"particle_emitter_count": _emitters.size(),
		"particle_budget_per_wheel": PARTICLES_PER_TIRE,
		"particle_budget_total": _emitters.size() * PARTICLES_PER_TIRE,
		"grime_overlay_count": _grime_materials.size(),
		"grime_shell_mesh_count": _shell_meshes.size(),
		"full_shell_grime": _full_shell_grime,
		"grime_amount": _grime_amount,
		"wet_amount": _wet_amount,
		"headlights_enabled": headlights_enabled and not _headlight_lights.is_empty(),
		"headlight_energy": _last_headlight_energy,
		"brake_lights": _brake_lights,
		"reverse_lights": _reverse_lights,
		"paused": _paused,
	}


func _build_grime_overlay() -> bool:
	if _shell_meshes.is_empty():
		return false
	var shader := ResourceLoader.load(GRIME_SHADER_PATH, "Shader") as Shader
	if shader == null:
		return false
	var shell_bounds := _body_bounds_in_vehicle_space() if _full_shell_grime else _body_mesh.get_aabb()
	for shell_mesh in _shell_meshes:
		var material := _make_grime_material(shader, shell_bounds, false, _full_shell_grime)
		shell_mesh.material_overlay = material
		_grime_materials.append(material)
		if shell_mesh == _body_mesh or _grime_material == null:
			_grime_material = material
	for wheel_value in _wheel_nodes:
		var wheel_mesh := wheel_value as MeshInstance3D
		if wheel_mesh == null:
			return false
		var wheel_bounds := _mesh_bounds_in_vehicle_space(wheel_mesh) if _full_shell_grime else wheel_mesh.get_aabb()
		var wheel_material := _make_grime_material(shader, wheel_bounds, true, _full_shell_grime)
		wheel_mesh.material_overlay = wheel_material
		_grime_materials.append(wheel_material)
	return true


func _make_grime_material(shader: Shader, bounds: AABB, full_height: bool, vehicle_space: bool = false) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("dirt_amount", 0.0)
	material.set_shader_parameter("wet_amount", 0.0)
	material.set_shader_parameter("use_vehicle_space", vehicle_space)
	material.set_shader_parameter(
		"dirt_opacity_gain",
		FULL_SHELL_GRIME_OPACITY_GAIN if vehicle_space else 1.0,
	)
	if full_height:
		var margin := maxf(bounds.size.y * 0.04, 0.002)
		material.set_shader_parameter("dirt_band_bottom", bounds.end.y + margin)
		material.set_shader_parameter("dirt_band_top", bounds.end.y + margin * 2.0)
	else:
		material.set_shader_parameter("dirt_band_bottom", bounds.position.y + bounds.size.y * 0.04)
		material.set_shader_parameter("dirt_band_top", bounds.position.y + bounds.size.y * 0.48)
	return material


func _append_shell_mesh(mesh: MeshInstance3D) -> void:
	if mesh != null and not _shell_meshes.has(mesh):
		_shell_meshes.append(mesh)


func _sync_grime_frame() -> void:
	if not _full_shell_grime or _vehicle_root == null:
		return
	var vehicle_from_world := _vehicle_root.global_transform.affine_inverse()
	for material in _grime_materials:
		material.set_shader_parameter("vehicle_from_world", vehicle_from_world)


func _build_dust_emitters() -> void:
	var dust_material := StandardMaterial3D.new()
	dust_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dust_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dust_material.vertex_color_use_as_albedo = true
	dust_material.albedo_color = Color(0.79, 0.68, 0.53, 0.34)
	dust_material.albedo_texture = SMOKE_TEXTURE
	dust_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	dust_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	dust_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var dust_quad := QuadMesh.new()
	dust_quad.size = Vector2(0.20, 0.20)
	dust_quad.material = dust_material
	for i in 4:
		var wheel := _wheel_nodes[i] as MeshInstance3D
		var radius := TIRE_RADIUS_FALLBACK_M
		if wheel != null and wheel.mesh != null:
			var wheel_bounds := wheel.get_aabb()
			radius = clampf(maxf(wheel_bounds.size.y, wheel_bounds.size.z) * 0.5, 0.035, 0.10)
		_wheel_radii.append(radius)
		var particles := CPUParticles3D.new()
		particles.name = CORNERS[i] + "Dust"
		particles.amount = PARTICLES_PER_TIRE
		particles.lifetime = 1.35
		particles.lifetime_randomness = 0.28
		particles.local_coords = false
		particles.one_shot = false
		particles.emitting = false
		particles.speed_scale = 1.0
		particles.fixed_fps = 60
		particles.fract_delta = true
		particles.mesh = dust_quad
		particles.direction = Vector3(0.0, 0.84, 0.54)
		particles.spread = 31.0
		particles.gravity = Vector3(0.0, -0.3, 0.0)
		particles.initial_velocity_min = 0.16
		particles.initial_velocity_max = 0.82
		particles.linear_accel_min = 0.03
		particles.linear_accel_max = 0.22
		particles.scale_amount_min = 0.35
		particles.scale_amount_max = 0.8
		particles.color = Color(1.0, 0.92, 0.81, 0.45)
		particles.visibility_aabb = AABB(Vector3(-2.5, -1.0, -2.5), Vector3(5.0, 4.0, 5.0))
		add_child(particles)
		_emitters.append(particles)


func _build_vehicle_lights() -> void:
	if not _authored_lights.is_empty():
		_bind_lamp_materials(_authored_lights.heads, _headlight_materials, _headlight_lens_colors)
		_bind_lamp_materials(_authored_lights.tails, _tail_materials, _tail_lens_colors)
		for point: Vector3 in _authored_lights.positions:
			var spot := SpotLight3D.new()
			spot.name = "HeadlightBeam"
			spot.position = point
			spot.spot_range = 8.0
			spot.spot_angle = 22.0
			spot.rotation.x = deg_to_rad(-6.0)
			spot.shadow_enabled = false
			_vehicle_root.add_child(spot)
			_headlight_lights.append(spot)
		_update_lights({}, {}, _night_weight)
		return
	var bounds := _body_bounds_in_vehicle_space()
	var half_width := clampf(bounds.size.x * 0.34, 0.075, 0.15)
	var body_y := bounds.position.y + bounds.size.y * 0.53
	var front_z := bounds.position.z - 0.013
	var rear_z := bounds.end.z + 0.013
	var sphere := SphereMesh.new()
	sphere.radius = 0.013
	sphere.height = 0.026
	sphere.radial_segments = 10
	sphere.rings = 6
	for side in [-1.0, 1.0]:
		var head_position := Vector3(side * half_width, body_y, front_z)
		var head_color := Color(1.0, 0.79, 0.48)
		var head_material := _make_lens_material(head_color, 0.25)
		_headlight_materials.append(head_material)
		_headlight_lens_colors.append(head_color)
		_add_lens(sphere, head_material, head_position, Vector3(0.88, 0.7, 0.55), "HeadlightLens")
		var spot := SpotLight3D.new()
		spot.name = "HeadlightBeam"
		spot.position = head_position + Vector3(0.0, 0.0, -0.012)
		spot.light_color = Color(1.0, 0.87, 0.68)
		spot.light_energy = 0.18
		spot.spot_range = 8.0
		spot.spot_angle = 22.0
		spot.rotation.x = deg_to_rad(-6.0)
		spot.shadow_enabled = false
		_vehicle_root.add_child(spot)
		_headlight_lights.append(spot)
		var tail_position := Vector3(side * half_width * 0.83, body_y, rear_z)
		var tail_color := Color(1.0, 0.025, 0.012)
		var tail_material := _make_lens_material(tail_color, 0.18)
		_tail_materials.append(tail_material)
		_tail_lens_colors.append(tail_color)
		_add_lens(sphere, tail_material, tail_position, Vector3(0.78, 0.65, 0.55), "TailLightLens")
		var reverse_color := Color(0.78, 0.83, 0.93)
		var reverse_material := _make_lens_material(reverse_color, 0.0)
		_reverse_materials.append(reverse_material)
		_reverse_lens_colors.append(reverse_color)
		_add_lens(sphere, reverse_material, tail_position + Vector3(-side * 0.018, 0.0, 0.0), Vector3(0.48, 0.38, 0.28), "ReverseLightLens")
	_update_lights({}, {}, _night_weight)


## Copy authored lens materials per instance; keep the supplied textures and geometry.
func _bind_lamp_materials(nodes: Array, materials: Array[StandardMaterial3D], colors: Array[Color]) -> void:
	for node: MeshInstance3D in nodes:
		for surface in node.mesh.get_surface_count():
			var source := node.get_active_material(surface) as StandardMaterial3D
			if source == null:
				continue
			var material: StandardMaterial3D = source.duplicate()
			material.emission_enabled = true
			if material.emission.is_equal_approx(Color.BLACK):
				material.emission = material.albedo_color
			node.set_surface_override_material(surface, material)
			materials.append(material)
			colors.append(material.albedo_color)


func _body_bounds_in_vehicle_space() -> AABB:
	if _full_shell_grime:
		var shell_bounds := AABB()
		var has_bounds := false
		for shell_mesh in _shell_meshes:
			var mesh_bounds := _mesh_bounds_in_vehicle_space(shell_mesh)
			if not has_bounds:
				shell_bounds = mesh_bounds
				has_bounds = true
			else:
				var low := shell_bounds.position.min(mesh_bounds.position)
				var high := shell_bounds.end.max(mesh_bounds.end)
				shell_bounds = AABB(low, high - low)
		if has_bounds:
			return shell_bounds
	if _body_mesh != null:
		return _mesh_bounds_in_vehicle_space(_body_mesh)
	var front_left := _vehicle_root.to_local(_wheel_nodes[0].global_position)
	var front_right := _vehicle_root.to_local(_wheel_nodes[1].global_position)
	var rear_left := _vehicle_root.to_local(_wheel_nodes[2].global_position)
	var rear_right := _vehicle_root.to_local(_wheel_nodes[3].global_position)
	var min_x := minf(minf(front_left.x, front_right.x), minf(rear_left.x, rear_right.x))
	var max_x := maxf(maxf(front_left.x, front_right.x), maxf(rear_left.x, rear_right.x))
	var min_z := minf(front_left.z, front_right.z) - 0.05
	var max_z := maxf(rear_left.z, rear_right.z) + 0.05
	return AABB(Vector3(min_x, front_left.y + 0.035, min_z), Vector3(max_x - min_x, 0.06, max_z - min_z))


func _mesh_bounds_in_vehicle_space(mesh: MeshInstance3D) -> AABB:
	var local_bounds := mesh.get_aabb()
	var mesh_to_vehicle := _vehicle_root.global_transform.affine_inverse() * mesh.global_transform
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for x in 2:
		for y in 2:
			for z in 2:
				var local_point := local_bounds.position + Vector3(
					local_bounds.size.x * float(x),
					local_bounds.size.y * float(y),
					local_bounds.size.z * float(z),
				)
				var vehicle_point := mesh_to_vehicle * local_point
				lo = lo.min(vehicle_point)
				hi = hi.max(vehicle_point)
	if lo.is_finite() and hi.is_finite():
		return AABB(lo, hi - lo)
	return local_bounds


func _add_lens(mesh: Mesh, material: StandardMaterial3D, position: Vector3, scale_value: Vector3, label: String) -> void:
	var lens := MeshInstance3D.new()
	lens.name = label
	lens.mesh = mesh
	lens.material_override = material
	lens.position = position
	lens.scale = scale_value
	_vehicle_root.add_child(lens)


func _make_lens_material(color: Color, initial_energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = initial_energy
	material.roughness = 0.3
	return material


func _update_lights(telemetry: Dictionary, controls: Dictionary, night_weight: float) -> void:
	var night := clampf(night_weight, 0.0, 1.0) if is_finite(night_weight) else 0.0
	_night_weight = night
	_last_headlight_energy = lerpf(0.18, 2.4, night) if headlights_enabled else 0.0
	for i in _headlight_lights.size():
		_headlight_lights[i].light_energy = _last_headlight_energy
	for i in _headlight_materials.size():
		_headlight_materials[i].emission_energy_multiplier = lerpf(0.28, 1.9, night) if headlights_enabled else 0.0
		_headlight_materials[i].albedo_color = _headlight_lens_colors[i] if headlights_enabled else _headlight_lens_colors[i] * 0.12
	var brake_value: Variant = controls.get("brake", 0.0)
	_brake_lights = typeof(brake_value) in [TYPE_FLOAT, TYPE_INT] and float(brake_value) >= 0.08
	_reverse_lights = bool(controls.get("reverse", false))
	_apply_tail_light_state()


func _apply_tail_light_state() -> void:
	for i in _tail_materials.size():
		_tail_materials[i].emission_energy_multiplier = 2.1 if _brake_lights else 0.24
		_tail_materials[i].albedo_color = _tail_lens_colors[i] if _brake_lights else _tail_lens_colors[i] * 0.14
	for i in _reverse_materials.size():
		_reverse_materials[i].emission_energy_multiplier = 1.25 if _reverse_lights else 0.0
		_reverse_materials[i].albedo_color = _reverse_lens_colors[i] if _reverse_lights else _reverse_lens_colors[i] * 0.10


func _clear_dust_levels() -> void:
	for i in 4:
		_dust_levels[i] = 0.0
		_emitters[i].emitting = false


static func _vector3_is_finite(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)


func _accepted_environment(telemetry: Dictionary) -> Dictionary:
	var value: Variant = telemetry.get("environment")
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	var environment: Dictionary = value
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
	for i in 4:
		if not _finite_number(wheel_submersion[i]) or float(wheel_submersion[i]) < 0.0 \
				or float(wheel_submersion[i]) > 1.0 or not _finite_number(wheel_water_height[i]) \
				or not _finite_number(wheel_depth[i]) or float(wheel_depth[i]) < 0.0 \
				or not _finite_number(wheel_mud[i]) or float(wheel_mud[i]) < 0.0 \
				or float(wheel_mud[i]) > 1.0:
			return {}
	return environment


static func _finite_number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))


static func _surface_dust_factor(surface_id: String) -> float:
	var id := surface_id.to_lower()
	if id.contains("gravel"):
		return 1.0
	if id.contains("dirt"):
		return 0.88
	if id.contains("grass") or id.contains("mown") or id.contains("rough"):
		return 0.48
	return 0.0
