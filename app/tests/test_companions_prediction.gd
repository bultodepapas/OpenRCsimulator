## AFC-04-R9: production guidance and continuous forecast geometry regressions.
extends SceneTree

const Pilot := preload("res://ai/companions/pilot.gd")
const Circuit := preload("res://ai/companions/circuit_controller.gd")
const Body := preload("res://physics/rigid_body.gd")
const Math3D := preload("res://physics/math3d.gd")
const Field := preload("res://data/field_loader.gd")

class ObservedPilot extends "res://ai/companions/pilot.gd":
	var scored_nominal := NAN
	func _score_bank(state: PackedFloat64Array, velocity: PackedFloat64Array, speed: float,
			current: float, nominal: float, candidate: float, clearance: float,
			threats: Array[Dictionary], trace: bool = false) -> Dictionary:
		scored_nominal = nominal
		return super._score_bank(state, velocity, speed, current, nominal, candidate, clearance, threats, trace)

var _checks := 0
var _failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(label: String, passed: bool) -> void:
	_checks += 1
	if not passed:
		_failures += 1
		printerr("FAIL ", label)

func _near(label: String, actual: float, expected: float, tolerance: float = 1e-9) -> void:
	_check("%s: %.12f vs %.12f" % [label, actual, expected], absf(actual - expected) <= tolerance)

func _state(speed: float = 15.0, bank: float = 0.0) -> PackedFloat64Array:
	return Body.make_state(PackedFloat64Array([0.0, 0.0, -100.0]),
		PackedFloat64Array([speed, 0.0, 0.0]), Math3D.q_from_euler(0.0, 0.0, bank),
		PackedFloat64Array([0.0, 0.0, 0.0]))

func _run() -> void:
	_check_segments()
	_check_turns()
	_check_continuous_scoring()
	_check_guidance()
	print("companion prediction: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)

func _check_segments() -> void:
	_near("interior horizontal CPA", Pilot._relative_segment_distance(-1, 4, 0, 1, 4, 0), 4.0)
	_near("zero relative motion", Pilot._relative_segment_distance(3, 4, 12, 3, 4, 12), 13.0)
	_near("approaching endpoint", Pilot._relative_segment_distance(5, 0, 0, 3, 0, 0), 3.0)
	_near("receding endpoint", Pilot._relative_segment_distance(3, 0, 0, 5, 0, 0), 3.0)
	_near("vertical crossing", Pilot._relative_segment_distance(0, 0, -2, 0, 0, 2), 0.0)
	_near("tangent CPA", Pilot._relative_segment_distance(-2, 31.5, 0, 2, 31.5, 0), 31.5)
	_near("straight sinc", Pilot._sinc(0.0), 1.0)
	_near("near-zero sinc", Pilot._sinc(1e-12), 1.0)
	_near("zero curvature", Pilot._arc_chord_error(15.0, 0.0), 0.0)

func _check_turns() -> void:
	for wind: PackedFloat64Array in [PackedFloat64Array([0.0, 0.0, 0.0]), PackedFloat64Array([1.2, -0.5, 0.0])]:
		for bank: float in [0.0, 1e-12, deg_to_rad(25.0), -deg_to_rad(25.0)]:
			var pilot := Pilot.new()
			pilot._planning_wind = wind
			var rate: float = Pilot.G * tan(bank) / 15.0
			var ground_velocity := PackedFloat64Array([15.0 + wind[0], wind[1], 0.0])
			var threat := {id = "peer", is_player = false, position_ned = PackedFloat64Array([0, 0, -100]),
				velocity_ned = ground_velocity, wind_ned = wind, bank_rad = bank}
			var prepared: Array[Dictionary] = pilot._prepare_threats([threat], ground_velocity)
			var positions: PackedFloat64Array = prepared[0].positions
			var angle: float = rate * Pilot.PREDICTION_HORIZON_S
			var expected_north: float = 120.0 if absf(rate) < 1e-10 else 15.0 * sin(angle) / rate
			# 2 sin²(angle/2) avoids cancellation in the analytic east displacement.
			var expected_east: float = 0.0 if absf(rate) < 1e-10 else 30.0 * sin(0.5 * angle) ** 2 / rate
			expected_north += wind[0] * 8.0
			expected_east += wind[1] * 8.0
			_near("real threat arc north", positions[-3], expected_north)
			_near("real threat arc east", positions[-2], expected_east)
			# Two independent stationary landmarks recover own endpoint components
			# from distances emitted by the real scorer, without cloning its loop.
			var origin := {id = "origin", is_player = false, position_ned = PackedFloat64Array([0, 0, -100]),
				velocity_ned = PackedFloat64Array([0, 0, 0]), wind_ned = PackedFloat64Array([0, 0, 0])}
			var north_landmark: Dictionary = origin.duplicate(true)
			north_landmark.position_ned[0] = 1000.0
			var east_landmark: Dictionary = origin.duplicate(true)
			east_landmark.position_ned[1] = 1000.0
			var landmarks: Array[Dictionary] = pilot._prepare_threats([origin, north_landmark, east_landmark], ground_velocity)
			var result: Dictionary = pilot._score_bank(_state(), ground_velocity, 15.0, bank, bank, bank, 100.0, landmarks, true)
			var traces: Array = result.distance_traces_m
			var d0: float = traces[0][-1]
			var dn: float = traces[1][-1]
			var de: float = traces[2][-1]
			_near("real own arc north", (d0*d0 - dn*dn + 1000000.0) / 2000.0, expected_north)
			_near("real own arc east", (d0*d0 - de*de + 1000000.0) / 2000.0, expected_east)
			_near("arc sagitta", Pilot._arc_chord_error(15.0, rate),
				0.0 if absf(rate) < 1e-10 else 30.0 / absf(rate) * sin(rate * 0.25 / 4.0) ** 2)

func _check_continuous_scoring() -> void:
	var pilot := Pilot.new()
	var velocity := PackedFloat64Array([15.0, 0.0, 0.0])
	var peer := {id = "peer", is_player = false, position_ned = PackedFloat64Array([1.875, 31.49, -100.0]),
		velocity_ned = PackedFloat64Array([0.0, 0.0, 0.0])}
	var before := var_to_bytes(peer)
	var threats: Array[Dictionary] = pilot._prepare_threats([peer], velocity)
	_near("production padded peer requirement", threats[0].required_separation_m, 31.5)
	var result: Dictionary = pilot._score_bank(_state(), velocity, 15.0, 0.0, 0.0, 0.0, 100.0, threats, true)
	_near("midpoint violation detected", result.traffic_margin_m, -0.01, 2e-9)
	_check("sampled endpoints are still clear", result.distance_traces_m[0][0] > 31.5
		and result.distance_traces_m[0][1] > 31.5)
	_check("prediction leaves traffic untouched", before == var_to_bytes(peer))
	peer.position_ned[1] = 31.5
	threats = pilot._prepare_threats([peer], velocity)
	result = pilot._score_bank(_state(), velocity, 15.0, 0.0, 0.0, 0.0, 100.0, threats)
	_check("exact tangency is conservatively not clear", result.traffic_margin_m < 0.0)
	# Relative down reaches 37.49 m at 0.9 s, although both enclosing
	# sample endpoints are clear against the 37.5 m player requirement.
	velocity[2] = 10.0
	peer = {id = "player", is_player = true, position_ned = PackedFloat64Array([0, 0, -58.01]),
		velocity_ned = PackedFloat64Array([15.0, 0.0, 5.0])}
	threats = pilot._prepare_threats([peer], velocity)
	result = pilot._score_bank(_state(), velocity, 15.0, 0.0, 0.0, 0.0, 100.0, threats, true)
	_check("vertical reaction kink is not falsely clear", result.traffic_margin_m < 0.0)
	_check("vertical kink endpoints stay clear", result.distance_traces_m[0][3] > 37.5
		and result.distance_traces_m[0][4] > 37.5)
	# A curved own segment bows toward a peer on the outside of its chord.
	# Its midpoint violates the margin although endpoint-chord CPA stays clear.
	velocity = PackedFloat64Array([15.0, 0.0, 0.0])
	var bank: float = deg_to_rad(25.0)
	var rate: float = Pilot.G * tan(bank) / 15.0
	var middle_north: float = 15.0 * sin(rate * 0.125) / rate
	var middle_east: float = 30.0 * sin(rate * 0.125 / 2.0) ** 2 / rate
	peer = {id = "peer", is_player = false, position_ned = PackedFloat64Array([middle_north, middle_east - 31.49, -100]),
		velocity_ned = PackedFloat64Array([0, 0, 0])}
	threats = pilot._prepare_threats([peer], velocity)
	result = pilot._score_bank(_state(), velocity, 15.0, bank, bank, bank, 100.0, threats, true)
	_check("own arc bow is not falsely clear", result.traffic_margin_m < 0.0)
	_check("own arc bow endpoints are clear", result.distance_traces_m[0][0] > 31.5
		and result.distance_traces_m[0][1] > 31.5)
	# Swapping the turning aircraft exercises the threat's independent bound.
	peer = {id = "peer", is_player = false, position_ned = PackedFloat64Array([-middle_north, 31.49 - middle_east, -100]),
		velocity_ned = velocity, bank_rad = bank}
	var stopped := PackedFloat64Array([0, 0, 0])
	threats = pilot._prepare_threats([peer], stopped)
	result = pilot._score_bank(_state(), stopped, 0.0, 0.0, 0.0, 0.0, 100.0, threats, true)
	_check("threat arc bow is not falsely clear", result.traffic_margin_m < 0.0)
	_check("threat arc bow endpoints are clear", result.distance_traces_m[0][0] > 31.5
		and result.distance_traces_m[0][1] > 31.5)

func _check_guidance() -> void:
	var loaded: Dictionary = Field.load_from()
	_check("Club field loads", loaded.get("ok", false))
	if not loaded.get("ok", false):
		return
	for seed_value: int in [20261020, 20261021]:
		for target_speed: float in [5.0, 15.0, 20.0, 30.0]:
			for heading_error: float in [-0.05, 0.0, 0.05, 0.8]:
				var pilot := ObservedPilot.new()
				var circuit := Circuit.new()
				_check("guidance fixtures configure", pilot.configure(0, 1, seed_value, {V = 15.0, throttle = 0.45}, loaded.field)
					and circuit.configure(0, 1, seed_value, {V = 15.0, throttle = 0.45}, loaded.field))
				var pose: Dictionary = pilot.initial_pose()
				var heading: float = pose.heading_rad + heading_error
				var bank: float = 0.05 # Keep the actuator unsaturated at both bank limits.
				var state: PackedFloat64Array = Body.make_state(PackedFloat64Array([pose.north + 10.0, pose.east, -pose.height_m]),
					PackedFloat64Array([15.0, 0.0, 0.0]), Math3D.q_from_euler(heading, 0.0, bank),
					PackedFloat64Array([0.1, 0.0, 0.0]))
				var snapshot := {state = state, airspeed_m_s = 15.0, wind_ned = PackedFloat64Array([1.2, -0.5, 0.0]),
					ground_clearance_m = 35.0, trim = {V = target_speed, throttle = 0.45}}
				var far := {id = "player", is_player = true, position_ned = PackedFloat64Array([10000, 10000, -100]),
					velocity_ned = PackedFloat64Array([0, 0, 0])}
				var original := var_to_bytes([snapshot, far])
				var nominal: Dictionary = pilot.command(snapshot, 0)
				var packet: Dictionary = pilot.command(snapshot, 4, [far])
				_check("clear production command equals circuit guidance", packet.ok and not packet.avoidance_active
					and packet.roll == nominal.roll and packet.roll == circuit.command(snapshot, 4).roll)
				_near("scorer nominal equals applied bank", pilot.scored_nominal, (packet.roll + 0.035) / 1.8 + bank)
				_near("snapshot speed is shared after clamp", pilot._nominal_demand.target_speed_mps, clampf(target_speed, 10.0, 25.0))
				_check("guidance inputs remain immutable", original == var_to_bytes([snapshot, far]))
	var old: Dictionary = Pilot.new().snapshot_state()
	old.version = "reachable-pilot-state-v1"
	_check("old predictor checkpoint is refused", not Pilot.new().restore_state(old).ok)
	_check_selection_and_checkpoint(loaded.field)

func _check_selection_and_checkpoint(field: Dictionary) -> void:
	var pilot := Pilot.new()
	_check("selection pilot configures", pilot.configure(0, 1, 20261020, {V = 15.0, throttle = 0.45}, field))
	var pose: Dictionary = pilot.initial_pose()
	var heading: float = pose.heading_rad
	var state: PackedFloat64Array = Body.make_state(PackedFloat64Array([pose.north, pose.east, -pose.height_m]),
		PackedFloat64Array([15, 0, 0]), Math3D.q_from_euler(heading, 0, 0), PackedFloat64Array([0, 0, 0]))
	var velocity: PackedFloat64Array = Math3D.q_rotate(state.slice(6, 10), state.slice(3, 6))
	var snapshot := {state = state, airspeed_m_s = 15.0, ground_clearance_m = 24.0,
		trim = {V = 15.0, throttle = 0.45}, wind_ned = PackedFloat64Array([0, 0, 0])}
	var peer := {id = "peer", is_player = false, position_ned = PackedFloat64Array([
		pose.north + 60.0*cos(heading) - 40.0*sin(heading),
		pose.east + 60.0*sin(heading) + 40.0*cos(heading), -pose.height_m]),
		velocity_ned = PackedFloat64Array([0, 0, 0])}
	var packet: Dictionary = pilot.command(snapshot, 0, [peer])
	var nominal: float = pilot._nominal_demand.bank_rad
	var threats: Array[Dictionary] = pilot._prepare_threats([peer], velocity)
	var baseline: Dictionary = pilot._score_bank(state, velocity, 15, 0, nominal, nominal, 24, threats)
	var selected: Dictionary = pilot._score_bank(state, velocity, 15, 0, nominal, pilot.snapshot_state().held_bank_rad, 24, threats)
	_check("fixture needs traffic avoidance during terrain recovery", packet.avoidance_active and packet.recovering_clearance
		and baseline.traffic_margin_m < 0.0 and baseline.terrain_margin_m < 0.0)
	_check("terrain penalty cannot hide a traffic-feasible turn", selected.traffic_margin_m >= 0.0)
	# Evaluate the prior weighted ranking on the corrected real forecasts.
	var legacy_score: float = baseline.score
	var legacy_margin: float = baseline.traffic_margin_m
	for degrees: float in Pilot.BANK_CHOICES_DEG:
		var bank: float = deg_to_rad(degrees)
		var result: Dictionary = pilot._score_bank(state, velocity, 15, 0, nominal, bank, 24, threats)
		var preference: float = result.score - 0.75 * absf(bank - nominal) + (0.15 if bank > 0.0 else 0.0)
		if preference > legacy_score:
			legacy_score = preference
			legacy_margin = result.traffic_margin_m
	_check("fixture reproduces unsafe weighted preference", legacy_margin < 0.0)
	var unsafe: Dictionary = pilot.snapshot_state()
	unsafe.held_bank_rad = deg_to_rad(25.0)
	_check("unsafe held fixture restores", pilot.restore_state(unsafe).ok)
	pilot.command(snapshot, 4, [peer])
	selected = pilot._score_bank(state, velocity, 15, 0, nominal, pilot.snapshot_state().held_bank_rad, 24, threats)
	_check("held commitment yields immediately to a traffic-feasible turn", selected.traffic_margin_m >= 0.0)
	# Preserve an active latch and partially elapsed clear dwell across restore.
	var far: Dictionary = peer.duplicate(true)
	far.position_ned[0] += 10000.0
	pilot.command(snapshot, 400, [far])
	var saved: Dictionary = pilot.snapshot_state()
	_check("checkpoint contains active maneuver and clear dwell", saved.has_held_maneuver and saved.clear_since_tick == 400)
	var restored := Pilot.new()
	_check("checkpoint receiver configures", restored.configure(0, 1, 20261020, {V = 15.0, throttle = 0.45}, field))
	_check("v2 held state restores exactly", restored.restore_state(saved).ok and var_to_bytes(saved) == var_to_bytes(restored.snapshot_state()))
	var malformed: Dictionary = saved.duplicate(true)
	malformed.held_bank_rad = 99.0
	_check("malformed v2 restore is atomic", not restored.restore_state(malformed).ok
		and var_to_bytes(saved) == var_to_bytes(restored.snapshot_state()))
	for tick: int in [636, 640, 644]:
		_check("restored continuation is byte-identical", var_to_bytes(pilot.command(snapshot, tick, [far]))
			== var_to_bytes(restored.command(snapshot, tick, [far]))
			and var_to_bytes(pilot.snapshot_state()) == var_to_bytes(restored.snapshot_state()))
	_check("restored clear dwell releases on time", not restored.snapshot_state().has_held_maneuver)
	# All candidates violate the margin in this deliberate initial conflict.
	# Preference must not hide the least-bad forecast, even below terrain reserve.
	peer.position_ned = PackedFloat64Array([pose.north + 40.0*cos(heading),
		pose.east + 40.0*sin(heading), -pose.height_m])
	pilot.configure(0, 1, 20261020, {V = 15.0, throttle = 0.45}, field)
	pilot.command(snapshot, 0, [peer])
	threats = pilot._prepare_threats([peer], velocity)
	var maximum_margin: float = pilot._score_bank(state, velocity, 15, 0, nominal, nominal, 24, threats).traffic_margin_m
	for degrees: float in Pilot.BANK_CHOICES_DEG:
		var margin: float = pilot._score_bank(state, velocity, 15, 0, nominal, deg_to_rad(degrees), 24, threats).traffic_margin_m
		maximum_margin = maxf(maximum_margin, margin)
	selected = pilot._score_bank(state, velocity, 15, 0, nominal, pilot.snapshot_state().held_bank_rad, 24, threats)
	_check("fixture has no traffic-feasible candidate", maximum_margin < 0.0)
	_near("all-infeasible choice maximizes worst traffic margin", selected.traffic_margin_m, maximum_margin)
