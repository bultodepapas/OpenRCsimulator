extends SceneTree
## NK-6q: Simulation.step's own checks and the session's state checks answered by the native kernel.
## - Parity: state_valid, scenery_state_valid, arrays_finite and inertia_cached equal Simulation.state_is_valid,
##   SceneryCollision._state_is_valid, Simulation._array_is_finite and the inertia cache test on random and boundary
##   values (NaN, ±inf, ±0, subnormals, wrong sizes, quaternion norms at 1e-24 and at 1 ± 1.0e-9).
## - A native flight answers through the kernel, and flights are byte-identical with the native checks on and off.
## Skips (passes) without a verified native library.

const Flight := preload("res://sim/flight_session.gd")
const Sim := preload("res://sim/simulation.gd")
const SceneryCollision := preload("res://sim/scenery_collision.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const LakeLoader := preload("res://data/lake_loader.gd")
const NativeStage := preload("res://sim/native_stage.gd")

var _checks := 0
var _failures := 0
var _rng := RandomNumberGenerator.new()


func _initialize() -> void:
	Engine.physics_ticks_per_second = 240
	_run.call_deferred()


func _run() -> void:
	_rng.seed = 6062
	var field: Dictionary = FieldLoader.load_from().field
	var lake: Dictionary = LakeLoader.load_from(LakeLoader.DEFAULT_PATH).lake
	var probe := _session("f4u-corsair-250", field, lake, true)
	if probe == null or probe.stage_backend_identity().backend != NativeStage.BACKEND_NATIVE:
		print("NK6Q_SKIP no native session")
		if probe != null:
			probe.free()
		quit(0)
		return
	_parity(probe._native_stage._native, probe.sim)
	probe.free()
	for id: String in ["f4u-corsair-250", "jensen-das-ugly-stik-60", "stik-glow-61fx-2t"]:
		_pair(id, field, lake)
	print("native state checks: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 or _checks == 0 else 0)


func _session(id: String, field: Dictionary, lake: Dictionary, native_checks: bool) -> Node:
	var s: Node = Flight.new()
	s.input_enabled = true
	s.crash_auto_restart = false
	s.soft_hull_contacts = true
	s.start_choice = Flight.START_RUNWAY
	s.native_state_checks_enabled = native_checks
	s.setup_stage_backend(NativeStage.BACKEND_NATIVE)
	s.setup(Catalog.data_for(id, Catalog.default_battery_mode(id)), id)
	if not s.aircraft.get("ok", false):
		s.free()
		return null
	s.set_field(field)
	s.set_lake_context(lake)
	s.reset()
	if s.glow_is_active() and not bool(s.glow_state().get("running", false)):
		s.glow_start()
	return s


func _value() -> float:
	match _rng.randi() % 12:
		0: return NAN
		1: return INF
		2: return -INF
		3: return 0.0
		4: return -0.0
		5: return 5e-324 * float(_rng.randi_range(1, 4))
		6: return _rng.randf_range(-1.0e300, 1.0e300)
		_: return _rng.randf_range(-2.0, 2.0)


## A body whose quaternion has a chosen norm square near a boundary.
func _body(norm_sq: float) -> PackedFloat64Array:
	var s := PackedFloat64Array()
	for i in 13:
		s.append(_rng.randf_range(-50.0, 50.0))
	var q := PackedFloat64Array([_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)])
	var n := sqrt(q[0] * q[0] + q[1] * q[1] + q[2] * q[2] + q[3] * q[3])
	var k := sqrt(norm_sq) / n
	for i in 4:
		s[6 + i] = q[i] * k
	return s


func _parity(kernel: Object, sim: Node) -> void:
	var mismatches := {state = 0, scenery = 0, arrays = 0, inertia = 0}
	var accepted := {state = 0, scenery = 0, arrays = 0, inertia = 0}
	var samples := 0
	var boundary_sq := [1e-24, 1.0e-24, 1.0000000001e-24, 0.9999999999e-24, 1.0, 1.0 + 1.0e-9, 1.0 - 1.0e-9,
		1.0 + 0.99e-9, 1.0 - 0.99e-9, 1.0 + 1.01e-9, 1.0 - 1.01e-9, 0.0, 4.0]
	for round: int in 20000:
		var s: PackedFloat64Array
		match round % 4:
			0:
				s = _body(boundary_sq[_rng.randi() % boundary_sq.size()])
				# Nudge the norm by a few ulps around its target.
				for step in _rng.randi_range(0, 3):
					var i := 6 + _rng.randi() % 4
					s[i] = s[i] * (1.0 + float(_rng.randi_range(-2, 2)) * 2.220446049250313e-16)
			1:
				s = _body(1.0)
				s[_rng.randi() % 13] = _value()
			2:
				s = PackedFloat64Array()
				for i in [12, 13, 13, 13, 14][_rng.randi() % 5]:
					s.append(_value())
			_:
				s = _body(_rng.randf_range(0.0, 2.0))
		samples += 1
		if bool(kernel.state_valid(s)) != Sim.state_is_valid(s):
			mismatches.state += 1
		if bool(kernel.scenery_state_valid(s)) != SceneryCollision._state_is_valid(s):
			mismatches.scenery += 1
		accepted.state += int(Sim.state_is_valid(s))
		accepted.scenery += int(SceneryCollision._state_is_valid(s))
		var sizes := [_rng.randi_range(3, 8), _rng.randi_range(0, 40), _rng.randi_range(0, 40)]
		var arrays: Array = []
		for k in 3:
			var a := PackedFloat64Array()
			for i in sizes[k] + [0, 0, 0, 1, -1][_rng.randi() % 5] if sizes[k] > 0 else sizes[k]:
				a.append(_value() if _rng.randi() % 40 == 0 else _rng.randf_range(-100.0, 100.0))
			arrays.append(a)
		var expected: bool = sim._array_is_finite(arrays[0], sizes[0]) and sim._array_is_finite(arrays[1], sizes[1]) \
			and sim._array_is_finite(arrays[2], sizes[2])
		if bool(kernel.arrays_finite(arrays[0], sizes[0], arrays[1], sizes[1], arrays[2], sizes[2])) != expected:
			mismatches.arrays += 1
		accepted.arrays += int(expected)
		var inertia := PackedFloat64Array([_value(), 0.3, 0.5, 0.0, -0.0, 0.01])
		var cache := inertia.duplicate()
		match _rng.randi() % 5:
			0: cache[_rng.randi() % 6] = _value()
			1: cache.append(1.0)
			2: cache[3] = -cache[3]
			_: pass
		var inverse := PackedFloat64Array([1.0, 2.0, 3.0, 0.0, 0.0, _value() if _rng.randi() % 4 == 0 else 0.5])
		if _rng.randi() % 7 == 0:
			inverse.resize(5)
		var reference: bool = sim._same_array(inertia, cache) and sim._array_is_finite(inverse, 6)
		if bool(kernel.inertia_cached(inertia, cache, inverse)) != reference:
			mismatches.inertia += 1
		accepted.inertia += int(reference)
	for key: String in mismatches:
		_check("native %s check equals the GDScript reference (%d samples)" % [key, samples], mismatches[key] == 0,
			str(mismatches[key]))
		# Both answers occur often, so the parity is not vacuous.
		_check("the %s samples include many accepted and many refused values" % key,
			accepted[key] > 1000 and samples - accepted[key] > 1000, str(accepted[key]))
	print("NK6Q_PARITY samples=%d accepted=%s" % [samples, str(accepted)])


func _tick(s: Node) -> void:
	var dt: float = s.sim.dt()
	s._physics_process(dt)
	s.sim._physics_process(dt)


func _pair(id: String, field: Dictionary, lake: Dictionary) -> void:
	var pair: Array = []
	for native_checks: bool in [true, false]:
		Sim.native_checks_enabled = native_checks
		var s := _session(id, field, lake, native_checks)
		s.read_raw = func() -> Dictionary:
			return {roll = 0.0, pitch = 0.12 if s.sim.tick > 500 else 0.0, yaw = 0.05, throttle = 1.0}
		pair.append(s)
	Sim.native_checks_enabled = true
	_check(id + ": the native session's model offers the kernel's checks", pair[0].sim._native_checker() != null)
	Sim.native_checks_enabled = false
	_check(id + ": the hook keeps the checks in GDScript", pair[1].sim._native_checker() == null)
	var mismatched := 0
	for tick in 1500:
		Sim.native_checks_enabled = true
		_tick(pair[0])
		Sim.native_checks_enabled = false
		_tick(pair[1])
		if var_to_bytes([pair[0].sim.tick, pair[0].sim.state, pair[0].sim.continuous, pair[0].sim.aux,
				pair[0].sim.fault_reason, pair[0].crash.is_empty()]) != var_to_bytes([pair[1].sim.tick, pair[1].sim.state,
				pair[1].sim.continuous, pair[1].sim.aux, pair[1].sim.fault_reason, pair[1].crash.is_empty()]):
			mismatched += 1
	Sim.native_checks_enabled = true
	_check(id + ": flights are byte-identical with the native checks on and off", mismatched == 0
		and pair[0].sim.fault_reason.is_empty() and pair[0].sim.tick >= 600, "%d %s" % [mismatched, pair[0].sim.fault_reason])
	print("NK6Q_PAIR %s ticks=%d height=%.1f" % [id, pair[0].sim.tick, -pair[0].sim.state[2]])
	for s: Node in pair:
		s.free()


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL ", label, " ", detail)
