## AFC-04: independent witnesses for the retained linear CPA fallback policy.
## This is a prediction/selection test, not a reachable-maneuver guarantee.
extends SceneTree

const Pilot := preload("res://ai/companions/circuit_controller.gd")
const Field := preload("res://data/field_loader.gd")
const Math := preload("res://physics/math3d.gd")
const Body := preload("res://physics/rigid_body.gd")
var _checks := 0
var _failed := 0
var _pilot: RefCounted
var _own := PackedFloat64Array()
var _velocity := PackedFloat64Array([15.0, 0.0, 0.0])


func _initialize() -> void:
	_run.call_deferred()


func _check(label: String, passed: bool) -> void:
	_checks += 1
	if not passed:
		_failed += 1
		printerr("FAIL ", label)


func _run() -> void:
	_pilot = Pilot.new()
	var field: Dictionary = Field.load_from()
	_check("normalized field loads", field.get("ok", false))
	_check("circuit pilot configures", _pilot.configure(0, 1, 20261020, {V = 15.0, throttle = 0.45}, field.field))
	_own = Body.make_state(PackedFloat64Array([279.0, 0.0, -35.0]), _velocity,
		PackedFloat64Array([1.0, 0.0, 0.0, 0.0]), PackedFloat64Array([0.0, 0.0, 0.0]))
	_check_boundaries()
	_check_strongest_threat()
	_check_dense_oracle()
	print("companion encounters: %d checks, %d failed" % [_checks, _failed])
	quit(1 if _failed else 0)


func _traffic(id: String, relative_position: Array, relative_velocity: Array, player := true) -> Dictionary:
	return {id = id, is_player = player,
		position_ned = PackedFloat64Array([_own[0] + relative_position[0], _own[1] + relative_position[1], _own[2] + relative_position[2]]),
		velocity_ned = PackedFloat64Array([_velocity[0] + relative_velocity[0], _velocity[1] + relative_velocity[1], _velocity[2] + relative_velocity[2]])}


func _response(traffic: Array) -> Dictionary:
	return _pilot._avoidance_velocity(_own, _own.slice(6, 10), _velocity, 15.0, 0.0, traffic)


func _check_boundaries() -> void:
	for fixture: Dictionary in [
		{name = "head-on within horizon", p = [120.0, 0.0, 0.0], v = [-30.0, 0.0, 0.0], active = true},
		{name = "horizon margin inside", p = [209.5, 0.0, 0.0], v = [-30.0, 0.0, 0.0], active = true},
		{name = "horizon margin exact tangent", p = [210.0, 0.0, 0.0], v = [-30.0, 0.0, 0.0], active = false},
		{name = "horizon margin outside", p = [210.5, 0.0, 0.0], v = [-30.0, 0.0, 0.0], active = false},
		{name = "receding outside", p = [31.0, 0.0, 0.0], v = [20.0, 0.0, 0.0], active = false},
		{name = "receding but already inside", p = [29.0, 0.0, 0.0], v = [20.0, 0.0, 0.0], active = true},
		{name = "co-moving outside", p = [0.0, 31.0, 0.0], v = [0.0, 0.0, 0.0], active = false},
		{name = "co-moving exact tangent", p = [0.0, 30.0, 0.0], v = [0.0, 0.0, 0.0], active = false},
		{name = "co-moving inside", p = [0.0, 29.0, 0.0], v = [0.0, 0.0, 0.0], active = true},
		{name = "zero distance and speed", p = [0.0, 0.0, 0.0], v = [0.0, 0.0, 0.0], active = true},
		{name = "closing from behind", p = [-30.0, 0.0, 0.0], v = [10.0, 0.0, 0.0], active = true},
		{name = "vertical crossing", p = [0.0, 0.0, 50.0], v = [0.0, 0.0, -10.0], active = true},
		{name = "crossing tangent", p = [60.0, -60.0, 30.0], v = [-15.0, 15.0, 0.0], active = false},
		{name = "crossing inside", p = [60.0, -60.0, 29.0], v = [-15.0, 15.0, 0.0], active = true},
	]:
		var actual: Dictionary = _response([_traffic("player", fixture.p, fixture.v)])
		_check(fixture.name, actual.active == fixture.active and _finite(actual))
	var ai_tangent := _traffic("companion-1", [0.0, 15.0, 0.0], [0.0, 0.0, 0.0], false)
	_check("AI center-separation exact tangent", not _response([ai_tangent]).active)
	ai_tangent.wingspan_m = 6.0
	_check("larger span expands predicted clearance", _response([ai_tangent]).active)
	var fast := _traffic("fast", [0.0, 35.0, 0.0], [80.0, 0.0, 0.0], false)
	_check("closure-speed margin includes fast receding nearby traffic", _response([fast]).active)
	_check("invalid traffic never corrupts finite response", not _response([{}, "bad",
		{id = "bad", position_ned = PackedFloat64Array([NAN, 0.0, 0.0])}]).active)
	var own_item := _traffic("companion-0", [0.0, 0.0, 0.0], [0.0, 0.0, 0.0], false)
	_check("self is excluded at coincident position", not _response([own_item]).active)
	var baseline: Dictionary = _response([_traffic("player", [60.0, 29.0, 0.0], [-15.0, 0.0, 0.0])])
	_own[0] += 100000000.0
	_own[1] -= 100000000.0
	_check("large NED translation preserves the response", baseline == _response([
		_traffic("player", [60.0, 29.0, 0.0], [-15.0, 0.0, 0.0])]))
	_own[0] -= 100000000.0
	_own[1] += 100000000.0


func _check_strongest_threat() -> void:
	# The weaker co-altitude player asks for descent. The stronger AI below is
	# already outside the vertical-action band and must not inherit that descent.
	var weak := _traffic("player", [0.0, 29.0, 0.0], [0.0, 0.0, 0.0])
	var strong := _traffic("companion-1", [0.0, 0.0, 9.0], [0.0, 0.0, 0.0], false)
	var far := _traffic("companion-2", [100.0, 100.0, 100.0], [0.0, 0.0, 0.0], false)
	var single: Dictionary = _response([strong])
	_check("stronger vertically separated target needs no vertical action", single.active and single.altitude_delta == 0.0)
	for permutation: Array in [[weak, strong, far], [weak, far, strong], [strong, weak, far],
			[strong, far, weak], [far, weak, strong], [far, strong, weak]]:
		_check("unique strongest threat owns every response component", _response(permutation) == single)
	var snapshot := {state = _own, airspeed_m_s = 15.0, ground_clearance_m = 35.0,
		trim = {V = 15.0, throttle = 0.45}, wind_ned = PackedFloat64Array([0.0, 0.0, 0.0])}
	var expected: Dictionary = _pilot.command(snapshot, 0, [strong])
	var actual: Dictionary = _pilot.command(snapshot, 0, [weak, strong])
	_check("full controller cannot descend toward stronger traffic below due to weaker traffic",
		actual.ok and actual.target_height_m == expected.target_height_m and actual.pitch == expected.pitch)
	var before := var_to_bytes([snapshot, weak, strong])
	_pilot.command(snapshot, 0, [weak, strong])
	_check("threat selection remains read-only", before == var_to_bytes([snapshot, weak, strong]))


func _check_dense_oracle() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261020
	for population: int in [1, 2, 8, 32]:
		for sample in 20:
			var traffic: Array = []
			var maximum := 0.0
			for index in population:
				var position := [rng.randf_range(-180.0, 180.0), rng.randf_range(-180.0, 180.0), rng.randf_range(-40.0, 40.0)]
				var velocity := [rng.randf_range(-45.0, 45.0), rng.randf_range(-45.0, 45.0), rng.randf_range(-3.0, 3.0)]
				var player := index == 0
				traffic.append(_traffic("traffic-%d" % index, position, velocity, player))
				var margin := maxf(30.0 if player else 15.0, 0.5 * sqrt(velocity[0] ** 2 + velocity[1] ** 2 + velocity[2] ** 2))
				var distance := _minimum_distance(position, velocity)
				maximum = maxf(maximum, maxf(0.0, 1.0 - distance / margin))
			var response: Dictionary = _response(traffic)
			var correction := sqrt((float(response.air_north) - 15.0) ** 2 + float(response.air_east) ** 2)
			_check("dense %d/%d matches independently minimized CPA severity" % [population, sample],
				_finite(response) and response.active == (maximum > 0.0) and absf(correction - 14.0 * maximum) < 1e-8)
			traffic.reverse()
			_check("dense unique maximum is stable under reversed observations", _response(traffic) == response)


## Minimize squared range over [0,6] by interval narrowing, independently of
## the pilot's dot-product projection. Include endpoints for receding traffic.
func _minimum_distance(position: Array, velocity: Array) -> float:
	var low := 0.0
	var high := 6.0
	for _iteration in 96:
		var left := low + (high - low) / 3.0
		var right := high - (high - low) / 3.0
		if _range_squared(position, velocity, left) <= _range_squared(position, velocity, right): high = right
		else: low = left
	return sqrt(minf(_range_squared(position, velocity, 0.0),
		minf(_range_squared(position, velocity, 6.0), _range_squared(position, velocity, (low + high) * 0.5))))


func _range_squared(position: Array, velocity: Array, time: float) -> float:
	var total := 0.0
	for axis in 3:
		var coordinate: float = position[axis] + velocity[axis] * time
		total += coordinate * coordinate
	return total


func _finite(response: Dictionary) -> bool:
	return is_finite(float(response.air_north)) and is_finite(float(response.air_east)) \
		and is_finite(float(response.altitude_delta))
