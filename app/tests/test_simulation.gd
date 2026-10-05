# C5: interpolation between physics steps, and pausing on focus loss.
# Run: godot --headless --path . --script res://tests/test_simulation.gd
extends SceneTree

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const Sim := preload("res://sim/simulation.gd")

var _failures := 0
var _count := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _initialize() -> void:
	var sim: Node = Sim.new()
	root.add_child(sim)
	sim.reset(RB.make_state(M.v3(0, 0, -20), M.v3(15, 0, 0), M.q_identity(), M.v3(0.5, 0.2, 0.1)))
	sim.step()
	var prev: PackedFloat64Array = sim.previous
	var cur: PackedFloat64Array = sim.state

	# Interpolation endpoints and midpoint.
	var i0: PackedFloat64Array = sim.interpolated(0.0)
	var i1: PackedFloat64Array = sim.interpolated(1.0)
	var ih: PackedFloat64Array = sim.interpolated(0.5)
	var ok0 := true
	var ok1 := true
	for k in 3:
		ok0 = ok0 and absf(i0[RB.POS + k] - prev[RB.POS + k]) < 1e-12
		ok1 = ok1 and absf(i1[RB.POS + k] - cur[RB.POS + k]) < 1e-12
	_check("fraction 0 = previous position", ok0)
	_check("fraction 1 = current position", ok1)
	_check("fraction 0.5 = midpoint", absf(ih[RB.POS] - 0.5 * (prev[RB.POS] + cur[RB.POS])) < 1e-12)
	var qn := ih[RB.ATT] ** 2 + ih[RB.ATT + 1] ** 2 + ih[RB.ATT + 2] ** 2 + ih[RB.ATT + 3] ** 2
	_check("interpolated attitude is unit", absf(qn - 1.0) < 1e-12, str(qn))

	# Shortest path: q and -q are the same attitude; interpolating must not swing through 360°.
	sim.state[RB.ATT] *= -1.0
	sim.state[RB.ATT + 1] *= -1.0
	sim.state[RB.ATT + 2] *= -1.0
	sim.state[RB.ATT + 3] *= -1.0
	var mid: PackedFloat64Array = sim.interpolated(0.5)
	var dot := absf(mid[RB.ATT] * prev[RB.ATT] + mid[RB.ATT + 1] * prev[RB.ATT + 1] + mid[RB.ATT + 2] * prev[RB.ATT + 2] + mid[RB.ATT + 3] * prev[RB.ATT + 3])
	_check("nlerp takes the shortest path", dot > 0.999, str(dot))

	# Pause on focus loss; no automatic resume.
	var t_before: int = sim.tick
	sim._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check("focus loss pauses", sim.paused)
	sim._physics_process(sim.dt())
	_check("paused: no step", sim.tick == t_before)
	sim._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	_check("focus back: still paused (explicit resume only)", sim.paused)
	sim.set_paused(false)
	sim._physics_process(sim.dt())
	_check("resumed: steps again", sim.tick == t_before + 1)

	# stop_at_tick ends a run exactly.
	sim.stop_at_tick = sim.tick
	sim._physics_process(sim.dt())
	_check("stop_at_tick holds", sim.tick == t_before + 1)

	_check("240 Hz physics tick", sim.dt() == 1.0 / 240.0, str(sim.dt()))

	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)
