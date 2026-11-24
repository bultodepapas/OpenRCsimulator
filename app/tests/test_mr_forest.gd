## Exercise the actual quad preparation, contact laws and rollbackable flight state.
extends SceneTree

const Session := preload("res://sim/multirotor/session.gd")
const World := preload("res://scenery/collision_world.gd")
const FC := preload("res://physics/multirotor/flight_controller.gd")
const Plant := preload("res://physics/multirotor/controlled_plant.gd")
const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")
const Fixtures := preload("res://tests/mr_fixtures.gd")
var _failures := 0


func _check(label_text: String, passed: bool) -> void:
	print("ok " if passed else "FAIL ", label_text)
	if not passed:
		_failures += 1


func _initialize() -> void:
	_run.call_deferred()


func _world(with_trunk: bool) -> Dictionary:
	var proxies: Array[Dictionary] = []
	World._add_box_at_down(proxies, "leaves", "tree_foliage", "crown", "soft_foliage_impulse",
		0, 0, -10, 6, 6, 6, 0)
	if with_trunk:
		World._add_capsule(proxies, "stem", "tree_trunk", "trunk", "hard_terminal", 0, 0, -10, 0.14, 2.8)
	return {format = World.FORMAT, identity = "test-forest-" + str(with_trunk), cell_size_m = World.CELL_SIZE_M,
		proxies = proxies, bins = World._build_bins(proxies)}


func _fly(world: Dictionary, mode: String, east: float) -> Dictionary:
	var session := Session.new()
	root.add_child(session)
	var ok := session.set_collision_world(world) and session.prepare({}, {crash_model = mode, start = "air",
		north_offset_m = -4.0, east_offset_m = east, altitude_m = 10.0})
	var mark: Dictionary = session.checkpoint()
	if ok:
		mark.kernel.state[RB.VEL] = 22.0
		mark.kernel.previous = mark.kernel.state.duplicate()
		ok = session.restore_checkpoint(mark) and session.resume()
	var inside := {}
	var input := FC.neutral_input()
	const TICKS := 108
	const MARK_STEP := 40
	for step in TICKS:
		if not ok or not session.crash.is_empty():
			break
		ok = session.tick_once(input)
		if step == MARK_STEP:
			inside = session.checkpoint()
	var result := {ok = ok, body = session.sim.state.duplicate(), reason = str(session.crash.get("reason", "")),
		health = session.sim.continuous.slice(Plant.C_HEALTH, Plant.C_HEALTH + 4), repeatable = false}
	if ok and result.reason == "" and not inside.is_empty():
		ok = session.restore_checkpoint(inside) and session.resume()
		for _step in TICKS - MARK_STEP - 1:
			ok = ok and session.tick_once(input)
		result.repeatable = ok and session.sim.state.to_byte_array() == result.body.to_byte_array()
	session.free()
	return result


## Both endpoints of the nominal 40 m/s tick lie outside the thin board. The front of the frame encounters
## its near face after only about 5 cm. No arm end can enter the downstream leaves on the accepted path.
func _board_tick(mode: String, leaves: String) -> Dictionary:
	var proxies: Array[Dictionary] = []
	World._add_box_at_down(proxies, "board", "fixture", "board", "hard_terminal", 0.14, 0, -10, 1.0, 1.0, 0.012, 0)
	if leaves != "none":
		var north := 0.33 if leaves == "beyond" else -0.05
		World._add_box_at_down(proxies, "leaves", "tree_foliage", "hedge", "soft_foliage_impulse",
			north, 0.08, -10, 0.18, 0.6, 0.36, 0)
	var world := {format = World.FORMAT, identity = "board-" + leaves, cell_size_m = World.CELL_SIZE_M,
		proxies = proxies, bins = World._build_bins(proxies)}
	var s := Session.new()
	root.add_child(s)
	var ok := s.set_collision_world(world) and s.prepare({}, {prepared_data = Fixtures.electric(), crash_model = mode,
		start = "air", north_offset_m = 0.0, east_offset_m = 0.0, altitude_m = 10.0, heading_deg = 0.0})
	if ok:
		var mark: Dictionary = s.checkpoint()
		mark.kernel.state[RB.VEL] = 40.0
		mark.kernel.state[RB.VEL + 1] = 6.0
		mark.kernel.previous = mark.kernel.state.duplicate()
		for i in 4:
			mark.kernel.continuous[i] = 0.0
		ok = s.restore_checkpoint(mark) and s.resume() and s.tick_once(FC.neutral_input())
	var result := {ok = ok and s.crash.get("reason") == "Obstacle strike", frame = s.frame()}
	s.free()
	return result


## Uniform occupancy in still foliage reduces to dv/dt = -k*v²/m for a level, symmetric quad.
func _leaf_refinement() -> void:
	var s := Session.new()
	root.add_child(s)
	if not s.prepare({}, {prepared_data = Fixtures.electric()}):
		_check("symmetric foliage fixture prepares", false)
		s.free()
		return
	s.plant.foliage_density = func(_body: PackedFloat64Array, _q: PackedFloat64Array) -> PackedFloat64Array:
		return PackedFloat64Array([1, 1, 1, 1])
	var duration := 0.25
	var speed := 12.0
	var expected: float = speed / (1.0 + Plant.FOLIAGE_DRAG_KG_PER_M * speed * duration / float(s.data.mass_kg))
	var errors := PackedFloat64Array()
	for pieces: int in [60, 120, 240]:
		var body := RB.make_state(M.v3(0, 0, -10), M.v3(speed, 0, 0), M.q_identity(), M.v3(0, 0, 0))
		var continuous: PackedFloat64Array = s.plant.initial_frame(body).continuous
		for _i in pieces:
			body = s.plant._foliage_arrival(body, body, continuous, duration / pieces)
		errors.append(absf(body[RB.VEL] - expected))
	_check("uniform leaf drag converges to the analytic coast-down at h, h/2 and h/4",
		errors[0] < 0.01 and errors[1] < 0.52 * errors[0] and errors[2] < 0.52 * errors[1])
	s.free()


func _run() -> void:
	for mode: String in ["strict", "graded"]:
		var board := _board_tick(mode, "none")
		var beyond := _board_tick(mode, "beyond")
		var incoming := _board_tick(mode, "incoming")
		_check("%s leaves beyond the actual wood contact have zero effect on the entire accepted frame" % mode,
			board.ok and beyond.ok and var_to_bytes(board.frame) == var_to_bytes(beyond.frame))
		_check("%s brush on the incoming side changes both speed and yaw before the wood response" % mode,
			board.ok and incoming.ok and absf(incoming.frame.body[RB.VEL + 1] - board.frame.body[RB.VEL + 1]) > 1e-5
			and absf(incoming.frame.body[RB.RATE + 2] - board.frame.body[RB.RATE + 2]) > 1e-4)
		var air := _fly({}, mode, 0.0)
		var leaves := _fly(_world(false), mode, 0.0)
		_check("%s crosses a 6 m crown and exits moving forward" % mode, leaves.ok and leaves.reason == ""
			and leaves.body[RB.POS] > 3.0 and leaves.body[RB.VEL] > 0.0)
		_check("%s loses speed to leaf drag while all props survive" % mode, air.ok
			and air.body[RB.VEL] - leaves.body[RB.VEL] > 0.1
			and leaves.health == PackedFloat64Array([1, 1, 1, 1]))
		_check("%s restores a mid-crown checkpoint exactly" % mode, leaves.repeatable)
		var wood := _fly(_world(true), mode, 0.0)
		_check("%s hits the stem inside the crown, on its approach side" % mode,
			wood.ok and wood.reason == "Obstacle strike" and wood.body[RB.POS] < -0.13)
		var gap := _fly(_world(true), mode, 4.0)
		var clear := _fly({}, mode, 4.0)
		_check("%s clear passage gives identical flight state" % mode,
			gap.ok and gap.reason == "" and gap.body.to_byte_array() == clear.body.to_byte_array())

	var s := Session.new()
	root.add_child(s)
	if s.prepare({}):
		var force := M.v3(0, 0, 0)
		var moment := M.v3(0, 0, 0)
		var velocity := M.v3(12, 0, 0)
		var rates := M.v3(1, -2, 3)
		s.plant._apply_foliage_drag(PackedFloat64Array([1, 0, 0, 0]), velocity, rates, force, moment)
		_check("one-sided leaf brush produces torque and dissipates mechanical power",
			M.norm(moment) > 0.01 and M.dot(force, velocity) + M.dot(moment, rates) < 0.0)
	else:
		_check("quad prepared", false)
	s.free()
	_leaf_refinement()
	print("FPV forest flight: %d failed" % _failures)
	quit(1 if _failures else 0)
