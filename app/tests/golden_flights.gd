# Golden flights (D8a, formerly E4): record the per-tick inputs of a scripted maneuver and checkpoints of its state;
# replaying the inputs must reproduce the checkpoints. The regression test for every later physics change: a
# deliberate change re-records the goldens (tests/record_golden.gd) with a note in the commit; an accidental one
# fails test_golden.gd. Format "openrc-golden v1" (JSON, full float precision).
extends RefCounted

const Maneuvers := preload("res://sim/maneuvers.gd")
const RB := preload("res://physics/rigid_body.gd")

const FORMAT := "openrc-golden v1"
const DIR := "res://tests/golden/"
const NAMES := ["roll_15", "pull_throttle", "rudder_doublet", "glide_15"]
const CHECKPOINT_EVERY := 60 # ticks (0.25 s)
## Replay tolerances: generous against libm differences between machines, far below any physics change.
const TOL_POS := 1e-6 # m
const TOL_VEL := 1e-6 # m/s
const TOL_ATT := 1e-9 # quaternion components
const TOL_RATE := 1e-6 # rad/s


## Flies a maneuver and returns its golden record.
static func record(session: Node, name: String) -> Dictionary:
	var m: Dictionary = Maneuvers.all()[name]
	var trace: RefCounted = Maneuvers.fly(session, m)
	var inputs := []
	var checkpoints := []
	var last := []
	var n: int = trace.row_count()
	for r in n:
		# The input applied DURING the step that produced row r + 1 is logged on that row; row 0 holds the start.
		var row := [r, trace.value(r, "cmd_roll"), trace.value(r, "cmd_pitch"), trace.value(r, "cmd_yaw"), trace.value(r, "cmd_throttle")]
		if r > 0 and row.slice(1) != last:
			inputs.append(row)
			last = row.slice(1)
		elif r == 0:
			last = row.slice(1)
			inputs.append(row)
		if r % CHECKPOINT_EVERY == 0 or r == n - 1:
			checkpoints.append([r] + Array(_state(trace, r)))
	return { format = FORMAT, maneuver = name, mode = m.mode, speed = m.speed, ticks = n - 1, inputs = inputs, checkpoints = checkpoints,
		note = "Recorded by tests/record_golden.gd; re-record only for a deliberate physics change." }


static func _state(trace: RefCounted, r: int) -> PackedFloat64Array:
	var s := PackedFloat64Array()
	for c in ["north_m", "east_m", "down_m", "u_mps", "v_mps", "w_mps", "qw", "qx", "qy", "qz", "p_radps", "q_radps", "r_radps"]:
		s.append(trace.value(r, c))
	return s


## Replays a golden record. Returns { ok, message, worst: { pos, vel, att, rate } }.
static func replay(session: Node, g: Dictionary) -> Dictionary:
	if g.get("format") != FORMAT:
		return { ok = false, message = "not a golden flight (%s)" % g.get("format") }
	session.input_enabled = false
	var t: Dictionary = session.trim_at(g.speed, g.mode)
	if not t.ok:
		return { ok = false, message = "trim failed: " + t.message }
	session.reset()
	var sim: Node = session.sim
	var by_tick := {}
	for row in g.inputs:
		by_tick[int(row[0])] = row
	var cps := {}
	for cp in g.checkpoints:
		cps[int(cp[0])] = cp
	var worst := { pos = 0.0, vel = 0.0, att = 0.0, rate = 0.0 }
	var current: Array = g.inputs[0]
	for tick in range(0, int(g.ticks) + 1):
		if cps.has(tick):
			var cp: Array = cps[tick]
			var s: PackedFloat64Array = sim.state
			for i in 3:
				worst.pos = maxf(worst.pos, absf(s[RB.POS + i] - cp[1 + i]))
				worst.vel = maxf(worst.vel, absf(s[RB.VEL + i] - cp[4 + i]))
				worst.rate = maxf(worst.rate, absf(s[RB.RATE + i] - cp[11 + i]))
			for i in 4:
				worst.att = maxf(worst.att, absf(s[RB.ATT + i] - cp[7 + i]))
		if tick == int(g.ticks):
			break
		if by_tick.has(tick + 1):
			current = by_tick[tick + 1]
		sim.inputs = PackedFloat64Array([current[1], current[2], current[3], current[4]])
		sim.step()
	var ok: bool = worst.pos <= TOL_POS and worst.vel <= TOL_VEL and worst.att <= TOL_ATT and worst.rate <= TOL_RATE
	var msg := "worst error: position %s m, velocity %s m/s, attitude %s, rate %s rad/s" % [
		String.num_scientific(worst.pos), String.num_scientific(worst.vel), String.num_scientific(worst.att), String.num_scientific(worst.rate)]
	return { ok = ok, message = msg, worst = worst }


static func path(name: String) -> String:
	return DIR + name + ".json"
