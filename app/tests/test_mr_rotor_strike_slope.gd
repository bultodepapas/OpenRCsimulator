# DR-19 (FPV audit 2026-11-16, A07): a spinning rotor disc that reaches sloped terrain is a propeller strike wherever
# its rim meets the surface, not only at the rim point lowest in the world. Expected values are closed forms of the
# plane geometry (rim penetration = r·|slope across the disc| − hub clearance) cross-checked by a brute-force 720-point
# rim scan, never crash_reason itself. Fixture and shipped data both run; the shipped RC ramp case reproduces the
# audit's constructed endpoint. Software checks on estimated data: no physical contact validation.
extends SceneTree

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const Data := preload("res://physics/multirotor_data.gd")
const Plant := preload("res://physics/multirotor/controlled_plant.gd")
const FC := preload("res://physics/multirotor/flight_controller.gd")
const Rates := preload("res://physics/multirotor/rates.gd")
const Fixtures := preload("res://tests/mr_fixtures.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const Track := preload("res://physics/ground_vehicle/airfield_track.gd")
const Session := preload("res://sim/multirotor/session.gd")
const Catalog := preload("res://vehicles/multirotor/multirotor_catalog.gd")

const SPIN := 1000.0
const SLOPE := 0.5
const STRIKE := "Propeller strike"

var _count := 0
var _failures := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if not ok:
		_failures += 1
	print("%s %s %s" % ["ok  " if ok else "FAIL", label, detail])


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_suite("fixture", Fixtures.electric())
	var loaded: Dictionary = Data.load_file(Catalog.DATA_PATH)
	var made: Dictionary = Data.prepare(loaded.data, str(loaded.get("sha256", ""))) if loaded.get("ok", false) else {}
	if made.get("ok", false):
		_suite("shipped", made.prepared)
	else:
		_check("shipped data prepares", false, str(loaded.get("errors", [])) + str(made.get("errors", [])))
	_rc_ramp()
	print("rotor strike on slopes: %d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)


## Height field h(n,e) = 0.5·n (height up) with its production slope contract.
func _plane(n: float, _e: float) -> PackedFloat64Array:
	return PackedFloat64Array([SLOPE * n, SLOPE, 0.0])


func _flat(_n: float, _e: float) -> PackedFloat64Array:
	return PackedFloat64Array([0.0, 0.0, 0.0])


func _height(ground: Callable, north: float, east: float) -> float:
	return float(ground.call(north, east)[0]) if ground.is_valid() else 0.0


## {body, rotor}: a stationary body whose least-clear hub is exactly `clearance` above the terrain (negative = below).
func _pose(data: Dictionary, attitude: PackedFloat64Array, clearance: float, north: float, east: float, ground: Callable) -> Dictionary:
	var worst := -INF
	var rotor_index := 0
	for i in 4:
		var offset: PackedFloat64Array = M.q_rotate(attitude, data.rotors[i].hub_frd)
		var value: float = offset[2] + _height(ground, north + offset[0], east + offset[1])
		if value > worst:
			worst = value
			rotor_index = i
	var zero: PackedFloat64Array = M.v3(0.0, 0.0, 0.0)
	return {body = RB.make_state(M.v3(north, east, -clearance - worst), zero, attitude, zero), rotor = rotor_index}


## Deepest rim penetration over all four discs (disc in the body x-y plane), 720 points each; the test's own oracle.
func _brute(data: Dictionary, body: PackedFloat64Array, ground: Callable) -> float:
	var attitude: PackedFloat64Array = M.quat(body[RB.ATT], body[RB.ATT + 1], body[RB.ATT + 2], body[RB.ATT + 3])
	var best := -INF
	for rotor: Dictionary in data.rotors:
		var radius: float = 0.5 * float(rotor.diameter_m)
		for k in 720:
			var angle: float = TAU * float(k) / 720.0
			var point: PackedFloat64Array = M.add(rotor.hub_frd, M.v3(radius * cos(angle), radius * sin(angle), 0.0))
			var offset: PackedFloat64Array = M.q_rotate(attitude, point)
			var h: float = _height(ground, body[RB.POS] + offset[0], body[RB.POS + 1] + offset[1])
			best = maxf(best, body[RB.POS + 2] + offset[2] + h)
	return best


func _reason(plant: RefCounted, body: PackedFloat64Array, speeds: Array) -> String:
	var continuous: PackedFloat64Array = plant.initial_frame(body).continuous
	for i in 4:
		continuous[i] = float(speeds[i])
	return plant.crash_reason(body, body, continuous)


func _all(speed: float) -> Array:
	return [speed, speed, speed, speed]


func _suite(tag: String, data: Dictionary) -> void:
	var made: Dictionary = Plant.create(data, Rates.default_profile(), FC.THROTTLE_ABSOLUTE)
	if not made.get("ok", false):
		_check("%s plant prepared" % tag, false, str(made.get("errors", [])))
		return
	var p: RefCounted = made.plant
	var radius: float = 0.5 * float(data.rotors[0].diameter_m)
	var strike_speed: float = float(data.contacts.rotor_strike_speed_rad_s)
	var plane := Callable(self, "_plane")
	var flat := Callable(self, "_flat")
	var level: PackedFloat64Array = M.q_identity()

	# 1. The audit's analytic uphill rim: level disc, least-clear hub 2 cm above its local terrain, several yaws.
	p.ground = plane
	for yaw_deg: float in [0.0, 90.0, 135.0, 200.0]:
		var pose: Dictionary = _pose(data, M.q_from_euler(deg_to_rad(yaw_deg), 0.0, 0.0), 0.02, 10.0, -3.0, plane)
		var brute: float = _brute(data, pose.body, plane)
		var expected: float = SLOPE * radius - 0.02
		var reason: String = _reason(p, pose.body, _all(SPIN))
		_check("%s plane h=0.5n, yaw %.0f: the uphill rim penetrates by r·0.5−0.02 and is a propeller strike" % [tag, yaw_deg],
			absf(brute - expected) < 1.0e-4 and brute > 0.0 and reason == STRIKE, "brute %.6f m, expected %.6f, '%s'" % [brute, expected, reason])
	var graze_in: Dictionary = _pose(data, level, 0.5 * SLOPE * radius + 0.4 * (SLOPE * radius - 0.5 * SLOPE * radius), 10.0, -3.0, plane)
	var in_depth: float = _brute(data, graze_in.body, plane)
	var graze_out: Dictionary = _pose(data, level, SLOPE * radius + 0.003, 10.0, -3.0, plane)
	var out_depth: float = _brute(data, graze_out.body, plane)
	_check("%s plane: a rim just under the slope strikes, 3 mm clear of it does not" % tag,
		in_depth > 0.0 and _reason(p, graze_in.body, _all(SPIN)) == STRIKE
		and out_depth < 0.0 and _reason(p, graze_out.body, _all(SPIN)).is_empty(), "%.6f / %.6f m" % [in_depth, out_depth])

	# 2. Tilted disc over flat ground: rim drop r·sin(30°).
	p.ground = flat
	for tilt: Array in [["pitch +30", M.q_from_euler(0.0, deg_to_rad(30.0), 0.0)], ["roll -30", M.q_from_euler(0.0, 0.0, deg_to_rad(-30.0))]]:
		var low: Dictionary = _pose(data, tilt[1], 0.02, 5.0, 2.0, flat)
		var high: Dictionary = _pose(data, tilt[1], 0.04, 5.0, 2.0, flat)
		_check("%s flat ground, %s deg: rim under the ground strikes, 7.6 mm clear does not" % [tag, tilt[0]],
			_brute(data, low.body, flat) > 0.0 and _reason(p, low.body, _all(SPIN)) == STRIKE
			and _brute(data, high.body, flat) < 0.0 and _reason(p, high.body, _all(SPIN)).is_empty())

	# 3. A disc parallel to the slope: no rim penetration with the hubs clear; a buried hub strikes.
	p.ground = plane
	var parallel: PackedFloat64Array = M.q_from_euler(0.0, atan(SLOPE), 0.0)
	var clear: Dictionary = _pose(data, parallel, 0.01, 10.0, -3.0, plane)
	if _brute(data, clear.body, plane) > -0.009:
		parallel = M.q_from_euler(0.0, -atan(SLOPE), 0.0) # the other pitch sign convention
		clear = _pose(data, parallel, 0.01, 10.0, -3.0, plane)
	var buried: Dictionary = _pose(data, parallel, -0.005, 10.0, -3.0, plane)
	_check("%s disc parallel to the slope, hubs 10 mm clear: no strike; hub 5 mm under the surface: strike" % tag,
		absf(_brute(data, clear.body, plane) + 0.01) < 1.0e-4 and _reason(p, clear.body, _all(SPIN)).is_empty()
		and _reason(p, buried.body, _all(SPIN)) == STRIKE, "%.6f m" % _brute(data, clear.body, plane))

	# 4. A level quad resting on the flat pad: no strike at idle or spinning fast.
	p.ground = flat
	var rest: PackedFloat64Array = _pose(data, level, 0.0215, 0.0, 0.0, flat).body
	_check("%s level quad 21.5 mm over the flat pad: no strike below the threshold or at 1000 rad/s" % tag,
		_reason(p, rest, _all(250.0)).is_empty() and _reason(p, rest, _all(SPIN)).is_empty())

	# 5. Stopped rotors and the strike threshold on the uphill-strike pose.
	p.ground = plane
	var hit: Dictionary = _pose(data, level, 0.02, 10.0, -3.0, plane)
	_check("%s stopped rotors never strike; the threshold speed itself does not, just above it does" % tag,
		_reason(p, hit.body, _all(0.0)).is_empty() and _reason(p, hit.body, _all(strike_speed)).is_empty()
		and _reason(p, hit.body, _all(strike_speed + 0.001)) == STRIKE)
	# Rotors with the same forward hub position share the uphill clearance (left/right symmetry): stop them together.
	var others: Array = _all(SPIN)
	for i in 4:
		if absf(float(data.rotors[i].hub_frd[0]) - float(data.rotors[hit.rotor].hub_frd[0])) < 1.0e-9:
			others[i] = 0.0
	var only: Array = _all(0.0)
	only[hit.rotor] = SPIN
	_check("%s only the intersecting rotors' own speeds decide" % tag,
		_reason(p, hit.body, others).is_empty() and _reason(p, hit.body, only) == STRIKE)

	# 6. Clear hovers over flat ground and over the slope.
	p.ground = flat
	_check("%s clear hover at 0.2 m and 1 m: no strike" % tag, _reason(p, _pose(data, level, 0.2, 0.0, 0.0, flat).body, _all(SPIN)).is_empty()
		and _reason(p, _pose(data, level, 1.0, 0.0, 0.0, flat).body, _all(SPIN)).is_empty())
	p.ground = plane
	_check("%s clear hover 0.3 m above the 0.5 slope: no strike" % tag,
		_reason(p, _pose(data, level, 0.3, 10.0, -3.0, plane).body, _all(SPIN)).is_empty())


## The shipped default RC circuit (audit experiments/rc_ramp_disc.gd): north 39.0, east -5.1, yaw 0, hubs 5 mm clear
## of their sampled terrain; the audit's rim witness penetrates by 0.0283 m.
func _rc_ramp() -> void:
	var field: Dictionary = FieldLoader.load_from(FieldLoader.DEFAULT_PATH)
	var track: Dictionary = Track.load_default()
	if not field.get("ok", false) or not track.get("ok", false):
		_check("RC ramp: field and track load", false)
		return
	var s: Node = Session.new()
	root.add_child(s)
	if not s.prepare(field.field, {rc_track = track.track}):
		_check("RC ramp: session prepares", false, str(s.load_error))
		s.free()
		return
	var ground: Callable = s.plant.ground
	var level: PackedFloat64Array = M.q_identity()
	var hit: Dictionary = _pose(s.data, level, 0.005, 39.0, -5.1, ground)
	var witness: float = _brute(s.data, hit.body, ground)
	_check("RC ramp premise: hubs 5 mm clear, a rim point penetrates by more than 2 cm (audit: 0.0283 m)", witness > 0.02, "%.6f m" % witness)
	_check("RC ramp: the uphill rim is a propeller strike", _reason(s.plant, hit.body, _all(SPIN)) == STRIKE)
	var clear: Dictionary = _pose(s.data, level, 0.05, 39.0, -5.1, ground)
	_check("RC ramp: hubs 50 mm clear is no strike", _brute(s.data, clear.body, ground) < 0.0
		and _reason(s.plant, clear.body, _all(SPIN)).is_empty(), "%.6f m" % _brute(s.data, clear.body, ground))
	s.free()
