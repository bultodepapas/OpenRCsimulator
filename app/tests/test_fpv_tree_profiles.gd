extends SceneTree

const Forest := preload("res://scenery/fpv_forest.gd")
const World := preload("res://scenery/collision_world.gd")
const Field := preload("res://data/field_loader.gd")
const Session := preload("res://sim/multirotor/session.gd")

var failures := 0


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _initialize() -> void:
	var field := Field.load_from(Field.DEFAULT_PATH)
	var built := World.build(field.field, {groups = []}, {})
	var stock := Forest.project(built.world)
	_check(stock.ok and stock.foliage.size() == 1680, "every near and far field tree has an FPV leaf volume")
	var valid := true
	for shape: Dictionary in stock.solids:
		if shape.kind == "tree_trunk":
			valid = valid and World._proxy_is_valid(shape) and not str(shape.id).ends_with(":trunk")
	_check(valid, "all stock stems have valid fitted geometry")

	# A rotated 20 m pine with its base 3 m above the datum. The old hard trunk ended at 6.8 m.
	var proxies: Array[Dictionary] = []
	World._add_field_tree_proxies(proxies, "test:0000", 100.0, 50.0, -3.0, 20.0, 2, PI / 2.0)
	var source := {identity = "fixture-v1", proxies = proxies}
	var projected := Forest.project(source)
	_check(projected.ok and projected.foliage.size() == 1, "exactly one pine foliage volume")
	if projected.ok and projected.foliage.size() == 1:
		var high_stem := false
		for shape: Dictionary in projected.solids:
			if shape.bounds_down_min < -12.0 and shape.bounds_down_max > -12.0:
				high_stem = high_stem or Vector2(shape.north - 100.0, shape.east - 50.0).length() < shape.radius
		_check(high_stem, "source pine stem crosses its root axis at 45% height inside the crown")
		var crown: Dictionary = projected.foliage[0]
		# The source pine has a needle cluster on its +X limb and an open corner at the high outer edge.
		# With a quarter turn +X is south and +Z west. The query must follow the oriented source.
		_check(Forest.density_at(crown, 97.02, 49.87, -11.75) > 0.75, "rotated pine has needles on its source limb")
		_check(Forest.density_at(crown, 103.69, 53.79, -16.75) == 0.0, "open air inside the old solid crown box")
		_check(Forest.density_at(crown, 100.0, 50.0, -4.0) == 0.0, "bare stem below the needles gives no leaf drag")
		var original_identity: String = projected.identity
		proxies[1].fpv_tree[5] += 15.0
		_check(Forest.project(source).identity != original_identity, "changing the FPV transform changes its identity")
		_check(not proxies[1].has("grid_bytes"), "FPV preparation leaves the shared proxy untouched")

	var synthetic: Array[Dictionary] = []
	World._add_capsule(synthetic, "person", "person", "person", "soft_foliage_impulse", 1, 2, 3, 0.25, 0.5)
	var person := Forest.project({identity = "people", proxies = synthetic})
	_check(person.solids.size() == 1 and person.foliage.is_empty() and person.identity == "people",
		"the foliage response assigned to a person does not opt it into forest contact")
	World._add_box_at_down(synthetic, "hedge", "tree_foliage", "hedge", "soft_foliage_impulse", 0, 0, -1, 1, 2, 5, 0)
	synthetic[0]["tags"] = ["before"]
	var detached := Forest.project({identity = "fixture", proxies = synthetic})
	synthetic[0].tags[0] = "after"
	synthetic[1].half_x = 3.0
	_check(detached.solids[0].tags[0] == "before" and detached.foliage[0].half_x == 0.5,
		"installed solids and unprofiled crowns remain detached from the input")
	_test_source_limbs()
	print("FPV tree profile failures: %d" % failures)
	quit(0 if failures == 0 else 1)


func _test_source_limbs() -> void:
	# Independent +X rays through the source bark triangles at (y,z), normalized to specimen height.
	# For maple, oak and beech the intersected limb intervals are [-.05569,-.02214],
	# [.02462,.05391], [.01294,.02722]. The offset samples fall outside all wood on their ray.
	var probes := {
		"maple_tree": [-0.0389, 0.274, 0.005], "landscapelab_quercus": [0.0393, 0.246, -0.032],
		"landscapelab_fagus": [0.0201, 0.328, 0.04], "landscapelab_pine": [0.0315, 0.509, 0.007],
		"landscapelab_quercus2": [0.0199, 0.391, 0.03],
	}
	for species: String in probes:
		var proxies: Array[Dictionary] = []
		World._add_field_detail_tree_proxies(proxies, "specimen", 10.0, 11.0, -2.0, 10.0, species, 90.0, 0)
		var projected := Forest.project({identity = species, proxies = proxies})
		var sample: Array = probes[species]
		var north := 10.0 - 10.0 * float(sample[0])
		var east := 11.0 - 10.0 * float(sample[2])
		var down := -2.0 - 10.0 * float(sample[1])
		var hits_limb := false
		var gap := INF
		var bounds_ok := true
		var count := 0
		for proxy: Dictionary in projected.solids:
			gap = minf(gap, Session._clearance(proxy, north - 0.20, east, down))
			if proxy.part != "branch":
				continue
			count += 1
			if Session._clearance(proxy, north, east, down) < 0.0:
				hits_limb = true
				bounds_ok = bounds_ok and World._aabb_sphere_overlap(proxy, north, east, down, 0.0)
		_check(hits_limb and gap > 0.0, "%s matches the off-axis source branch and adjacent gap" % species)
		_check(bounds_ok and count <= 18, "%s keeps measured limb contacts inside its bounded index" % species)
