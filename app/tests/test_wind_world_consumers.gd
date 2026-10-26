extends SceneTree

const HeliSession := preload("res://sim/helicopter_flight_session.gd")
const SimEnvironment := preload("res://sim/environment.gd")
const Plant := preload("res://physics/multirotor/plant.gd")
const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")
const FieldBuilder := preload("res://render/field.gd")

class PositionWeather extends "res://physics/wind_field.gd":
	var sampled_positions: Array[PackedFloat64Array] = []
	var sampled_times: Array[float] = []

	func sample_world(position_ned: PackedFloat64Array, time_s: float) -> PackedFloat64Array:
		sampled_positions.append(position_ned.duplicate())
		sampled_times.append(time_s)
		return PackedFloat64Array([0.0, 0.0, 0.0])


var _checks := 0
var _failures := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _same(actual: PackedFloat64Array, expected: PackedFloat64Array) -> bool:
	return actual.to_byte_array() == expected.to_byte_array()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_helicopter_uses_candidate_and_endpoint_positions()
	_multirotor_uses_stage_body_position()
	_local_visual_cue()
	print("world wind consumers: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _helicopter_uses_candidate_and_endpoint_positions() -> void:
	var session: Node = HeliSession.new()
	session.input_enabled = false
	session.physics_enabled = false
	root.add_child(session)
	var prepared: bool = session.setup()
	var weather := PositionWeather.new()
	session._weather = weather
	var reset_ok: bool = prepared and session.reset()
	_check("helicopter resets with a position-recording wind fixture", reset_ok, session.start_error)
	if not reset_ok:
		session.free()
		return

	var reset_position_ok := not weather.sampled_positions.is_empty()
	for point: PackedFloat64Array in weather.sampled_positions:
		reset_position_ok = reset_position_ok and _same(point, session._start)
	_check("hover reset queries its selected candidate start", reset_position_ok)

	var stage_body: PackedFloat64Array = session.sim.state.duplicate()
	stage_body[RB.POS] += 6.0
	stage_body[RB.POS + 1] -= 2.0
	var stage_time: float = session.sim.time() + session.sim.dt() * 0.5
	weather.sampled_positions.clear()
	weather.sampled_times.clear()
	var stage: Dictionary = session.sim.model.stage.call(stage_body, session.sim.continuous, stage_time)
	var stage_position: PackedFloat64Array = stage_body.slice(0, RB.SIZE).slice(RB.POS, RB.POS + 3)
	_check("helicopter RK stage queries the candidate body, not the accepted endpoint",
		stage.has("loads") and weather.sampled_positions.size() == 1
		and _same(weather.sampled_positions[0], stage_position)
		and weather.sampled_times[0] == stage_time,
		"samples=%s endpoint=%s candidate=%s" % [str(weather.sampled_positions), str(session.sim.state.slice(0, 3)), str(stage_position)])

	weather.sampled_positions.clear()
	var observed: PackedFloat64Array = session.wind_at(stage_time)
	var endpoint_position: PackedFloat64Array = session.sim.state.slice(RB.POS, RB.POS + 3)
	_check("observer wind queries use the accepted endpoint by default",
		observed.size() == 3 and weather.sampled_positions.size() == 1
		and _same(weather.sampled_positions[0], endpoint_position))

	var saved: Dictionary = session.sim.checkpoint()
	var candidate_body: PackedFloat64Array = saved.state.duplicate()
	candidate_body[RB.POS] += 11.0
	saved.state = candidate_body
	weather.sampled_positions.clear()
	var checkpoint_valid: bool = session._checkpoint_flight_state_is_valid(saved, session.commands,
		session.flight_mode, session.trainer_enabled, session.zero_drive_hold, session.power)
	var checkpoint_position: PackedFloat64Array = candidate_body.slice(RB.POS, RB.POS + 3)
	_check("checkpoint preflight queries its saved candidate body",
		checkpoint_valid and weather.sampled_positions.size() == 1
		and _same(weather.sampled_positions[0], checkpoint_position),
		"samples=%s candidate=%s" % [str(weather.sampled_positions), str(checkpoint_position)])
	session.free()


func _local_visual_cue() -> void:
	var field := Node3D.new()
	root.add_child(field)
	field.position = Vector3(10.0, 2.0, -20.0)
	var cue := Node3D.new()
	field.add_child(cue)
	cue.position = Vector3(3.0, 0.0, -4.0)
	cue.set_meta("windsock_dimensions", {height_m = 5.0})
	var observations: Array = []
	var sampler := func(point: PackedFloat64Array, time_s: float) -> PackedFloat64Array:
		observations.append([point.duplicate(), time_s])
		return PackedFloat64Array([point[0] * 0.1, point[1] * 0.1, point[2] * 0.1])
	field.set_meta("wind_world_sampler", sampler)
	var actual := FieldBuilder._cue_wind(field, cue, 3.5, [99.0, 99.0, 99.0])
	_check("cue samples its own fixed pole head in NED", observations.size() == 1 and observations[0][0] == PackedFloat64Array([24.0, 13.0, -7.0]) and observations[0][1] == 3.5)
	_check("cue receives its local wind instead of aircraft fallback", actual == [2.4, 1.3, -0.7] or (absf(actual[0] - 2.4) < 1e-14 and absf(actual[1] - 1.3) < 1e-14 and absf(actual[2] + 0.7) < 1e-14))
	field.set_meta("wind_world_sampler", func(_p: PackedFloat64Array, _t: float) -> PackedFloat64Array: return PackedFloat64Array([NAN, 0.0, 0.0]))
	_check("invalid local wind does not become calm or aircraft wind", FieldBuilder._cue_wind(field, cue, 3.5, [99.0, 99.0, 99.0]).is_empty())
	field.set_meta("wind_world_sampler", Callable())
	_check("legacy visual route retains exact uniform fallback", FieldBuilder._cue_wind(field, cue, 3.5, [1.25, -3.5, 0.0]) == [1.25, -3.5, 0.0])
	field.free()


func _multirotor_uses_stage_body_position() -> void:
	var environment := SimEnvironment.new()
	var weather := PositionWeather.new()
	environment.weather = weather
	var plant: RefCounted = Plant.new()
	plant.data = Plant.research_quad()
	plant.environment = environment
	var hover: Dictionary = plant.hover()
	plant.duties = PackedFloat64Array([hover.duty, hover.duty, hover.duty, hover.duty])
	var body: PackedFloat64Array = RB.make_state(M.v3(24.0, -9.0, -1.5), M.v3(0.5, -0.25, 0.1),
		M.q_identity(), M.v3(0.0, 0.0, 0.0))
	var continuous := PackedFloat64Array([hover.omega, hover.omega, hover.omega, hover.omega])
	var stage_time := 2.75
	var result: Dictionary = plant.stage(body, continuous, stage_time)
	var expected_position: PackedFloat64Array = body.slice(RB.POS, RB.POS + 3)
	_check("multirotor stage queries the actual body NED position and stage time",
		result.has("loads") and weather.sampled_positions.size() == 1
		and _same(weather.sampled_positions[0], expected_position)
		and weather.sampled_times[0] == stage_time,
		"samples=%s expected=%s" % [str(weather.sampled_positions), str(expected_position)])
