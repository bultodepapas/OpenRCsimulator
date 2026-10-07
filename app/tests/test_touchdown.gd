# E1b: continuous touchdown. The gear damping ramps in from zero at δ = 0 (linearly at first: Hunt–Crossley onset)
# and joins its value with zero slope at half each contact's static compression (ground_contact.gd damping()), so the
# contact force no longer jumps by c·δ̇ when a wheel touches. Checks: derived onsets; force continuity at touchdown and
# a C¹ join at the end of the ramp; the E1 law bit for bit at or beyond the onset; level drops at 0.5/1/2 m/s sink: no
# energy gain, tick refinement within a declared budget and better than the E1 law, restitution plausible.
# Run: godot --headless --path . --script res://tests/test_touchdown.gd
extends SceneTree

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const Sim := preload("res://sim/simulation.gd")
const Ground := preload("res://physics/ground_contact.gd")
const AD := preload("res://physics/aircraft_data.gd")

const PATH := "res://data/aircraft/jensen_ugly_stik_60.json"
const G := 9.80665
## Declared accuracy budget through one touchdown: |Δz| (m) + |Δw| (m/s) between 240 and 480 Hz, 0.4 s after a level
## touchdown at sink ≤ 2 m/s. The E1 law (damping from δ = 0) misses it at 1 and 2 m/s.
const REFINEMENT_BUDGET := 2e-4
const SINKS := [0.5, 1.0, 2.0]

var _failures := 0
var _count := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	print(("ok   " if ok else "FAIL ") + label + ("" if detail.is_empty() else "  " + detail))
	if not ok:
		_failures += 1


func _level(alt: float, vel_down := 0.0, pitch := 0.0, roll := 0.0) -> PackedFloat64Array:
	var q := M.q_from_euler(0.0, pitch, roll)
	return RB.make_state(M.v3(0, 0, -alt), M.q_rotate(M.q_conj(q), M.v3(0, 0, vel_down)), q, M.v3(0, 0, 0))


func _initialize() -> void:
	var model: Dictionary = AD.load_file(PATH).model
	var gear: Dictionary = model.landing_gear
	var e1 := gear.duplicate(true) # the E1 law: damping from δ = 0
	for c in e1.contacts:
		c.damping_onset = 0.0

	# Derived onsets: each contact's static compression; together the springs carry m·g at their onsets.
	var carried := 0.0
	for c in gear.contacts:
		carried += float(c.stiffness) * float(c.damping_onset)
		print("info %s: k %.0f N/m, c %.1f N·s/m, onset %.1f mm" % [c.name, c.stiffness, c.damping, 1000.0 * float(c.damping_onset)])
	_check("onsets are %.0f %% of the static compressions: Σ k·δ_onset = %.2f·m·g" % [100.0 * Ground.DAMPING_ONSET_FRACTION, Ground.DAMPING_ONSET_FRACTION],
		absf(carried / (model.mass_kg * G) - Ground.DAMPING_ONSET_FRACTION) < 1e-9, "%.6f m·g" % (carried / (model.mass_kg * G)))

	# Continuity at touchdown: a wheel just touching at 2 m/s sink feels (almost) nothing; the E1 law felt c·v.
	var worst_new := 0.0
	var worst_old := 0.0
	var worst_end := 0.0
	var worst_slope := 0.0
	for c in gear.contacts:
		var eps := 1e-9
		worst_new = maxf(worst_new, float(c.stiffness) * eps + Ground.damping(c, eps) * 2.0)
		var c_old: Dictionary = c.duplicate()
		c_old.damping_onset = 0.0
		worst_old = maxf(worst_old, float(c.stiffness) * eps + Ground.damping(c_old, eps) * 2.0)
		var onset: float = c.damping_onset
		worst_end = maxf(worst_end, absf(Ground.damping(c, onset * (1.0 - 1e-12)) - Ground.damping(c, onset * (1.0 + 1e-12))) / float(c.damping))
		var h := 1e-4 * onset # slope just below the end (zero above it): C¹
		worst_slope = maxf(worst_slope, absf(Ground.damping(c, onset) - Ground.damping(c, onset - h)) / h * onset / float(c.damping))
	_check("touchdown at 2 m/s sink: force 1 nm into contact ≤ 1e-5 N (the E1 law jumped by c·v = %.1f N)" % worst_old, worst_new < 1e-5,
		String.num_scientific(worst_new) + " N")
	_check("the ramp joins the gear's damping continuously and with zero slope (C¹) at its end", worst_end < 1e-9 and worst_slope < 1e-3,
		"step %s, relative slope %s" % [String.num_scientific(worst_end), String.num_scientific(worst_slope)])

	# At or beyond the static compression the law is E1 bit for bit (rest, taxi, takeoff roll keep their numbers).
	var rng := RandomNumberGenerator.new()
	rng.seed = 1104
	var same := 0
	var tried := 0
	while tried < 2000:
		var s := _level(rng.randf_range(0.10, 0.20), rng.randf_range(-2.0, 2.0), rng.randf_range(-0.03, 0.03), rng.randf_range(-0.03, 0.03))
		s[RB.RATE] = rng.randf_range(-1.0, 1.0)
		s[RB.RATE + 1] = rng.randf_range(-1.0, 1.0)
		var deep := true
		var comp := Ground.compressions(s, gear)
		for i in comp.size():
			deep = deep and comp[i] >= float(gear.contacts[i].damping_onset)
		if not deep:
			continue
		tried += 1
		if Ground.loads(s, gear, 0.3).to_byte_array() == Ground.loads(s, e1, 0.3).to_byte_array():
			same += 1
	_check("every wheel at or beyond its onset: loads equal the E1 law byte for byte (2000 states)", same == 2000, "%d/2000" % same)

	# Rest is outside the ramp with room: settled by a drop (not from the loader's numbers), every wheel's compression
	# stays above its onset for a ±20 % oscillation about rest (H11's ring-down), so rest and small oscillations use the
	# E1 law unchanged and stay smooth for RK4.
	var settled := _drop(model, gear, _level(0.35), 6.0, 240)
	var rest := Ground.compressions(settled.s, gear)
	var room := INF
	for i in rest.size():
		room = minf(room, 0.8 * rest[i] / float(gear.contacts[i].damping_onset))
	_check("settled on its wheels, 0.8 × each rest compression is still beyond its onset (smallest ratio ≥ 1)", room >= 1.0,
		"%.3f; rest %s mm" % [room, str(Array(rest).map(func(x): return snappedf(1000.0 * x, 0.1)))])

	# Level drops through touchdown.
	var touch := -INF
	var comp0 := Ground.compressions(_level(1.0), gear)
	for i in comp0.size():
		touch = maxf(touch, 1.0 + comp0[i])
	var restitution := PackedFloat64Array()
	for v in SINKS:
		var start := _level(touch + 0.002, v)
		var errors := {}
		var last := {}
		for law in ["E1b", "E1"]:
			var g: Dictionary = gear if law == "E1b" else e1
			var a := _drop(model, g, start, 0.4, 240)
			var b := _drop(model, g, start, 0.4, 480)
			errors[law] = absf(a.s[RB.POS + 2] - b.s[RB.POS + 2]) + absf(a.s[RB.VEL + 2] - b.s[RB.VEL + 2])
			last[law] = a
		print("info sink %.1f m/s: E1b peak %.1f N, largest tick-to-tick force step %.1f N, rebound e %.3f; E1 %.1f N, %.1f N, e %.3f"
			% [v, last.E1b.fmax, last.E1b.step, last.E1b.rebound / v, last.E1.fmax, last.E1.step, last.E1.rebound / v])
		_check("sink %.1f m/s: no energy gain in a tick (≤ 1e-6 J)" % v, last.E1b.max_gain < 1e-6, String.num_scientific(last.E1b.max_gain) + " J")
		_check("sink %.1f m/s: 240 vs 480 Hz within the budget %s and below the E1 law's" % [v, String.num_scientific(REFINEMENT_BUDGET)],
			errors.E1b <= REFINEMENT_BUDGET and errors.E1b < errors.E1,
			"E1b %s, E1 %s" % [String.num_scientific(errors.E1b), String.num_scientific(errors.E1)])
		restitution.append(last.E1b.rebound / v)
	var lowest := 1.0
	var highest := 0.0
	for e in restitution:
		lowest = minf(lowest, e)
		highest = maxf(highest, e)
	_check("restitution 0.25–0.5 at every sink (wire gear on rubber tyres, estimated)", lowest > 0.25 and highest < 0.5, str(restitution))
	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)


## Gear only (no air) from `start` for `seconds` at `hz`. Returns { s, fmax (N), step (largest tick-to-tick change of
## the vertical ground force, N), rebound (largest upward CG speed, m/s), max_gain (J per tick) }.
func _drop(model: Dictionary, gear: Dictionary, start: PackedFloat64Array, seconds: float, hz: int) -> Dictionary:
	var saved := Engine.physics_ticks_per_second
	Engine.physics_ticks_per_second = hz
	var sim: Node = Sim.new()
	sim.mass = model.mass_kg
	sim.inertia = model.inertia.duplicate()
	sim.loads = func(s: PackedFloat64Array, _t: float) -> PackedFloat64Array:
		var g := Ground.loads(s, gear)
		return g if not g.is_empty() else PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	sim.reset(start)
	var out := { fmax = 0.0, step = 0.0, rebound = 0.0, max_gain = -INF }
	var prev := 0.0
	var e_prev := _energy(sim.state, sim.mass, sim.inertia, gear)
	for i in roundi(seconds * hz):
		sim.step()
		var g := Ground.loads(sim.state, gear)
		var f := 0.0 if g.is_empty() else -g[2]
		out.step = maxf(out.step, absf(f - prev))
		prev = f
		out.fmax = maxf(out.fmax, f)
		out.rebound = maxf(out.rebound, -sim.state[RB.VEL + 2])
		var e := _energy(sim.state, sim.mass, sim.inertia, gear)
		out.max_gain = maxf(out.max_gain, e - e_prev)
		e_prev = e
	out.s = sim.state.duplicate()
	sim.free()
	Engine.physics_ticks_per_second = saved
	return out


## Mechanical energy of the bare rigid body on the gear: kinetic + m·g·h + springs.
func _energy(s: PackedFloat64Array, mass: float, j: PackedFloat64Array, gear: Dictionary) -> float:
	var v := M.v3(s[RB.VEL], s[RB.VEL + 1], s[RB.VEL + 2])
	var w := M.v3(s[RB.RATE], s[RB.RATE + 1], s[RB.RATE + 2])
	return 0.5 * mass * M.dot(v, v) + 0.5 * M.dot(w, RB.inertia_mul(j, w)) - mass * G * s[RB.POS + 2] + Ground.spring_energy(s, gear)
