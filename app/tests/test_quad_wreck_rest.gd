## CR-AUD-20 regression: a quad that crashes onto a flat roof (terminal obstacle strike) rests on it for 10 s of
## aftermath ticks: never inside the solid, no perpetual hop or spin (Good Enemy review of R2).
extends SceneTree

const Session := preload("res://sim/multirotor/session.gd")
const CollisionWorld := preload("res://scenery/collision_world.gd")
const FC := preload("res://physics/multirotor/flight_controller.gd")
const Plant := preload("res://physics/multirotor/controlled_plant.gd")
const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")
const ALT := 30.0
const ROOF_TOP_DOWN := -28.0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var proxies: Array[Dictionary] = []
	CollisionWorld._add_box_at_down(proxies, "scratch:roof", "building", "roof", "hard_terminal",
		0.0, 0.0, ROOF_TOP_DOWN + 1.0, 20.0, 2.0, 20.0, 0.0)
	var world := {"format": CollisionWorld.FORMAT, "identity": "scratch-roof", "cell_size_m": CollisionWorld.CELL_SIZE_M,
		"proxies": proxies, "bins": CollisionWorld._build_bins(proxies)}
	var s: Node = Session.new()
	root.add_child(s)
	var ok: bool = s.prepare({}, {"crash_model": "graded", "start": "air", "altitude_m": ALT, "north_offset_m": 0.0,
		"east_offset_m": 0.0, "heading_deg": 0.0}) and s.set_collision_world(world)
	var pilot: PackedFloat64Array = FC.neutral_input(0)
	var frame: Dictionary = s.frame()
	var body: PackedFloat64Array = frame.body
	body[RB.VEL + 2] = 12.0
	frame.body = body
	var continuous: PackedFloat64Array = frame.continuous
	for rotor in 4:
		continuous[Plant.C_SPEED + rotor] = 0.0
	frame.continuous = continuous
	var reset: Dictionary = s.sim.prepare_reset_frame(frame, pilot)
	ok = ok and bool(reset.get("ok", false)) and s.sim.commit_prepared_reset_frame(reset) and s.resume()
	var accepted := 0
	var lowest_bottom := -INF
	var late_speed := 0.0
	var half: PackedFloat64Array = s.plant._frame_box_half
	for tick in 2400:
		if not s.tick_once(pilot):
			break
		accepted += 1
		var b: PackedFloat64Array = s.sim.state
		var q := RB._att(b)
		var extent := 0.0
		for i in 3:
			var axis := M.q_rotate(q, [M.v3(1, 0, 0), M.v3(0, 1, 0), M.v3(0, 0, 1)][i])
			extent += half[i] * absf(axis[2])
		var centre: PackedFloat64Array = M.add(RB._slice3(b, RB.POS), M.q_rotate(q, s.plant._frame_box_centre))
		lowest_bottom = maxf(lowest_bottom, centre[2] + extent)
		if tick >= 1200:
			late_speed = maxf(late_speed, M.norm(RB._slice3(b, RB.VEL)))
	var below_mm := 1000.0 * (lowest_bottom - ROOF_TOP_DOWN)
	var failures := 0
	for item: Array in [
			["session prepares, installs the roof and resumes", ok],
			["all 2400 ticks accepted without a fault", accepted == 2400 and s.sim.fault_reason.is_empty()],
			["the roof strike is a terminal obstacle crash", str(s.crash.get("reason", "")) == "Obstacle strike"],
			["the wreck never sinks more than 1 mm into the roof", below_mm <= 1.0],
			["the wreck comes to rest (late speed below 0.05 m/s)", late_speed < 0.05]]:
		print("%s %s" % ["ok  " if item[1] else "FAIL", item[0]])
		if not item[1]:
			failures += 1
	print("quad wreck rest: 5 checks, %d failed (deepest %.3f mm below roof, late speed %.4f m/s)" % [failures, below_mm, late_speed])
	s.free()
	quit(1 if failures > 0 else 0)
