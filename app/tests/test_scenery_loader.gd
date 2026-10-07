# SCENERY-PLAN SC-02: the scenery loader accepts the committed layout and refuses every rule violation.
# Run: godot --headless --path . --script res://tests/test_scenery_loader.gd
extends SceneTree

const Loader = preload("res://scenery/scenery_loader.gd")
const FieldLoader = preload("res://data/field_loader.gd")
const Scenery = preload("res://scenery/scenery.gd")

var _failures := 0
var _field: Dictionary
var _raw: Dictionary


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _initialize() -> void:
	_field = FieldLoader.load_from(FieldLoader.DEFAULT_PATH).field
	_raw = JSON.parse_string(FileAccess.get_file_as_string(Loader.DEFAULT_PATH))
	var loaded := Loader.validate(_raw.duplicate(true), _field)
	_check("committed default.json validates against the default field", loaded.ok, str(loaded.errors))
	_check("it has groups", loaded.ok and (loaded.scenery.groups as Array).size() >= 30)
	_check("load_from reads the same file", Loader.load_from(Loader.DEFAULT_PATH, _field).ok)
	_check("a missing file is refused", not Loader.load_from("res://data/scenery/missing.json", _field).ok)
	_mutations()
	_switch()
	_layout_current()
	print("all scenery loader checks passed" if _failures == 0 else "%d scenery loader checks failed" % _failures)
	quit(1 if _failures > 0 else 0)


func _group(id: String) -> Dictionary:
	for g: Dictionary in _raw.groups:
		if g.id == id:
			return g
	return {}


## Applies `edit` to a deep copy and expects the loader to refuse it with an error containing `needle`.
func _refuse(label: String, edit: Callable, needle: String) -> void:
	var copy: Dictionary = _raw.duplicate(true)
	edit.call(copy)
	var r := Loader.validate(copy, _field)
	var hit := false
	for e: String in r.errors:
		if e.contains(needle):
			hit = true
	_check("refused: " + label, not r.ok and hit, "errors: %s" % [r.errors])


func _set_placement(copy: Dictionary, id: String, row: Array) -> void:
	for g: Dictionary in copy.groups:
		if g.id == id:
			g.placements.value = [row]


func _mutations() -> void:
	_refuse("unknown format", func(c: Dictionary) -> void: c.format = "openrc-scenery v0", "format")
	_refuse("another field's data", func(c: Dictionary) -> void: c.field = "elsewhere", "field")
	_refuse("unknown theme", func(c: Dictionary) -> void: c.theme = "winter", "theme")
	_refuse("unknown prefab", func(c: Dictionary) -> void: c.groups[0].prefab = "castle", "unknown prefab")
	_refuse("collides = true (L14 owns collisions)", func(c: Dictionary) -> void: c.groups[0].collides = true, "visual only")
	_refuse("duplicate group id", func(c: Dictionary) -> void: c.groups[1].id = c.groups[0].id, "duplicate")
	_refuse("no groups", func(c: Dictionary) -> void: c.groups = [], "groups")
	_refuse("wrong unit", func(c: Dictionary) -> void: c.profile.pits_min_behind_m.unit = "ft", "unit")
	_refuse("unknown evidence kind", func(c: Dictionary) -> void: c.profile.approach_slope.kind = "guess", "kind")
	_refuse("missing source", func(c: Dictionary) -> void: c.profile.tree_clearance_m.source = " ", "source")
	_refuse("a non-numeric coordinate", func(c: Dictionary) -> void: _set_placement(c, "pavilion", ["x", 0.0, 0.0]), "non-finite")
	_refuse("a prop on the runway", func(c: Dictionary) -> void: _set_placement(c, "benches", [15.0, 0.0, 0.0]), "runway")
	_refuse("pits too close to the safety line", func(c: Dictionary) -> void: _set_placement(c, "pits-people", [-1.0, -31.0, 0.0]), "pits zone")
	_refuse("pits too close to the take-off path (BMFA)", func(c: Dictionary) -> void: _set_placement(c, "pit-shelters", [-12.0, -31.0, 0.0]), "take-off path")
	_refuse("parking too close", func(c: Dictionary) -> void: _set_placement(c, "cars", [-10.0, 0.0, 180.0]), "parking")
	_refuse("a tall prop in the flight box", func(c: Dictionary) -> void: _set_placement(c, "farm-barn", [120.0, 40.0, 0.0]), "flight box")
	_refuse("above the approach surface", func(c: Dictionary) -> void: _set_placement(c, "farm-silo", [15.0, 80.0, 0.0]), "approach surface")
	_refuse("a landmark closer than 1 km", func(c: Dictionary) -> void: _set_placement(c, "church", [600.0, -100.0, 0.0]), "closer than 1 km")
	_refuse("a landmark beyond 5 km (SC-01 depth rule)", func(c: Dictionary) -> void: _set_placement(c, "church", [0.0, -5600.0, 0.0]), "beyond 5 km")
	var tree: Array = _field.objects[0].positions[0]
	_refuse("a prop on a treeline tree", func(c: Dictionary) -> void: _set_placement(c, "tractor", [tree[0], tree[1], 0.0]), "treeline tree")
	_refuse("an unknown fence style", func(c: Dictionary) -> void:
		for g: Dictionary in c.groups:
			if g.type == "fence":
				g.style = "electric", "style")
	_refuse("an unknown track surface", func(c: Dictionary) -> void:
		for g: Dictionary in c.groups:
			if g.type == "track":
				g.surface = "tarmac", "surface")
	_refuse("flowers on the runway", func(c: Dictionary) -> void:
		for g: Dictionary in c.groups:
			if g.type == "flowers":
				g.positions.value = [[15.0, 0.0, 0.3]], "runway")
	_refuse("a fleet aircraft without a baked model", func(c: Dictionary) -> void:
		for g: Dictionary in c.groups:
			if g.type == "fleet":
				g.aircraft = ["unknown-aircraft"], "baked fleet model")


## The committed layout must be what tools/scenery/place.py writes today (no hand edits to generated data).
func _layout_current() -> void:
	var tool := ProjectSettings.globalize_path("res://").path_join("../tools/scenery/place.py").simplify_path()
	if not FileAccess.file_exists(tool):
		_check("tools/scenery/place.py present", false, tool)
		return
	var out: Array = []
	var code := OS.execute("python3", [tool, "--check"], out, true)
	_check("app/data/scenery/default.json matches tools/scenery/place.py", code == 0, str(out))


func _switch() -> void:
	_check("scenery is off by default (Gate SC)", not Scenery.enabled())
	OS.set_environment("OPENRC_SCENERY", "on")
	_check("OPENRC_SCENERY=on turns it on", Scenery.enabled())
	OS.set_environment("OPENRC_SCENERY_QUALITY", "low")
	_check("OPENRC_SCENERY_QUALITY is read", Scenery.options().quality == "low")
	OS.unset_environment("OPENRC_SCENERY")
	OS.unset_environment("OPENRC_SCENERY_QUALITY")
	_check("and off again without it", not Scenery.enabled())
