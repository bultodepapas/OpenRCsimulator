extends Node3D
## LU-29: static regional fixtures, existing buildings and a downloaded communications tower.
## All positions are render-only. No physics or navigation-light certification is implied.
const Palette := preload("res://scenery/palette.gd")
const Kit := preload("res://scenery/mesh_kit.gd")
const Scenery := preload("res://scenery/scenery.gd")
const PowerLines := preload("res://scenery/power_lines.gd")
const ShaderClock := preload("res://render/shader_clock.gd")
const BEACON := preload("res://render/landscape_upgrade/regional_beacon.gdshader")
const WINDOW := preload("res://render/landscape_upgrade/regional_window.gdshader")
const POOL := preload("res://render/landscape_upgrade/regional_pool.gdshader")
const WARM := Color(1.0, 0.64, 0.32)
const RED := Color(1.0, 0.025, 0.008)
const CELL_M := 600.0
var _batches := {}
var _hardware := {}
var _materials: Array[ShaderMaterial] = []
var _counts := {}
var _last_night := -1.0
var _optics: Array[MultiMeshInstance3D] = []
var _head: RefCounted
var _head_bounds := AABB()

static func build(scenery: Dictionary) -> Node3D:
	ShaderClock.register()
	var script: GDScript = load("res://render/landscape_upgrade/regional_lighting.gd")
	var node: Node3D = script.new()
	node.name = "RegionalLighting"
	node._build(scenery)
	return node

func apply_night(factor: float) -> void:
	if is_equal_approx(factor, _last_night):
		return
	_last_night = factor
	for material: ShaderMaterial in _materials:
		material.set_shader_parameter("night_factor", factor)
	for node: MultiMeshInstance3D in _optics:
		node.visible = factor > 0.0
	set_meta("night_factor", factor)

func _build(scenery: Dictionary) -> void:
	_head = _fixture_head()
	for group: Dictionary in scenery.get("groups", []):
		if group.get("type", "") != "instances":
			continue
		for p: Dictionary in group.get("placements", []):
			var prefab := str(p.get("prefab", group.get("prefab", "")))
			var xf := Transform3D(Basis(Vector3.UP, -deg_to_rad(float(p.get("heading", 0)))),
				Vector3(float(p.east), 0, -float(p.north)))
			var seed := int(p.get("seed", 0))
			match prefab:
				"pylon":
					_point(xf * Vector3(0, 30.12, 0), RED, false, 0.35, false, 3000, "pylon_top_lights")
				"turbine":
					_point(xf * Vector3(0, 82.4, 1.5), RED, true, 0.9, false, 12000, "turbine_beacons")
					_fixture(xf * Vector3(0, 2.8, 3.3), 2.8, "turbine_service", false, 0.35)
				"village_house", "farmhouse":
					_house(xf, seed, prefab == "farmhouse")
				"barn":
					_fixture(xf * Vector3(0, 3.45, -7.5), 3.45, "barn_loading", false, 1.0)
				"silo":
					_fixture(xf * Vector3(0.5, 2.4, -3.05), 2.4, "silo_access", false, 0.4)
				"church":
					_fixture(xf * Vector3(-1.5, 3, -10.4), 3, "church_entrance", false, 0.55)
					for side: float in [-1.0, 1.0]:
						for i in 4:
							_window(xf * Transform3D(Basis(Vector3.UP, side * PI / 2),
								Vector3(side * 4.06, 3.2, -1.0 + i * 3.6)), Vector2(0.85, 2.35), 0.45, "church_windows")
				"shed":
					_fixture(xf * Vector3(0.6, 2.15, -1.4), 2.15, "shed_worklight", false, 0.4)
		var placements: Array = group.get("placements", [])
		for i in maxi(0, placements.size() - 1):
			var a: Dictionary = placements[i]
			var b: Dictionary = placements[i + 1]
			if a.get("prefab", group.get("prefab", "")) != "pylon" or b.get("prefab", group.get("prefab", "")) != "pylon":
				continue
			var ax := Scenery._placement_xf(a.north, a.east, a.get("heading", 0))
			var bx := Scenery._placement_xf(b.north, b.east, b.get("heading", 0))
			# Steady red wire markers on the upper energized conductor.
			# Static shader billboards share regional cells; no Light3D or tick.
			_point(PowerLines.conductor_point(ax, bx, 4, 0.5), RED, false,
				0.22, false, 3000, "power_wire_markers")
	# Sparse junctions and gates, not a continuous bright road across the agricultural plain.
	for p: Vector3 in [Vector3(948, 5.5, 430), Vector3(923, 5.5, -600), Vector3(-863, 4.5, 687)]:
		_fixture(p, p.y, "rural_junctions", true, 1.0)
	for p: Vector3 in [Vector3(-850, 3.8, 669), Vector3(-450, 3.8, 669)]:
		_fixture(p, p.y, "village_street_ends", true, 0.65)
	for p: Vector3 in [Vector3(376, 1.2, -604), Vector3(376, 1.2, -615),
			Vector3(687, 1.2, -733), Vector3(687, 1.2, -743)]:
		_fixture(p, 1.2, "farm_gate_bollards", true, 0.25)
	_build_hills()
	_build_antennas()
	_flush()
	set_meta("counts", _counts.duplicate())
	set_meta("batch_count", _batches.size())
	set_meta("dynamic_lights", 0)
	_batches.clear()
	_hardware.clear()
	_head = null
	apply_night(0.0)

func _house(xf: Transform3D, seed: int, farm := false) -> void:
	var w := 9.0 if farm else 7.0 + 2.0 * Palette.hash01(seed, 1)
	var d := 7.0 if farm else 8.0 + 3.0 * Palette.hash01(seed, 2)
	for i in 2:
		var x := (-1.0 if i == 0 else 1.0) * (3.0 if farm else w * 0.28)
		# Fixed occupancy, no random per-frame flashing.
		if Palette.hash01(seed, i, 113) < 0.74:
			var pane := xf * Transform3D(Basis(Vector3.UP, PI), Vector3(x, 1.55, -d * 0.5 - 0.09))
			_window(pane,
				Vector2(0.92, 1.02), 0.65 + Palette.hash01(seed, i, 117) * 0.35, "occupied_house_windows")
			if xf.origin.y > 1.0:
				_point(pane.origin, WARM, false, 0.14, false, 8500, "hill_window_optics")
		if farm and i == 0:
			_window(xf * Transform3D(Basis(Vector3.UP, PI), Vector3(x, 3.9, -d * 0.5 - 0.09)),
				Vector2(1.02, 0.92), 0.55, "farm_upper_windows")
	if Palette.hash01(seed, 91) < 0.7:
		_fixture(xf * Vector3(w * 0.1, 2.45, -d * 0.5 - 0.35), 2.45, "house_porches", false, 0.35, xf.origin.y)

func _build_hills() -> void:
	var path := "res://render/landscape_upgrade/hill_settlements.gd"
	if not ResourceLoader.exists(path):
		push_error("Missing regional hill settlements: " + path)
		return
	var script: GDScript = load(path)
	var hills: Node3D = script.build()
	add_child(hills)
	for house: Dictionary in hills.get_meta("houses", []):
		_house(Transform3D(house.basis, house.position), int(house.seed))
	set_meta("hill_houses", hills.get_meta("houses", []).size())

func _build_antennas() -> void:
	# The downloaded tower is installed once its retained asset has been imported.
	var path := "res://assets/landscape/regional-lighting/radio_tower.glb"
	if not ResourceLoader.exists(path):
		push_error("Missing regional antenna asset: " + path)
		return
	var scene: PackedScene = load(path)
	for site: Vector3 in [Vector3(-1400, 0, -1000), Vector3(2100, 0, -1300)]:
		var tower: Node3D = scene.instantiate()
		tower.name = "CommunicationsTower_%d" % get_child_count()
		tower.scale = Vector3.ONE * 1.76745263
		tower.position = site + Vector3(0, 0.10839434, 0)
		add_child(tower)
		for mesh: MeshInstance3D in tower.find_children("*", "MeshInstance3D", true, false):
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Measured source mast centers, retained in the asset provenance.
		_point(site + Vector3(0, 65.3, 0), RED, true, 0.85, false, 10000, "antenna_top_beacons")
		for side: float in [-1.0, 1.0]:
			_point(site + Vector3(side * 2.36, 32.5, -side * 1.19),
				RED, false, 0.28, false, 6000, "antenna_mid_lights")
		_fixture(site + Vector3(5, 2.6, 6), 2.6, "antenna_service", true, 0.4)
		_count("antenna_towers")

func _count(category: String) -> void:
	_counts[category] = int(_counts.get(category, 0)) + 1

func _queue(kind: String, xf: Transform3D, color: Color, custom: Color) -> void:
	var cell := Vector2i(floori(xf.origin.x / CELL_M), floori(xf.origin.z / CELL_M))
	var key := "%s_%d_%d" % [kind, cell.x, cell.y]
	if not _batches.has(key):
		_batches[key] = {kind = kind, origin = Vector3(cell.x * CELL_M, 0, cell.y * CELL_M), rows = []}
	var local := xf
	local.origin -= _batches[key].origin
	_batches[key].rows.append({xf = local, color = color, custom = custom})

func _point(p: Vector3, color: Color, flashing: bool, gain: float, shielded: bool, distance_m: float, category: String) -> void:
	_queue("beacon", Transform3D(Basis.IDENTITY, p), color, Color(1.0 if flashing else 0.0, gain, 1.0 if shielded else 0.0, distance_m))
	_count(category)

func _window(xf: Transform3D, size: Vector2, occupancy: float, category: String) -> void:
	var pane := xf
	pane.basis = pane.basis.scaled_local(Vector3(size.x, size.y, 1))
	_queue("window", pane, WARM, Color(occupancy, 0, 0, 1))
	_count(category)

func _fixture(p: Vector3, height: float, category: String, pole: bool, gain: float, ground_y := 0.0) -> void:
	_point(p - Vector3(0, 0.08, 0), WARM, false, gain * 0.6, true, 2200, category)
	var cell := Vector2i(floori(p.x / CELL_M), floori(p.z / CELL_M))
	if not _hardware.has(cell):
		_hardware[cell] = Kit.new()
	var kit: RefCounted = _hardware[cell]
	kit.xf = Transform3D(Basis.IDENTITY, p - Vector3(cell.x * CELL_M, 0, cell.y * CELL_M))
	# The club keeps the downloaded fitting. At distant sites its measured envelope
	# is a 10-triangle LOD: a subpixel housing does not need thousands of fins.
	if Vector2(p.x, p.z).length() < 400.0:
		kit.append_arrays(_head.verts, _head.norms, _head.cols,
			Transform3D(Basis(Vector3.RIGHT, -PI / 2).scaled(Vector3.ONE * 1.25), Vector3.ZERO))
	else:
		kit.box(Vector3(_head_bounds.size.x, _head_bounds.size.z, _head_bounds.size.y) * 1.25,
			Vector3.ZERO, Color("#343b3b"))
	if pole:
		kit.block(Vector3(0.1, height, 0.1), Vector3(0, -height, 0), Color("#545b58"))
	if ground_y > 1.0:
		return # slope houses retain their real facade lamps, without a floating planar pool
	var pool := Transform3D(Basis(Vector3.RIGHT, -PI / 2), Vector3(p.x, ground_y + 0.11, p.z))
	pool.basis = pool.basis.scaled_local(Vector3(height * 2.6, height * 1.8, 1))
	_queue("pool", pool, WARM, Color(gain, 0, 0, 1))

func _fixture_head() -> RefCounted:
	var kit := Kit.new()
	var scene: PackedScene = load("res://assets/landscape/night-lighting/lamp-head.glb")
	var source: Node3D = scene.instantiate()
	for part: MeshInstance3D in source.find_children("*", "MeshInstance3D", true, false):
		for s in part.mesh.get_surface_count():
			var arrays: Array = part.mesh.surface_get_arrays(s)
			var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var material: StandardMaterial3D = part.mesh.surface_get_material(s)
			var tint := material.albedo_color if material != null else Color.GRAY
			for i in indices:
				kit.verts.append(part.transform * positions[i])
				kit.norms.append(part.transform.basis * normals[i])
				kit.cols.append(tint)
	source.free()
	if not kit.verts.is_empty():
		_head_bounds = AABB(kit.verts[0], Vector3.ZERO)
		for vertex: Vector3 in kit.verts:
			_head_bounds = _head_bounds.expand(vertex)
	return kit

func _flush() -> void:
	var materials := {}
	for kind: String in ["beacon", "window", "pool"]:
		var m := ShaderMaterial.new()
		m.shader = BEACON if kind == "beacon" else WINDOW if kind == "window" else POOL
		materials[kind] = m
		_materials.append(m)
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	for key: String in _batches:
		var batch: Dictionary = _batches[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = quad
		mm.instance_count = batch.rows.size()
		for i in batch.rows.size():
			mm.set_instance_transform(i, batch.rows[i].xf)
			mm.set_instance_color(i, batch.rows[i].color)
			mm.set_instance_custom_data(i, batch.rows[i].custom)
		var node := MultiMeshInstance3D.new()
		node.name = key
		node.position = batch.origin
		node.multimesh = mm
		node.material_override = materials[batch.kind]
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Shader expansion is a few pixels; a small pad protects edge-of-frustum beacons.
		node.extra_cull_margin = 50.0 if batch.kind == "beacon" else 1.0
		add_child(node)
		_optics.append(node)
	var opaque := Scenery.opaque_material()
	var hardware_triangles := 0
	for cell: Vector2i in _hardware:
		hardware_triangles += int(_hardware[cell].triangle_count())
		var node := MeshInstance3D.new()
		node.name = "FixtureHardware_%d_%d" % [cell.x, cell.y]
		node.position = Vector3(cell.x * CELL_M, 0, cell.y * CELL_M)
		node.mesh = _hardware[cell].to_mesh(opaque)
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
	set_meta("hardware_triangles", hardware_triangles)
