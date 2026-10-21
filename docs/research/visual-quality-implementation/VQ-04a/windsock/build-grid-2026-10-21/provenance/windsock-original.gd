## Data-sized windsock sleeve and bearing assembly; motion is supplied by WindsockMotion.
## Dimensions come from the validated field cue. Flexible cloth remains visual-only.
extends RefCounted

const Frames = preload("res://render/frames.gd")
const MeshKit = preload("res://scenery/mesh_kit.gd")
const WindsockMotion = preload("res://render/windsock_motion.gd")
const SIDES: int = 32
const SECTIONS: int = 60
const BANDS: int = 5
const MOTION_POINTS: int = 13
const RIGID_FRACTION: float = 0.375
const ARM_BASE_M: float = 0.35
const FOLD_AMPLITUDE: float = 0.10
const ORANGE: Color = Color("#e47b35")
const WHITE: Color = Color("#eee9dd")
const STEEL: Color = Color("#8d9296")
const FabricFinish = preload("res://render/windsock_fabric.gdshader")
const SupportFinish = preload("res://render/windsock_support.gdshader")
const FABRIC_MAPS := {
	"fabric_color": preload("res://assets/landscape/windsock/Fabric001_1K-JPG_Color.jpg"),
	"fabric_normal": preload("res://assets/landscape/windsock/Fabric001_1K-JPG_NormalGL.jpg"),
	"fabric_roughness": preload("res://assets/landscape/windsock/Fabric001_1K-JPG_Roughness.jpg"),
}
const SUPPORT_MAPS := {
	"metal_normal": preload("res://assets/landscape/pilot-station/Metal032_1K-JPG_NormalGL.jpg"),
	"metal_roughness": preload("res://assets/landscape/pilot-station/Metal032_1K-JPG_Roughness.jpg"),
	"concrete_color": preload("res://assets/landscape/pilot-station/Concrete034_1K-JPG_Color.jpg"),
	"concrete_normal": preload("res://assets/landscape/pilot-station/Concrete034_1K-JPG_NormalGL.jpg"),
}


static func build(cue: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = str(cue.id)
	root.position = Frames.ned_to_render([cue.north, cue.east, 0.0])
	var length_m: float = float(cue.length)
	var height_m: float = float(cue.pole_height)
	var throat_diameter_m: float = float(cue.throat_diameter)
	var tail_diameter_m: float = float(cue.tail_diameter)
	var throat_radius_m: float = throat_diameter_m * 0.5
	var arm_m: float = maxf(ARM_BASE_M, throat_radius_m + 0.10)
	var mount := Vector3(arm_m, height_m, 0.0)
	var cue_dimensions := {
		"length_m": length_m,
		"height_m": height_m,
		"throat_diameter_m": throat_diameter_m,
		"tail_diameter_m": tail_diameter_m,
		"arm_m": arm_m,
	}
	root.set_meta("windsock_dimensions", cue_dimensions)
	var motion: Variant = WindsockMotion.new(length_m, throat_diameter_m, tail_diameter_m)
	motion.reset(0.0, [0.0, 0.0, 0.0])
	root.set_meta("windsock_motion", motion)

	# The shader owns per-frame centreline and cloth deformation. This mesh keeps
	# fixed topology, UVs and vertex bands, so no mesh or tangent rebuild is needed.
	var cloth: RefCounted = MeshKit.new()
	var uvs := PackedVector2Array()
	var smooth_normals := PackedVector3Array()
	for section: int in SECTIONS:
		var s0: float = length_m * float(section) / float(SECTIONS)
		var s1: float = length_m * float(section + 1) / float(SECTIONS)
		var band: int = section / (SECTIONS / BANDS)
		var colour: Color = ORANGE if band % 2 == 0 else WHITE
		for side_index: int in SIDES:
			var a: float = TAU * float(side_index) / float(SIDES)
			var b: float = TAU * float(side_index + 1) / float(SIDES)
			cloth.quad(mount + cloth_point(s0, a, cue), mount + cloth_point(s0, b, cue),
				mount + cloth_point(s1, b, cue), mount + cloth_point(s1, a, cue), colour)
			# MeshKit emits a,c,b / a,d,c; store UVs in the same vertex order.
			for uv: Vector2 in [Vector2(s0, a), Vector2(s1, b), Vector2(s0, b),
				Vector2(s0, a), Vector2(s1, a), Vector2(s1, b)]:
				uvs.append(Vector2(uv.x / length_m, uv.y / TAU))
				smooth_normals.append(_cloth_normal(uv.x, uv.y, cue))
	var fabric := _instance("Fabric", cloth, true)
	var arrays: Array = fabric.mesh.surface_get_arrays(0)
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_NORMAL] = smooth_normals
	var mapped := ArrayMesh.new()
	mapped.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var surface := SurfaceTool.new()
	surface.create_from(mapped, 0)
	surface.generate_tangents()
	fabric.mesh = surface.commit()
	var fabric_material := _material(FabricFinish, FABRIC_MAPS)
	fabric_material.set_shader_parameter("length_m", length_m)
	fabric_material.set_shader_parameter("circumference_m", TAU * throat_radius_m)
	fabric_material.set_shader_parameter("throat_diameter_m", throat_diameter_m)
	fabric_material.set_shader_parameter("tail_diameter_m", tail_diameter_m)
	fabric_material.set_shader_parameter("basket_height_m", height_m)
	fabric_material.set_shader_parameter("arm_m", arm_m)
	fabric.mesh.surface_set_material(0, fabric_material)
	root.add_child(fabric)

	# Fixed mast, ground plate and bearing remain still while the boom, hoops and
	# four rigid throat rails turn together as the single Basket mesh below.
	var fixed_hardware: RefCounted = MeshKit.new()
	fixed_hardware.cylinder(0.035, 0.026, height_m, 24, Vector3.ZERO, STEEL)
	fixed_hardware.block(Vector3(0.28, 0.10, 0.28), Vector3.ZERO, Color(0, 0, 1))
	fixed_hardware.box(Vector3(0.22, 0.012, 0.22), Vector3(0, 0.106, 0), STEEL, true)
	for x: float in [-0.085, 0.085]:
		for z: float in [-0.085, 0.085]:
			fixed_hardware.cylinder(0.014, 0.014, 0.003, 12, Vector3(x, 0.112, z), STEEL)
			fixed_hardware.cylinder(0.009, 0.009, 0.012, 6, Vector3(x, 0.115, z), STEEL.darkened(0.15))
	# Splice and bearing races are fixed to the mast; the swivelling boom starts
	# at the bearing axis at the pole top.
	for y: float in [height_m * 0.53, height_m - 0.055]:
		fixed_hardware.cylinder(0.042, 0.042, 0.075, 24, Vector3(0, y, 0), STEEL)
		fixed_hardware.cylinder(0.044, 0.044, 0.008, 24, Vector3(0, y + 0.008, 0), STEEL.darkened(0.2))
	var support := _instance("Support", fixed_hardware, false)
	support.mesh.surface_set_material(0, _material(SupportFinish, SUPPORT_MAPS))
	root.add_child(support)

	var basket_hardware: RefCounted = MeshKit.new()
	var rigid_length_m: float = length_m * RIGID_FRACTION
	basket_hardware.beam(Vector3(0.0, height_m, 0.0), mount, 0.025, STEEL)
	for station_m: float in [0.0, rigid_length_m]:
		var station_radius_m: float = lerpf(throat_radius_m, float(cue.tail_diameter) * 0.5, station_m / length_m)
		for side_index: int in SIDES:
			var a: float = TAU * float(side_index) / float(SIDES)
			var b: float = TAU * float(side_index + 1) / float(SIDES)
			var ring_a := mount + Vector3(station_m, station_radius_m * cos(a), station_radius_m * sin(a))
			var ring_b := mount + Vector3(station_m, station_radius_m * cos(b), station_radius_m * sin(b))
			basket_hardware.beam(ring_a, ring_b, 0.009, STEEL)
	for a: float in [0.0, PI * 0.5, PI, PI * 1.5]:
		var rear_radius_m: float = lerpf(throat_radius_m, float(cue.tail_diameter) * 0.5, RIGID_FRACTION)
		var front_radial := Vector3(0.0, throat_radius_m * cos(a), throat_radius_m * sin(a))
		var rear_radial := Vector3(0.0, rear_radius_m * cos(a), rear_radius_m * sin(a))
		basket_hardware.beam(mount + front_radial, mount + Vector3(rigid_length_m, 0.0, 0.0) + rear_radial, 0.009, STEEL)
	var basket := _instance("Basket", basket_hardware, false)
	basket.mesh.surface_set_material(0, _material(SupportFinish, SUPPORT_MAPS))
	root.add_child(basket)
	var hardware_boxes: Array[AABB] = [support.mesh.get_aabb(), basket.mesh.get_aabb()]
	var hardware_transforms: Array[Transform3D] = [support.transform, basket.transform]
	# These meshes and materials belong to this cue for its lifetime. Keep their
	# handles and static local bounds instead of resolving them at every upload.
	root.set_meta("_windsock_view", {fabric = fabric, basket = basket, support = support,
		material = fabric_material, dimensions = cue_dimensions,
		hardware_boxes = hardware_boxes, hardware_transforms = hardware_transforms})
	_apply_motion(root, motion)
	return root


## Advance only from the owner of the fixed simulation/wind clock.
static func advance(root: Node3D, time_s: float, wind_ned: Array) -> void:
	var motion: Variant = _motion_model(root)
	if motion == null:
		return
	motion.update_to(time_s, wind_ned)


## Render the latest state once per frame. The model itself is deterministic and
## safely ignores repeated timestamps from the physics and presentation routes.
static func update(root: Node3D, time_s: float, wind_ned: Array) -> void:
	advance(root, time_s, wind_ned)
	var motion: Variant = _motion_model(root)
	if motion != null:
		_apply_motion(root, motion)


static func reset(root: Node3D, time_s: float = 0.0, wind_ned: Array = [0.0, 0.0, 0.0]) -> void:
	var motion: Variant = _motion_model(root)
	if motion == null:
		return
	motion.reset(time_s, wind_ned)
	_apply_motion(root, motion, true)


## Arc-length reference used to build the bind mesh: the first 3/8 stays straight,
## then a smooth bend gives the unsupported tail a modest gravity sag.
static func centreline(s: float, length_m: float) -> Vector3:
	var rigid: float = length_m * RIGID_FRACTION
	var bend_radius: float = length_m * 0.10
	if s <= rigid:
		return Vector3(s, 0.0, 0.0)
	var angle: float = minf((s - rigid) / bend_radius, PI * 0.5)
	var drop: float = maxf(s - rigid - bend_radius * PI * 0.5, 0.0)
	return Vector3(rigid + bend_radius * sin(angle), -bend_radius * (1.0 - cos(angle)) - drop, 0.0)


static func cloth_point(s: float, angle: float, cue: Dictionary) -> Vector3:
	var length_m: float = float(cue.length)
	var rigid: float = length_m * RIGID_FRACTION
	var bend_angle: float = clampf((s - rigid) / (length_m * 0.10), 0.0, PI * 0.5)
	var up: Vector3 = Vector3(sin(bend_angle), cos(bend_angle), 0.0)
	var taper: float = clampf(s / maxf(length_m, 1.0e-6), 0.0, 1.0)
	var radius: float = lerpf(float(cue.throat_diameter), float(cue.tail_diameter), taper) * 0.5
	var slack: float = smoothstep(rigid, length_m, s)
	var fold: float = 1.0 + slack * (0.055 * sin(angle * 6.0)
		+ 0.035 * sin(s / length_m * TAU * 7.0 + angle * 3.0))
	return centreline(s, length_m) + radius * fold * (up * cos(angle)
		+ Vector3.BACK * sin(angle) * lerpf(1.0, 0.16, slack))


static func _instance(node_name: String, kit: RefCounted, double_sided: bool) -> MeshInstance3D:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.94
	material.metallic = 0.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED if double_sided else BaseMaterial3D.CULL_BACK
	var mesh := MeshInstance3D.new()
	mesh.name = node_name
	mesh.mesh = kit.to_mesh(material)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mesh


static func _cloth_normal(s: float, angle: float, cue: Dictionary) -> Vector3:
	var step_m: float = float(cue.length) * 0.0001
	var along: Vector3 = cloth_point(minf(s + step_m, cue.length), angle, cue) - cloth_point(maxf(s - step_m, 0.0), angle, cue)
	var around: Vector3 = cloth_point(s, angle + 0.001, cue) - cloth_point(s, angle - 0.001, cue)
	return around.cross(along).normalized()


static func _material(shader: Shader, maps: Dictionary) -> ShaderMaterial:
	var result := ShaderMaterial.new()
	result.shader = shader
	for channel: String in maps:
		result.set_shader_parameter(channel, maps[channel])
	return result


static func _motion_model(root: Node3D) -> Variant:
	if not root.has_meta("windsock_motion"):
		return null
	return root.get_meta("windsock_motion")


static func _apply_motion(root: Node3D, motion: Variant, force: bool = false) -> void:
	var view: Dictionary = root.get_meta("_windsock_view", {})
	if view.is_empty() or not is_instance_valid(view.fabric) \
			or not is_instance_valid(view.basket) or not is_instance_valid(view.support):
		return
	var chain: PackedVector3Array = motion.centerline_local
	if chain.size() != MOTION_POINTS:
		return
	var yaw_rad: float = float(motion.basket_yaw_rad)
	var inflation_value: float = clampf(float(motion.inflation), 0.0, 1.0)
	if not force and view.has("chain") and chain == view.chain \
			and yaw_rad == view.yaw and inflation_value == view.inflation:
		return # GPU flutter still follows the shared clock; these bounds cover every phase.
	var fabric: MeshInstance3D = view.fabric
	var basket: MeshInstance3D = view.basket
	var material: ShaderMaterial = view.material
	var dimensions: Dictionary = view.dimensions
	material.set_shader_parameter("centerline_points", chain)
	material.set_shader_parameter("basket_yaw_rad", yaw_rad)
	material.set_shader_parameter("inflation", inflation_value)
	basket.rotation.y = yaw_rad
	var rendered_centres := PackedVector3Array()
	var mount := Vector3(float(dimensions.arm_m), float(dimensions.height_m), 0.0)
	var yaw_basis := Basis(Vector3.UP, yaw_rad)
	for point: Vector3 in chain:
		rendered_centres.append(yaw_basis * (mount + point))
	fabric.set_meta("centreline", rendered_centres)
	var fabric_bounds := _fabric_bounds(chain, yaw_rad, inflation_value, dimensions)
	fabric.custom_aabb = fabric_bounds
	fabric.set_meta("visual_bounds", fabric_bounds)
	var minimum := fabric_bounds.position
	var maximum := fabric_bounds.end
	var hardware_boxes: Array[AABB] = view.hardware_boxes
	var hardware_transforms: Array[Transform3D] = view.hardware_transforms
	hardware_transforms[1] = basket.transform
	for index: int in hardware_boxes.size():
		for corner: int in 8:
			var point: Vector3 = hardware_transforms[index] * hardware_boxes[index].get_endpoint(corner)
			minimum = minimum.min(point)
			maximum = maximum.max(point)
	root.set_meta("visual_bounds", AABB(minimum, maximum - minimum))
	view.chain = chain
	view.yaw = yaw_rad
	view.inflation = inflation_value


static func _fabric_bounds(
		chain: PackedVector3Array,
		yaw_rad: float,
		inflation_value: float,
		dimensions: Dictionary) -> AABB:
	var minimum := Vector3(1.0e20, 1.0e20, 1.0e20)
	var maximum := Vector3(-1.0e20, -1.0e20, -1.0e20)
	var throat_diameter_m: float = float(dimensions.throat_diameter_m)
	var tail_diameter_m: float = float(dimensions.tail_diameter_m)
	var length_m: float = float(dimensions.length_m)
	var arm_m: float = float(dimensions.arm_m)
	var height_m: float = float(dimensions.height_m)
	var yaw_basis := Basis(Vector3.UP, yaw_rad)
	for point_index: int in chain.size():
		var t: float = _station_fraction(point_index)
		var taper: float = t
		var nominal_radius: float = lerpf(throat_diameter_m, tail_diameter_m, taper) * 0.5
		var slack_taper: float = clampf((t - RIGID_FRACTION) / (1.0 - RIGID_FRACTION), 0.0, 1.0)
		var up_scale: float = lerpf(1.0, lerpf(0.92, 1.0, inflation_value), slack_taper)
		var side_scale: float = lerpf(1.0, lerpf(0.16, 1.0, inflation_value), slack_taper)
		var section_scale: float = maxf(up_scale, side_scale)
		var margin: float = nominal_radius * section_scale * (1.0 + FOLD_AMPLITUDE)
		margin += length_m * (0.01 + 0.004 * inflation_value)
		var centre := Vector3(arm_m + chain[point_index].x, height_m + chain[point_index].y, chain[point_index].z)
		centre = yaw_basis * centre
		# Every old corner was centre +/- this same margin on each axis.
		# Accumulate the extrema directly instead of allocating/scanning 104 points.
		var half_extent := Vector3(margin, margin, margin)
		minimum = minimum.min(centre - half_extent)
		maximum = maximum.max(centre + half_extent)
	return AABB(minimum, maximum - minimum)


static func _station_fraction(point_index: int) -> float:
	if point_index <= 5:
		return RIGID_FRACTION * float(point_index) / 5.0
	return RIGID_FRACTION + (1.0 - RIGID_FRACTION) * float(point_index - 5) / 7.0


static func _append_aabb_corners(points: PackedVector3Array, box: AABB, transform: Transform3D) -> void:
	for x: float in [0.0, box.size.x]:
		for y: float in [0.0, box.size.y]:
			for z: float in [0.0, box.size.z]:
				points.append(transform * (box.position + Vector3(x, y, z)))


static func _aabb_from_points(points: PackedVector3Array) -> AABB:
	if points.is_empty():
		return AABB()
	var minimum := Vector3(1.0e20, 1.0e20, 1.0e20)
	var maximum := Vector3(-1.0e20, -1.0e20, -1.0e20)
	for point: Vector3 in points:
		minimum = minimum.min(point)
		maximum = maximum.max(point)
	return AABB(minimum, maximum - minimum)
