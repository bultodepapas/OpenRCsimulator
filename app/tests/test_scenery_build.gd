# SCENERY-PLAN SC-02…SC-24: the scenery builds deterministically, within budget, with the catalog's real sizes, Godot's
# winding, the quality tiers and themes, and changes nothing when it is off.
# Run: godot --headless --path . --script res://tests/test_scenery_build.gd
extends SceneTree

const Scenery = preload("res://scenery/scenery.gd")
const Loader = preload("res://scenery/scenery_loader.gd")
const Prefabs = preload("res://scenery/prefabs.gd")
const Models = preload("res://scenery/models.gd")
const MeshKit = preload("res://scenery/mesh_kit.gd")
const Palette = preload("res://scenery/palette.gd")
const FieldLoader = preload("res://data/field_loader.gd")
const FieldBuilder = preload("res://render/field.gd")
const ShaderClock = preload("res://render/shader_clock.gd")

const OPTS := {audio = false, birds = false, theme = "", quality = "high"}
const BUDGET_TRIANGLES := 250000 # the whole scenery, all views together; per-view primitives are checked by the captures (≤ 150 k)
const BUDGET_BUILD_MS := 400.0 # generous on the shared CI/VM CPU; the plan's 150 ms target is reported, not gated here

var _failures := 0
var _field: Dictionary
var _scenery: Dictionary


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _initialize() -> void:
	ShaderClock.register()
	_field = FieldLoader.load_from(FieldLoader.DEFAULT_PATH).field
	_scenery = Loader.load_from(Loader.DEFAULT_PATH, _field).scenery
	_test_off_is_noop()
	_test_build()
	_test_determinism()
	_test_catalog_sizes()
	_test_models()
	_test_winding()
	_test_tiers()
	_test_themes()
	print("all scenery build checks passed" if _failures == 0 else "%d scenery build checks failed" % _failures)
	quit(1 if _failures > 0 else 0)


func _test_off_is_noop() -> void:
	var node := FieldBuilder.build(_field)
	_check("switch off: the field has no Scenery node", node.get_node_or_null("Scenery") == null)
	var rough := node.get_node_or_null("rough") as MeshInstance3D
	_check("switch off: the field owns the contiguous L7 ground independently of scenery",
		rough != null and rough.mesh is ArrayMesh and rough.mesh.get_surface_count() == 1
		and rough.mesh.get_aabb().size.x == 40000.0)
	node.free()


func _triangles(root: Node) -> int:
	var n := 0
	for c in root.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).mesh:
			var m := (c as MeshInstance3D).mesh
			for s in m.get_surface_count():
				n += m.surface_get_array_len(s) / 3
		elif c is MultiMeshInstance3D:
			var mm := (c as MultiMeshInstance3D).multimesh
			n += mm.instance_count * mm.mesh.surface_get_array_len(0) / 3
		n += _triangles(c) if c.get_child_count() > 0 else 0
	return n


func _test_build() -> void:
	var root := Scenery.build(_field, _scenery, OPTS)
	var stats: Dictionary = root.get_meta("stats")
	print("     stats: ", stats)
	_check("instances built (> 120)", int(stats.instances) > 120)
	_check("the parked fleet: 4 aircraft", int(stats.fleet) == 4)
	_check("moving parts: 4 rotors + 1 flag", int(stats.motion) == 5)
	_check("contact shadows for the near props", int(stats.shadows) > 50)
	_check("wildflowers placed", int(stats.flowers) > 2000)
	_check("compact cells (≤ 64 merged meshes)", int(stats.cells) <= 64)
	var cell_surfaces := 0
	for c in root.get_children():
		if c is MeshInstance3D and str(c.name).begins_with("cell_"):
			cell_surfaces += (c as MeshInstance3D).mesh.get_surface_count()
	_check("one surface per cell (one shared material)", cell_surfaces == int(stats.cells))
	var tris := _triangles(root)
	print("     triangles: %d, build %.1f ms" % [tris, stats.build_ms])
	_check("triangles within the scenery budget (%d)" % BUDGET_TRIANGLES, tris <= BUDGET_TRIANGLES, str(tris))
	_check("build time under %.0f ms on this CPU" % BUDGET_BUILD_MS, float(stats.build_ms) < BUDGET_BUILD_MS, str(stats.build_ms))
	for c in root.get_children():
		if c is GeometryInstance3D and (c as GeometryInstance3D).cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			_check("no engine shadow casting (0 shadow-pass draws)", false, str(c.name))
	root.free()


func _digest(root: Node) -> String:
	var bytes := PackedByteArray()
	for c in root.get_children():
		bytes.append_array(str(c.name).to_utf8_buffer())
		if c is MeshInstance3D and (c as MeshInstance3D).mesh:
			var m := (c as MeshInstance3D).mesh
			for s in m.get_surface_count():
				var a := m.surface_get_arrays(s)
				bytes.append_array((a[Mesh.ARRAY_VERTEX] as PackedVector3Array).to_byte_array())
				if a[Mesh.ARRAY_COLOR] != null:
					bytes.append_array((a[Mesh.ARRAY_COLOR] as PackedColorArray).to_byte_array())
		elif c is MultiMeshInstance3D:
			bytes.append_array((c as MultiMeshInstance3D).multimesh.buffer.to_byte_array())
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(bytes)
	return ctx.finish().hex_encode()


func _test_determinism() -> void:
	var a := Scenery.build(_field, _scenery, OPTS)
	var b := Scenery.build(_field, _scenery, OPTS)
	_check("two builds are byte-identical (no RNG, no clock)", _digest(a) == _digest(b))
	a.free()
	b.free()


func _test_catalog_sizes() -> void:
	for id: String in Prefabs.CATALOG:
		var spec: Dictionary = Prefabs.CATALOG[id]
		var k := MeshKit.new()
		Prefabs.build(id, k, 1234, "temperate")
		var box := AABB(k.verts[0], Vector3.ZERO)
		for v: Vector3 in k.verts:
			box = box.expand(v)
		var want: Vector3 = spec.size
		var tol := 0.3 if spec.get("variable", false) else 0.1
		var ok := true
		for i in 3:
			if absf(box.size[i] - want[i]) > maxf(tol * want[i], 0.1):
				ok = false
		_check("%s size %.2f × %.2f × %.2f m matches the catalog %s" % [id, box.size.x, box.size.y, box.size.z, want], ok)
		_check("%s has evidence (kind and source)" % id, ["borrowed", "estimated", "manual", "measured"].has(spec.kind) and not str(spec.source).is_empty())


func _test_models() -> void:
	for id: String in Models.CATALOG:
		var arr := Models.arrays(id)
		_check("model %s loads" % id, not arr.is_empty())
		if arr.is_empty():
			continue
		var box := AABB((arr.pos as PackedVector3Array)[0], Vector3.ZERO)
		for v: Vector3 in arr.pos:
			box = box.expand(v)
		var want: Vector3 = Models.CATALOG[id].size
		var ok := absf(box.size.z - want.z) < 0.02 * want.z + 0.01 and absf(box.size.y - want.y) < 0.03 * want.y + 0.02
		_check("model %s is %.2f × %.2f × %.2f m (catalog %s)" % [id, box.size.x, box.size.y, box.size.z, want], ok)
		_check("model %s rests on the ground" % id, absf(box.position.y) < 0.005)
		var bad := 0
		for n: Vector3 in arr.nrm:
			if absf(n.length() - 1.0) > 1e-3:
				bad += 1
		_check("model %s normals are unit length" % id, bad == 0, str(bad))
	for id: String in ["car_sedan", "car_hatch", "car_suv", "car_sport"]:
		var paint := 0
		for c: Color in Models.arrays(id).col:
			if c.a < 0.5:
				paint += 1
		_check("%s marks its paint for per-car colours" % id, paint > 100)


## Every emitted triangle (p0, p1, p2) must be clockwise from its normal's side: (p2 − p0) × (p1 − p0) · n > 0.
func _test_winding() -> void:
	var root := Scenery.build(_field, _scenery, OPTS)
	var bad := 0
	var total := 0
	for c in root.get_children():
		if c is MeshInstance3D and str(c.name).begins_with("cell_"):
			var a := (c as MeshInstance3D).mesh.surface_get_arrays(0)
			var p: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var n: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
			for i in range(0, p.size(), 3):
				var face := (p[i + 2] - p[i]).cross(p[i + 1] - p[i])
				if face.length_squared() < 1e-12:
					continue
				total += 1
				if face.dot(n[i]) <= 0.0:
					bad += 1
	_check("all %d cell triangles wind clockwise toward their normal (Godot front faces)" % total, bad == 0, "%d reversed" % bad)
	root.free()


func _test_tiers() -> void:
	var counts := {}
	for q: String in ["low", "balanced", "high"]:
		var r := Scenery.build(_field, _scenery, {audio = false, birds = false, theme = "", quality = q})
		counts[q] = r.get_meta("stats")
		r.free()
	_check("tiers: low < balanced < high instances", int(counts.low.instances) < int(counts.balanced.instances) and int(counts.balanced.instances) < int(counts.high.instances))
	_check("tiers: low keeps no ornamental flowers", int(counts.low.flowers) == 0)
	_check("tiers: every landmark survives low (rotors and flag)", int(counts.low.motion) == int(counts.high.motion))
	_check("tiers: balanced keeps a fixed half of the flowers", absf(float(counts.balanced.flowers) / float(counts.high.flowers) - 0.5) < 0.08)


func _test_themes() -> void:
	var t := Palette.veg("hedge", "temperate")
	var s := Palette.veg("hedge", "summer")
	var a := Palette.veg("hedge", "autumn")
	_check("themes recolour vegetation", not t.is_equal_approx(s) and not t.is_equal_approx(a))
	_check("summer is paler and drier (lower saturation)", s.s < t.s)
	var r := Scenery.build(_field, _scenery, {audio = false, birds = false, theme = "autumn", quality = "high"})
	_check("a themed build reports its theme", r.get_meta("stats").theme == "autumn")
	r.free()
