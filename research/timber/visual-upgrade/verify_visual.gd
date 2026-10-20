## TT-20: visual additions must not change original articulation or wreck contact boxes.
extends SceneTree

const Timber := preload("res://aircraft/timber_model.gd")
const Builder := preload("res://render/airplane.gd")
const Imported := preload("res://aircraft/imported_model.gd")
const WreckScript := preload("res://render/crash/wreck.gd")
const Lights := preload("res://render/world/aircraft_lights.gd")
const ShaderClock := preload("res://render/shader_clock.gd")

var _failures: Array[String] = []
var _checks := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(label: String, passed: bool) -> void:
	_checks += 1
	if not passed:
		_failures.append(label)
		printerr("FAIL ", label)

func _groups(wreck: Node) -> Array:
	var records: Array = []
	for group: Dictionary in wreck._prepared_groups:
		records.append({
			kind = group.get("kind", ""),
			bounds = str(group.bounds),
			center = str(group.center),
			member_bounds = str(group.get("member_bounds", [])),
		})
	return records

## Paint repartition and smoothed normals may change surface/index organization.
## Compare exact float32 position bits and triangle winding, including duplicate counts.
func _geometry_signature(mesh: Mesh) -> Dictionary:
	var triangles := {}
	for surface in mesh.get_surface_count():
		if mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES:
			return {unsupported_primitive = true}
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var keys: Array[String] = []
		for vertex in vertices:
			keys.append(PackedFloat32Array([vertex.x, vertex.y, vertex.z]).to_byte_array().hex_encode())
		var count := indices.size() if not indices.is_empty() else vertices.size()
		for first in range(0, count, 3):
			var a := keys[indices[first] if not indices.is_empty() else first]
			var b := keys[indices[first + 1] if not indices.is_empty() else first + 1]
			var c := keys[indices[first + 2] if not indices.is_empty() else first + 2]
			var rotations: Array[String] = [a + b + c, b + c + a, c + a + b]
			rotations.sort()
			var key := rotations[0]
			triangles[key] = int(triangles.get(key, 0)) + 1
	return {bounds = mesh.get_aabb(), triangles = triangles}

## Godot's CULL_BACK convention is clockwise front faces: (b-a)×(c-a) must
## point opposite the stored outward normal. Check every generated foam triangle.
func _fracture_face_cw_front(mesh: Mesh) -> bool:
	if mesh == null or mesh.get_surface_count() != 1:
		return false
	if mesh.surface_get_primitive_type(0) != Mesh.PRIMITIVE_TRIANGLES:
		return false
	var arrays: Array = mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array else PackedInt32Array()
	if vertices.is_empty() or normals.size() != vertices.size():
		return false
	var count := indices.size() if not indices.is_empty() else vertices.size()
	if count < 3 or count % 3 != 0:
		return false
	for first in range(0, count, 3):
		var ia := indices[first] if not indices.is_empty() else first
		var ib := indices[first + 1] if not indices.is_empty() else first + 1
		var ic := indices[first + 2] if not indices.is_empty() else first + 2
		if ia >= vertices.size() or ib >= vertices.size() or ic >= vertices.size():
			return false
		var face_cross: Vector3 = (vertices[ib] - vertices[ia]).cross(vertices[ic] - vertices[ia])
		if face_cross.length_squared() < 1.0e-18:
			return false
		var stored_normal := (normals[ia] + normals[ib] + normals[ic]).normalized()
		if face_cross.normalized().dot(stored_normal) >= -0.99:
			return false
	return true

func _run() -> void:
	ShaderClock.register()
	var source := Timber.build()
	var candidate := Builder.build(Builder.TIMBER_ID)
	_check("both models build", not source.is_empty() and not candidate.is_empty())
	if source.is_empty() or candidate.is_empty():
		quit(1)
		return
	root.add_child(source.root)
	root.add_child(candidate.root)
	var original_paths: Array[NodePath] = []
	for original: Node in source.root.find_children("*", "Node3D", true, false):
		var path: NodePath = source.root.get_path_to(original)
		original_paths.append(path)
		var current: Node3D = candidate.root.get_node_or_null(path)
		_check("original node survives " + str(path), current != null)
		if current == null:
			continue
		_check("rest transform " + str(path), Imported.relative(source.root, original).is_equal_approx(Imported.relative(candidate.root, current)))
		if original is MeshInstance3D:
			_check("exact original geometry and winding " + str(path),
				original.mesh == current.mesh or _geometry_signature(original.mesh) == _geometry_signature(current.mesh))
	var details := 0
	for node: MeshInstance3D in candidate.root.find_children("*", "MeshInstance3D", true, false):
		if not original_paths.has(candidate.root.get_path_to(node)):
			details += 1
			_check("detail excluded from collision bounds " + str(node.name), node.has_meta("crash_no_bounds"))
	for section: String in ["wing_left", "wing_right"]:
		var reveal: Node = candidate.root.find_child("TimberEPOFracture_" + section, true, false)
		var foam: MeshInstance3D = reveal.get_node_or_null("TornEPOCrossSection") as MeshInstance3D if reveal != null else null
		_check("fracture foam CW-front winding " + section, foam != null and _fracture_face_cw_front(foam.mesh))
	for pose: Dictionary in [{aileron_left = 10.0, aileron_right = -10.0, elevator = 12.0, rudder = 15.0},
			{aileron_left = -10.0, aileron_right = 10.0, elevator = -12.0, rudder = -15.0},
			{aileron_left = 0.0, aileron_right = 0.0, elevator = 0.0, rudder = 0.0}]:
		Timber.apply_surfaces(source, pose)
		Imported.apply_surfaces(candidate, pose)
		for key: String in source.hinges:
			_check("control pose " + key, Imported.relative(source.root, source.hinges[key].node).is_equal_approx(Imported.relative(candidate.root, candidate.hinges[key].node)))
	var kit := Lights.attach(candidate.root)
	_check("factory light kit builds", kit != null)
	for light_name in ["nav_left", "nav_right", "strobe_dorsal", "strobe_ventral", "landing_lamp", "landing_lamp_right"]:
		var lamp := kit.get_node_or_null(light_name) as Node3D
		_check("factory lens present " + light_name, lamp != null and lamp.visible and lamp.has_meta("crash_no_bounds"))
	for light_name in ["nav_tail", "strobe_left", "strobe_right", "strip_left", "strip_right", "strip_belly", "strip_top_left", "strip_top_right"]:
		var lamp := kit.get_node_or_null(light_name) as Node3D
		_check("unsupported light stays dark " + light_name, lamp == null or not lamp.visible)
	Lights.set_mode(kit, "nav")
	_check("NAV preserves beacons and disables landing lamps", kit.get_node("strobe_dorsal").visible and not kit.get_node("landing_lamp").visible and not kit.get_node("landing_lamp_right").visible)
	Lights.set_mode(kit, "off")
	_check("OFF disables complete factory kit", not kit.visible)
	Lights.set_mode(kit, "all")
	var source_wreck := WreckScript.new()
	var candidate_wreck := WreckScript.new()
	root.add_child(source_wreck)
	root.add_child(candidate_wreck)
	_check("source wreck prepares", source_wreck.prepare(source.root))
	_check("candidate wreck prepares", candidate_wreck.prepare(candidate.root))
	var source_groups := _groups(source_wreck)
	var candidate_groups := _groups(candidate_wreck)
	_check("wreck section contact boxes and centers unchanged", source_groups == candidate_groups)
	var report := {checks = _checks, failures = _failures, visual_detail_meshes = details,
		source_groups = source_groups, candidate_groups = candidate_groups,
		visual_details_sha256 = FileAccess.get_sha256("res://aircraft/timber_visual_details.gd"),
		visual_detail_data_sha256 = FileAccess.get_sha256("res://assets/aircraft/turbo-lumber-evolution/visual-upgrade/visual_detail_data.gd"),
		visual_lighting_sha256 = FileAccess.get_sha256("res://aircraft/timber_visual_lighting.gd"),
		asset_sha256 = FileAccess.get_sha256("res://assets/aircraft/turbo-lumber-evolution/timber.glb")}
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			var file := FileAccess.open(arg.trim_prefix("--out="), FileAccess.WRITE)
			file.store_string(JSON.stringify(report, "\t") + "\n")
	print("TT-20 visual isolation: %d checks, %d failed; %d detail meshes" % [_checks, _failures.size(), details])
	source_wreck.free()
	candidate_wreck.free()
	source.root.free()
	candidate.root.free()
	quit(1 if not _failures.is_empty() else 0)
