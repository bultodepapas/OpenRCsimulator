extends SceneTree
## NK-6h: the native stage may answer HullContact.terminal_at_properties for a liquid aircraft's contact sample at
## fraction 0 only where the reference returns {ok, no event} (FlightSession._native_terminal_quiet).
## - Random tick pairs touching the field and the lake, with random start stores: every quiet answer matches the
##   reference's {ok, no event}; new penetrations, deep points and lake-covered points are left to the reference.
## - Takeoff rolls, a hard landing and a nose-over fly byte-identical with the answer on and off.
## Skips (passes) without a verified native library.

const Flight := preload("res://sim/flight_session.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const LakeLoader := preload("res://data/lake_loader.gd")
const NativeStage := preload("res://sim/native_stage.gd")
const HullContact := preload("res://physics/hull_contact.gd")
const LiquidFlight := preload("res://sim/liquid_fuel_flight.gd")
const LakeCollision := preload("res://sim/lake_collision.gd")
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


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL ", label, " ", detail)


func _run() -> void:
	_rng.seed = 61627
	_field = FieldLoader.load_from().field
	_lake = LakeLoader.load_from(LakeLoader.DEFAULT_PATH).lake
	var tested := 0
	for id: String in ["f4u-corsair-250", "p51d-mustang-120"]:
		var probe := _session(id, true)
		if probe == null or probe.stage_backend_identity().backend != NativeStage.BACKEND_NATIVE \
				or not probe._native_stage._liquid_terminal_bound:
			print("NK6H_SKIP %s" % id)
			if probe != null:
				probe.free()
			continue
		tested += 1
		_soundness(probe, id)
		probe.free()
		_pair(id, "roll")
		_pair(id, "hard_landing")
		_pair(id, "nose_over")
	if tested == 0:
		print("NK6H_LIQUID_TERMINAL_SKIP no native liquid session")
	print("native liquid terminal: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _session(id: String, enabled: bool) -> Node:
	var s: Node = Flight.new()
	s.input_enabled = true
	s.crash_auto_restart = false
	s.soft_hull_contacts = true
	s.cost_observations_enabled = true
	s.native_terminal_quiet_enabled = enabled
	s.start_choice = Flight.START_RUNWAY
	s.setup_stage_backend(NativeStage.BACKEND_NATIVE)
	s.setup(Catalog.data_for(id, Catalog.default_battery_mode(id)), id)
	if not s.aircraft.get("ok", false):
		s.free()
		return null
	s.set_field(_field)
	s.set_lake_context(_lake)
	s.reset()
	return s


func _soundness(s: Node, id: String) -> void:
	var config: Dictionary = s.aircraft.model.propulsion.liquid_fuel
	var limit: float = float(config.capacity_kg) - float(config.unusable_kg)
	var index: int = s._liquid_index()
	var base_values: PackedFloat64Array = s.sim.continuous.duplicate()
	var bank := LakeCollision._polygon_bounds(_lake.bank_ne_m)
	var origin: PackedFloat64Array = s.sim.state.duplicate()
	var stats := {quiet = 0, reference_none = 0, unsound = 0, left = 0}
	for i in SAMPLES:
		var previous := origin.duplicate()
		if i % 4 == 0:
			previous[RB.POS] = lerpf(bank[0], bank[1], _rng.randf())
			previous[RB.POS + 1] = lerpf(bank[2], bank[3], _rng.randf())
		else:
			previous[RB.POS] += _rng.randf_range(-40.0, 40.0)
			previous[RB.POS + 1] += _rng.randf_range(-40.0, 40.0)
		# Mostly a rolling pose; one in five tilted or lowered so hull points touch, sink or newly penetrate.
		var rough: bool = i % 5 == 0
		previous[RB.POS + 2] += _rng.randf_range(-0.3, 0.3) if rough else _rng.randf_range(-0.02, 0.02)
		var q := Quaternion(Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)).normalized(),
			_rng.randf_range(-0.8, 0.8) if rough else _rng.randf_range(-0.05, 0.05)).normalized() * Quaternion(previous[RB.ATT + 1], previous[RB.ATT + 2],
			previous[RB.ATT + 3], previous[RB.ATT])
		# Quaternion is 32-bit; renormalize in float64 so |q|^2 meets the terminal's 1e-9 attitude check.
		var c := [float(q.w), float(q.x), float(q.y), float(q.z)]
		var n: float = sqrt(c[0] * c[0] + c[1] * c[1] + c[2] * c[2] + c[3] * c[3])
		for k in 4:
			previous[RB.ATT + k] = c[k] / n
		for axis in 3:
			previous[RB.VEL + axis] = _rng.randf_range(-8.0, 8.0)
			previous[RB.RATE + axis] = _rng.randf_range(-2.0, 2.0)
		var state := previous.duplicate()
		for axis in 3:
			state[RB.POS + axis] += _rng.randf_range(-0.05, 0.05) if rough else _rng.randf_range(-0.003, 0.003)
		var before := base_values.duplicate()
		before[index] = _rng.randf_range(-0.05 * limit, 1.05 * limit) if i % 9 else NAN
		var after := before.duplicate()
		var sampler: Callable = LiquidFlight.contact_sampler(s, before, after)
		if not sampler.is_valid():
			continue # the reference never asks the terminal without a sampler
		var reference: Dictionary = HullContact.terminal_at_properties(previous, state, s._hull_contact, sampler.call(0.0))
		var none: bool = reference.get("ok", false) and int(reference.event.index) < 0
		if none:
			stats.reference_none += 1
		var quiet: int = s._native_stage.liquid_terminal_quiet(previous, state, before[index])
		if quiet == 1:
			stats.quiet += 1
			if not none:
				stats.unsound += 1
		elif none:
			stats.left += 1
	_check(id + ": every quiet answer is the reference's {ok, no event}", stats.unsound == 0, str(stats))
	_check(id + ": the stage answers most quiet ticks", stats.quiet > SAMPLES / 4 and stats.quiet > stats.reference_none / 2,
		str(stats))
	print("NK6H_SOUNDNESS %s %s" % [id, str(stats)])


func _tick(s: Node) -> void:
	var dt: float = s.sim.dt()
	s._physics_process(dt)
	s.sim._physics_process(dt)


func _pair(id: String, scenario: String) -> void:
	var a := _session(id, true)
	var b := _session(id, false)
	var raw := func() -> Dictionary: return {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 1.0}
	if scenario == "hard_landing":
		for s: Node in [a, b]:
			var state: PackedFloat64Array = s.sim.state.duplicate()
			state[RB.POS + 2] -= 1.2
			state[RB.VEL + 2] = 7.0
			s.sim.state = state
			s.sim.previous = state.duplicate()
		raw = func() -> Dictionary: return {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.0}
	elif scenario == "nose_over":
		raw = func() -> Dictionary: return {roll = 0.0, pitch = -1.0, yaw = 0.0, throttle = 1.0}
	a.read_raw = raw
	b.read_raw = raw
	var same := true
	var first := ""
	for i in 2000:
		_tick(a)
		_tick(b)
		if var_to_bytes(a.checkpoint()) != var_to_bytes(b.checkpoint()):
			same = false
			first = "tick %d" % a.sim.tick
			break
		if not a.crash.is_empty():
			break
	_check("%s %s: byte-identical with the quiet answer on and off" % [id, scenario], same, first)
	if scenario == "roll":
		_check("%s roll: the stage answered rolling ticks" % id, a.native_terminal_quiet_answers > 100,
			str(a.native_terminal_quiet_answers))
	print("NK6H_PAIR %s %s ticks=%d answers=%d crash=%s" % [id, scenario, a.sim.tick, a.native_terminal_quiet_answers,
		str(a.crash.get("why", ""))])
	a.free()
	b.free()
