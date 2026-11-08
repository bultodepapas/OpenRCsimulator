## CF-05: interior contacts, composed surface, threshold ownership and atomic refusal.
extends SceneTree

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const Track := preload("res://physics/ground_vehicle/airfield_track.gd")
const Crossing := preload("res://physics/rc_track_crossing.gd")
const Pose := preload("res://sim/scenery_collision.gd")
const Session := preload("res://sim/flight_session.gd")
const LakeLoader := preload("res://data/lake_loader.gd")
const Terrain := preload("res://physics/ground_terrain.gd")
const Impact := preload("res://physics/impact_snapshot.gd")

var checks := 0
var failures := 0
var point := PackedFloat64Array([0.0, 0.0, 0.0])


class ObservedSession extends Session:
	var observed_sweep: Array[PackedFloat64Array] = []
	func _resolve_collision_step(previous: PackedFloat64Array, candidate: PackedFloat64Array,
			tick: int, mass_sample: Callable = Callable()) -> PackedFloat64Array:
		observed_sweep.assign([previous.duplicate(), candidate.duplicate()])
		return super._resolve_collision_step(previous, candidate, tick, mass_sample)


class ThreeWaySession extends Session:
	func _rc_track_hit(_p: PackedFloat64Array, _c: PackedFloat64Array, _tick: int) -> Dictionary:
		return {ok = true, impact = Impact.Snapshot.new(), fraction = 0.5,
			uncertainty = 0.02, state = PackedFloat64Array()}
	func _scenery_hit(_p: PackedFloat64Array, _c: PackedFloat64Array, _tick: int, _mass: Callable) -> Dictionary:
		var event := Pose.Event.new()
		event.time_fraction = 0.5
		return {ok = true, event = event}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var loaded := Track.load_default()
	_check("stock track loads", loaded.ok)
	if not loaded.ok:
		quit(1)
		return
	var track: Dictionary = loaded.track
	var previous := _state(39.0, -4.0, 1.0)
	var below_datum := _state(39.0, -4.0, -0.1)
	var hit := Crossing.first(previous, below_datum, point, track, PackedFloat64Array(), 0.05)
	var expected: float = (1.0 - float(Track.sample(track, 39.0, -4.0).height_m)) / 1.1
	_check("tabletop crossing survives a final pose below datum", hit.ok and hit.index == 0 \
		and absf(hit.fraction - expected) < Crossing.FRACTION_TOLERANCE)
	var roller_a := _state(51.0, -4.5, 0.154)
	var roller_b := _state(51.0, -3.5, 0.154)
	_check("roller endpoints clear but middle penetrates", _depth(roller_a, track) < 0.0 \
		and _depth(roller_b, track) < 0.0 and _depth(Pose.state_at_fraction(roller_a, roller_b, 0.5), track) > 0.0)
	var roller := Crossing.first(roller_a, roller_b, point, track, PackedFloat64Array(), 0.05)
	_check("two-clear-endpoint roller enters before its crest", roller.ok and roller.index == 0 \
		and roller.fraction > 0.0 and roller.fraction < 0.5)
	if roller.ok and roller.index >= 0:
		var oracle := _first_monotone_root(roller_a, roller_b, track, 0.5)
		_check("roller agrees with independent monotone first-root oracle", absf(roller.fraction - oracle) < Crossing.FRACTION_TOLERANCE)
		_check("reported pose actually penetrates", _depth(Pose.state_at_fraction(roller_a, roller_b, roller.fraction), track) > 0.0)
	var clear_a := _state(51.0, -4.5, 0.156)
	var clear_b := _state(51.0, -3.5, 0.156)
	var clear := Crossing.first(clear_a, clear_b, point, track, PackedFloat64Array(), 0.05)
	_check("near-crest clear sweep is proven clear", clear.ok and clear.index == -1)
	_check("budget exhaustion refuses instead of clearing", not Crossing.first(roller_a, roller_b, point,
		track, PackedFloat64Array(), 0.05, {}, 1).ok)
	var many := PackedFloat64Array()
	for index in 20: many.append_array(point)
	_check("one budget covers all hull points", not Crossing.first(_state(0.0, 0.0, 10.0),
		_state(0.0, 0.0, 10.1), many, track, PackedFloat64Array(), 0.05, {}, 12).ok)
	var outside := track.duplicate(true)
	outside.ramps[0].east_m = 21.0
	_check("custom clipped feature remains valid", Track.valid(outside))
	var outside_a := _state(39.0, 20.9, 0.1)
	var outside_b := _state(39.0, 21.1, 0.1)
	var clipped := Crossing.first(outside_a, outside_b, point, outside, PackedFloat64Array(), 0.05)
	_check("out-of-footprint uncut feature cannot exhaust a clear sweep", clipped.ok and clipped.index == -1)
	_test_rotation(track)
	_test_height_envelopes(track)
	_test_threshold(track)
	_test_stock_hull(track)
	_test_session(track, previous, below_datum)
	_test_three_way_order()
	_test_lake(track)
	print("CF-05 track crossing: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)


func _test_rotation(track: Dictionary) -> void:
	var a := _state(39.0, -4.0, 1.15)
	var b := a.duplicate()
	var q := M.q_from_euler(0.0, 0.0, PI)
	for axis in 4: b[RB.ATT + axis] = q[axis]
	var hull := PackedFloat64Array([0.0, 1.0, 0.0])
	var found := Crossing.first(a, b, hull, track, PackedFloat64Array(), 0.05)
	_check("rotating point with clear endpoints finds an interior contact", found.ok and found.index == 0 \
		and found.fraction > 0.0 and found.fraction < 0.5)
	for axis in 4: b[RB.ATT + axis] = -b[RB.ATT + axis]
	var signed := Crossing.first(a, b, hull, track, PackedFloat64Array(), 0.05)
	_check("quaternion sign retains shortest path contact", signed.ok and found.ok and signed.fraction == found.fraction)
	# The resolver permits a small norm tolerance; use its raw endpoint interpolation.
	for axis in 4:
		a[RB.ATT + axis] *= 1.0 + 1.0e-10
		b[RB.ATT + axis] *= 1.0 - 1.0e-10
	var scaled := Crossing.first(a, b, hull, track, PackedFloat64Array(), 0.05)
	_check("accepted nonunit endpoint tolerance remains bounded", scaled.ok and scaled.index == 0 \
		and absf(scaled.fraction - found.fraction) < Crossing.FRACTION_TOLERANCE)


func _test_height_envelopes(track: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 50612026
	var bounded := true
	# Independent witnesses complement the factor/interval derivation; samples
	# are regression controls, not a proof of conservative coverage.
	for trial in 800:
		var north: float = rng.randf_range(20.0, 56.0)
		var east: float = rng.randf_range(-23.0, 23.0)
		var reach: float = rng.randf_range(0.0, 1.5)
		var upper: float = Track.height_upper_bound(track, north, east, reach)
		for dn: float in [-reach, 0.0, reach]:
			for de: float in [-reach, 0.0, reach]:
				bounded = bounded and float(Track.sample(track, north + dn, east + de).height_m) <= upper + 1.0e-12
	_check("interval envelopes retain capsule/mask/ramp boundary witnesses", bounded)
	for east: float in [-5.225, -4.225, -4.0, -3.775, -1.975]:
		var upper: float = Track.height_upper_bound(track, 39.0, east, 1.0e-9)
		_check("tabletop seam enclosed at %.3f" % east, float(Track.sample(track, 39.0, east).height_m) <= upper + 1.0e-12)
	_check("local plateau envelope stays exact", absf(Track.height_upper_bound(track, 39.0, -4.0, 0.02) - 0.515) < 1.0e-15)


func _test_threshold(track: Dictionary) -> void:
	var pad := track.duplicate(true)
	pad.bank_height_m = 0.0
	for group in ["ramps", "rollers"]:
		for feature: Dictionary in pad[group]: feature.height_m = 0.0
	var a := _state(39.0, 0.0, 0.04)
	for height: float in [0.05 - 1.0e-12, 0.05, 0.05 + 1.0e-12]:
		pad.pad_height_m = height
		var found := Crossing.first(a, a, point, pad, PackedFloat64Array(), 0.05)
		_check("relief threshold %.15f is inclusive" % height, found.ok \
			and (found.index == 0) == (height >= 0.05))
	var below := _state(39.0, 0.0, -0.01)
	var found := Crossing.first(below, below, point, pad, PackedFloat64Array(), 0.05)
	_check("flat-datum half-space keeps ownership", found.ok and found.index == -1)
	# Already inside the height surface, but only later enters the qualifying relief.
	var enter_a := _state(39.0, -5.3, 0.04)
	var enter_b := _state(39.0, -4.8, 0.04)
	var entered := Crossing.first(enter_a, enter_b, point, track, PackedFloat64Array(), 0.05)
	_check("eligibility threshold crossing is searched independently of depth", entered.ok and entered.index == 0)


func _test_stock_hull(track: Dictionary) -> void:
	var session := ObservedSession.new()
	session.input_enabled = false
	session.crash_auto_restart = false
	session.setup("res://data/aircraft/f4u_corsair_250.json")
	_check("stock Corsair fixture loads", session.aircraft.get("ok", false))
	if not session.aircraft.get("ok", false):
		session.free()
		return
	var hull: PackedFloat64Array = session.aircraft.model.crash_hull
	var q := M.q_from_euler(0.0, 0.0, 0.6)
	var lowest := PackedFloat64Array([0.0, 0.0, -INF])
	for offset in range(0, hull.size(), 3):
		var rotated := M.q_rotate(q, hull.slice(offset, offset + 3))
		if rotated[2] > lowest[2]: lowest = rotated
	var a := _state(51.0 - lowest[0], -4.5 - lowest[1], 0.154 + lowest[2])
	var b := a.duplicate()
	b[RB.POS + 1] += 1.0
	for axis in 4:
		a[RB.ATT + axis] = q[axis]
		b[RB.ATT + axis] = q[axis]
	var found := Crossing.first(a, b, hull, track, PackedFloat64Array(), 0.05)
	_check("all 23 stock hull points retained", hull.size() == 69)
	_check("stock tilted hull catches the interior roller", found.ok and found.index >= 0 and found.fraction < 0.5)
	# A real production RK tick, distinct from the controlled geometry/rollback
	# fixtures below. No solver callbacks or stock crash probes are substituted.
	_check("real tick installs circuit", session.set_rc_track(track))
	var peak: float = session.environment.ground(51.0, -4.0)[0]
	var actual_a := _state(51.0 - lowest[0], -4.05 - lowest[1], peak - 0.0002 + lowest[2])
	for axis in 4: actual_a[RB.ATT + axis] = q[axis]
	var velocity := M.q_rotate(PackedFloat64Array([q[0], -q[1], -q[2], -q[3]]), PackedFloat64Array([0.0, 24.0, 0.0]))
	for axis in 3: actual_a[RB.VEL + axis] = velocity[axis]
	session.soft_hull_contacts = false
	_check("stock hull real tick installs circuit and resets", session.set_rc_track(track) and session.sim.reset(actual_a))
	session.sim.set_paused(false)
	session.sim.step()
	var raw: Array[PackedFloat64Array] = session.observed_sweep
	_check("production RK tick accepts interior stock-hull contact", session.sim.tick == 1 \
		and session.sim.fault_reason.is_empty() and not session.crash.is_empty())
	if raw.size() == 2:
		_check("real raw RK endpoints are both track-clear", _all_clear(raw[0], hull, track, session.ground_surfaces) \
			and _all_clear(raw[1], hull, track, session.ground_surfaces))
	else: _check("real RK candidate captured", false)
	session.free()


func _test_session(track: Dictionary, previous: PackedFloat64Array, candidate: PackedFloat64Array) -> void:
	for refuse: bool in [false, true]:
		var session := Session.new()
		session.input_enabled = false
		session.crash_auto_restart = false
		session.setup()
		session.aircraft.model.crash_hull = point
		session.aircraft.model.landing_gear = {}
		session._prop_disc = {}
		_check("session track installs", session.set_rc_track(track))
		session.sim.continuous = PackedFloat64Array()
		session.sim.gravity = 0.0
		for key: String in ["step_policy", "stage", "block_loads", "block_derivative", "stage_rotor_momentum", "block_aux", "pre_tick"]:
			session.sim.model.set(key, Callable())
		session.sim.model.pre_tick = func(aux: PackedFloat64Array, _inputs: PackedFloat64Array, _dt: float) -> PackedFloat64Array:
			return aux.duplicate()
		session.sim.model.loads = func(_s: PackedFloat64Array, _t: float) -> PackedFloat64Array:
			return PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
		_check("controlled source reset", session.sim.reset(previous))
		session.sim.model.post_tick = func(_p: PackedFloat64Array, _c: PackedFloat64Array, tick: int) -> PackedFloat64Array:
			var filtered: PackedFloat64Array = session._resolve_collision_step(previous, candidate, tick)
			_check("staged impact stays private", session.crash.is_empty())
			return PackedFloat64Array() if refuse else filtered
		var accepted_before: PackedByteArray = session.sim.state.to_byte_array()
		session.sim.set_paused(false)
		session.sim.step()
		if refuse:
			_check("post-contact refusal rolls back body and publishes no crash", session.sim.tick == 0 \
				and session.sim.state.to_byte_array() == accepted_before and session.crash.is_empty() \
				and not session.sim.fault_reason.is_empty())
		else:
			_check("accepted tick publishes earlier raised contact", session.sim.tick == 1 and not session.crash.is_empty() \
				and session.sim.state[RB.POS + 2] < 0.0 and session.sim.fault_reason.is_empty())
		var collision := {impact = RefCounted.new(), fraction = 0.5, uncertainty = 3.0e-8}
		_check("competing event inside uncertainty refuses arbitration", session._rc_track_order_unresolved(collision, 0.5 - 1.0e-8))
		_check("separated event has known ordering", not session._rc_track_order_unresolved(collision, 0.5 - 1.0e-6))
		collision.uncertainty = 0.0
		_check("exact tie retains existing policy", not session._rc_track_order_unresolved(collision, 0.5))
		collision.uncertainty = 0.8e-12
		_check("uncertainty below tie cannot cross the winner boundary", session._rc_track_order_unresolved(collision, 0.5 + 0.5e-12))
		session.free()


func _test_three_way_order() -> void:
	var session := ThreeWaySession.new()
	session.input_enabled = false
	session.crash_auto_restart = false
	session.setup()
	session.aircraft.model.crash_hull = point
	session.soft_hull_contacts = false
	session._collision_world = {proxies = [{}]}
	var a := _state(39.0, -4.0, 0.01)
	var b := _state(39.0, -4.0, -0.09)
	var filtered: PackedFloat64Array = session._resolve_collision_step(a, b, 1)
	_check("early ground wins despite uncertain later track/scenery pair", not filtered.is_empty() \
		and session._pending_crash != null and absf(filtered[RB.POS + 2]) < 1.0e-10)
	session.free()


func _test_lake(track: Dictionary) -> void:
	var loaded := LakeLoader.load_from("res://data/fields/lake.json")
	_check("lake fixture loads", loaded.ok)
	if not loaded.ok: return
	var lake: Dictionary = loaded.lake
	# Move the stock bank/bed over the tabletop; use only normalized scalar geometry.
	for key: String in ["shoreline_ne_m", "bank_ne_m"]:
		for offset in range(0, lake[key].size(), 2):
			lake[key][offset] -= 71.0
			lake[key][offset + 1] -= 129.0
	lake.identity = LakeLoader.identity(lake)
	var session := Session.new()
	session.input_enabled = false
	session.setup()
	session.aircraft.model.crash_hull = point
	session.aircraft.model.landing_gear = {}
	session._prop_disc = {}
	_check("custom normalized lake and circuit admitted by real session", session.set_lake_context(lake) and session.set_rc_track(track))
	var a := _state(39.0, -4.0, 0.3)
	_check("shifted lake depresses the tabletop base", Terrain.sample_validated(39.0, -4.0, PackedFloat64Array(), lake)[0] < -0.3)
	var result := Crossing.first(a, a, point, track, PackedFloat64Array(), 0.05, lake)
	_check("dry upper envelope cannot fabricate lake-depressed contact", result.ok and result.index == -1)
	var session_result: Dictionary = session._rc_track_hit(a, a, 1)
	_check("session also respects the lake-depressed base", session_result.ok and session_result.impact == null)
	var b := a.duplicate()
	b[RB.POS + 1] += 0.02
	var moving: Dictionary = session._rc_track_hit(a, b, 1)
	_check("moving clear path over depressed bed remains available", moving.ok and moving.impact == null)
	var mismatched := lake.duplicate(true)
	for offset in range(0, mismatched.bank_ne_m.size(), 2): mismatched.bank_ne_m[offset] += 1000.0
	mismatched.identity = LakeLoader.identity(mismatched)
	_check("structural admission does not imply nested lake polygons", session.set_lake_context(mismatched))
	var dry_hit: Dictionary = session._rc_track_hit(_state(39.0, -4.0, 1.0), _state(39.0, -4.0, 0.3), 1)
	_check("shore without covering bank cannot prune dry-track contact", dry_hit.ok and dry_hit.impact != null)
	var narrow: Dictionary = LakeLoader.load_from("res://data/fields/lake.json").lake
	narrow.shoreline_ne_m = PackedFloat64Array([38.0, -5.0, 38.5, -5.0, 39.0, -5.0, 39.0, -4.5, 39.0, -3.0, 38.5, -3.0, 38.0, -3.0, 38.0, -4.0])
	var bank_edge := 39.0 + 1.5e-8
	narrow.bank_ne_m = PackedFloat64Array([37.0, -6.0, 38.0, -6.0, bank_edge, -6.0, bank_edge, -4.5, bank_edge, -2.0, 38.0, -2.0, 37.0, -2.0, 37.0, -4.0])
	narrow.identity = LakeLoader.identity(narrow)
	_check("epsilon-width custom bank admits structurally", session.set_lake_context(narrow))
	var edge_result: Dictionary = session._rc_track_hit(_state(39.0 + 0.5e-8, -4.0, 0.3), _state(39.0 + 1.3e-8, -4.0, 0.3), 1)
	_check("polygon tolerance band cannot falsely declare a crossing clear", not edge_result.ok or edge_result.impact != null)
	session.free()


func _state(north: float, east: float, up: float) -> PackedFloat64Array:
	return RB.make_state(PackedFloat64Array([north, east, -up]), PackedFloat64Array([0.0, 0.0, 0.0]),
		M.q_from_euler(0.0, 0.0, 0.0), PackedFloat64Array([0.0, 0.0, 0.0]))


func _depth(state: PackedFloat64Array, track: Dictionary) -> float:
	return float(Track.sample(track, state[RB.POS], state[RB.POS + 1]).height_m) + state[RB.POS + 2]


func _all_clear(state: PackedFloat64Array, hull: PackedFloat64Array, track: Dictionary, surfaces: PackedFloat64Array) -> bool:
	for offset in range(0, hull.size(), 3):
		var p := M.add(RB._slice3(state, RB.POS), M.q_rotate(RB._att(state), hull.slice(offset, offset + 3)))
		var relief: float = float(Track.sample(track, p[0], p[1]).height_m)
		if relief >= 0.05 and relief + Terrain.sample_validated(p[0], p[1], surfaces)[0] + p[2] > 0.0:
			return false
	return true


func _first_monotone_root(a: PackedFloat64Array, b: PackedFloat64Array, track: Dictionary, end: float) -> float:
	var low := 0.0
	var high := end
	for iteration in 70:
		var mid := 0.5 * (low + high)
		if _depth(Pose.state_at_fraction(a, b, mid), track) > 0.0: high = mid
		else: low = mid
	return high


func _check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL " + label)
