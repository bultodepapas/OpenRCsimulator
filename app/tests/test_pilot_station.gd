extends SceneTree
const Station = preload("res://render/pilot_station.gd")
const Loader = preload("res://data/field_loader.gd")
const Field = preload("res://render/field.gd")
const Grass = preload("res://render/near_grass.gd")
var _count: int = 0
var _failed: int = 0

func _initialize() -> void:
	var loaded: Dictionary = Loader.load_from()
	_check("default field validates", loaded.ok)
	if not loaded.ok:
		quit(1)
		return
	var cues: Array = loaded.field.flight_cues.filter(func(c: Dictionary) -> bool: return c.type == "pilot_station")
	_check("one default pilot station", cues.size() == 1)
	if cues.size() != 1:
		quit(1)
		return
	var cue: Dictionary = cues[0]
	for width: float in [1.2, float(cue.width), 2.4]:
		var variant: Dictionary = cue.duplicate()
		variant.width = width
		if width != float(cue.width):
			variant.depth = 1.0 if width == 1.2 else 2.0
			variant.height = 0.6 if width == 1.2 else 0.9
			variant.north = 57.0
			variant.east = -88.0
		_check_mesh(variant)
	var built: Node3D = Field.build(loaded.field)
	_check("field attaches station", built.get_node_or_null(str(cue.id) + "/Station") is MeshInstance3D)
	built.free()
	var legacy: Dictionary = loaded.field.duplicate(true)
	legacy.erase("flight_cues")
	built = Field.build(legacy)
	_check("absent optional cues preserve field", built.get_node_or_null(str(cue.id)) == null)
	built.free()
	_check("grass excludes platform and full clump margin", not Grass.accepts(cue.north, cue.east, loaded.field)
		and not Grass.accepts(cue.north + cue.depth / 2 + Grass.CLEARANCE_M - 0.001, cue.east, loaded.field)
		and not Grass.accepts(cue.north, cue.east + cue.width / 2 + Grass.CLEARANCE_M - 0.001, loaded.field))
	_check("grass resumes outside platform margin", Grass.accepts(cue.north + cue.depth / 2 + Grass.CLEARANCE_M + 0.001, cue.east, loaded.field))
	_check("legacy centre is still grass", Grass.accepts(cue.north, cue.east, legacy))
	var sock: Dictionary = loaded.field.flight_cues.filter(func(c: Dictionary) -> bool: return c.type == "windsock")[0]
	_check("windsock retains its grass policy", Grass.accepts(sock.north, sock.east, loaded.field) == Grass.accepts(sock.north, sock.east, legacy))
	var rows: Array = Grass.validated_rows(JSON.parse_string(FileAccess.get_file_as_string(Grass.DATA_PATH)))
	var removed: int = 0
	var grass_clear: bool = true
	var chunks: Array = Grass.clipped_chunks(loaded.field, rows)
	for chunk: Array in chunks:
		for point: Array in chunk:
			grass_clear = grass_clear and (absf(float(point[0])-cue.north) > cue.depth/2+Grass.CLEARANCE_M or absf(float(point[1])-cue.east) > cue.width/2+Grass.CLEARANCE_M)
	for row: Array in rows:
		var n: float = loaded.field.pilot.north + float(row[0])*.001
		var e: float = loaded.field.pilot.east + float(row[1])*.001
		if Grass.accepts(n,e,legacy) and not Grass.accepts(n,e,loaded.field):
			removed += 1
	_check("actual placement removes clumps and clears pad envelope", removed > 0 and grass_clear)
	print("station removes %d grass clumps" % removed)
	print("%d checks, %d failed" % [_count, _failed])
	quit(1 if _failed else 0)

func _check_mesh(cue: Dictionary) -> void:
	var first: Node3D = Station.build(cue)
	var second: Node3D = Station.build(cue)
	var mesh: MeshInstance3D = first.get_node("Station") as MeshInstance3D
	var bounds: AABB = mesh.mesh.get_aabb()
	_check("dimensions are data driven, fittings contained", bounds.size.is_equal_approx(Vector3(cue.width, cue.height, cue.depth)) and is_zero_approx(bounds.position.y))
	_check("NED location", first.position.is_equal_approx(Vector3(cue.east, 0, -cue.north)))
	_check("one mesh only, no process or physics nodes", first.get_child_count() == 1 and mesh.get_child_count() == 0 and not first.is_processing() and not mesh.is_processing())
	var arrays: Array = mesh.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var finite: bool = true
	for i: int in vertices.size():
		finite = finite and vertices[i].is_finite() and normals[i].is_finite() and absf(normals[i].length() - 1.0) < 0.00001
	_check("finite mesh, unit normals", finite)
	_check("bounded one-surface geometry", mesh.mesh.get_surface_count() == 1 and vertices.size() / 3 < 400)
	_check("opaque material without shadow pass", mesh.mesh.surface_get_material(0).transparency == BaseMaterial3D.TRANSPARENCY_DISABLED and mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	_check("rear entry stays open", not _intersects(vertices, Vector3(0, 0.13, cue.depth), Vector3(0, 0.13, 0)))
	_check("front and sides have barrier geometry", _intersects(vertices, Vector3(0, 0.13, -cue.depth), Vector3(0, 0.13, 0))
		and _intersects(vertices, Vector3(cue.width, 0.13, 0), Vector3(0, 0.13, 0))
		and _intersects(vertices, Vector3(-cue.width, 0.13, 0), Vector3(0, 0.13, 0)))
	_check("independent repeat geometry", mesh.mesh != second.get_node("Station").mesh and vertices.to_byte_array() == second.get_node("Station").mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].to_byte_array())
	first.free()
	second.free()

func _intersects(vertices: PackedVector3Array, a: Vector3, b: Vector3) -> bool:
	for i: int in range(0, vertices.size(), 3):
		if Geometry3D.segment_intersects_triangle(a, b, vertices[i], vertices[i+1], vertices[i+2]) != null:
			return true
	return false

func _check(label: String, passed: bool) -> void:
	_count += 1
	if not passed:
		_failed += 1
		printerr("FAIL: ", label)
