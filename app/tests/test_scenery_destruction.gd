## CR-17a: shared fence/barrier geometry, local batch removal, aftermath budgets, pause and exact reset.
extends SceneTree
const Scenery := preload("res://scenery/scenery.gd")
const FenceParts := preload("res://scenery/fence_parts.gd")
const World := preload("res://scenery/collision_world.gd")
const Collision := preload("res://sim/scenery_collision.gd")
const Barrier := preload("res://render/flightline_barrier.gd")
const Batches := preload("res://scenery/damage_batches.gd")
const Presentation := preload("res://render/crash/scenery_damage.gd")
const Sim := preload("res://sim/simulation.gd")
const RB := preload("res://physics/rigid_body.gd")
const ShaderClock := preload("res://render/shader_clock.gd")

class SessionFixture extends Node:
	signal scenery_damage_changed
	var sim := Sim.new()
	var holds := {}
	var crash := {}
	var damage := {}
	func scenery_damage() -> Dictionary:
		return damage.duplicate(true)

class FlightFixture extends Node3D:
	var _field_node: Node3D
	var session := SessionFixture.new()

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	ShaderClock.register()
	_test_fence_contact()
	_test_open_gate()
	_test_stock_gate()
	_test_barrier_contact()
	_test_batches_and_effects()
	print("scenery destruction: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _field() -> Dictionary:
	return {pilot = {north = 0.0, east = 0.0, down = 0.0}, objects = [], flight_cues = []}

func _fence(style: String = "wire") -> Dictionary:
	return {id = "test", type = "fence", points = [Vector2(5, 0), Vector2(5, 9)], style = style, seed = 42, height = 1.25}

func _test_fence_contact() -> void:
	for style: String in ["wire", "rail", "barbed"]:
		var group := _fence(style)
		var world: Dictionary = World.build(_field(), {groups = [group]}).world
		var pieces := FenceParts.build(PackedVector2Array([Vector2(0, -5), Vector2(9, -5)]), style, 42)
		_check("%s every visible post/bay has a collision proxy" % style, pieces.size() == world.proxies.size())
		var ids := {}
		for proxy: Dictionary in world.proxies:
			_check("%s unique local IDs" % style, not ids.has(proxy.id))
			ids[proxy.id] = true
			_check("%s damage ID identifies exactly one piece" % style, proxy.damage_id == proxy.id)
		var height := 0.95 if style == "rail" else 0.85
		var hit := _hit(world, 1.5, height)
		_check("high-speed sweep hits %s at its actual visible height" % style, hit != null and hit.obstacle_kind == "fence")
		if hit != null:
			var damage := {hit.damage_id: _record(hit.damage_profile, hit.point_ned, "broken")}
			_check("destroyed local bay no longer collides", _hit(world, 1.5, height, damage) == null)
			_check("neighbour bay still collides", _hit(world, 4.5, height, damage) != null)
		_check("open air between rails stays clear", _hit(world, 1.5, 0.70) == null)

func _test_open_gate() -> void:
	var world: Dictionary = World.build(_field(), {groups = [_fence("gate")]}).world
	_check("vehicle passage is clear between the gateposts", _hit(world, 4.5, 0.80) == null)
	var post := _hit(world, 9.0, 1.58)
	_check("the limewashed gate pier has masonry contact above the leaf", post != null
		and post.damage_id == "fence:test:latch" and post.damage_profile == "masonry")
	var hit := Collision.first_hit(_state(8.0, -3.0, -1.36), _state(8.0, 2.0, -1.36),
		PackedFloat64Array([0,0,0]), world, 1, 2.0, PackedFloat64Array([1,1,1,0,0,0]))
	_check("open metal leaf stands inside the property", hit != null and hit.damage_id == "fence:test:leaf"
		and hit.damage_profile == "metal")
	var opening := Collision.first_hit(_state(12.3, -3.0, -0.79), _state(12.3, 2.0, -0.79),
		PackedFloat64Array([0,0,0]), world, 1, 2.0, PackedFloat64Array([1,1,1,0,0,0]))
	_check("a sweep between the open leaf's rails passes through air", opening == null)

func _test_stock_gate() -> void:
	var fence := _fence("stock_gate")
	fence.points = [Vector2(5, 0), Vector2(5, 4)]
	var world: Dictionary = World.build(_field(), {groups = [fence]}).world
	var hit := _hit(world, 2.0, 0.57)
	_check("stock gate planks have a wood leaf damage ID", hit != null
		and hit.damage_id == "fence:test:leaf" and hit.damage_profile == "wood")
	_check("stock gate has an opening between its planks", _hit(world, 0.85, 0.75) == null)
	var brace := _hit(world, 2.0, 0.755)
	_check("stock gate brace spans the middle opening", brace != null and brace.damage_id == "fence:test:leaf")
	if hit != null:
		var damage := {hit.damage_id: _record("wood", hit.point_ned, "broken")}
		_check("the broken wooden leaf clears the bay and leaves its jamb", _hit(world, 2.0, 0.57, damage) == null
			and _hit(world, 0.0, 1.4, damage) != null)

func _hit(world: Dictionary, east: float, height: float, damage: Dictionary = {}) -> RefCounted:
	return Collision.first_hit(_state(0, east, -height), _state(10, east, -height),
		PackedFloat64Array([0,0,0]), world, 1, 2.0, PackedFloat64Array([1,1,1,0,0,0]), damage)

func _state(north: float, east: float, down: float) -> PackedFloat64Array:
	return RB.make_state(PackedFloat64Array([north,east,down]), PackedFloat64Array([40,0,0]),
		PackedFloat64Array([1,0,0,0]), PackedFloat64Array([0,0,0]))

func _test_barrier_contact() -> void:
	var cue := {id = "flightline", type = "flightline_barrier", north = 5.0, east = 0.0, width = 12.0, gap_width = 2.0, height = 0.6}
	var field := _field()
	field.flight_cues = [cue]
	var built: Dictionary = World.build(field, {groups = []})
	_check("near-pilot barrier is in the production inventory", built.ok and not built.world.proxies.is_empty())
	_check("barrier central walking gap remains clear", _hit(built.world, 0.0, 0.225) == null)
	var hit := _hit(built.world, -3.0, 0.225)
	_check("barrier rail can be struck", hit != null and hit.damage_profile == "wood")
	var visual := Barrier.build(cue)
	var source := visual.get_node("Barrier") as MeshInstance3D
	var original: Mesh = source.mesh
	if hit != null:
		var piece := Batches.piece(source, hit.damage_id)
		_check("barrier contact ID owns visible geometry", not piece.is_empty())
		Batches.apply(source, {hit.damage_id: _record("wood", hit.point_ned, "broken")})
		_check("barrier damage removes only the struck rail", source.mesh.surface_get_array_len(0) == original.surface_get_array_len(0) - piece.verts.size())
		Batches.apply(source, {})
		_check("barrier reset restores the exact original resource", source.mesh == original)
	visual.free()

func _test_batches_and_effects() -> void:
	var field := _field()
	var scenery := {theme = "late_spring", groups = [_fence("rail"),
		{id = "tables", type = "instances", placements = [{prefab = "picnic_table", seed = 3, north = 12.0, east = 0.0, heading = 0.0}]}]}
	var scene := FlightFixture.new()
	scene._field_node = Scenery.build(field, scenery, {theme = "", quality = "high", audio = false, birds = false})
	scene.add_child(scene._field_node)
	scene.add_child(scene.session)
	root.add_child(scene)
	var director := Presentation.new()
	scene.add_child(director)
	director.configure(scene)
	var originals := {}
	for source: MeshInstance3D in director._sources:
		originals[source] = source.mesh
	var id := "prop:tables:00"
	scene.session.damage = {id: _record("wood", PackedFloat64Array([12,0,-0.7]), "broken")}
	scene.session.scenery_damage_changed.emit()
	_check("one committed failure creates one aftermath group", director._groups.size() == 1)
	var changed := 0
	for source: MeshInstance3D in director._sources:
		if source.mesh != originals[source]:
			changed += 1
	_check("destruction rebuilds only the affected cell", changed == 1)
	var shadow_nodes: Dictionary = scene._field_node.get_meta("directional_shadow_nodes")
	var shadow_triangles := 0
	for node: MeshInstance3D in shadow_nodes.values():
		shadow_triangles += node.mesh.get_surface_count()
	_check("broken table no longer casts its original contact shadow", shadow_triangles == 0)
	Scenery.update_lighting(scene._field_node, {sun_azimuth_deg = 110.0, sun_elevation_deg = 45.0, shadow_strength = 1.0})
	shadow_triangles = 0
	for node: MeshInstance3D in shadow_nodes.values():
		shadow_triangles += node.mesh.get_surface_count()
	_check("lighting changes do not resurrect a broken prop shadow", shadow_triangles == 0)
	director.sync()
	_check("repeated sync does not duplicate debris", director._groups.size() == 1)
	scene.session.holds.menu = true
	var age: float = director._groups[0].age
	director._process(0.1)
	_check("menu pause freezes debris and particles", director._groups[0].age == age and director._groups[0].particles.speed_scale == 0.0)
	scene.session.holds.clear()
	director._process(0.1)
	_check("resume advances aftermath", director._groups[0].age > age)
	for at: int in 30:
		director._spawn("mark%d" % at, _record("metal", PackedFloat64Array([12,0,-0.7]), "marked"), 0.0)
	_check("repeated impacts obey the effect group cap", director._groups.size() == Presentation.MAX_EFFECT_GROUPS)
	scene.session.damage = {}
	scene.session.scenery_damage_changed.emit()
	_check("reset removes every aftermath group", director._groups.is_empty())
	for source: MeshInstance3D in director._sources:
		_check("reset restores original cell mesh resources exactly", source.mesh == originals[source])
	scene.session.sim.free()
	scene.free()

func _record(profile: String, point: PackedFloat64Array, state: String) -> Dictionary:
	return {profile = profile, state = state, tick = 0, energy_j = 100.0, point_ned = point,
		normal_ned = PackedFloat64Array([-1,0,0]), velocity_ned = PackedFloat64Array([40,0,0]), obstacle_id = "test"}

func _check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)
