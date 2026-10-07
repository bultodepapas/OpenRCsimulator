# Golden flights (D8a, formerly E4): record the per-tick inputs of a scripted maneuver and checkpoints of its state;
# replaying the inputs must reproduce the checkpoints. The regression test for every later physics change: a
# deliberate change re-records the goldens (tests/record_golden.gd) with a note in the commit; an accidental one
# fails test_golden.gd. Format "openrc-golden v1" (JSON, full float precision).
extends RefCounted

const Maneuvers := preload("res://sim/maneuvers.gd")
const RB := preload("res://physics/rigid_body.gd")
const Policy := preload("res://tests/replay_policy.gd")
const Session := preload("res://sim/flight_session.gd")
const GroundContact := preload("res://physics/ground_contact.gd") # not "Ground": H7 injects that name

const FORMAT := "openrc-golden v1"
const DIR := "res://tests/golden/"
const NAMES := ["roll_15", "pull_throttle", "rudder_doublet", "glide_15"]
const CHECKPOINT_EVERY := 60 # ticks (0.25 s)
## Replay tolerances: generous against libm differences between machines, far below any physics change.
const TOL_POS: float = Policy.COMPONENTS.position.absolute # m
const TOL_VEL: float = Policy.COMPONENTS.velocity.absolute # m/s
const TOL_ATT: float = Policy.COMPONENTS.attitude.absolute # quaternion components
const TOL_RATE: float = Policy.COMPONENTS.rate.absolute # rad/s


## Flies a maneuver and returns its golden record.
static func record(session: Node, name: String) -> Dictionary:
	var m: Dictionary = Maneuvers.all()[name]
	var auxiliaries: Array = []
	var discrete: Array = []
	var boundary := func(tick: int, _t: float, _state_values: PackedFloat64Array, _loads: PackedFloat64Array, _inputs: PackedFloat64Array, aux: PackedFloat64Array) -> void:
		if tick % CHECKPOINT_EVERY == 0:
			auxiliaries.append([tick] + Array(aux))
			discrete.append([tick] + Array(session.sim.modes))
	session.sim.stepped.connect(boundary)
	var trace: RefCounted = Maneuvers.fly(session, m)
	session.sim.stepped.disconnect(boundary)
	if int(auxiliaries[-1][0]) != session.sim.tick:
		auxiliaries.append([session.sim.tick] + Array(session.sim.aux))
		discrete.append([session.sim.tick] + Array(session.sim.modes))
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
		policy = Policy.descriptor(), stamp = Policy.stamp(), aux_checkpoints = auxiliaries, mode_checkpoints = discrete,
		note = "Recorded by tests/record_golden.gd; re-record only for a deliberate physics change." }


static func _state(trace: RefCounted, r: int) -> PackedFloat64Array:
	var s := PackedFloat64Array()
	for c in ["north_m", "east_m", "down_m", "u_mps", "v_mps", "w_mps", "qw", "qx", "qy", "qz", "p_radps", "q_radps", "r_radps"]:
		s.append(trace.value(r, c))
	return s


## Replays a golden record. Returns { ok, message, worst: { pos, vel, att, rate } }.
static func replay(session: Node, g: Dictionary) -> Dictionary:
	if typeof(g.get("format")) != TYPE_STRING or g.format != FORMAT:
		return { ok = false, message = "not a golden flight (%s)" % g.get("format") }
	if not _valid_record(g):
		return { ok = false, message = "malformed golden checkpoints, inputs or policy" }
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
	var aux_cps := {}
	var mode_cps := {}
	for cp in g.get("aux_checkpoints", []):
		aux_cps[int(cp[0])] = cp
	for cp in g.get("mode_checkpoints", []):
		mode_cps[int(cp[0])] = cp
	var auxiliary_ok := true
	var worst := { pos = 0.0, vel = 0.0, att = 0.0, rate = 0.0, rpm = 0.0, servo = 0.0, anchor = 0.0, downwash = 0.0 }
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
		if not sim.fault_reason.is_empty() or sim.tick != tick:
			return { ok = false, message = "replay fault or incomplete tick %d" % tick }
		if aux_cps.has(tick):
			var aux_cp: Array = aux_cps[tick]
			auxiliary_ok = auxiliary_ok and aux_cp.size() == sim.aux.size() + 1
			for i in mini(sim.aux.size(), aux_cp.size() - 1):
				var component: String = session.aux_component(i)
				worst[component] = maxf(worst[component], absf(sim.aux[i] - float(aux_cp[i + 1])))
				auxiliary_ok = auxiliary_ok and Policy.accepted(component, sim.aux[i], float(aux_cp[i + 1]))
		if mode_cps.has(tick):
			auxiliary_ok = auxiliary_ok and sim.modes.size() == mode_cps[tick].size() - 1
			for i in sim.modes.size():
				auxiliary_ok = auxiliary_ok and sim.modes[i] == int(mode_cps[tick][i + 1])
		if tick == int(g.ticks):
			break
		if by_tick.has(tick + 1):
			current = by_tick[tick + 1]
		sim.inputs = PackedFloat64Array([current[1], current[2], current[3], current[4]])
		sim.step()
	var ok: bool = auxiliary_ok and worst.pos <= TOL_POS and worst.vel <= TOL_VEL and worst.att <= TOL_ATT and worst.rate <= TOL_RATE
	var msg := "worst error: position %s m, velocity %s m/s, attitude %s, rate %s rad/s" % [
		String.num_scientific(worst.pos), String.num_scientific(worst.vel), String.num_scientific(worst.att), String.num_scientific(worst.rate)]
	return { ok = ok, message = msg + "; auxiliary/discrete " + ("ok" if auxiliary_ok else "mismatch"), worst = worst }


static func path(name: String) -> String:
	return DIR + name + ".json"


static func _valid_record(g: Dictionary) -> bool:
	if not g.has_all(["ticks", "speed", "mode", "inputs", "checkpoints"]) or not _finite_number(g.ticks) \
			or g.ticks < 0 or g.ticks != floor(g.ticks) or not _finite_number(g.speed) or g.speed <= 0:
		return false
	if typeof(g.mode) != TYPE_STRING or g.mode not in ["level", "glide"]:
		return false
	if g.has("policy") or g.has("stamp") or g.has("aux_checkpoints") or g.has("mode_checkpoints"):
		if not g.has_all(["policy", "stamp", "aux_checkpoints", "mode_checkpoints"]) \
				or not g.policy is Dictionary or typeof(g.policy.get("format")) != TYPE_STRING \
				or g.policy.format != Policy.FORMAT or not g.stamp is Dictionary:
			return false
		for key in ["os", "architecture", "cpu", "godot", "build", "ticks_per_second"]:
			if not g.stamp.has(key):
				return false
		if not _finite_number(g.stamp.ticks_per_second) or g.stamp.ticks_per_second != Engine.physics_ticks_per_second:
			return false
	for spec in [["inputs", 5], ["checkpoints", 14], ["aux_checkpoints", 5], ["mode_checkpoints", 2]]:
		var key: String = spec[0]
		if not g.has(key):
			continue # auxiliary fields are additive; legacy v1 stays readable
		if not g[key] is Array or g[key].is_empty():
			return false
		var last_tick := -1
		for row in g[key]:
			# E3b1/E0a2b: aux rows may carry anchors and a downwash lag after the four sampled values; replay then requires
			# the session's exact layout.
			var extended_ok: bool = key == "aux_checkpoints" and row is Array and row.size() > spec[1]
			if not row is Array or (row.size() != spec[1] and not extended_ok):
				return false
			for value in row:
				if not _finite_number(value):
					return false
			if row[0] != floor(row[0]) or row[0] <= last_tick or row[0] > g.ticks:
				return false
			last_tick = int(row[0])
			if key == "mode_checkpoints" and row[1] != 0 and row[1] != 1:
				return false
		if g[key][0][0] != 0 or (key != "inputs" and last_tick != int(g.ticks)):
			return false
	return true


static func _finite_number(value: Variant) -> bool:
	return (typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT) and is_finite(float(value))
