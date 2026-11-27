extends SceneTree
## NK-6g: two ground-contact shortcuts of the accepted tick, each exact.
## - The native lake reach proof also tests the sweep's horizontal box against the lake bank's bounds
##   (FlightSession._lake_bank_bounds); NK-5d's proof was vertical only and never held while rolling at the datum.
##   Over random ground-level tick pairs around the lake, every lake proof matches a null LakeCollision sweep, the
##   horizontal test proves pairs the vertical one cannot, and it never proves a pair over the water (NK-5d's test
##   also finds real hits among unproven pairs).
## - The pre-tick guard's gear collapse reads the compressions the contact observer just published
##   (FlightSession._guard_gear_collapsed).
## - NK-6j: the guard's gear collapse from the native stage's endpoint compressions equals gear_collapsed for perturbed
##   states on, into and past the gear's travel.
## - NK-6k: wherever the native stage proves the propeller clear, HullContact.prop_disc_depth's depth is <= 0, for
##   perturbed states on the runway, at the lake's bank and over its water, from level to nosed over, some with
##   quaternions off unit length; away from the lake, and without a lake, it proves every clear state.
## - NK-6l: wherever the native stage answers the guard's hull checks, HullContact.terminal has no event and
##   HullContact.contacts no contact, for perturbed tick pairs from clear of the ground to below it.
## Paired sessions with all of them on and all off fly byte-identical through a takeoff roll, a lake-shore taxi, a
## hard landing that collapses the gear and a nose-over that strikes the propeller. Skips (passes) without a verified
## native library.

const Flight := preload("res://sim/flight_session.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const LakeLoader := preload("res://data/lake_loader.gd")
const CollisionSetup := preload("res://scenery/collision_setup.gd")
const NativeStage := preload("res://sim/native_stage.gd")
const LakeCollision := preload("res://sim/lake_collision.gd")
const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")
const HullContact := preload("res://physics/hull_contact.gd")

const SAMPLES := 4000
var _checks := 0
var _failures := 0
var _rng := RandomNumberGenerator.new()
var _field: Dictionary
var _lake: Dictionary
var _world: Dictionary


func _initialize() -> void:
	Engine.physics_ticks_per_second = 240
	_run.call_deferred()


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL ", label, " ", detail)


func _run() -> void:
	_rng.seed = 6227
	_field = FieldLoader.load_from().field
	_lake = LakeLoader.load_from(LakeLoader.DEFAULT_PATH).lake
	var built: Dictionary = CollisionSetup.build(_field)
	_world = built.get("world", {})
	var tested := 0
	for id: String in ["f4u-corsair-250", "jensen-das-ugly-stik-60", "turbo-lumber-evolution"]:
		var probe := _session(id, true, Flight.START_RUNWAY)
		if probe == null or probe.stage_backend_identity().backend != NativeStage.BACKEND_NATIVE:
			print("NK6G_SKIP %s" % id)
			if probe != null:
				probe.free()
			continue
		tested += 1
		_soundness(probe, id)
		probe.free()
		_collapse(id)
		_strike(id)
		_hull(id)
		_pair(id, "roll")
		_pair(id, "shore")
		_pair(id, "hard_landing")
		_pair(id, "nose_over")
	if tested == 0:
		print("NK6G_GROUND_GUARD_SKIP no native session")
	print("native ground guard: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _session(id: String, enabled: bool, start: String, with_lake := true) -> Node:
	var s: Node = Flight.new()
	s.input_enabled = true
	s.crash_auto_restart = false
	s.soft_hull_contacts = true
	s.cost_observations_enabled = true
	s.lake_bank_proof_enabled = enabled
	s.guard_published_collapse_enabled = enabled
	s.native_guard_collapse_enabled = enabled
	s.native_prop_strike_enabled = enabled
	s.native_hull_guard_enabled = enabled
	s.start_choice = start
	s.setup_stage_backend(NativeStage.BACKEND_NATIVE)
	s.setup(Catalog.data_for(id, Catalog.default_battery_mode(id)), id)
	if not s.aircraft.get("ok", false):
		s.free()
		return null
	s.set_field(_field)
	if not _world.is_empty():
		s.set_collision_world(_world)
	if with_lake:
		s.set_lake_context(_lake)
	s.reset()
	if s.glow_is_active() and not bool(s.glow_state().get("running", false)):
		s.glow_start()
	return s


## Ground-level tick pairs at random distances from the lake's bank box.
func _soundness(s: Node, id: String) -> void:
	var hull: PackedFloat64Array = s.aircraft.model.crash_hull
	var unit := PackedFloat64Array([1.0, 1.0, 1.0, 0.0, 0.0, 0.0])
	var bank := LakeCollision._polygon_bounds(_lake.bank_ne_m)
	var stats := {proved = 0, horizontal_only = 0, hits = 0, unsound = 0, over_water_box_proofs = 0}
	for i: int in SAMPLES:
		var base := PackedFloat64Array([0.0, 0.0, 0.0])
		if i % 3 == 0:
			# Over the water, low enough for the hull, gear or disc to touch it.
			base[0] = lerpf(bank[0], bank[1], _rng.randf_range(0.3, 0.7))
			base[1] = lerpf(bank[2], bank[3], _rng.randf_range(0.3, 0.7))
			base[2] = _rng.randf_range(-0.5, 3.0)
		else:
			var margin: float = _rng.randf_range(-20.0, 160.0)
			base[0] = _rng.randf_range(bank[0] - margin, bank[1] + margin)
			base[1] = _rng.randf_range(bank[2] - margin, bank[3] + margin)
			base[2] = _rng.randf_range(-1.5, 0.8)
		var previous := _state(base)
		var candidate := _advance(previous, 0.05 if i % 10 else 1.5, 0.02 if i % 7 else 0.4)
		s.lake_bank_proof_enabled = true
		var reach: int = s._native_contact_reach(previous, candidate)
		s.lake_bank_proof_enabled = false
		var vertical: int = s._native_contact_reach(previous, candidate)
		s.lake_bank_proof_enabled = true
		var water: Variant = LakeCollision.first_hit(s._lake, previous, candidate, hull, s.current_landing_gear(), 1 + i,
			s.sim.dt(), 1.0, unit, true, s._prop_disc, s._hull_contact)
		if reach & Flight.REACH_LAKE_CLEAR:
			stats.proved += 1
			if not (vertical & Flight.REACH_LAKE_CLEAR):
				stats.horizontal_only += 1
				if i % 3 == 0:
					stats.over_water_box_proofs += 1
			if water != null:
				stats.unsound += 1
		elif water != null:
			stats.hits += 1
	_check(id + ": every lake proof matches a null sweep", stats.unsound == 0, str(stats))
	_check(id + ": the bank box proves ground-level pairs the vertical proof cannot", stats.horizontal_only > SAMPLES / 5,
		str(stats))
	_check(id + ": pairs over the water are left to the sweep", stats.over_water_box_proofs == 0, str(stats))
	print("NK6G_SOUNDNESS %s %s" % [id, str(stats)])


## NK-6j: after real ticks the guarded context belongs to the endpoint; perturbed states around it must answer as
## gear_collapsed does wherever the native stage answers.
func _collapse(id: String) -> void:
	var s := _session(id, true, Flight.START_RUNWAY)
	s.read_raw = func() -> Dictionary: return {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.2}
	for i in 120:
		_tick(s)
	var origin: PackedFloat64Array = s.sim.state.duplicate()
	var stats := {answered = 0, collapsed = 0, mismatched = 0, refused = 0}
	for i in 3000:
		var state := origin.duplicate()
		state[RB.POS + 2] += _rng.randf_range(-0.3, 0.6) # from clear of the ground to past the gear's travel
		state[RB.POS] += _rng.randf_range(-20.0, 20.0)
		state[RB.POS + 1] += _rng.randf_range(-20.0, 20.0)
		var q := Quaternion(Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)).normalized(),
			_rng.randf_range(-0.3, 0.3)) * Quaternion(state[RB.ATT + 1], state[RB.ATT + 2], state[RB.ATT + 3], state[RB.ATT])
		state[RB.ATT] = q.w
		state[RB.ATT + 1] = q.x
		state[RB.ATT + 2] = q.y
		state[RB.ATT + 3] = q.z
		var answer: int = s._native_stage.guard_collapsed(state, s.sim.aux)
		if answer < 0:
			stats.refused += 1
			continue
		stats.answered += 1
		var reference: bool = s.gear_collapsed(state)
		if reference:
			stats.collapsed += 1
		if (answer == 1) != reference:
			stats.mismatched += 1
	_check(id + ": the native guard collapse equals gear_collapsed", stats.mismatched == 0 and stats.answered > 2500, str(stats))
	_check(id + ": both answers occur", stats.collapsed > 100 and stats.collapsed < stats.answered, str(stats))
	print("NK6J_COLLAPSE %s %s" % [id, str(stats)])
	s.free()


## NK-6k: perturbed endpoints around a rolling one, a third of them at the lake's bank or over its water.
func _strike(id: String) -> void:
	var s := _session(id, true, Flight.START_RUNWAY)
	s.read_raw = func() -> Dictionary: return {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.2}
	for i in 120:
		_tick(s)
	var origin: PackedFloat64Array = s.sim.state.duplicate()
	var bank := LakeCollision._polygon_bounds(_lake.bank_ne_m)
	var time_s: float = float(s.sim.tick) * s.sim.dt()
	var stats := {answered = 0, strikes = 0, unsound = 0, refused = 0, refused_far_clear = 0}
	for i in 3000:
		var state := origin.duplicate()
		if i % 3 == 0:
			state[RB.POS] = lerpf(bank[0], bank[1], _rng.randf_range(-0.2, 1.2))
			state[RB.POS + 1] = lerpf(bank[2], bank[3], _rng.randf_range(-0.2, 1.2))
		else:
			state[RB.POS] += _rng.randf_range(-20.0, 20.0)
			state[RB.POS + 1] += _rng.randf_range(-20.0, 20.0)
		state[RB.POS + 2] += _rng.randf_range(-0.3, 0.3)
		var q := Quaternion(Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)).normalized(),
			_rng.randf_range(-0.6, 0.6)) * Quaternion(state[RB.ATT + 1], state[RB.ATT + 2], state[RB.ATT + 3], state[RB.ATT])
		var n := sqrt(float(q.w) * q.w + float(q.x) * q.x + float(q.y) * q.y + float(q.z) * q.z)
		if i % 4 == 1:
			n *= 1.0 + _rng.randf_range(-1.0e-3, 1.0e-3) # the stage's quaternion is not exactly unit
		state[RB.ATT] = q.w / n
		state[RB.ATT + 1] = q.x / n
		state[RB.ATT + 2] = q.y / n
		state[RB.ATT + 3] = q.z / n
		var answer: int = s._native_stage.prop_strike_clear(state, s._prop_disc, s._lake)
		var depth: float = float(HullContact.prop_disc_depth(state, s._prop_disc, s._lake, time_s).depth)
		if depth > 0.0:
			stats.strikes += 1
		if answer == 1:
			stats.answered += 1
			if not (depth <= 0.0):
				stats.unsound += 1
			continue
		stats.refused += 1
		# 5 m clears every hub offset and radius here: only the lake's neighbourhood may keep the reference.
		var far: bool = state[RB.POS] < bank[0] - 5.0 or state[RB.POS] > bank[1] + 5.0 \
			or state[RB.POS + 1] < bank[2] - 5.0 or state[RB.POS + 1] > bank[3] + 5.0
		if far and depth <= 0.0:
			stats.refused_far_clear += 1
	_check(id + ": every native propeller clearance has prop_disc_depth <= 0", stats.unsound == 0 and stats.answered > 1000,
		str(stats))
	_check(id + ": away from the lake the native stage proves every clear state", stats.refused_far_clear == 0, str(stats))
	_check(id + ": strikes occur and stay with the reference", stats.strikes > 50, str(stats))
	_check(id + ": another disc or lake dictionary is refused",
		s._native_stage.prop_strike_clear(origin, s._prop_disc.duplicate(), s._lake) == -1
		and s._native_stage.prop_strike_clear(origin, s._prop_disc, s._lake.duplicate()) == -1)
	print("NK6K_STRIKE %s %s" % [id, str(stats)])
	s.free()
	# Without a lake the flat-datum depth decides alone: every clear endpoint is answered natively.
	var dry := _session(id, true, Flight.START_RUNWAY, false)
	dry.read_raw = func() -> Dictionary: return {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.2}
	for i in 120:
		_tick(dry)
	var dry_origin: PackedFloat64Array = dry.sim.state.duplicate()
	var dry_stats := {answered = 0, strikes = 0, unsound = 0, refused_clear = 0}
	for i in 1000:
		var state := dry_origin.duplicate()
		state[RB.POS + 2] += _rng.randf_range(-0.3, 0.3)
		_turn(state, 0.6)
		var answer: int = dry._native_stage.prop_strike_clear(state, dry._prop_disc, dry._lake)
		var depth: float = float(HullContact.prop_disc_depth(state, dry._prop_disc, dry._lake, time_s).depth)
		if depth > 0.0:
			dry_stats.strikes += 1
		if answer == 1:
			dry_stats.answered += 1
			if not (depth <= 0.0):
				dry_stats.unsound += 1
		elif depth <= 0.0:
			dry_stats.refused_clear += 1
	_check(id + ": without a lake the native stage proves every clear state and only those",
		dry_stats.unsound == 0 and dry_stats.refused_clear == 0 and dry_stats.answered > 300 and dry_stats.strikes > 50,
		str(dry_stats))
	print("NK6K_STRIKE_DRY %s %s" % [id, str(dry_stats)])
	dry.free()


## Rotate the state's attitude by a random angle up to max_turn, renormalized in float64.
func _turn(state: PackedFloat64Array, max_turn: float) -> void:
	var q := Quaternion(Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)).normalized(),
		_rng.randf_range(-max_turn, max_turn)) * Quaternion(state[RB.ATT + 1], state[RB.ATT + 2], state[RB.ATT + 3], state[RB.ATT])
	var n := sqrt(float(q.w) * q.w + float(q.x) * q.x + float(q.y) * q.y + float(q.z) * q.z)
	state[RB.ATT] = q.w / n
	state[RB.ATT + 1] = q.x / n
	state[RB.ATT + 2] = q.y / n
	state[RB.ATT + 3] = q.z / n


## NK-6l: tick pairs around a rolling endpoint, a third of them at the lake's bank or over its water. The terminal
## answer is checked where the guard asks for it: aircraft without finite fuel.
func _hull(id: String) -> void:
	var s := _session(id, true, Flight.START_RUNWAY)
	s.read_raw = func() -> Dictionary: return {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.2}
	for i in 120:
		_tick(s)
	var origin: PackedFloat64Array = s.sim.state.duplicate()
	var bank := LakeCollision._polygon_bounds(_lake.bank_ne_m)
	var terminal_checked: bool = not s.finite_fuel_is_active()
	var stats := {quiet = 0, empty = 0, events = 0, touching = 0, unsound_quiet = 0, unsound_empty = 0, refused_far_empty = 0}
	for i in 3000:
		var previous := origin.duplicate()
		if i % 3 == 0:
			previous[RB.POS] = lerpf(bank[0], bank[1], _rng.randf_range(-0.2, 1.2))
			previous[RB.POS + 1] = lerpf(bank[2], bank[3], _rng.randf_range(-0.2, 1.2))
		else:
			previous[RB.POS] += _rng.randf_range(-20.0, 20.0)
			previous[RB.POS + 1] += _rng.randf_range(-20.0, 20.0)
		previous[RB.POS + 2] += _rng.randf_range(-0.4, 0.4)
		for axis: int in 3:
			previous[RB.VEL + axis] += _rng.randf_range(-3.0, 3.0)
		_turn(previous, 0.5)
		var state := previous.duplicate()
		for axis: int in 3:
			state[RB.POS + axis] += _rng.randf_range(-0.05, 0.05)
		_turn(state, 0.05)
		var bits: int = s._native_stage.hull_guard(previous, state, s._hull_contact)
		var contacts: Array = HullContact.contacts(previous, state, s._hull_contact)
		if not contacts.is_empty():
			stats.touching += 1
		if bits & 2:
			stats.empty += 1
			if not contacts.is_empty():
				stats.unsound_empty += 1
		elif contacts.is_empty() and HullContact._hull_clear_of_lake(state, s._hull_contact):
			# Away from the lake by the reference's own bound (the reach padded for the quaternion's length).
			stats.refused_far_empty += 1
		if terminal_checked:
			var hit: Dictionary = HullContact.terminal(previous, state, s._hull_contact)
			if int(hit.index) >= 0:
				stats.events += 1
			if bits & 1:
				stats.quiet += 1
				if int(hit.index) >= 0:
					stats.unsound_quiet += 1
	_check(id + ": every native empty-contacts answer matches HullContact.contacts",
		stats.unsound_empty == 0 and stats.empty > 1000, str(stats))
	_check(id + ": away from the lake the native stage proves every empty contact set", stats.refused_far_empty == 0,
		str(stats))
	_check(id + ": contacts occur and stay with the reference", stats.touching > 100, str(stats))
	if terminal_checked:
		_check(id + ": every native quiet terminal matches HullContact.terminal",
			stats.unsound_quiet == 0 and stats.quiet > 1000, str(stats))
	_check(id + ": another hull dictionary is refused",
		s._native_stage.hull_guard(s.sim.previous, s.sim.state, s._hull_contact.duplicate()) == 0)
	print("NK6L_HULL %s terminal_checked=%s %s" % [id, str(terminal_checked), str(stats)])
	s.free()


func _state(position: PackedFloat64Array) -> PackedFloat64Array:
	var s := PackedFloat64Array()
	s.resize(RB.SIZE)
	for axis: int in 3:
		s[RB.POS + axis] = position[axis]
		s[RB.VEL + axis] = _rng.randf_range(-20.0, 20.0)
		s[RB.RATE + axis] = _rng.randf_range(-2.0, 2.0)
	var q := Quaternion(Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)).normalized(),
		_rng.randf_range(-0.6, 0.6)).normalized()
	s[RB.ATT] = q.w
	s[RB.ATT + 1] = q.x
	s[RB.ATT + 2] = q.y
	s[RB.ATT + 3] = q.z
	return s


func _advance(previous: PackedFloat64Array, max_move: float, max_turn: float) -> PackedFloat64Array:
	var s := previous.duplicate()
	for axis: int in 3:
		s[RB.POS + axis] += _rng.randf_range(-max_move, max_move)
	var q := Quaternion(s[RB.ATT + 1], s[RB.ATT + 2], s[RB.ATT + 3], s[RB.ATT])
	q = (q * Quaternion(Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)).normalized(),
		_rng.randf_range(-max_turn, max_turn))).normalized()
	s[RB.ATT] = q.w
	s[RB.ATT + 1] = q.x
	s[RB.ATT + 2] = q.y
	s[RB.ATT + 3] = q.z
	return s


func _tick(s: Node) -> void:
	var dt: float = s.sim.dt()
	s._physics_process(dt)
	s.sim._physics_process(dt)


func _pair(id: String, scenario: String) -> void:
	var a := _session(id, true, Flight.START_RUNWAY)
	var b := _session(id, false, Flight.START_RUNWAY)
	var raw := func() -> Dictionary: return {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 1.0}
	if scenario == "shore":
		# Taxi slowly along the lake's bank, where the bank box decides and the sweep sometimes runs.
		var bank := LakeCollision._polygon_bounds(_lake.bank_ne_m)
		for s: Node in [a, b]:
			var state: PackedFloat64Array = s.sim.state.duplicate()
			state[RB.POS] = bank[0] - 6.0
			state[RB.POS + 1] = (bank[2] + bank[3]) * 0.5
			s.sim.state = state
			s.sim.previous = state.duplicate()
		raw = func() -> Dictionary: return {roll = 0.0, pitch = 0.0, yaw = 0.3, throttle = 0.35}
	elif scenario == "hard_landing":
		for s: Node in [a, b]:
			var state: PackedFloat64Array = s.sim.state.duplicate()
			state[RB.POS + 2] -= 1.2
			state[RB.VEL + 2] = 7.0 # body-down sink onto the gear
			s.sim.state = state
			s.sim.previous = state.duplicate()
		raw = func() -> Dictionary: return {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.0}
	elif scenario == "nose_over":
		# test_prop_strike's nose-over: pitch the resting airplane nose-down until the blade tips sit 1 cm above the
		# runway, rolling at 4 m/s at full power.
		for s: Node in [a, b]:
			var rest: PackedFloat64Array = s.sim.state.duplicate()
			var state := rest.duplicate()
			var pitch := 0.0
			while pitch > -0.6:
				pitch -= 0.002
				var qn := M.q_mul(RB._att(rest), M.q_from_euler(0, pitch, 0))
				for k in 4:
					state[RB.ATT + k] = qn[k]
				if HullContact.prop_disc_depth(state, s._prop_disc).depth > -0.01:
					break
			var forward := M.q_rotate(M.q_conj(RB._att(state)), M.v3(4.0, 0.0, 0.3))
			for k in 3:
				state[RB.VEL + k] = forward[k]
			s.sim.state = state
			s.sim.previous = state.duplicate()
	a.read_raw = raw
	b.read_raw = raw
	var same := true
	var first := ""
	for i in 1440:
		_tick(a)
		_tick(b)
		if var_to_bytes(a.checkpoint()) != var_to_bytes(b.checkpoint()):
			same = false
			first = "tick %d" % a.sim.tick
			break
		if not a.crash.is_empty():
			break
	_check("%s %s: both shortcuts on and off fly byte-identical" % [id, scenario], same, first)
	var why_a := str(a.crash.get("why", ""))
	if scenario == "hard_landing":
		_check("%s hard landing: both decide the same crash on the same tick" % id, a.sim.tick == b.sim.tick
			and why_a == str(b.crash.get("why", "")) and a.crash.get("speed") == b.crash.get("speed")
			and a.crash.get("sink") == b.crash.get("sink"), str([why_a, str(b.crash.get("why", ""))]))
	print("NK6G_PAIR %s %s ticks=%d crash=%s why=%s native_collapse=%d native_strike=%d strike_tick=%s" % [id, scenario,
		a.sim.tick, str(not a.crash.is_empty()), why_a, a.native_guard_collapse_answers, a.native_prop_strike_answers,
		str(a.prop_strike.get("tick", "-"))])
	_check("%s %s: both decide the same propeller strike" % [id, scenario],
		var_to_bytes(a.prop_strike) == var_to_bytes(b.prop_strike), str([a.prop_strike, b.prop_strike]))
	if scenario == "nose_over":
		_check("%s nose-over: the propeller strikes" % id, not a.prop_strike.is_empty())
	if scenario in ["roll", "nose_over"]:
		_check("%s %s: the native stage answered the guard's hull checks" % [id, scenario], a.native_hull_guard_answers > 100,
			str(a.native_hull_guard_answers))
	if scenario == "roll":
		_check("%s roll: the native guard answered the collapse" % id, a.native_guard_collapse_answers > 1000,
			str(a.native_guard_collapse_answers))
		_check("%s roll: the native stage answered the propeller check" % id, a.native_prop_strike_answers > 300,
			str(a.native_prop_strike_answers))
	a.free()
	b.free()
