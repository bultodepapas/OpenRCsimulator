# Presentation-only LED traces for a two-blade rotor. This node consumes only the
# caller's signed visual speed and absolute phase; it never advances rotor state.
extends Node3D
class_name HeliNightRotor

const SHADER: Shader = preload("res://render/rotor/heli_night_rotor.gdshader")
const Exposure := preload("res://render/world/exposure.gd")
const SHUTTER_SECONDS := 1.0 / 60.0
const SEGMENTS := 64
const LED_RADIUS_FRACTIONS: Array[float] = [0.66, 0.93]
const LED_WIDTH_M := 0.008
const SCREEN_MIN_PX := 2.0
const RADIANCE := 5.0
const DISPLAY_CAP := 1.35
const SIDE_OFFSET_M := 0.0015 # LED package clearance beyond the measured blade skin
const TWO_PI := TAU

var radius_local_m := 1.0
var plane_z_local_m := 0.0
var rest_phase_offset_rad := 0.0
var current_omega_rad_s := 0.0
var current_phase_rad := 0.0
var _gain := 1.0
var gain: float:
	get:
		return _gain
	set(value):
		set_gain(value)
var top_material: ShaderMaterial
var bottom_material: ShaderMaterial
var _top_mesh: MeshInstance3D
var _bottom_mesh: MeshInstance3D


## Attach two slim annular LED paths to the rotor's local XY plane. The mount keeps
## ownership of scale, position, tilt and rotation; the caller owns phase and speed.
static func attach(mount: Node3D, radius_local_m: float, plane_z_local_m: float,
		top_color: Color, bottom_color: Color) -> Node3D:
	if mount == null or not is_finite(radius_local_m) or radius_local_m <= 0.0 \
			or not is_finite(plane_z_local_m) \
			or not _finite_color(top_color) or not _finite_color(bottom_color):
		return null
	Exposure.register()
	var rotor_script := load("res://render/rotor/heli_night_rotor.gd") as Script
	var node := rotor_script.new() as Node3D
	node.name = "HeliNightRotor"
	node.set("radius_local_m", radius_local_m)
	node.set("plane_z_local_m", plane_z_local_m)
	var geometry := _derive_blade_geometry(mount, radius_local_m, plane_z_local_m)
	node.set("rest_phase_offset_rad", geometry.phase)
	var upper_material := _make_material(top_color, 1.0)
	var lower_material := _make_material(bottom_color, -1.0)
	node.set("top_material", upper_material)
	node.set("bottom_material", lower_material)
	node.set("_top_mesh", _make_side_mesh(node, radius_local_m, "upper_led_traces",
		geometry.upper_z + SIDE_OFFSET_M, upper_material))
	node.set("_bottom_mesh", _make_side_mesh(node, radius_local_m, "lower_led_traces",
		geometry.lower_z - SIDE_OFFSET_M, lower_material))
	mount.add_child(node)
	return node


## Apply already-signed presentation inputs. There is no delta-time accumulation or
## shader clock, so the same phase and speed always produce the same shutter trace.
func update(omega_rad_s: float, phase_rad: float) -> void:
	current_omega_rad_s = omega_rad_s if is_finite(omega_rad_s) else 0.0
	var finite_phase := phase_rad if is_finite(phase_rad) else 0.0
	var combined_phase := finite_phase + rest_phase_offset_rad
	current_phase_rad = fposmod(combined_phase, TWO_PI) if is_finite(combined_phase) else 0.0
	for material: ShaderMaterial in [top_material, bottom_material]:
		if material == null:
			continue
		material.set_shader_parameter("omega_rad_s", current_omega_rad_s)
		material.set_shader_parameter("phase_rad", current_phase_rad)
		material.set_shader_parameter("shutter_s", SHUTTER_SECONDS)


## Let the aircraft night-light kit crossfade dusk without changing exposure or hue.
func set_gain(value: float) -> void:
	_gain = clampf(value, 0.0, 1.0) if is_finite(value) else 0.0
	for material: ShaderMaterial in [top_material, bottom_material]:
		if material != null:
			material.set_shader_parameter("effect_gain", _gain)


static func _make_material(color: Color, visible_side: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("light_color", color)
	material.set_shader_parameter("surface_side", visible_side)
	material.set_shader_parameter("omega_rad_s", 0.0)
	material.set_shader_parameter("phase_rad", 0.0)
	material.set_shader_parameter("shutter_s", SHUTTER_SECONDS)
	material.set_shader_parameter("width_m", LED_WIDTH_M)
	material.set_shader_parameter("min_px", SCREEN_MIN_PX)
	material.set_shader_parameter("radiance", RADIANCE)
	material.set_shader_parameter("display_cap", DISPLAY_CAP)
	material.set_shader_parameter("effect_gain", 1.0)
	return material


static func _make_side_mesh(parent: Node3D, radius_m: float, label: String, plane_z: float,
		material: ShaderMaterial) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = label
	instance.mesh = _build_annular_mesh(radius_m, plane_z)
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.extra_cull_margin = 0.04
	parent.add_child(instance)
	return instance


static func _build_annular_mesh(radius_m: float, plane_z: float) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for fraction: float in LED_RADIUS_FRACTIONS:
		var ring_radius := radius_m * fraction
		var first_vertex := vertices.size()
		for segment in range(SEGMENTS + 1):
			var angle := TWO_PI * float(segment) / float(SEGMENTS)
			var radial := Vector3(cos(angle), sin(angle), 0.0)
			var point := Vector3(radial.x * ring_radius, radial.y * ring_radius, plane_z)
			vertices.append(point)
			vertices.append(point)
			normals.append(radial)
			normals.append(radial)
			uvs.append(Vector2(-1.0, 0.0))
			uvs.append(Vector2(1.0, 0.0))
		for segment in SEGMENTS:
			var inner_a := first_vertex + segment * 2
			var outer_a := inner_a + 1
			var inner_b := inner_a + 2
			var outer_b := inner_a + 3
			indices.append_array(PackedInt32Array([
				inner_a, outer_a, inner_b,
				outer_a, outer_b, inner_b,
			]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _derive_blade_geometry(mount: Node3D, rotor_radius_m: float, plane_z: float) -> Dictionary:
	# Reduce the far-tip vertices modulo pi because the two blades are opposite and
	# therefore define the same LED pair when their first blade is swapped.
	var candidates := PackedVector2Array()
	var largest_radius := 0.0
	var lower_z := plane_z
	var upper_z := plane_z
	var tolerance := maxf(rotor_radius_m * 0.018, 0.001)
	for candidate: Node in mount.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := candidate as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		var local_from_mesh := mesh_instance.transform
		var ancestor := mesh_instance.get_parent()
		while ancestor != null and ancestor != mount:
			if ancestor is Node3D:
				local_from_mesh = (ancestor as Node3D).transform * local_from_mesh
			ancestor = ancestor.get_parent()
		if ancestor != mount:
			continue
		for surface in mesh_instance.mesh.get_surface_count():
			var arrays := mesh_instance.mesh.surface_get_arrays(surface)
			if arrays.size() <= Mesh.ARRAY_VERTEX or arrays[Mesh.ARRAY_VERTEX] == null:
				continue
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for vertex: Vector3 in vertices:
				var point := local_from_mesh * vertex
				var radial := Vector2(point.x, point.y)
				var radial_length := radial.length()
				if radial_length < rotor_radius_m * 0.5 or radial_length > rotor_radius_m * 1.12:
					continue
				lower_z = minf(lower_z, point.z)
				upper_z = maxf(upper_z, point.z)
				if radial_length > largest_radius + tolerance:
					largest_radius = radial_length
					candidates.clear()
					candidates.append(radial)
				elif largest_radius - radial_length <= tolerance:
					largest_radius = maxf(largest_radius, radial_length)
					candidates.append(radial)
	if candidates.is_empty():
		return {phase=0.0, lower_z=lower_z, upper_z=upper_z}
	var cosine_sum := 0.0
	var sine_sum := 0.0
	for radial: Vector2 in candidates:
		var angle := atan2(radial.y, radial.x) * 2.0
		cosine_sum += cos(angle)
		sine_sum += sin(angle)
	if absf(cosine_sum) + absf(sine_sum) < 1e-9:
		return {phase=0.0, lower_z=lower_z, upper_z=upper_z}
	var phase := 0.5 * atan2(sine_sum, cosine_sum)
	return {phase=fposmod(phase + PI * 0.5, PI) - PI * 0.5, lower_z=lower_z, upper_z=upper_z}


## Deterministic CPU reference for the shader's angular sample mask. It is also useful
## to audit stationary points, signed shutter direction and frame-cadence independence.
static func _sample_coverage(angle_rad: float, omega_rad_s: float, phase_rad: float,
		ring_radius_m: float) -> float:
	if not is_finite(angle_rad) or not is_finite(omega_rad_s) \
			or not is_finite(phase_rad) or not is_finite(ring_radius_m) or ring_radius_m <= 0.0:
		return 0.0
	var span := absf(omega_rad_s) * SHUTTER_SECONDS
	var edge := LED_WIDTH_M * 0.5 / ring_radius_m
	if span <= 1e-8:
		var first_distance := absf(fposmod(angle_rad - phase_rad + PI, TWO_PI) - PI)
		var second_distance := absf(fposmod(angle_rad - phase_rad - PI + PI, TWO_PI) - PI)
		return 1.0 if minf(first_distance, second_distance) <= edge else 0.0
	if span >= TWO_PI:
		return 1.0
	var direction := 1.0 if omega_rad_s >= 0.0 else -1.0
	for blade in 2:
		var start := phase_rad + float(blade) * PI - omega_rad_s * SHUTTER_SECONDS
		var progress := fposmod((angle_rad - start) * direction, TWO_PI)
		if progress <= span + edge:
			return 1.0
	return 0.0


static func _finite_color(color: Color) -> bool:
	return is_finite(color.r) and is_finite(color.g) and is_finite(color.b) and is_finite(color.a)
