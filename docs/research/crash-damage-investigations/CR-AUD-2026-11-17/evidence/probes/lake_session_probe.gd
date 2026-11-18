extends SceneTree

# Baseline observation probe, not a test of a proposed water-contact law.
# Invoke with the app as the Godot project; do not copy into production sources.
const FieldLoader := preload("res://data/field_loader.gd")
const LakeWorld := preload("res://render/lake/lake_world.gd")
const LakeSurface := preload("res://physics/lake_surface.gd")
const Terrain := preload("res://physics/ground_terrain.gd")
const Quad := preload("res://sim/multirotor/session.gd")
const Blimp := preload("res://sim/airship/session.gd")
const FC := preload("res://physics/multirotor/flight_controller.gd")

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(label: String, condition: bool, detail: String = "") -> void:
	checks += 1
	if not condition:
		failures += 1
	print("%s %s %s" % ["PASS" if condition else "FAIL", label, detail])

func _finite3(v: PackedFloat64Array) -> bool:
	return v.size() == 3 and is_finite(v[0]) and is_finite(v[1]) and is_finite(v[2])

func _run() -> void:
	OS.set_environment("OPENRC_LAKE", "on")
	var loaded: Dictionary = FieldLoader.load_from()
	_check("default field loads", bool(loaded.get("ok", false)), str(loaded.get("errors", [])))
	if not loaded.get("ok", false):
		_finish()
		return
	var field: Dictionary = loaded.field
	# This is the same resolution policy used by FieldBuilder; no render scene is constructed here.
	var resolved: Dictionary = LakeWorld.resolve(field, {"enabled": true, "file_explicit": false})
	_check("default-field lake policy resolves an enabled lake", bool(resolved.get("ok", false)) \
		and bool(resolved.get("enabled", false)) and not resolved.get("lake", {}).is_empty(), str(resolved.get("errors", [])))
	if not resolved.get("ok", false) or resolved.get("lake", {}).is_empty():
		_finish()
		return
	var lake: Dictionary = resolved.lake
	var n := 110.0
	var e := 125.0
	var water: Dictionary = LakeSurface.sample_terrain_validated(lake, n, e)
	_check("sample point is submerged stock lake interior", water.get("region", "") == "bed" \
		and float(water.get("depth_m", 0.0)) > 0.0, str(water))
	var quad: Node = Quad.new()
	var blimp: Node = Blimp.new()
	root.add_child(quad)
	root.add_child(blimp)
	var q_ok: bool = quad.prepare(field, {"crash_model": "graded"})
	var b_ok: bool = blimp.prepare(field, {})
	_check("quad and blimp prepare with stock field", q_ok and b_ok,
		"quad=%s blimp=%s" % [quad.load_error, blimp.load_error])
	if q_ok and b_ok:
		for entry: Dictionary in [{"name": "quad", "session": quad}, {"name": "blimp", "session": blimp}]:
			var s: Node = entry.session
			var env: RefCounted = s.environment
			var dry: PackedFloat64Array = Terrain.sample_validated(n, e, env.surfaces)
			var with_lake: PackedFloat64Array = Terrain.sample_validated(n, e, env.surfaces, lake)
			var actual: PackedFloat64Array = env.ground(n, e)
			var dry_control: PackedFloat64Array = env.ground(15.0, 0.0)
			var label := str(entry.name)
			_check(label + " finite ground-query controls", _finite3(actual) and _finite3(dry) \
				and _finite3(with_lake) and _finite3(dry_control))
			_check(label + " prepared environment has no water provider", env.lake.is_empty() and env.water(n, e).is_empty())
			_check(label + " sees dry rather than lake-composed ground at the interior", \
				absf(actual[0] - dry[0]) < 1.0e-10 and absf(actual[0] - with_lake[0]) > 0.1,
				"n=%.1f e=%.1f actual=%s dry=%s lake=%s" % [n, e, actual, dry, with_lake])
		var q_query: PackedFloat64Array = quad.plant._ground_at(n, e)
		var b_query: PackedFloat64Array = blimp._ground.call(n, e)
		_check("vehicle contact callbacks use their dry session environment", _finite3(q_query) and _finite3(b_query) \
			and absf(q_query[0] - quad.environment.ground(n, e)[0]) < 0.00001 \
			and absf(b_query[0] - blimp.environment.ground(n, e)[0]) < 1.0e-10,
			"quad_contact=%s blimp_contact=%s" % [q_query, b_query])
		var q_tick: bool = quad.resume() and quad.tick_once(FC.neutral_input())
		var b_tick: bool = blimp.resume() and blimp.tick_once(PackedFloat64Array([0.0, 0.0, 0.0, 0.0]))
		_check("normal dry starts accept an ordinary tick", q_tick and b_tick \
			and quad.crash.is_empty() and blimp.crash.is_empty(),
			"quad_fault=%s blimp_fault=%s" % [quad.fault_reason, blimp.fault_reason])
		_check("normal session resets succeed", quad.reset_to_pad() and blimp.reset())
	quad.free()
	blimp.free()
	_finish()

func _finish() -> void:
	print("LAKE_SESSION_PROBE: %d checks, %d failed" % [checks, failures])
	quit(1 if failures > 0 else 0)
