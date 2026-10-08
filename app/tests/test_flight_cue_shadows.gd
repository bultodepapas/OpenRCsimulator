# L10d: one ground-level mesh with softly feathered flight-cue contact footprints.
# Run: godot --headless --path app --script res://tests/test_flight_cue_shadows.gd
extends SceneTree

const CueShadows = preload("res://render/flight_cue_shadows.gd")
const FlightlineBarrier = preload("res://render/flightline_barrier.gd")
const FieldLoader = preload("res://data/field_loader.gd")

const GROUND_Y: float = 0.012
const ALPHA_LIMIT: float = 0.20
const STATION_FEATHER_M: float = 0.14

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_test_empty_legacy()
	_test_committed_field()
	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_empty_legacy() -> void:
	var empty: MeshInstance3D = CueShadows.build([])
	_check("empty legacy cue list returns a named empty mesh", empty.name == "FlightCueShadows"
		and empty.mesh != null and empty.mesh.get_surface_count() == 0)
	_check("empty shadow instance has no work or children", not empty.is_processing()
		and empty.get_child_count() == 0 and empty.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	empty.free()


func _test_committed_field() -> void:
	var loaded: Dictionary = FieldLoader.load_from()
	_check("default field loads for contact-shadow geometry", bool(loaded.get("ok", false)), str(loaded.get("errors", [])))
	if not bool(loaded.get("ok", false)):
		return
	var field: Dictionary = loaded.get("field", {})
	var cues: Array = field.get("flight_cues", [])
	var windsock: Dictionary = _find_cue(cues, "windsock")
	var station: Dictionary = _find_cue(cues, "pilot_station")
	_check("default field provides the L10a and L10b cues", not windsock.is_empty() and not station.is_empty())
	if windsock.is_empty() or station.is_empty():
		return
	var build_cues: Array = cues
	var first: MeshInstance3D = CueShadows.build(build_cues)
	var second: MeshInstance3D = CueShadows.build(build_cues)
	_check("single named mesh instance, no children or processing", first.name == "FlightCueShadows"
		and first.get_child_count() == 0 and not first.is_processing())
	_check("no engine shadow casting", first.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	var mesh: ArrayMesh = first.mesh as ArrayMesh
	_check("one merged surface and one material", mesh != null and mesh.get_surface_count() == 1)
	if mesh == null or mesh.get_surface_count() != 1:
		first.free()
		second.free()
		return
	var arrays: Array = mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colours: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var triangle_count: int = vertices.size() / 3
	_check("combined cue geometry stays below 1,500 triangles", triangle_count <= 1500, str(triangle_count))
	_check("built vertex colours contain a feathered opacity ramp", _has_alpha(colours, 0.0)
		and _has_alpha_between(colours, 0.08, 0.12) and _has_alpha_between(colours, 0.16, ALPHA_LIMIT))
	var valid: bool = vertices.size() == colours.size()
	var all_ground: bool = true
	var alpha_bounded: bool = true
	for index: int in range(vertices.size()):
		var vertex: Vector3 = vertices[index]
		var colour: Color = colours[index]
		valid = valid and vertex.is_finite() and is_finite(colour.a)
		all_ground = all_ground and absf(vertex.y - GROUND_Y) < 0.000001
		alpha_bounded = alpha_bounded and colour.a >= 0.0 and colour.a <= ALPHA_LIMIT
	_check("all generated vertices are finite and share the ground plane", valid and all_ground)
	_check("all vertex alpha is nonnegative and capped at 0.20", alpha_bounded)
	var wind_centre: Vector3 = Vector3(float(windsock.get("east", 0.0)), GROUND_Y, -float(windsock.get("north", 0.0)))
	_check("windsock footprint is in the cue's NED-derived field position", _contains_xz(vertices, wind_centre))
	var wind_edge: Vector3 = wind_centre + Vector3(0.23, 0.0, 0.0)
	_check("windsock contact ellipse reaches its estimated 0.23 m radius", _contains_xz(vertices, wind_edge))
	_check("windsock core is darkest and its outer ring fades to zero",
		_alpha_at(vertices, colours, wind_centre) > 0.16 and is_zero_approx(_alpha_at(vertices, colours, wind_edge)))
	var station_centre: Vector3 = Vector3(float(station.get("east", 0.0)), GROUND_Y, -float(station.get("north", 0.0)))
	var station_outer_corner: Vector3 = Vector3(
		station_centre.x + float(station.get("width", 0.0)) * 0.5 + STATION_FEATHER_M,
		GROUND_Y,
		station_centre.z + float(station.get("depth", 0.0)) * 0.5 + STATION_FEATHER_M)
	_check("station feather extends 0.14 m beyond its data footprint", _contains_xz(vertices, station_outer_corner))
	_test_barrier_posts(build_cues, vertices)
	var material: StandardMaterial3D = mesh.surface_get_material(0) as StandardMaterial3D
	_check("material uses vertex alpha, alpha blending, depth test, and double-sided faces",
		material != null and material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA
		and material.vertex_color_use_as_albedo and not material.no_depth_test
		and material.depth_draw_mode == BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
		and material.cull_mode == BaseMaterial3D.CULL_DISABLED
		and material.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED
		and material.albedo_texture == null)
	_check("independent builds have equal arrays and independent mesh/material resources",
		mesh != second.mesh and mesh.surface_get_material(0) != second.mesh.surface_get_material(0)
		and vertices.to_byte_array() == second.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].to_byte_array()
		and colours.to_byte_array() == second.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR].to_byte_array())
	first.free()
	second.free()


func _test_barrier_posts(cues: Array, vertices: PackedVector3Array) -> void:
	var barrier: Dictionary = _find_cue(cues, "flightline_barrier")
	if barrier.is_empty():
		_check("default field contains the L10c flightline barrier cue", false)
		return
	var expected: PackedVector3Array = FlightlineBarrier.post_positions(barrier)
	var centre: Vector3 = Vector3(float(barrier.get("east", 0.0)), GROUND_Y, -float(barrier.get("north", 0.0)))
	var posts_present: bool = not expected.is_empty()
	for post_offset: Vector3 in expected:
		var post_centre: Vector3 = Vector3(centre.x + post_offset.x, GROUND_Y, centre.z + post_offset.z)
		posts_present = posts_present and _contains_xz(vertices, post_centre)
		posts_present = posts_present and _contains_xz(vertices, post_centre + Vector3(0.14, 0.0, 0.0))
		posts_present = posts_present and _contains_xz(vertices, post_centre + Vector3(0.0, 0.0, 0.14))
	_check("barrier discs use every post centre returned by its geometry helper", posts_present)


func _find_cue(cues: Array, cue_type: String) -> Dictionary:
	for cue_value: Variant in cues:
		if cue_value is Dictionary:
			var cue: Dictionary = cue_value
			if str(cue.get("type", "")) == cue_type:
				return cue
	return {}


func _contains_xz(vertices: PackedVector3Array, expected: Vector3) -> bool:
	for vertex: Vector3 in vertices:
		if absf(vertex.x - expected.x) < 0.00001 and absf(vertex.z - expected.z) < 0.00001:
			return true
	return false


func _has_alpha(colours: PackedColorArray, expected: float) -> bool:
	for colour: Color in colours:
		if absf(colour.a - expected) < 0.00001:
			return true
	return false


func _has_alpha_between(colours: PackedColorArray, minimum: float, maximum: float) -> bool:
	for colour: Color in colours:
		if colour.a >= minimum and colour.a <= maximum:
			return true
	return false


func _alpha_at(vertices: PackedVector3Array, colours: PackedColorArray, expected: Vector3) -> float:
	var result: float = -1.0
	for index: int in range(vertices.size()):
		if absf(vertices[index].x - expected.x) < 0.00001 and absf(vertices[index].z - expected.z) < 0.00001:
			result = maxf(result, colours[index].a)
	return result


func _check(label: String, passed: bool, detail: String = "") -> void:
	_checks += 1
	if not passed:
		_failures += 1
		printerr("FAIL: %s %s" % [label, detail])
