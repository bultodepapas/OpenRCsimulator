## L10d: subtle ground contact cues for the static field objects.
## Radii, spread and opacity are visual estimates; these are not projected sun shadows or physical ambient occlusion.
extends RefCounted

const Frames = preload("res://render/frames.gd")
const FlightlineBarrier = preload("res://render/flightline_barrier.gd")

const GROUND_Y: float = 0.012
const MAX_OPACITY: float = 0.18 # Estimated visual strength, capped below the 0.20 acceptance limit.
const MID_OPACITY: float = 0.10
const STATION_FEATHER_M: float = 0.14
const CIRCLE_SEGMENTS: int = 12
const CONTACT_COLOR: Color = Color(0.08, 0.08, 0.08, 1.0)


static func build(cues: Array) -> MeshInstance3D:
	var shadow: MeshInstance3D = MeshInstance3D.new()
	shadow.name = "FlightCueShadows"
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var surface: SurfaceTool = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var emitted: bool = false
	for cue_value: Variant in cues:
		if not cue_value is Dictionary:
			continue
		var cue: Dictionary = cue_value
		var centre: Vector3 = _cue_centre(cue)
		match str(cue.get("type", "")):
			"windsock":
				_append_circle(surface, centre, 0.23)
				emitted = true
			"pilot_station":
				_append_station(surface, centre, float(cue.get("width", 0.0)), float(cue.get("depth", 0.0)))
				emitted = true
			"flightline_barrier":
				var posts: PackedVector3Array = FlightlineBarrier.post_positions(cue)
				for post_offset: Vector3 in posts:
					_append_circle(surface, centre + post_offset, 0.14)
					emitted = true
	if not emitted:
		shadow.mesh = ArrayMesh.new()
		return shadow
	var material: StandardMaterial3D = _material()
	surface.set_material(material)
	shadow.mesh = surface.commit()
	return shadow


static func _cue_centre(cue: Dictionary) -> Vector3:
	return Frames.ned_to_render([float(cue.get("north", 0.0)), float(cue.get("east", 0.0)), 0.0])


static func _append_circle(surface: SurfaceTool, centre: Vector3, radius: float) -> void:
	var core_radius: float = radius * 0.64
	var middle_radius: float = radius * 0.84
	var ground_centre: Vector3 = Vector3(centre.x, GROUND_Y, centre.z)
	for index: int in range(CIRCLE_SEGMENTS):
		var angle_a: float = TAU * float(index) / float(CIRCLE_SEGMENTS)
		var angle_b: float = TAU * float(index + 1) / float(CIRCLE_SEGMENTS)
		var core_a: Vector3 = _circle_point(ground_centre, core_radius, angle_a)
		var core_b: Vector3 = _circle_point(ground_centre, core_radius, angle_b)
		var middle_a: Vector3 = _circle_point(ground_centre, middle_radius, angle_a)
		var middle_b: Vector3 = _circle_point(ground_centre, middle_radius, angle_b)
		var outer_a: Vector3 = _circle_point(ground_centre, radius, angle_a)
		var outer_b: Vector3 = _circle_point(ground_centre, radius, angle_b)
		_emit_triangle(surface, ground_centre, core_a, core_b, MAX_OPACITY, MAX_OPACITY, MAX_OPACITY)
		_emit_quad(surface, core_a, middle_a, middle_b, core_b, MAX_OPACITY, MID_OPACITY, MID_OPACITY, MAX_OPACITY)
		_emit_quad(surface, middle_a, outer_a, outer_b, middle_b, MID_OPACITY, 0.0, 0.0, MID_OPACITY)


static func _circle_point(centre: Vector3, radius: float, angle: float) -> Vector3:
	return centre + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)


static func _append_station(surface: SurfaceTool, centre: Vector3, width: float, depth: float) -> void:
	if width <= 0.0 or depth <= 0.0:
		return
	var ground_centre: Vector3 = Vector3(centre.x, GROUND_Y, centre.z)
	var core: Array[Vector3] = _rect_corners(ground_centre, width * 0.5, depth * 0.5)
	var middle: Array[Vector3] = _rect_corners(ground_centre,
		width * 0.5 + STATION_FEATHER_M * 0.5, depth * 0.5 + STATION_FEATHER_M * 0.5)
	var outer: Array[Vector3] = _rect_corners(ground_centre,
		width * 0.5 + STATION_FEATHER_M, depth * 0.5 + STATION_FEATHER_M)
	_emit_triangle(surface, core[0], core[1], core[2], MAX_OPACITY, MAX_OPACITY, MAX_OPACITY)
	_emit_triangle(surface, core[0], core[2], core[3], MAX_OPACITY, MAX_OPACITY, MAX_OPACITY)
	_append_rect_ring(surface, core, middle, MAX_OPACITY, MID_OPACITY)
	_append_rect_ring(surface, middle, outer, MID_OPACITY, 0.0)


static func _rect_corners(centre: Vector3, half_width: float, half_depth: float) -> Array[Vector3]:
	return [
		Vector3(centre.x - half_width, GROUND_Y, centre.z - half_depth),
		Vector3(centre.x + half_width, GROUND_Y, centre.z - half_depth),
		Vector3(centre.x + half_width, GROUND_Y, centre.z + half_depth),
		Vector3(centre.x - half_width, GROUND_Y, centre.z + half_depth),
	]


static func _append_rect_ring(surface: SurfaceTool, inner: Array[Vector3], outer: Array[Vector3], inner_opacity: float, outer_opacity: float) -> void:
	for index: int in range(4):
		var next: int = (index + 1) % 4
		_emit_quad(surface, inner[index], inner[next], outer[next], outer[index],
			inner_opacity, inner_opacity, outer_opacity, outer_opacity)


static func _emit_quad(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		a_opacity: float, b_opacity: float, c_opacity: float, d_opacity: float) -> void:
	_emit_triangle(surface, a, b, c, a_opacity, b_opacity, c_opacity)
	_emit_triangle(surface, a, c, d, a_opacity, c_opacity, d_opacity)


static func _emit_triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		a_opacity: float, b_opacity: float, c_opacity: float) -> void:
	surface.set_color(_color(a_opacity))
	surface.add_vertex(a)
	surface.set_color(_color(b_opacity))
	surface.add_vertex(b)
	surface.set_color(_color(c_opacity))
	surface.add_vertex(c)


static func _color(opacity: float) -> Color:
	return Color(CONTACT_COLOR.r, CONTACT_COLOR.g, CONTACT_COLOR.b, clampf(opacity, 0.0, MAX_OPACITY))


static func _material() -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = false
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
	return material
