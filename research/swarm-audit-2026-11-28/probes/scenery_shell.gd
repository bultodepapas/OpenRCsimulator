extends SceneTree

const Collision := preload("res://sim/scenery_collision.gd")
const World := preload("res://scenery/collision_world.gd")
const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")

var failures := 0
var cases: Array[Dictionary] = []


func _initialize() -> void:
	var cube := _cube()
	_case("north entry with yaw", cube, 1.0, 0.000020, -0.009980, 0.0, 1.5, 0)
	_case("north entry without yaw", cube, 1.0, 0.000020, -0.009980, 0.0, 0.0, 1)
	_case("south entry with yaw", cube, -1.0, 0.000020, -0.009980, 0.0, 1.5, 0)
	_case("south entry without yaw", cube, -1.0, 0.000020, -0.009980, 0.0, 0.0, 1)
	_case("no crossing, moving outward", cube, 1.0, 0.000020, 0.010020, 0.0, 1.5, 0)
	_case("true initial overlap", cube, 1.0, -0.010, -0.020, 0.0, 1.5, 0)
	_case("entry starts beyond padded shell", cube, 1.0, 0.001, -0.009, 0.0, 1.5, 1)

	# Adjacent ticks have identical shared endpoint pose, velocity and rate. A constant
	# angular acceleration makes yaw increments 1.48 then 1.50 degrees over equal ticks.
	# At their join 84.5 um clears the smaller padding, but lies inside the larger one.
	_case("prior tick still clear", cube, 1.0, 0.0100845, 0.0000845, -1.48, 0.0, 0, 1.47, 1.49)
	_case("following tick crosses", cube, 1.0, 0.0000845, -0.0099155, 0.0, 1.50, 0, 1.49, 1.51)

	var field := {id = "shell-witness", pilot = {north = 0.0, east = 0.0, down = 0.0}, objects = []}
	var groups := [{id = "shed-witness", type = "instances", placements = [
		{north = 0.0, east = 0.0, heading = 37.0, prefab = "shed"}]}]
	var built := World.build(field, {groups = groups}, {fixtures = []})
	if built.ok and built.world.proxies.size() == 1:
		_case("authored 37-degree shed, entry with yaw", built.world, 1.0, 0.000020, -0.009980, 0.0, 1.5, 0)
		_case("authored 37-degree shed, entry without yaw", built.world, 1.0, 0.000020, -0.009980, 0.0, 0.0, 1)
	else:
		failures += 1
		print("Shed fixture build failed: ", built)
	print("SCENERY_SHELL ", JSON.stringify({cases = cases, failures = failures}))
	quit(0 if failures == 0 else 1)


func _cube() -> Dictionary:
	var proxies: Array[Dictionary] = []
	World._add_box_at_down(proxies, "audit-box", "building", "box", "hard_terminal",
		0.0, 0.0, 0.0, 2.0, 2.0, 2.0, 0.0)
	return {format = World.FORMAT, cell_size_m = World.CELL_SIZE_M, proxies = proxies, bins = World._build_bins(proxies)}


func _case(label: String, world: Dictionary, side: float, clearance0: float, clearance1: float,
		yaw0: float, yaw1: float, expected_count: int, rate0: float = NAN, rate1: float = NAN) -> void:
	var proxy: Dictionary = world.proxies[0]
	var direction := PackedFloat64Array([side * float(proxy.cos_heading), side * float(proxy.sin_heading), 0.0])
	var velocity := M.scale(direction, (clearance1 - clearance0) * 240.0)
	var before := _state(proxy, direction, clearance0, velocity, yaw0, yaw1 - yaw0 if is_nan(rate0) else rate0)
	var after := _state(proxy, direction, clearance1, velocity, yaw1, yaw1 - yaw0 if is_nan(rate1) else rate1)
	var hits := Collision.contacts(before, after, PackedFloat64Array([0.0, 0.0, 1.0]), world,
		1, 1.0, PackedFloat64Array([1.0, 1.0, 1.0, 0.0, 0.0, 0.0]))
	var fraction := -1.0
	if not hits.is_empty():
		fraction = hits[0].time_fraction
	var analytic_fraction := clearance0 / (clearance0 - clearance1) if clearance0 > 0 and clearance1 < 0 else -1.0
	var padding := Collision._rotational_chord_padding(RB._att(before), RB._att(after), 1.0)
	cases.append({label = label, contacts = hits.size(), returned_fraction = fraction,
		analytic_entry_fraction = analytic_fraction, padding_m = padding})
	if hits.size() != expected_count:
		failures += 1
	if expected_count == 1 and is_equal_approx(yaw0, yaw1) and absf(analytic_fraction - fraction) > 2e-7:
		failures += 1


func _state(proxy: Dictionary, direction: PackedFloat64Array, clearance: float, velocity: PackedFloat64Array,
		yaw_deg: float, yaw_deg_per_tick: float) -> PackedFloat64Array:
	var attitude := M.q_from_euler(deg_to_rad(yaw_deg), 0.0, 0.0)
	var position := M.add(PackedFloat64Array([proxy.north, proxy.east, float(proxy.down) - 1.0]),
		M.scale(direction, float(proxy.half_z) + clearance))
	return RB.make_state(position, M.q_rotate(M.q_conj(attitude), velocity), attitude,
		PackedFloat64Array([0.0, 0.0, deg_to_rad(yaw_deg_per_tick) * 240.0]))
