extends SceneTree
## UI-FS-08-R2: composed terrain must agree with the physical wheel query.

const Session := preload("res://sim/flight_session.gd")
const Adapter := preload("res://statistics/fixed_wing_adapter.gd")
const Detector := preload("res://statistics/detector.gd")
const Field := preload("res://data/field_loader.gd")
const Lake := preload("res://data/lake_loader.gd")
const Track := preload("res://physics/ground_vehicle/airfield_track.gd")
const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")

var checks := 0
var failures := 0
var session: Node
var adapter: RefCounted


func _initialize() -> void:
	session = Session.new()
	session.physics_enabled = false
	session.input_enabled = false
	session.setup()
	_check("stock Stik loads", session.is_flyable())
	_check("Club field installs", session.set_field(Field.load_from().field))
	adapter = Adapter.new()
	adapter.configure(session, "jensen-das-ugly-stik-60", func(_sample: Dictionary) -> void: pass)
	_check("reviewed wheel landing profile is available", adapter.profile.landing_available)
	# Install after configuration as well as removing/replacing it below: observations
	# must follow the session's accepted terrain, not a cached observer copy.
	var track: Dictionary = Track.load_default().track
	_check("circuit installs at tick zero", session.set_rc_track(track))
	_pose(39.0, -4.0, 0.755)
	var narrow: PackedFloat64Array = session.gear_compressions(session.sim.state)
	print("F3 physical wheel compression: ", narrow)
	_check("tabletop witness has three physical contacts", narrow.size() == 3
		and narrow[0] > 0.00001 and narrow[1] > 0.00001 and narrow[2] > 0.00001)
	var witness: Dictionary = adapter.sample()
	_check("tabletop witness reports all support roles", witness.valid and witness.supported
		and witness.intended_support and witness.stop_support and not witness.clearance_ok)
	_check("tabletop broadphase retains the physical wheel values",
		adapter._compressions(session.sim.state).to_byte_array() == narrow.to_byte_array())
	_pose(39.0, -4.0, 0.915)
	var near: Dictionary = adapter.sample()
	_check("airborne just above tabletop has not cleared the landing envelope", near.valid
		and not near.supported and not near.clearance_ok)
	_test_ground_grid()
	_test_banked_control()
	_test_mutations(track)
	_test_invalid_inputs()
	_test_episodes()
	session.free()
	print("Statistics terrain: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)


func _pose(north: float, east: float, height: float, speed := 0.0, roll := 0.0) -> void:
	session.sim.state = RB.make_state(M.v3(north, east, -height), M.v3(speed, 0.0, 0.0),
		PackedFloat64Array([cos(roll * 0.5), sin(roll * 0.5), 0.0, 0.0]), M.v3(0.0, 0.0, 0.0))


func _test_ground_grid() -> void:
	# Tabletop, ramp, roller, bank, circuit edge, runway and ordinary field.
	for point: Array in [[39.0, -4.0], [39.31, -4.1], [50.91, -3.7],
		[40.527864045, 16.0], [37.0, -4.0], [15.0, 0.0], [80.0, 0.0]]:
		var ground: PackedFloat64Array = session.environment.ground(point[0], point[1])
		for relative_height: float in [0.24, 0.40, 0.60, 50.0]:
			_pose(point[0], point[1], ground[0] + relative_height)
			var before := var_to_bytes(session.sim.checkpoint())
			var physical: PackedFloat64Array = session.gear_compressions(session.sim.state)
			var observed: PackedFloat64Array = adapter._compressions(session.sim.state)
			var masks_match := physical.size() == observed.size()
			var supported := false
			for i: int in physical.size():
				supported = supported or physical[i] > 0.00001
				masks_match = masks_match and (physical[i] > 0.00001) == (observed[i] > 0.00001)
			var sample: Dictionary = adapter.sample()
			var clearance: bool = not supported and relative_height >= adapter.profile.rest_height_m + adapter.profile.clearance_m
			_check("support/clearance match composed ground at %s + %.2f" % [point, relative_height],
				masks_match and sample.valid and sample.supported == supported and sample.clearance_ok == clearance)
			_check("sampling does not mutate the accepted frame", var_to_bytes(session.sim.checkpoint()) == before)


func _test_banked_control() -> void:
	var point := [40.527864045, 16.0]
	var ground: PackedFloat64Array = session.environment.ground(point[0], point[1])
	var aligned_roll := -atan(ground[2])
	var roll := aligned_roll + signf(aligned_roll) * deg_to_rad(14.0)
	_pose(point[0], point[1], 50.0, 0.0, roll)
	_check("bank fixture distinguishes terrain-relative from datum-relative roll", absf(roll) > deg_to_rad(15.0))
	_check("aircraft within 14 degrees of bank is controlled", adapter.sample().controlled)


func _test_mutations(track: Dictionary) -> void:
	_pose(39.0, -4.0, 0.755)
	_check("circuit can be removed before flight", session.set_rc_track({}))
	var removed: Dictionary = adapter.sample()
	_check("removed circuit stops supporting elevated aircraft", not removed.supported and removed.clearance_ok)
	_check("invalid circuit is refused", not session.set_rc_track({"format": "invalid"}))
	_check("refused replacement leaves observation unchanged", adapter.sample() == removed)
	_check("circuit reinstalls", session.set_rc_track(track))
	_check("reinstalled circuit restores support without adapter reconfiguration", adapter.sample().supported)
	var lake: Dictionary = Lake.load_from().lake
	_check("lake installs after observer configuration", session.set_lake_context(lake))
	# At the lake center the bed is below the original datum. Above-bed clearance
	# must use that current bed, even though the observer was configured without it.
	_pose(110.0, 125.0, 0.30)
	_check("current lake bed permits clearance at its center", adapter.sample().clearance_ok)
	_check("lake can be removed before flight", session.set_lake_context({}))
	_check("removed lake restores the field clearance test", not adapter.sample().clearance_ok)


func _test_invalid_inputs() -> void:
	var surfaces: PackedFloat64Array = session.ground_surfaces.duplicate()
	session.ground_surfaces = PackedFloat64Array([NAN])
	_check("malformed surface table cannot yield a valid statistics sample", not adapter.sample().valid)
	session.ground_surfaces = surfaces
	_pose(39.0, -4.0, 0.755)
	session.sim.state[RB.POS] = NAN
	_check("nonfinite position cannot yield a valid sample", not adapter.sample().valid)
	_pose(39.0, -4.0, 0.755)


func _test_episodes() -> void:
	# Staged geometry at consecutive 240 Hz ticks, not a simulated landing or a
	# physical-validation claim. The real adapter supplies every detector input.
	var detector := Detector.new()
	detector.configure(adapter.profile)
	var events: Array[Dictionary] = []
	_feed(detector, events, 300, 2.0, 5.0)
	_feed(detector, events, 150, 0.755, 2.0)
	_feed(detector, events, 500, 2.0, 5.0)
	_feed(detector, events, 650, 0.755, 0.0)
	var landings := events.filter(func(event: Dictionary) -> bool: return event.type == "landing")
	var closed := events.filter(func(event: Dictionary) -> bool: return event.type == "closed")
	_check("track episode resolves one touch-and-go and one full stop", landings.size() == 2
		and landings[0].kind == "touch_and_go" and landings[0].outcome == "success"
		and landings[1].kind == "full_stop" and landings[1].outcome == "success")
	_check("track full stop completes one flight", closed.size() == 1 and closed[0].outcome == "completed")
	_feed(detector, events, 300, 2.0, 5.0)
	var started := events.filter(func(event: Dictionary) -> bool: return event.type == "started")
	_check("subsequent departure starts exactly one new flight", started.size() == 2)
	_check("terrain changes are refused once ticks have advanced", not session.set_rc_track({})
		and not session.set_lake_context(Lake.load_from().lake))


func _feed(detector: RefCounted, events: Array[Dictionary], ticks: int, height: float, speed: float) -> void:
	_pose(39.0, -4.0, height, speed)
	for i: int in ticks:
		session.sim.tick += 1
		events.append_array(detector.observe(adapter.sample()))


func _check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
		printerr("FAIL ", label)
