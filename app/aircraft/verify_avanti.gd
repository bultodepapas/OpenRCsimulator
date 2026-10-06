# AV-03 contract checks for the Avanti S visual preview (headless; no physics, not flyable).
# Ported from research/avanti-s/av02/verify.gd. Run: godot --headless --path app --script res://aircraft/verify_avanti.gd
extends SceneTree

const Commands := preload("res://input/commands.gd")
const Avanti := preload("res://aircraft/avanti_s_model.gd")
const AvantiGeometry := preload("res://aircraft/avanti_s_geometry.gd")

const HINGE_NAMES := ["flap_left", "flap_right", "aileron_left", "aileron_right", "elevator_left", "elevator_right", "rudder"]
# Span and length are the manufacturer nominal values the geometry is built to (DATA.nominal). Vertices are
# float32 (rounding ~1e-7 m at 1 m), so 0.1 mm (as in AV-02) passes float rounding but no change of the data.
const SIZE_TOLERANCE_M := 0.0001
const TEST_DEG := 10.0
const MIN_TRAVEL_M := 0.001 # smallest TE chord in the data is > 2 cm: 10 deg moves it > 3 mm
const EXACT_M := 0.000001

var _checks := 0
var _failures := 0


func _check(label: String, passed: bool, detail := "") -> void:
	_checks += 1
	if not passed:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _initialize() -> void:
	call_deferred("_run")


func _meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for m in node.find_children("*", "MeshInstance3D", true, false): out.append(m)
	return out


# Bounds of the visible built vertices, in the root frame.
func _vertex_bounds(root: Node3D) -> AABB:
	var box := AABB()
	var first := true
	var finite := true
	for m in _meshes(root):
		if not m.is_visible_in_tree(): continue
		var t := root.global_transform.affine_inverse() * m.global_transform
		for v in m.mesh.get_faces():
			var p: Vector3 = t * v
			finite = finite and p.is_finite()
			box = AABB(p, Vector3.ZERO) if first else box.expand(p)
			first = false
	_check("finite vertices", finite and not first)
	return box


func _witness(h: Dictionary) -> Vector3:
	return h.node.to_global(h.witness)


# Global position of the aft-most rest vertex of a hinge's meshes (its trailing edge), tracked through the pose.
func _aft_point(h: Dictionary) -> Vector3:
	var best := Vector3(0, 0, -INF)
	var rest_basis: Basis = h.node.basis
	h.node.basis = h.rest
	var index := -1
	var meshes := _meshes(h.node)
	var all := PackedVector3Array()
	for m in meshes:
		for v in m.mesh.get_faces():
			var p := m.global_transform * v
			all.append(p)
			if p.z > best.z:
				best = p
				index = all.size() - 1
	h.node.basis = rest_basis
	var posed := PackedVector3Array()
	for m in meshes:
		for v in m.mesh.get_faces(): posed.append(m.global_transform * v)
	return posed[index]


func _travel(model: Dictionary, surfaces: Dictionary) -> Dictionary:
	var rest := {}
	for key in HINGE_NAMES: rest[key] = [_aft_point(model.hinges[key]), _witness(model.hinges[key])]
	Avanti.apply_surfaces(model, surfaces)
	var moved := {}
	for key in HINGE_NAMES:
		moved[key] = [_aft_point(model.hinges[key]) - rest[key][0], _witness(model.hinges[key]) - rest[key][1]]
	Avanti.apply_surfaces(model, {})
	return moved


func _check_concave_panels() -> void:
	# A C has area 7 and its vertex centroid lies outside the polygon. A centroid fan overlaps its recess; ear clipping must not.
	for vertical in [false, true]:
		var outline: Array = []
		for p in [Vector2(0, 0), Vector2(3, 0), Vector2(3, 1), Vector2(1, 1), Vector2(1, 2), Vector2(3, 2), Vector2(3, 3), Vector2(0, 3)]:
			outline.append(Vector3(0, p.y, p.x) if vertical else Vector3(p.x, 0, p.y))
		var parent := Node3D.new()
		var mesh := Avanti.slab(outline, Vector3(.01, 0, 0) if vertical else Vector3(0, .01, 0), parent, "concave_probe", Color.WHITE)
		var vertices := mesh.mesh.get_faces()
		var volume := 0.0
		for i in range(0, vertices.size(), 3):
			volume -= vertices[i].dot(vertices[i + 1].cross(vertices[i + 2])) / 6.0
		_check("concave panel volume", absf(volume - .14) < .000001, str(volume))
		parent.free()


func _check_lofts(model: Dictionary) -> void:
	for key in ["fuselage_stations", "canopy_stations"]:
		var knots: Array = model.data[key]
		var samples := Avanti.interpolate_sections(knots, 4)
		var valid := samples.size() == (knots.size() - 1) * 4 + 1
		for i in knots.size() - 1:
			valid = valid and samples[i * 4] == knots[i]
			for j in 4:
				var row: Array = samples[i * 4 + j]
				valid = valid and row[1] > 0 and row[2] > row[3]
				for c in range(1, row.size()):
					valid = valid and row[c] >= minf(knots[i][c], knots[i + 1][c]) - 1e-8 and row[c] <= maxf(knots[i][c], knots[i + 1][c]) + 1e-8
		_check(key + " interpolation keeps knots and bounds", valid and samples[-1] == knots[-1])
	for node in [model.skin, model.canopy]:
		var arrays: Array = node.mesh.surface_get_arrays(0)
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var valid := normals.size() == vertices.size()
		for n in normals: valid = valid and n.is_finite() and absf(n.length() - 1) < .001
		_check("%s loft normals unit" % node.name, valid)
		var outward := true
		for i in range(0, vertices.size(), 3):
			var geometric := (vertices[i + 2] - vertices[i]).cross(vertices[i + 1] - vertices[i]).normalized()
			outward = outward and geometric.dot(normals[i] + normals[i + 1] + normals[i + 2]) > 0
		_check("%s loft normals agree with faces" % node.name, outward)
	var parent := Node3D.new()
	var flat := Avanti.loft(model.data.canopy_stations, parent, "flat_probe", Color.WHITE, 1, 4, false)
	_check("smooth shading keeps canopy vertices", flat.mesh.get_faces() == model.canopy.mesh.get_faces())
	parent.free()


func _run() -> void:
	_check_concave_panels()
	var model := Avanti.build()
	var root: Node3D = model.root
	get_root().add_child(root)
	await process_frame
	var data: Dictionary = AvantiGeometry.DATA
	_check("visual revision", Avanti.VISUAL_REVISION == data.revision and root.get_meta("visual_revision", "") == data.revision)
	_check("root name", root.name == "airplane")
	_check("not flyable status", String(root.get_meta("status", "")).contains("not flyable"))
	var prop = model.get("propeller")
	_check("propeller marker", prop is Node3D and prop.name == "propeller" and prop.get_parent() == root)
	_check("propeller empty and invisible", prop is Node3D and prop.get_child_count() == 0 and not prop.visible)
	_check("has_propeller false", model.get("has_propeller", true) == false)
	_check("gear empty", model.get("gear") is Dictionary and model.gear.is_empty())
	_check("data is the generated geometry", is_same(model.data, data))
	_check("hinge keys", model.hinges.size() == HINGE_NAMES.size() and HINGE_NAMES.all(func(k): return model.hinges.has(k)), str(model.hinges.keys()))
	for key in model.hinges:
		var h: Dictionary = model.hinges[key]
		_check("%s hinge node" % key, h.node is Node3D and h.node.name == key + "_hinge" and h.node.get_child_count() > 0)

	_check_lofts(model)
	var box := _vertex_bounds(root)
	_check("span 2.00 m", absf(box.size.x - data.nominal.span_m) < SIZE_TOLERANCE_M, "%.6f m" % box.size.x)
	_check("length 2.22 m", absf(box.size.z - data.nominal.length_m) < SIZE_TOLERANCE_M, "%.6f m" % box.size.z)
	_check("fuselage 2.22 m", absf(model.skin.mesh.get_aabb().size.z - data.nominal.length_m) < SIZE_TOLERANCE_M)
	_check("nose toward -Z", model.skin.mesh.get_aabb().position.z < -1.0 and box.position.z < -1.0, str(box))
	_check("lateral symmetry", absf(box.position.x + box.end.x) < SIZE_TOLERANCE_M, str(box))
	_check("P100 envelope", absf(model.motor.mesh.height - data.nominal.engine_length_m) < .00001
		and absf(model.motor.mesh.top_radius * 2 - data.nominal.engine_diameter_m) < .00001 and not model.motor.visible)
	# Intermediate tail stations must meet the same straight elevator hinge.
	for side in [-1.0, 1.0]:
		var panel: Dictionary = data.tail
		var span: Array = ["probe", panel.stations[0][0], panel.stations[-1][0]]
		var h: Dictionary = model.hinges["elevator_left" if side < 0 else "elevator_right"]
		var straight := true
		for row in panel.stations:
			straight = straight and (Avanti.hinge_point(panel, span, row[0], side) - h.end_a).cross(h.axis).length() < .000001
		_check("straight elevator hinge %s" % side, straight)

	# apply_surfaces: the commands.gd convention, measured on trailing-edge points (aft-most vertex and witness).
	var rest := {}
	for key in HINGE_NAMES: rest[key] = model.hinges[key].node.transform
	var cases := [["aileron_right", "y", 1.0, ["aileron_right"]], ["aileron_left", "y", 1.0, ["aileron_left"]],
		["elevator", "y", 1.0, ["elevator_left", "elevator_right"]], ["rudder", "x", 1.0, ["rudder"]]]
	for c in cases:
		for sign in [1.0, -1.0]:
			var moved := _travel(model, {c[0]: sign * TEST_DEG})
			for key in HINGE_NAMES:
				var d: Array = moved[key]
				if key in c[3]:
					var ok: bool = d[0][c[1]] * sign > MIN_TRAVEL_M and d[1][c[1]] * sign > MIN_TRAVEL_M
					_check("%s %+.0f deg moves %s TE %s%s" % [c[0], sign * TEST_DEG, key, "+" if sign > 0 else "-", c[1]], ok, str(d))
				else:
					_check("%s leaves %s still" % [c[0], key], d[0].length() < EXACT_M and d[1].length() < EXACT_M, str(d))
	# The same senses from a real command through commands.gd: right roll raises the right aileron, pull raises
	# the elevator, right yaw moves the rudder TE right.
	var deflections := Commands.surface_deflections_deg({roll = 1.0, pitch = 1.0, yaw = 1.0, throttle = 0.5},
		{aileron = TEST_DEG, elevator = TEST_DEG, rudder = TEST_DEG})
	var moved := _travel(model, deflections)
	_check("right roll: right aileron up", moved.aileron_right[0].y > MIN_TRAVEL_M)
	_check("right roll: left aileron down", moved.aileron_left[0].y < -MIN_TRAVEL_M)
	_check("pull: both elevators up", moved.elevator_left[0].y > MIN_TRAVEL_M and moved.elevator_right[0].y > MIN_TRAVEL_M)
	_check("right yaw: rudder TE right", moved.rudder[0].x > MIN_TRAVEL_M)
	# Pivots and axes stay put under deflection; neutral restores rest exactly.
	Avanti.apply_surfaces(model, deflections)
	Avanti.set_flaps(model, 20.0)
	for key in HINGE_NAMES:
		var h: Dictionary = model.hinges[key]
		_check("%s pivot fixed" % key, h.node.position.distance_to(h.end_a) < EXACT_M)
		_check("%s axis invariant" % key, (h.node.basis * h.axis).distance_to(h.axis) < EXACT_M)
	Avanti.apply_surfaces(model, Commands.surface_deflections_deg({roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.0},
		{aileron = TEST_DEG, elevator = TEST_DEG, rudder = TEST_DEG}))
	Avanti.set_flaps(model, 0.0)
	for key in HINGE_NAMES:
		_check("%s neutral is rest exactly" % key, model.hinges[key].node.transform == rest[key])

	# set_flaps: TE down, clamped to the data range; apply_surfaces leaves flaps alone.
	var c_deg: Dictionary = data.controls_deg
	var flap_rest := _aft_point(model.hinges.flap_left)
	Avanti.set_flaps(model, 999.0)
	var flap_full := _aft_point(model.hinges.flap_left)
	_check("flap TE goes down", flap_full.y < flap_rest.y - MIN_TRAVEL_M)
	_check("flap clamped to landing", model.hinges.flap_right.node.basis.is_equal_approx(
		Basis(model.hinges.flap_right.axis, deg_to_rad(c_deg.flap_landing)) * model.hinges.flap_right.rest))
	Avanti.apply_surfaces(model, {})
	_check("apply_surfaces keeps flaps", _aft_point(model.hinges.flap_left).distance_to(flap_full) < EXACT_M)
	Avanti.set_flaps(model, -30.0)
	_check("flap clamped to cruise (rest)", model.hinges.flap_left.node.transform == rest.flap_left)
	# AV-02 inspector mapping still behaves as in AV-02.
	Avanti.apply_controls(model, 1, 1, 1, 50)
	var ac := {}
	for key in HINGE_NAMES: ac[key] = _witness(model.hinges[key])
	Avanti.apply_controls(model, 0, 0, 0, 0)
	for key in ["flap_left", "flap_right", "aileron_left"]:
		_check("apply_controls %s down" % key, ac[key].y < _witness(model.hinges[key]).y - .01)
	for key in ["elevator_left", "elevator_right", "aileron_right"]:
		_check("apply_controls %s up" % key, ac[key].y > _witness(model.hinges[key]).y + .01)
	_check("apply_controls rudder right", ac.rudder.x > _witness(model.hinges.rudder).x + .01)
	for key in HINGE_NAMES:
		_check("apply_controls neutral %s is rest" % key, model.hinges[key].node.transform == rest[key])

	# Two builds: independent nodes and meshes, shared immutable materials.
	var other := Avanti.build()
	get_root().add_child(other.root)
	var other_rest := _aft_point(other.hinges.aileron_right)
	Avanti.apply_surfaces(model, {aileron_right = TEST_DEG, elevator = TEST_DEG})
	Avanti.set_flaps(model, 50.0)
	_check("instances independent", _aft_point(other.hinges.aileron_right).distance_to(other_rest) < EXACT_M
		and other.hinges.flap_left.node.transform == rest.flap_left)
	_check("instances own their nodes", other.root != root and other.hinges.rudder.node != model.hinges.rudder.node)
	_check("instances share materials", model.skin.material_override == other.skin.material_override
		and model.hinges.rudder.node.get_child(0).material_override == other.hinges.rudder.node.get_child(0).material_override)
	var by_colour := {}
	var shared := true
	for m in _meshes(root) + _meshes(other.root):
		var key: String = m.material_override.albedo_color.to_html()
		shared = shared and by_colour.get(key, m.material_override) == m.material_override
		by_colour[key] = m.material_override
	_check("one material per colour", shared, "%d colours" % by_colour.size())
	Avanti.apply_surfaces(model, {})
	Avanti.set_flaps(model, 0.0)

	var meshes := _meshes(root)
	var triangles := 0
	for m in meshes: triangles += m.mesh.get_faces().size() / 3
	print("avanti preview %s: %d meshes, %d triangles, extent %.4f x %.4f x %.4f m" % [Avanti.VISUAL_REVISION, meshes.size(), triangles, box.size.x, box.size.y, box.size.z])
	other.root.free()
	root.free()
	if _failures == 0: print("PASS %d checks" % _checks)
	else: printerr("FAIL %d of %d checks" % [_failures, _checks])
	quit(1 if _failures > 0 else 0)
