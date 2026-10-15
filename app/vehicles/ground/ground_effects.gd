## Render-only effects for the bundled MT8. Physics values are read-only inputs.
extends Node3D

const CORNERS := ["FL", "FR", "RL", "RR"]
const SMOKE_TEXTURE: Texture2D = preload("res://assets/crash/smoke.png")
const GRIME_SHADER_PATH := "res://vehicles/ground/ground_grime_overlay.gdshader"
const PARTICLES_PER_TIRE := 24
const MAX_GRIME := 0.46
const TIRE_RADIUS_FALLBACK_M := 0.061

var _prepared := false
var headlights_enabled := true
var _vehicle_root: Node3D
var _body_mesh: MeshInstance3D
var _wheel_nodes: Array[Node3D] = []
var _wheel_radii := PackedFloat32Array()
var _emitters: Array[CPUParticles3D] = []
var _dust_levels := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
var _grime_material: ShaderMaterial
var _grime_materials: Array[ShaderMaterial] = []
var _grime_amount := 0.0
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
	if scene_parent != null and get_parent() == null:
		scene_parent.add_child(self)
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
	_wheel_nodes = checked_wheels
	_body_mesh = body_value as MeshInstance3D if body_value is MeshInstance3D else null
	if not _build_grime_overlay():
		_vehicle_root = null
		_wheel_nodes.clear()
		_body_mesh = null
		return false
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
	var speed := absf(float(speed_value))
	var dirt_activity := 0.0
	for i in 4:
		var level := 0.0
		var source := _wheel_nodes[i].global_position
		var sample_value: Variant = {}
		if _vector3_is_finite(source):
			sample_value = road.call(-source.z, source.x)
		if contacts[i] != 0 and typeof(sample_value) == TYPE_DICTIONARY:
			var sample: Dictionary = sample_value
			var surface_factor := _surface_dust_factor(str(sample.get("surface_id", "")))
			var slip_speed := absf(float(slips[i])) if is_finite(float(slips[i])) else 0.0
			var ground_height: Variant = sample.get("height_m", source.y - _wheel_radii[i])
			var ground_height_valid := typeof(ground_height) in [TYPE_FLOAT, TYPE_INT] \
				and is_finite(float(ground_height))
			if surface_factor > 0.0 and ground_height_valid and (speed >= 0.35 or slip_speed >= 0.12):
				var speed_factor := clampf((speed - 0.35) / 4.5, 0.0, 1.0)
				var slip_factor := clampf((slip_speed - 0.04) / 1.4, 0.0, 1.0)
				level = surface_factor * maxf(speed_factor * 0.45, slip_factor)
				source.y = float(ground_height) + 0.018
				var emitter := _emitters[i]
				emitter.global_transform = Transform3D(_vehicle_root.global_basis.orthonormalized(), source)
				var dust_tint := Color(1.0, 0.92, 0.81).lerp(Color(0.32, 0.38, 0.54), _night_weight)
				var dust_alpha := 0.8 * sqrt(level) * lerpf(1.0, 0.08, _night_weight)
				emitter.color = Color(dust_tint.r, dust_tint.g, dust_tint.b, dust_alpha)
		_dust_levels[i] = level
		_emitters[i].emitting = level > 0.015
		dirt_activity += level
	if dt > 0.0 and dirt_activity > 0.0:
		_grime_amount = minf(MAX_GRIME, _grime_amount + dirt_activity * 0.25 * dt * 0.028)
		for material in _grime_materials:
			material.set_shader_parameter("dirt_amount", _grime_amount)


## Reset clears only this component's particle buffers and overlay. Body visibility and source
## materials remain untouched.
func reset() -> void:
	if not _prepared:
		return
	_grime_amount = 0.0
	for material in _grime_materials:
		material.set_shader_parameter("dirt_amount", 0.0)
	for i in 4:
		_dust_levels[i] = 0.0
		_emitters[i].emitting = false
		_emitters[i].restart()
		_emitters[i].emitting = false
		_emitters[i].speed_scale = 1.0
	_paused = false
	_brake_lights = false
	_reverse_lights = false
	_apply_tail_light_state()


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
		"grime_amount": _grime_amount,
		"headlights_enabled": headlights_enabled and not _headlight_lights.is_empty(),
		"headlight_energy": _last_headlight_energy,
		"brake_lights": _brake_lights,
		"reverse_lights": _reverse_lights,
		"paused": _paused,
	}


func _build_grime_overlay() -> bool:
	if _body_mesh == null:
		return false
	var shader := ResourceLoader.load(GRIME_SHADER_PATH, "Shader") as Shader
	if shader == null:
		return false
	_grime_material = _make_grime_material(shader, _body_mesh.get_aabb(), false)
	_body_mesh.material_overlay = _grime_material
	_grime_materials.append(_grime_material)
	for wheel_value in _wheel_nodes:
		var wheel_mesh := wheel_value as MeshInstance3D
		if wheel_mesh == null:
			return false
		var wheel_material := _make_grime_material(shader, wheel_mesh.get_aabb(), true)
		wheel_mesh.material_overlay = wheel_material
		_grime_materials.append(wheel_material)
	return true


func _make_grime_material(shader: Shader, bounds: AABB, full_height: bool) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("dirt_amount", 0.0)
	if full_height:
		var margin := maxf(bounds.size.y * 0.04, 0.002)
		material.set_shader_parameter("dirt_band_bottom", bounds.end.y + margin)
		material.set_shader_parameter("dirt_band_top", bounds.end.y + margin * 2.0)
	else:
		material.set_shader_parameter("dirt_band_bottom", bounds.position.y + bounds.size.y * 0.04)
		material.set_shader_parameter("dirt_band_top", bounds.position.y + bounds.size.y * 0.48)
	return material


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


func _body_bounds_in_vehicle_space() -> AABB:
	if _body_mesh != null:
		var local_bounds := _body_mesh.get_aabb()
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
					var vehicle_point := _vehicle_root.to_local(_body_mesh.to_global(local_point))
					lo = lo.min(vehicle_point)
					hi = hi.max(vehicle_point)
		if lo.is_finite() and hi.is_finite():
			return AABB(lo, hi - lo)
	var front_left := _vehicle_root.to_local(_wheel_nodes[0].global_position)
	var front_right := _vehicle_root.to_local(_wheel_nodes[1].global_position)
	var rear_left := _vehicle_root.to_local(_wheel_nodes[2].global_position)
	var rear_right := _vehicle_root.to_local(_wheel_nodes[3].global_position)
	var min_x := minf(minf(front_left.x, front_right.x), minf(rear_left.x, rear_right.x))
	var max_x := maxf(maxf(front_left.x, front_right.x), maxf(rear_left.x, rear_right.x))
	var min_z := minf(front_left.z, front_right.z) - 0.05
	var max_z := maxf(rear_left.z, rear_right.z) + 0.05
	return AABB(Vector3(min_x, front_left.y + 0.035, min_z), Vector3(max_x - min_x, 0.06, max_z - min_z))


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


static func _surface_dust_factor(surface_id: String) -> float:
	var id := surface_id.to_lower()
	if id.contains("gravel"):
		return 1.0
	if id.contains("dirt"):
		return 0.88
	if id.contains("grass") or id.contains("mown") or id.contains("rough"):
		return 0.48
	return 0.0
