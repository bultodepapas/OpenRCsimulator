extends SceneTree
## NK-6e session reach bounds:
## - FlightSession._prop_disc_clear(s) is sound: wherever it lets _check_prop_strike stop, HullContact.prop_disc_depth
##   answers a depth <= 0 (random positions over the field and the lake, heights, attitudes, unnormalized quaternions);
##   it also clears real flight states;
## - _contact_probe_reach's identity cache answers the recomputed reach bit for bit through gear cycles;
## - flights with both enabled and both disabled are byte-identical (fixed and retractable gear, glow, takeoff and
##   landing near the lake).

const Flight := preload("res://sim/flight_session.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const LakeLoader := preload("res://data/lake_loader.gd")
const NativeStage := preload("res://sim/native_stage.gd")
const HullContact := preload("res://physics/hull_contact.gd")
const RB := preload("res://physics/rigid_body.gd")

const SAMPLES := 4000
var _checks := 0
var _failures := 0
var _rng := RandomNumberGenerator.new()
var _field: Dictionary
var _lake: Dictionary


func _initialize() -> void:
	Engine.physics_ticks_per_second = 240
	_run.call_deferred()


func _run() -> void:
	_rng.seed = 64646
	_field = FieldLoader.load_from().field
	_lake = LakeLoader.load_from(LakeLoader.DEFAULT_PATH).lake
	for id: String in ["f4u-corsair-250", "jensen-das-ugly-stik-60", "stik-glow-61fx-2t", "p51d-mustang-120"]:
		_soundness(id)
		_probe_cache(id)
		for scenario: String in ["takeoff", "landing"]:
			_pair(id, scenario)
	print("session reach bounds: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _session(id: String, start: String) -> Node:
	var s: Node = Flight.new()
	s.input_enabled = true
	s.crash_auto_restart = false
	s.soft_hull_contacts = true
	s.start_choice = start
	s.setup_stage_backend(NativeStage.BACKEND_NATIVE)
	s.setup(Catalog.data_for(id, Catalog.default_battery_mode(id)), id)
	s.set_field(_field)
	s.set_lake_context(_lake)
	s.reset()
	if s.glow_is_active() and not bool(s.glow_state().get("running", false)):
		s.glow_start()
	return s


func _tick(s: Node) -> void:
	var dt: float = s.sim.dt()
	s._physics_process(dt)
	s.sim._physics_process(dt)


func _soundness(id: String) -> void:
	var s := _session(id, Flight.START_RUNWAY)
	var shore: PackedFloat64Array = _lake.shoreline_ne_m
	var center := Vector2(0.0, 0.0)
	for i in range(0, shore.size(), 2):
		center += Vector2(shore[i], shore[i + 1])
	center /= float(shore.size() / 2)
	var stats := {cleared = 0, kept = 0, unsound = 0}
	var first := ""
	for i in SAMPLES:
		var body: PackedFloat64Array = s.sim.state.duplicate()
		var over_lake: bool = i % 3 == 0
		body[RB.POS] = (center.x if over_lake else 0.0) + _rng.randf_range(-150.0, 150.0)
		body[RB.POS + 1] = (center.y if over_lake else 0.0) + _rng.randf_range(-150.0, 150.0)
		body[RB.POS + 2] = -_rng.randf_range(-0.5, 12.0)
		var q := Quaternion(Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)).normalized(),
			_rng.randf_range(-PI, PI)).normalized()
		var scale: float = 1.0 if i % 5 != 0 else _rng.randf_range(0.6, 1.4)
		body[RB.ATT] = q.w * scale
		body[RB.ATT + 1] = q.x * scale
		body[RB.ATT + 2] = q.y * scale
		body[RB.ATT + 3] = q.z * scale
		if not s._prop_disc_clear(body):
			stats.kept += 1
			continue
		stats.cleared += 1
		var depth: float = float(HullContact.prop_disc_depth(body, s._prop_disc, s._lake, _rng.randf_range(0.0, 60.0)).depth)
		if not (depth <= 0.0):
			stats.unsound += 1
			if first.is_empty():
				first = "depth %f at %s " % [depth, str(body)]
	_check(id + ": every cleared state has a nonpositive disc depth", stats.unsound == 0, first + str(stats))
	_check(id + ": the bound clears and keeps states", stats.cleared > SAMPLES / 10 and stats.kept > SAMPLES / 10, str(stats))
	# A flying state well above the field clears.
	var flying: PackedFloat64Array = s.sim.state.duplicate()
	flying[RB.POS + 2] = -40.0
	_check(id + ": a state 40 m above the runway clears", s._prop_disc_clear(flying))
	print("NK6E_PROP %s %s" % [id, str(stats)])
	s.free()


func _probe_cache(id: String) -> void:
	var s := _session(id, Flight.START_AIRBORNE)
	s.read_raw = func() -> Dictionary: return {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.6}
	var stats := {ticks = 0, mismatched = 0, hits = 0}
	for tick in 1800:
		if s.gear_is_retractable() and tick in [10, 900]:
			s.set_gear_down(tick == 900)
		_tick(s)
		var before_gear: Variant = s._probe_reach_gear
		var cached: float = s._contact_probe_reach()
		if before_gear != null and is_same(before_gear, s.current_landing_gear()):
			stats.hits += 1
		s.probe_reach_cache_enabled = false
		var fresh: float = s._contact_probe_reach()
		s.probe_reach_cache_enabled = true
		stats.ticks += 1
		if var_to_bytes(cached) != var_to_bytes(fresh):
			stats.mismatched += 1
		if not s.crash.is_empty() or not s.sim.fault_reason.is_empty():
			break
	_check(id + ": the cached probe reach equals the recomputed one", stats.mismatched == 0 and stats.hits > 0, str(stats))
	print("NK6E_PROBE %s %s" % [id, str(stats)])
	s.free()


func _pair(id: String, scenario: String) -> void:
	var pair: Array = []
	for enabled in [true, false]:
		var s := _session(id, Flight.START_AIRBORNE if scenario == "landing" else Flight.START_RUNWAY)
		s.prop_clear_bound_enabled = enabled
		s.probe_reach_cache_enabled = enabled
		if scenario == "landing":
			var body: PackedFloat64Array = s.sim.state.duplicate()
			body[RB.POS + 2] = minf(body[RB.POS + 2], -3.0)
			body[RB.VEL] = 15.0
			body[RB.VEL + 2] = 2.0
			s.sim.reset(body)
		var holder := {tick = 0}
		s.set_meta(&"holder", holder)
		s.read_raw = func() -> Dictionary:
			return {roll = 0.0, pitch = (0.2 if holder.tick > 400 else 0.0) if scenario == "takeoff" else -0.05, yaw = 0.0,
				throttle = 1.0 if scenario == "takeoff" else 0.0}
		pair.append(s)
	var stats := {ticks = 0, mismatched = 0}
	for tick in 1440 if scenario == "takeoff" else 960:
		for s: Node in pair:
			s.get_meta(&"holder").tick = tick
		_tick(pair[0])
		_tick(pair[1])
		stats.ticks += 1
		if var_to_bytes([pair[0].sim.tick, pair[0].sim.state, pair[0].sim.continuous, pair[0].sim.aux, pair[0].sim.fault_reason,
				pair[0].prop_strike, pair[0].engine_running]) != var_to_bytes([pair[1].sim.tick, pair[1].sim.state,
				pair[1].sim.continuous, pair[1].sim.aux, pair[1].sim.fault_reason, pair[1].prop_strike, pair[1].engine_running]):
			stats.mismatched += 1
		if not pair[0].crash.is_empty() or not pair[1].crash.is_empty():
			break
	_check("%s %s: flights are byte-identical with the bounds on and off" % [id, scenario], stats.mismatched == 0, str(stats))
	for s: Node in pair:
		s.free()


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])
