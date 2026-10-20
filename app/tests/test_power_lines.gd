extends SceneTree
const Power = preload("res://scenery/power_lines.gd")
const Kit = preload("res://scenery/mesh_kit.gd")
const Scenery = preload("res://scenery/scenery.gd")
const Loader = preload("res://scenery/scenery_loader.gd")
const Field = preload("res://data/field_loader.gd")
var failures := 0
func check(label: String, ok: bool) -> void:
	if not ok:
		failures += 1
		printerr("FAIL ", label)
	else:
		print("ok   ", label)
func _initialize() -> void:
	var tower := Power.tower_arrays()
	check("supplier topology retained: 5743 triangles", tower.pos.size() == 5743 * 3)
	check("uniformly scaled tower height 30 m", absf(tower.size.y - 30.0) < 0.001)
	check("measured tower footprint", absf(tower.size.x - 8.652) < 0.01 and absf(tower.size.z - 8.450) < 0.01)
	var field: Dictionary = Field.load_from(Field.DEFAULT_PATH).field
	var scene: Dictionary = Loader.load_from(Loader.DEFAULT_PATH, field).scenery
	var pylons: Array = []
	for group: Dictionary in scene.groups:
		if group.id == "pylons":
			pylons = group.placements
	check("five existing placement identities retained", pylons.size() == 5)
	var profile: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Power.CABLE_DATA))
	check("downloaded span topology retained", profile.triangles.size() == 128 * 3)
	check("Godot winding declared", profile.transform.godot_clockwise)
	var kit := Kit.new()
	for i in pylons.size() - 1:
		var a: Dictionary = pylons[i]
		var b: Dictionary = pylons[i + 1]
		var ax := Scenery._placement_xf(a.north, a.east, a.heading)
		var bx := Scenery._placement_xf(b.north, b.east, b.heading)
		var route := (bx.origin - ax.origin).normalized()
		check("crossarms transverse to route %d" % i, absf(ax.basis.x.dot(route)) < 0.06)
		var before := kit.verts.size()
		Power.append_span(kit, ax, bx)
		check("seven complete conductors per span %d" % i, kit.verts.size() - before == 7 * 128 * 3)
	check("bounded full route: 3584 cable triangles", kit.verts.size() / 3 == 3584)
	var low := 1000.0
	var high := -1000.0
	var valid := true
	for v: Vector3 in kit.verts:
		valid = valid and v.is_finite()
		low = minf(low, v.y)
		high = maxf(high, v.y)
	check("finite imported world geometry", valid)
	check("sag remains above ground and below tower tops", low > 12.0 and low < 16.0 and high < 30.1)
	var clone := Kit.new()
	Power.append_tower(clone)
	check("cached source deterministic", clone.verts.slice(0, tower.pos.size()) == tower.pos)
	check("six downloaded insulators on each tower", clone.verts.size() == (5743 + 6 * 1488) * 3)
	print("all power-line checks passed" if failures == 0 else "%d power-line failures" % failures)
	quit(0 if failures == 0 else 1)
