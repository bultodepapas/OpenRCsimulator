# E3b1: per-wheel stiction anchors. Loader-derived springs; the stuck-wheel law and its release thresholds against hand
# values; a 60 s parked idle on the mown runway barely moves (vs the E2 creep); the breakaway throttle brackets
# breakaway·C_rr·m·g; an unclamped ring-down never gains energy; 240/480 Hz refinement; checkpoint replay with anchors;
# airborne flight bit-identical with and without stiction; a full-throttle takeoff roll still breaks away.
# Run: godot --headless --path . --script res://tests/test_ground_stiction.gd
extends SceneTree

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const Ground := preload("res://physics/ground_contact.gd")
const AD := preload("res://physics/aircraft_data.gd")
const Propulsion := preload("res://physics/propulsion.gd")
const Air := preload("res://physics/air_data.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const FlightSession := preload("res://sim/flight_session.gd")

const PATH := "res://data/aircraft/jensen_ugly_stik_60.json"
const G := 9.80665
const RUNWAY_ROLLING := 2.5 # surface_friction.json runway rolling factor (test_ground_surfaces pins it)

var _failures := 0
var _count := 0
var _session: Node
var _spot := PackedFloat64Array() # north, east on the runway


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	print(("ok   " if ok else "FAIL ") + label + ("" if detail.is_empty() else "  " + detail))
	if not ok:
		_failures += 1


func _initialize() -> void:
	var r := AD.load_file(PATH)
	_check("Stik data loads", r.ok, str(r.get("errors", [])))
	if not r.ok:
		quit(1)
		return
	var model: Dictionary = r.model
	var gear: Dictionary = model.landing_gear
	var mass: float = model.mass_kg
	# Static load shares by an independent side-view moment balance: nose = (x_main − x_cg) / (x_main − x_nose).
	var raw_gear: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PATH)).landing_gear
	var x_main: float = raw_gear.contacts[0].position.value[0]
	var x_nose: float = raw_gear.contacts[2].position.value[0]
	var nose_share: float = (x_main - model.cg_le[0]) / (x_main - x_nose)
	var expect_shares := [(1.0 - nose_share) / 2.0, (1.0 - nose_share) / 2.0, nose_share]
	var omega2 := Ground.ANCHOR_OMEGA * Ground.ANCHOR_OMEGA
	var total_k := 0.0
	var shares_ok: bool = gear.breakaway_factor == 1.25
	for i in 3:
		var share: float = gear.contacts[i].anchor_stiffness / (mass * omega2)
		total_k += gear.contacts[i].anchor_stiffness
		shares_ok = shares_ok and absf(share - expect_shares[i]) < 0.01 \
			and absf(gear.contacts[i].anchor_damping - 2.0 * Ground.ANCHOR_ZETA * sqrt(gear.contacts[i].anchor_stiffness * mass * share)) < 1e-12
	_check("loader: breakaway 1.25; anchor springs Σk = m·ω² split by static load share (nose %.3f), c = 2ζ·√(k·m·share)" % nose_share,
		shares_ok and absf(total_k - mass * omega2) < 1e-9, "k %s" % str([gear.contacts[0].anchor_stiffness, gear.contacts[1].anchor_stiffness, gear.contacts[2].anchor_stiffness]))
	var yaw_k := 0.0
	for c in gear.contacts:
		yaw_k += c.anchor_stiffness * (c.position[0] * c.position[0] + c.position[1] * c.position[1])
	var yaw_wdt := sqrt(yaw_k / model.inertia[2]) / 240.0
	_check("anchor yaw mode about the CG also satisfies ω·dt < 0.1 at 240 Hz", yaw_wdt < 0.1, "ω·dt %.3f" % yaw_wdt)
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	raw.landing_gear.breakaway_factor.value = 2.5
	_check("loader refuses a breakaway factor above 2", not AD.validate_and_derive(raw).ok)
	raw.landing_gear.erase("breakaway_factor")
	var plain := AD.validate_and_derive(raw)
	_check("without breakaway_factor: no anchor fields (E2 exactly)", plain.ok and not plain.model.landing_gear.has("breakaway_factor")
		and not plain.model.landing_gear.contacts[0].has("anchor_stiffness"))

	var f := FieldLoader.load_from()
	_session = FlightSession.new()
	_session.setup()
	root.add_child(_session)
	_session.input_enabled = false
	_check("session on the default field", f.ok and _session.set_field(f.field))
	for s in f.field.surfaces:
		if s.type == "runway":
			_spot = PackedFloat64Array([s.center_north, s.center_east - s.length_east_west / 2.0 + 10.0])
	var lag_entries := 1 if _session.downwash_index() >= 0 else 0 # E0a2b's lagged wing CL follows the anchors
	_check("session aux carries three anchor floats per wheel", _session.sim.aux.size() == FlightSession.AUX_ANCHORS + 9 + lag_entries
		and _session.anchor_count() == 3, str(_session.sim.aux.size()))
	var parked := _parked()
	_unit_checks(gear, parked)
	_parked_idle(parked)
	_breakaway(parked, mass)
	_energy_and_refinement(parked, model)
	_checkpoint(parked)
	_airborne_identity()
	_takeoff_roll(parked)
	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)


## At rest, heading east (down the runway), wheels settled with the engine off.
func _parked() -> PackedFloat64Array:
	_start(_state(0.27), false)
	for i in roundi(6.0 / _session.sim.dt()):
		_session.sim.step()
	return _session.sim.state.duplicate()


func _state(alt: float) -> PackedFloat64Array:
	var q := M.q_from_euler(PI / 2.0, 0.0, 0.0)
	return PackedFloat64Array([_spot[0], _spot[1], -alt, 0.0, 0.0, 0.0, q[0], q[1], q[2], q[3], 0.0, 0.0, 0.0])


## Restart the session's physics at `s` (every wheel sliding), engine idling or off, neutral servos.
func _start(s: PackedFloat64Array, engine: bool, throttle := 0.0) -> void:
	_session.reset()
	_session.engine_running = engine
	_session.trims = { roll = 0.0, pitch = 0.0, yaw = 0.0 }
	var aux := PackedFloat64Array([float(_session.aircraft.model.propulsion.idle_rpm) if engine else 0.0, 0.0, 0.0, 0.0])
	aux.resize(FlightSession.AUX_ANCHORS + _session.anchor_count() * Ground.ANCHOR_STRIDE)
	_session.sim.aux = aux
	_session.sim.inputs = PackedFloat64Array([0.0, 0.0, 0.0, throttle])
	_session.sim.reset(s)
	_session.sim.set_paused(false)


func _anchors() -> PackedFloat64Array:
	return _session.sim.aux.slice(FlightSession.AUX_ANCHORS, FlightSession.AUX_ANCHORS + _session.anchor_count() * Ground.ANCHOR_STRIDE)


func _unit_checks(gear: Dictionary, settled_state: PackedFloat64Array) -> void:
	var rects: PackedFloat64Array = _session.ground_surfaces
	var parked := settled_state.duplicate() # exactly at rest: E2 and the anchor law both give zero tangential force
	for i in 3:
		parked[RB.VEL + i] = 0.0
		parked[RB.RATE + i] = 0.0
	var free := PackedFloat64Array()
	free.resize(9)
	var stuck := Ground.anchor_step(parked, gear, 0.0, rects, free)
	var all_stuck := true
	for i in 3:
		all_stuck = all_stuck and stuck[i * 3 + 2] == 1.0
	_check("at rest every sliding wheel sticks, its anchor at the wheel (no stored energy)", all_stuck and Ground.anchor_energy(parked, gear, stuck) < 1e-20)
	var settled := Ground.loads(parked, gear, 0.0, rects, stuck)
	var e2 := Ground.loads(parked, gear, 0.0, rects)
	_check("stuck at rest with zero deflection: the same load as E2 at rest (no tangential force either way)",
		settled.size() == 6 and e2.size() == 6 and absf(settled[0] - e2[0]) < 1e-12 and absf(settled[1] - e2[1]) < 1e-12, "%s vs %s" % [settled, e2])
	# Shift the airplane 1 mm east (along every wheel): each stuck wheel pulls back k·1 mm, well inside its hold.
	var moved := parked.duplicate()
	moved[RB.POS + 1] += 0.001
	var east_force := _ned_east(moved, Ground.loads(moved, gear, 0.0, rects, stuck)) - _ned_east(moved, Ground.loads(moved, gear, 0.0, rects))
	var sum_k := 0.0
	for c in gear.contacts:
		sum_k += c.anchor_stiffness
	_check("1 mm along the wheels: the anchors pull back Σk·1 mm", absf(east_force + sum_k * 0.001) < 1e-9,
		"%.6f N vs %.6f N" % [east_force, -sum_k * 0.001])
	# Release thresholds: hold = breakaway·C_rr·runway·N per wheel; N from the E1 spring at the parked compression.
	var comp := Ground.compressions(parked, gear)
	var min_hold := INF
	var max_hold := 0.0
	for i in 3:
		var hold: float = gear.breakaway_factor * gear.rolling_resistance * RUNWAY_ROLLING * gear.contacts[i].stiffness * comp[i] / gear.contacts[i].anchor_stiffness
		min_hold = minf(min_hold, hold)
		max_hold = maxf(max_hold, hold)
	var below := parked.duplicate()
	below[RB.POS + 1] += 0.98 * min_hold
	var above := parked.duplicate()
	above[RB.POS + 1] += 1.02 * max_hold
	var kept := Ground.anchor_step(below, gear, 0.0, rects, stuck)
	var released := Ground.anchor_step(above, gear, 0.0, rects, stuck)
	_check("98 %% of the smallest hold distance keeps every anchor (%.3f mm; largest %.3f mm)" % [min_hold * 1000.0, max_hold * 1000.0], kept == stuck)
	_check("102 % of the largest hold distance releases every wheel", released == free)
	var lifted := parked.duplicate()
	lifted[RB.POS + 2] -= 0.05 # every wheel just off the ground, still within the gear's reach
	_check("wheels off the ground (within reach) release their anchors", Ground.loads(lifted, gear, 0.0, rects, stuck).is_empty()
		and Ground.anchor_step(lifted, gear, 0.0, rects, stuck) == free)
	# Inside an RK stage the stuck force is clamped at the hold: at twice the largest hold distance every wheel
	# pushes exactly breakaway·C_rr·runway·N (N = k·compression at rest), not k·d.
	var far := parked.duplicate()
	far[RB.POS + 1] += 2.0 * max_hold
	var far_comp := Ground.compressions(far, gear)
	var hold_sum := 0.0
	for i in 3:
		hold_sum += gear.breakaway_factor * gear.rolling_resistance * RUNWAY_ROLLING * gear.contacts[i].stiffness * far_comp[i]
	var far_force := _ned_east(far, Ground.loads(far, gear, 0.0, rects, stuck)) - _ned_east(far, Ground.loads(far, gear, 0.0, rects))
	_check("past the hold inside a stage: the stuck force is clamped at Σ breakaway·C_rr·N = %.4f N" % hold_sum,
		absf(far_force + hold_sum) < 1e-9, "%.6f N" % far_force)
	var rolling := parked.duplicate()
	rolling[RB.VEL] = 1.5 * Ground.STICK_SPEED
	_check("a sliding wheel faster than STICK_SPEED stays sliding", Ground.anchor_step(rolling, gear, 0.0, rects, free) == free)


## The NED east component of body loads at state s.
func _ned_east(s: PackedFloat64Array, loads: PackedFloat64Array) -> float:
	var w := s[RB.ATT]
	var x := s[RB.ATT + 1]
	var y := s[RB.ATT + 2]
	var z := s[RB.ATT + 3]
	return 2.0 * (x * y + w * z) * loads[0] + (1.0 - 2.0 * (x * x + z * z)) * loads[1] + 2.0 * (y * z - w * x) * loads[2]


func _parked_idle(parked: PackedFloat64Array) -> void:
	_start(parked, true)
	for i in roundi(2.0 / _session.sim.dt()):
		_session.sim.step()
	var settled: PackedFloat64Array = _session.sim.state.duplicate()
	for i in roundi(60.0 / _session.sim.dt()):
		_session.sim.step()
	var s: PackedFloat64Array = _session.sim.state
	var drift := sqrt((s[RB.POS] - settled[RB.POS]) ** 2 + (s[RB.POS + 1] - settled[RB.POS + 1]) ** 2)
	var anchors := _anchors()
	_check("60 s parked at idle on the mown runway: drift < 2 mm, every wheel still stuck", drift < 0.002 and anchors[2] == 1.0 and anchors[5] == 1.0 and anchors[8] == 1.0
		and _session.sim.fault_reason.is_empty(), "%.4f mm" % (drift * 1000.0))
	# The same 10 s with the E2 law alone (4-entry aux: no anchors) creeps, as E3a measured.
	_session.reset()
	_session.engine_running = true
	_session.sim.aux = PackedFloat64Array([float(_session.aircraft.model.propulsion.idle_rpm), 0.0, 0.0, 0.0])
	_session.sim.inputs = PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
	_session.sim.reset(parked)
	for i in roundi(10.0 / _session.sim.dt()):
		_session.sim.step()
	var e2_drift := sqrt((_session.sim.state[RB.POS] - parked[RB.POS]) ** 2 + (_session.sim.state[RB.POS + 1] - parked[RB.POS + 1]) ** 2)
	_check("reference: the E2 law alone creeps centimetres in 10 s at idle", e2_drift > 0.02, "%.1f mm" % (e2_drift * 1000.0))


## Throttle steps from idle: the first that rolls within 3 s brackets the breakaway thrust. The prediction is an
## independent quasi-static balance: thrust above the ground moves load from the mains to the nose and the propeller
## torque from the right main to the left; the stuck springs share the push by stiffness; breakaway is the thrust at
## which the first wheel's share reaches breakaway·C_rr·runway·N.
func _breakaway(parked: PackedFloat64Array, mass: float) -> void:
	var model: Dictionary = _session.aircraft.model
	var prop: Dictionary = model.propulsion
	var held_thrust := -1.0
	var broke_thrust := -1.0
	var broke_torque := 0.0
	var throttle := 0.0
	while throttle <= 0.3 and broke_thrust < 0.0:
		_start(parked, true, throttle)
		for i in roundi(3.0 / _session.sim.dt()):
			_session.sim.step()
		var s: PackedFloat64Array = _session.sim.state
		var moved := sqrt((s[RB.POS] - parked[RB.POS]) ** 2 + (s[RB.POS + 1] - parked[RB.POS + 1]) ** 2)
		var tq: PackedFloat64Array = Propulsion.thrust_torque(PackedFloat64Array([0.0, 0.0, 0.0]), _session.sim.aux[0], prop, Air.RHO_SEA_LEVEL)
		if moved > 0.05:
			broke_thrust = tq[0]
			broke_torque = tq[1]
		else:
			held_thrust = tq[0]
		throttle += 0.01
	var predicted := _predicted_breakaway(model, mass, broke_torque / maxf(broke_thrust, 1e-9))
	var ideal: float = model.landing_gear.breakaway_factor * model.landing_gear.rolling_resistance * RUNWAY_ROLLING * mass * G
	_check("breakaway: held at %.2f N, rolled at %.2f N; quasi-static prediction %.2f N within the bracket ±5 %% (all wheels at once would be %.2f N)"
		% [held_thrust, broke_thrust, predicted, ideal], held_thrust > 0.0 and broke_thrust > 0.0
		and held_thrust < predicted * 1.05 and broke_thrust > predicted * 0.95 and broke_thrust - held_thrust < 0.1 * predicted)


func _predicted_breakaway(model: Dictionary, mass: float, torque_per_newton: float) -> float:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PATH)).landing_gear
	var gear: Dictionary = model.landing_gear
	var cg: PackedFloat64Array = model.cg_le
	var x_m: float = -(float(raw.contacts[0].position.value[0]) - cg[0]) # forward of the CG, m
	var x_n: float = -(float(raw.contacts[2].position.value[0]) - cg[0])
	var track: float = 2.0 * absf(float(raw.contacts[0].position.value[1]))
	var h: float = cg[2] - float(raw.contacts[0].position.value[2]) # CG above the wheel bottoms
	var z_t: float = model.propulsion.offset[2] # thrust line above the CG
	var w := mass * G
	var hold_per_n: float = gear.breakaway_factor * gear.rolling_resistance * RUNWAY_ROLLING
	var sum_k := 0.0
	for c in gear.contacts:
		sum_k += c.anchor_stiffness
	var lo := 0.0
	var hi := w
	for i in 60:
		var t := 0.5 * (lo + hi)
		var nose := (-x_m * w + (h + z_t) * t) / (x_n - x_m)
		var roll := torque_per_newton * t / track # reaction torque loads the left main, unloads the right
		var loads := [(w - nose) / 2.0 + roll, (w - nose) / 2.0 - roll, nose]
		var slips := false
		for k in 3:
			slips = slips or gear.contacts[k].anchor_stiffness / sum_k * t > hold_per_n * float(loads[k])
		if slips:
			hi = t
		else:
			lo = t
	return 0.5 * (lo + hi)


## Engine off, a 1.5 cm/s eastward nudge (below STICK_SPEED): the anchors catch it and ring it down unclamped.
func _energy_and_refinement(parked: PackedFloat64Array, model: Dictionary) -> void:
	var nudged := parked.duplicate()
	nudged[RB.VEL] = 0.015
	nudged[RB.RATE + 2] = 0.02
	_start(nudged, false)
	var gear: Dictionary = model.landing_gear
	var worst_gain := -INF
	var last := _energy(model)
	for i in roundi(1.0 / _session.sim.dt()):
		_session.sim.step()
		var e := _energy(model)
		worst_gain = maxf(worst_gain, e - last)
		last = e
	_check("unclamped anchor ring-down: total energy never rises (KE + PE + gear + anchor springs)", worst_gain <= 1e-10, "max rise %s J" % worst_gain)
	var at_240: PackedFloat64Array = _session.sim.state.duplicate()
	Engine.physics_ticks_per_second = 480
	_start(nudged, false)
	for i in roundi(1.0 / _session.sim.dt()):
		_session.sim.step()
	var at_480: PackedFloat64Array = _session.sim.state.duplicate()
	Engine.physics_ticks_per_second = 240
	var gap := 0.0
	for i in 3:
		gap = maxf(gap, absf(at_240[RB.POS + i] - at_480[RB.POS + i]))
	_check("240 vs 480 Hz: the same ring-down within 1 µm after 1 s (tick-independent anchor springs)", gap < 1e-6 and _session.sim.fault_reason.is_empty(), String.num_scientific(gap) + " m")


func _energy(model: Dictionary) -> float:
	var s: PackedFloat64Array = _session.sim.state
	var I: PackedFloat64Array = model.inertia
	var p := s[RB.RATE]
	var q := s[RB.RATE + 1]
	var r := s[RB.RATE + 2]
	var rot := 0.5 * (I[0] * p * p + I[1] * q * q + I[2] * r * r) + I[3] * p * q + I[4] * p * r + I[5] * q * r
	var kin: float = 0.5 * model.mass_kg * (s[RB.VEL] ** 2 + s[RB.VEL + 1] ** 2 + s[RB.VEL + 2] ** 2)
	return kin + rot - model.mass_kg * G * s[RB.POS + 2] + Ground.spring_energy(s, model.landing_gear) \
		+ Ground.anchor_energy(s, model.landing_gear, _anchors())


func _checkpoint(parked: PackedFloat64Array) -> void:
	_start(parked, true)
	for i in 300:
		_session.sim.step()
	var cp: Dictionary = _session.checkpoint()
	for i in 200:
		_session.sim.step()
	var first: PackedByteArray = _session.sim.state.to_byte_array() + _session.sim.aux.to_byte_array()
	_check("checkpoint taken with stuck anchors", not cp.is_empty() and _anchors()[2] == 1.0)
	var restored: bool = _session.restore_checkpoint(cp)
	_session.sim.set_paused(false)
	for i in 200:
		_session.sim.step()
	_check("restore and replay 200 ticks: state and anchors byte-identical", restored and first == _session.sim.state.to_byte_array() + _session.sim.aux.to_byte_array())
	var bad: Dictionary = cp.duplicate(true)
	bad.simulation.aux[FlightSession.AUX_ANCHORS + 2] = 0.5
	_check("restore refuses an anchor flag that is neither stuck nor sliding", not _session.restore_checkpoint(bad))


## Trimmed flight at 30 m: stiction only acts on the ground, so state and loads match a gear without breakaway_factor.
func _airborne_identity() -> void:
	var stiction := FlightSession.new()
	stiction.setup()
	root.add_child(stiction)
	stiction.input_enabled = false
	var with := _trimmed_bytes(stiction)
	stiction.queue_free()
	var plain := FlightSession.new()
	plain.setup()
	root.add_child(plain)
	plain.input_enabled = false
	plain.aircraft.model.landing_gear.erase("breakaway_factor")
	for c in plain.aircraft.model.landing_gear.contacts:
		c.erase("anchor_stiffness")
		c.erase("anchor_damping")
	var without := _trimmed_bytes(plain)
	_check("airborne trimmed flight (960 ticks): state and loads byte-identical with and without stiction", with == without and with.size() > 0
		and plain.anchor_count() == 0)
	plain.queue_free()


func _trimmed_bytes(session: Node) -> PackedByteArray:
	session.reset()
	var out := PackedByteArray()
	for i in 960:
		session.sim.step()
		out.append_array(session.sim.state.to_byte_array())
		out.append_array(session.sim.last_loads.to_byte_array())
	return out


func _takeoff_roll(parked: PackedFloat64Array) -> void:
	_start(parked, true, 1.0)
	var released_at := -1.0
	for i in roundi(3.0 / _session.sim.dt()):
		_session.sim.step()
		var a := _anchors()
		if released_at < 0.0 and a[2] == 0.0 and a[5] == 0.0 and a[8] == 0.0:
			released_at = i * _session.sim.dt()
	var s: PackedFloat64Array = _session.sim.state
	var speed := sqrt(s[RB.VEL] ** 2 + s[RB.VEL + 1] ** 2)
	_check("full throttle: every anchor releases within 1 s and the roll accelerates past 5 m/s in 3 s",
		released_at >= 0.0 and released_at < 1.0 and speed > 5.0 and _session.sim.fault_reason.is_empty(), "released %.2f s, %.1f m/s" % [released_at, speed])
