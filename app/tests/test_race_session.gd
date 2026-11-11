# DR-23…26 end to end: a complete local race through the dedicated multirotor session (sim/multirotor/session.gd) on the
# default field with the shipped document, the shipped practice oval and the field's obstacle inventory, flown by a
# deterministic scripted pilot. Preparation and refusals, free flight in a race session, start refusal and acceptance,
# the 720-tick drive-inhibited countdown, GO refusal and GO, three valid laps with ordered events and interpolated
# crossing times, the terminal record and its persistence (outbox bound, failed save, idempotent save, discard), pad
# reset / crash / cancel paths, solid gate frames (RACE-02), a missed gate (RACE-12), checkpoint/restore replay inside
# lap 2 and a course swap (RACE-15, RACE-03) and pause (RACE-14). The flight-log replay of a whole race is in
# test_race_session_replay.gd. Software evidence on estimated data, same build and platform; local practice rules only:
# no federation compliance and no timing accuracy claim beyond the declared chord-path envelope.
extends SceneTree

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const FC := preload("res://physics/multirotor/flight_controller.gd")
const ActuatorMap := preload("res://physics/multirotor/actuator_map.gd")
const Fixtures := preload("res://tests/mr_fixtures.gd")
const Session := preload("res://sim/multirotor/session.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const CollisionSetup := preload("res://scenery/collision_setup.gd")
const Track := preload("res://sim/race/track.gd")
const Director := preload("res://sim/race/race_director.gd")
const RaceModel := preload("res://sim/race/race_model.gd")

const TRACK := "res://data/race/tracks/openrc-practice-oval-1.json"
const DIR := "user://test_race_session"
## The quad hovers near 15 % of full throttle; a 0.45 limit gives the scripted throttle loop a comfortable range.
const THROTTLE_LIMIT := 0.45
const CRUISE_MPS := 7.0
const RACE_TICK_LIMIT := 240 * 100
const WINDOW_TICKS := 480

var _count := 0
var _failures := 0
var _ticks := 0
var _field: Dictionary = {}
var _world: Dictionary = {}
## Main-race envelopes: at countdown tick 720 (before the GO sample) and in lap 2 just before gate 2, plus the
## 480 kernel input rows, frames and event lists that followed the lap-2 envelope.
var _go_envelope: Dictionary = {}
var _lap2_envelope: Dictionary = {}
var _lap2_rows: Array[PackedFloat64Array] = []
var _lap2_frames: Array[PackedByteArray] = []
var _lap2_events: Array[PackedByteArray] = []
var _lap1_duration := NAN


## Deterministic scripted pilot (tests only): Angle mode; straight legs between waypoints with a horizontal velocity
## loop (velocity error in the heading frame to pitch and roll sticks), the nose along the leg, and a model-inverted
## throttle loop that holds a height above the local ground. A pure function of the accepted frame and its own cursor
## (waypoint index, leg origin, airborne latch); no randomness and no wall clock.
class Pilot extends RefCounted:
	const G := 9.80665
	const K_CROSS := 1.5
	const MAX_CROSS_MPS := 3.0
	const K_VELOCITY := 2.5
	const MAX_ACCEL_MPS2 := 6.0
	const BRAKE_MPS2 := 3.0
	const MIN_CORNER_MPS := 1.5
	const SWITCH_M := 0.25
	const TURN_MPS2 := 4.0
	## Speed scale of the corners (a straight continuation keeps the cruise speed).
	const CORNER_MPS := 6.0
	var points: Array[PackedFloat64Array] = []
	var index := 0
	var origin := PackedFloat64Array([0.0, 0.0])
	var height_m := 2.0
	var cruise_mps := 6.0
	var arm := 1
	var landing := false
	var airborne := false

	## Fly the legs origin -> points[0] -> points[1] ...; hold over the last point afterwards.
	func fly(route: Array, from: PackedFloat64Array) -> void:
		points.assign(route)
		index = 0
		origin = PackedFloat64Array([from[0], from[1]])

	func done() -> bool:
		return index >= points.size()

	func command(s: Node) -> PackedFloat64Array:
		var b: PackedFloat64Array = s.sim.state
		var q: PackedFloat64Array = M.quat(b[RB.ATT], b[RB.ATT + 1], b[RB.ATT + 2], b[RB.ATT + 3])
		var v: PackedFloat64Array = M.q_rotate(q, M.v3(b[RB.VEL], b[RB.VEL + 1], b[RB.VEL + 2]))
		var n: float = b[RB.POS]
		var e: float = b[RB.POS + 1]
		var agl: float = -b[RB.POS + 2] - s.environment.ground(n, e)[0]
		var psi: float = FC.heading(q)
		if agl > 0.8 * height_m:
			airborne = true
		var heading_goal := psi
		var want_n := 0.0
		var want_e := 0.0
		var ground_speed: float = sqrt(v[0] * v[0] + v[1] * v[1])
		while index < points.size():
			var leg := _leg(index)
			# Lead the turn onto the next leg by the distance a coordinated turn at the current speed needs.
			var lead := SWITCH_M
			if index + 1 < points.size():
				var next := _leg(index + 1)
				var turn: float = acos(clampf(leg[0] * next[0] + leg[1] * next[1], -1.0, 1.0))
				lead = clampf(ground_speed * ground_speed / TURN_MPS2 * tan(minf(0.5 * turn, 1.2)), SWITCH_M, 2.5)
			if (n - origin[0]) * leg[0] + (e - origin[1]) * leg[1] < leg[2] - lead:
				break
			origin = points[index]
			index += 1
		if index < points.size():
			var leg := _leg(index)
			var along: float = (n - origin[0]) * leg[0] + (e - origin[1]) * leg[1]
			var cross_n: float = (n - origin[0]) - along * leg[0]
			var cross_e: float = (e - origin[1]) - along * leg[1]
			var corner := cruise_mps
			if index + 1 < points.size():
				var next := _leg(index + 1)
				var half_cos: float = 0.5 + 0.5 * (leg[0] * next[0] + leg[1] * next[1])
				corner = clampf(CORNER_MPS * half_cos * half_cos, MIN_CORNER_MPS, cruise_mps)
			var speed: float = minf(cruise_mps, sqrt(corner * corner + 2.0 * BRAKE_MPS2 * maxf(leg[2] - along, 0.0)))
			var fix_n: float = -K_CROSS * cross_n
			var fix_e: float = -K_CROSS * cross_e
			var fix: float = sqrt(fix_n * fix_n + fix_e * fix_e)
			if fix > MAX_CROSS_MPS:
				fix_n *= MAX_CROSS_MPS / fix
				fix_e *= MAX_CROSS_MPS / fix
			want_n = speed * leg[0] + fix_n
			want_e = speed * leg[1] + fix_e
			heading_goal = atan2(leg[1], leg[0])
		elif not points.is_empty():
			var last: PackedFloat64Array = points[points.size() - 1]
			want_n = clampf(0.8 * (last[0] - n), -2.0, 2.0)
			want_e = clampf(0.8 * (last[1] - e), -2.0, 2.0)
		var accel_n: float = K_VELOCITY * (want_n - v[0])
		var accel_e: float = K_VELOCITY * (want_e - v[1])
		var accel: float = sqrt(accel_n * accel_n + accel_e * accel_e)
		if accel > MAX_ACCEL_MPS2:
			accel_n *= MAX_ACCEL_MPS2 / accel
			accel_e *= MAX_ACCEL_MPS2 / accel
		var forward: float = accel_n * cos(psi) + accel_e * sin(psi)
		var right: float = -accel_n * sin(psi) + accel_e * cos(psi)
		var tilt: float = float(s.plant.config.angle_max_tilt)
		var pitch := 0.0
		var roll := 0.0
		var yaw := 0.0
		if airborne and not landing:
			pitch = clampf(-atan(forward / G) / tilt, -1.0, 1.0)
			roll = clampf(atan(right / G) / tilt, -1.0, 1.0)
			yaw = clampf(0.6 * wrapf(heading_goal - psi, -PI, PI), -0.6, 0.6)
		var climb: float = -v[2]
		var up: float = clampf(4.0 * (height_m - agl) - 3.0 * climb, -4.0, 5.0)
		if landing:
			up = clampf(2.5 * (-0.5 - climb), -4.0, 5.0)
		var level: float = maxf(M.q_rotate(q, M.v3(0.0, 0.0, 1.0))[2], 0.5)
		var map: Dictionary = s.plant.config.actuator
		var command_value: float = ActuatorMap.command_for_thrust(map, float(s.data.mass_kg) * (G + up) / level / 4.0,
			s.plant.supply_voltage(s.sim.continuous))
		var throttle: float = clampf((command_value - float(map.idle)) / ((float(map.top) - float(map.idle))
			* float(s.plant.config.throttle_limit)), 0.0, 1.0)
		if landing and agl < float(s.data.start.rest_height_m) + 0.03:
			throttle = 0.0
		return Fixtures.pilot(roll, pitch, yaw, throttle, arm, 1)

	## [unit north, unit east, length] of leg i (from the current origin for the active leg).
	func _leg(i: int) -> PackedFloat64Array:
		var from: PackedFloat64Array = origin if i == index else points[i - 1]
		var dn: float = points[i][0] - from[0]
		var de: float = points[i][1] - from[1]
		var length: float = maxf(sqrt(dn * dn + de * de), 1.0e-9)
		return PackedFloat64Array([dn / length, de / length, length])


## Approach (`before` m before the plane on the gate axis) and exit (`after` m beyond it) points of each course gate.
static func race_route(course: Dictionary, laps: int, before := 4.0, after := 3.0) -> Array[PackedFloat64Array]:
	var route: Array[PackedFloat64Array] = []
	for _lap in laps:
		for gate: Dictionary in course.gates:
			route.append(PackedFloat64Array([gate.c[0] - before * gate.n[0], gate.c[1] - before * gate.n[1]]))
			route.append(PackedFloat64Array([gate.c[0] + after * gate.n[0], gate.c[1] + after * gate.n[1]]))
	return route


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if not ok:
		_failures += 1
	print("%s %s %s" % ["ok  " if ok else "FAIL", label, detail])


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var started: int = Time.get_ticks_msec()
	_clean()
	DirAccess.make_dir_recursive_absolute(DIR)
	var loaded: Dictionary = FieldLoader.load_from(FieldLoader.DEFAULT_PATH)
	_field = loaded.field
	var built: Dictionary = CollisionSetup.build(_field)
	_world = built.world
	_check("the default field and its obstacle inventory load", loaded.ok and built.ok and not _world.is_empty())
	_write_tracks()
	var main := _case_prepare()
	if main.prepared:
		var log := _watch(main)
		_case_free_flight(main, log)
		if _case_start(main, log):
			_case_race(main, log)
			_case_results(main, log)
			_case_outbox(main, log)
			if not _lap2_envelope.is_empty():
				var second := _case_checkpoint()
				_case_aborts(second)
				_case_missed_gate(second)
				second.queue_free()
		main.queue_free()
	_clean()
	print("    %d accepted ticks, wall time %.1f s" % [_ticks, float(Time.get_ticks_msec() - started) / 1000.0])
	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)


# --- helpers ---------------------------------------------------------------------------------------------------------

func _session(options: Dictionary = {}) -> Node:
	var s: Node = Session.new()
	root.add_child(s)
	s.set_collision_world(_world)
	var requested := {race_track = TRACK, throttle_limit = THROTTLE_LIMIT}
	requested.merge(options, true)
	if not s.prepare(_field, requested):
		print("prepare refused: ", s.load_error)
	return s


## Collects every race event with its accepted tick, and every terminal record. `mute` suspends collection.
func _watch(s: Node) -> Dictionary:
	var log := {events = [], results = [], mute = false}
	s.race_event.connect(func(event: Dictionary) -> void:
		if not log.mute:
			log.events.append({tick = int(s.sim.tick), event = event}))
	s.race_result.connect(func(result: Dictionary) -> void:
		if not log.mute:
			log.results.append(result))
	return log


func _tick(s: Node, pilot: PackedFloat64Array, action: int = 0) -> bool:
	var accepted: bool = s.tick_once(pilot, action)
	if accepted:
		_ticks += 1
	return accepted


func _idle_pilot(arm: int) -> PackedFloat64Array:
	return Fixtures.pilot(0.0, 0.0, 0.0, 0.0, arm, 1)


func _frame_bytes(s: Node) -> PackedByteArray:
	return var_to_bytes(s.frame())


func _types(events: Array) -> String:
	var names := PackedStringArray()
	for item: Variant in events:
		var event: Dictionary = item.event if item.has("event") and typeof(item.event) == TYPE_DICTIONARY else item
		names.append(str(event.type))
	return ",".join(names)


func _of_type(events: Array, kind: String) -> Array:
	var out: Array = []
	for item: Dictionary in events:
		if str(item.event.type) == kind:
			out.append(item)
	return out


func _max_shaft(s: Node) -> float:
	return maxf(maxf(s.sim.continuous[0], s.sim.continuous[1]), maxf(s.sim.continuous[2], s.sim.continuous[3]))


func _phase(s: Node) -> int:
	return s.sim.modes[RaceModel.MODE_PHASE]


func _on_pad(s: Node) -> bool:
	var pad: Dictionary = s.course.pad
	return absf(s.sim.state[RB.POS] - float(pad.north)) < 1e-9 and absf(s.sim.state[RB.POS + 1] - float(pad.east)) < 1e-9


func _pad_point(s: Node) -> PackedFloat64Array:
	return PackedFloat64Array([float(s.course.pad.north), float(s.course.pad.east)])


## Every event time lies inside its accepted tick [(tick - 1) dt, tick dt].
func _inside_ticks(s: Node, events: Array) -> bool:
	var dt: float = s.sim.dt()
	for item: Dictionary in events:
		var t: float = float(item.event.time_s)
		if not (t >= float(int(item.tick) - 1) * dt and t <= float(item.tick) * dt):
			return false
	return true


func _write_json(path: String, value: Variant) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(value, "\t", false))
	file.close()


## Two isolated copies of the shipped track: one for another field, one with gate 1 moved 0.5 m east.
func _write_tracks() -> void:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(TRACK))
	var other: Dictionary = raw.duplicate(true)
	other.field_id = "lake"
	_write_json(DIR + "/other-field.json", other)
	var moved: Dictionary = raw.duplicate(true)
	moved.gates[1].east_m = float(moved.gates[1].east_m) + 0.5
	_write_json(DIR + "/moved-gate.json", moved)


func _clean() -> void:
	if not DirAccess.dir_exists_absolute(DIR):
		return
	for sub: String in DirAccess.get_directories_at(DIR):
		for name: String in DirAccess.get_files_at(DIR.path_join(sub)):
			DirAccess.remove_absolute(DIR.path_join(sub).path_join(name))
		DirAccess.remove_absolute(DIR.path_join(sub))
	for name: String in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR.path_join(name))
	DirAccess.remove_absolute(DIR)


# --- 1. preparation, identities and refusals --------------------------------------------------------------------------

func _case_prepare() -> Node:
	var s := _session()
	_check("1 a race session prepares on the default field with the shipped data and track", s.prepared and s.load_error.is_empty()
		and s.race != null and s.input_size() == RaceModel.INPUT_SIZE, s.load_error)
	if not s.prepared:
		return s
	var t: Dictionary = s.telemetry()
	var pad: Dictionary = s.course.pad
	var q: PackedFloat64Array = M.quat(s.sim.state[RB.ATT], s.sim.state[RB.ATT + 1], s.sim.state[RB.ATT + 2], s.sim.state[RB.ATT + 3])
	_check("1 prepared, paused, disarmed, resting on the course pad with the pad heading", s.paused and s.pause_reason == "prepared"
		and s.sim.tick == 0 and not t.armed and s.sim.modes[FC.MODE_MOTOR] == FC.MOTOR_DISARMED and s.crash.is_empty() and _on_pad(s)
		and absf(float(t.altitude_agl_m) - float(s.data.start.rest_height_m)) < 1e-9 and float(t.speed_mps) == 0.0
		and absf(FC.heading(q) - deg_to_rad(float(pad.heading_deg))) < 1e-9,
		"pad %.2f %.2f heading %.3f deg" % [float(pad.north), float(pad.east), rad_to_deg(FC.heading(q))])
	_check("1 race telemetry starts IDLE at gate 0 of six with an empty outbox", t.race.phase == "IDLE" and t.race.next_gate == 0
		and t.race.gate_count == 6 and t.race.attempt == 0 and t.race.pending_results == 0 and s.results.is_empty())
	var identity: Dictionary = s.identity()
	_check("1 identity().race pins the course identity, the ruleset and the path policy", identity.race.course == s.course.identity
		and not str(s.course.identity).is_empty() and identity.race.ruleset == Track.RULESET and identity.race.path_policy == Track.PATH_POLICY
		and identity.start.race_course == s.course.identity and s.course.track_id == "openrc-practice-oval-1")
	var free := _session({race_track = ""})
	_check("1 a session prepared without race_track has an empty race identity and a different identity",
		free.prepared and free.race == null and free.identity().race.course == "" and free.identity().race.ruleset == ""
		and var_to_bytes(free.identity()) != var_to_bytes(identity) and free.input_size() == FC.INPUT_SIZE, free.load_error)
	free.queue_free()
	return s


# --- 2. free flight in a race session (and refusals that keep the running flight) -----------------------------------

func _case_free_flight(s: Node, log: Dictionary) -> void:
	s.resume()
	var ok: bool = _tick(s, _idle_pilot(0)) and _tick(s, _idle_pilot(1)) and s.sim.modes[FC.MODE_MOTOR] == FC.MOTOR_ARMED
	var frame := _frame_bytes(s)
	var tape: PackedFloat64Array = s.tape()
	var identity := var_to_bytes(s.identity())
	var resets := [0]
	var counter := func() -> void: resets[0] += 1
	s.resetting.connect(counter)
	var cases := [["a missing track file", {race_track = "res://data/race/tracks/does-not-exist.json"}],
		["a track for another field", {race_track = DIR + "/other-field.json"}],
		["an air start with a race", {race_track = TRACK, start = "air"}]]
	for item: Array in cases:
		var refused: bool = not s.prepare(_field, item[1])
		_check("1 %s is refused by prepare and the running flight is untouched" % item[0], refused and not s.load_error.is_empty()
			and s.prepared and s.race != null and _frame_bytes(s) == frame and s.tape() == tape and var_to_bytes(s.identity()) == identity
			and resets[0] == 0 and not s.paused, s.load_error.left(140))
	s.resetting.disconnect(counter)
	var pilot := Pilot.new()
	pilot.height_m = 1.5
	pilot.cruise_mps = 2.0
	pilot.fly([PackedFloat64Array([float(s.course.pad.north) + 3.0, float(s.course.pad.east)])], _pad_point(s))
	var peak := 0.0
	for _i in 720:
		ok = ok and _tick(s, pilot.command(s))
		peak = maxf(peak, float(s.telemetry().altitude_agl_m))
	pilot.landing = true
	var landed := false
	for _i in 960:
		ok = ok and _tick(s, pilot.command(s))
		var t: Dictionary = s.telemetry()
		if float(t.altitude_agl_m) < float(s.data.start.rest_height_m) + 0.01 and float(t.speed_mps) < 0.05:
			landed = true
			break
	pilot.arm = 0
	for _i in 30:
		ok = ok and _tick(s, pilot.command(s))
	var away: float = Vector2(s.sim.state[RB.POS] - float(s.course.pad.north), s.sim.state[RB.POS + 1] - float(s.course.pad.east)).length()
	_check("2 free flight before any start request: arm, hop, land and disarm like free flight, with no race event",
		ok and peak > 1.2 and landed and s.crash.is_empty() and s.sim.modes[FC.MODE_MOTOR] == FC.MOTOR_DISARMED
		and log.events.is_empty() and log.results.is_empty() and s.telemetry().race.phase == "IDLE" and away > 2.0,
		"peak %.2f m, landed %s %.2f m from the pad, events %s" % [peak, landed, away, _types(log.events)])


# --- 3 + 12. start refusal, countdown, pause, GO refusal and GO ---------------------------------------------------------

func _case_start(s: Node, log: Dictionary) -> bool:
	var start_ok: bool = _tick(s, _idle_pilot(0), Director.ACTION_START)
	var race: Dictionary = s.telemetry().race
	var refused: Dictionary = log.events.back().event if not log.events.is_empty() else {}
	_check("3 a start request away from the pad is refused: race_refused, reason code in telemetry, still IDLE",
		start_ok and _types(log.events) == "race_refused" and refused.stage == "start" and refused.reason == "start_refused_not_on_pad"
		and int(refused.reason_code) == Director.REASON_START_NOT_ON_PAD and race.phase == "IDLE"
		and race.reason == "start_refused_not_on_pad" and race.reason_code == Director.REASON_START_NOT_ON_PAD and race.attempt == 0
		and _inside_ticks(s, log.events), _types(log.events))
	_check("3 reset_to_pad returns a paused, disarmed quad on the course pad", s.reset_to_pad() and s.paused and _on_pad(s)
		and s.sim.tick == 0 and s.sim.modes[FC.MODE_MOTOR] == FC.MOTOR_DISARMED and s.results.is_empty())
	s.resume()
	log.events.clear()
	var start_tick: int = s.sim.tick + 1
	start_ok = _tick(s, _idle_pilot(0), Director.ACTION_START)
	race = s.telemetry().race
	_check("3 a start on the pad is accepted: race_countdown at the start of its tick, COUNTDOWN, attempt 1",
		start_ok and _types(log.events) == "race_countdown" and float(log.events[0].event.time_s) == float(start_tick - 1) * s.sim.dt()
		and race.phase == "COUNTDOWN" and race.countdown_ticks == 1 and race.attempt == 1, _types(log.events))
	var shafts := 0.0
	var commands := 0.0
	var phases_ok := start_ok
	for i in range(1, 720):
		if i == 360:
			s.pause("pilot pause")
			var held := _frame_bytes(s)
			var tape: PackedFloat64Array = s.tape()
			var tick: int = s.sim.tick
			var none := true
			for _j in 30:
				none = none and not s.tick_once(_idle_pilot(1))
			_check("12 RACE-14 while paused no tick is accepted and the countdown does not advance", none and s.paused
				and _frame_bytes(s) == held and s.tape() == tape and s.sim.tick == tick and s.sim.modes[RaceModel.MODE_COUNTDOWN] == 360)
			_check("12 resume continues the countdown by one tick per accepted tick", s.resume() and _tick(s, _idle_pilot(1))
				and s.sim.modes[RaceModel.MODE_COUNTDOWN] == 361)
			continue
		phases_ok = phases_ok and _tick(s, _idle_pilot(0 if i < 3 else 1))
		shafts = maxf(shafts, _max_shaft(s))
		if s.sim.modes[FC.MODE_MOTOR] == FC.MOTOR_ARMED:
			commands = maxf(commands, s.sim.aux[FC.AUX_COMMAND])
		phases_ok = phases_ok and _phase(s) == Director.PHASE_COUNTDOWN and s.sim.modes[RaceModel.MODE_COUNTDOWN] == i + 1
	_check("3 RACE-11 the countdown is exactly 720 accepted ticks; the pilot armed, the shafts never spun",
		phases_ok and s.sim.tick == start_tick + 719 and s.sim.modes[RaceModel.MODE_COUNTDOWN] == 720
		and s.sim.modes[FC.MODE_MOTOR] == FC.MOTOR_ARMED and shafts == 0.0 and commands > 0.0 and _types(log.events) == "race_countdown",
		"shafts %.6f commands %.4f" % [shafts, commands])
	_go_envelope = s.checkpoint()
	log.events.clear()
	var refused_ok: bool = _tick(s, Fixtures.pilot(0.0, 0.0, 0.0, 0.6, 1, 1))
	var go_refusal: Dictionary = log.events[0].event if log.events.size() == 1 else {}
	_check("3 RACE-11 GO with the throttle high is refused: race_refused, IDLE, motors DISARMED, no drive",
		refused_ok and _types(log.events) == "race_refused" and go_refusal.stage == "go" and go_refusal.reason == "go_refused_throttle"
		and _phase(s) == Director.PHASE_IDLE and s.sim.modes[FC.MODE_MOTOR] == FC.MOTOR_DISARMED and _max_shaft(s) == 0.0,
		_types(log.events))
	var held_ok := true
	for _i in 30:
		held_ok = held_ok and _tick(s, _idle_pilot(1)) and s.sim.modes[FC.MODE_MOTOR] == FC.MOTOR_DISARMED and _max_shaft(s) == 0.0
	_check("3 RACE-11 an arm switch held high after the refused GO does not rearm", held_ok)
	_check("3 the pre-GO checkpoint restores (running)", s.restore_checkpoint(_go_envelope) and not s.paused
		and s.sim.modes[RaceModel.MODE_COUNTDOWN] == 720)
	log.events.clear()
	var go_start: float = s.sim.time()
	var go_ok: bool = _tick(s, _idle_pilot(1))
	_check("3 RACE-11 GO with low throttle and armed motors: RACING, race_go at the start of its tick, 3 s after the countdown began",
		go_ok and _types(log.events) == "race_go" and float(log.events[0].event.time_s) == go_start
		and go_start == float(start_tick + 719) * s.sim.dt() and _phase(s) == Director.PHASE_RACING
		and s.sim.aux[RaceModel.AUX_GO_TIME] == go_start, _types(log.events))
	return go_ok and _phase(s) == Director.PHASE_RACING


# --- 4 + 10a. the complete race; a lap-2 checkpoint replayed in the same session ---------------------------------------

func _case_race(s: Node, log: Dictionary) -> void:
	var pilot := Pilot.new()
	pilot.cruise_mps = CRUISE_MPS
	pilot.fly(race_route(s.course, 3), _pad_point(s))
	var flying := true
	var same_session := false
	var crossed_in_window := false
	var gate: Dictionary = s.course.gates[2]
	for _i in RACE_TICK_LIMIT:
		if _lap2_envelope.is_empty() and s.sim.modes[RaceModel.MODE_VALID_LAPS] == 1 and s.sim.modes[RaceModel.MODE_NEXT_GATE] == 2 \
				and (s.sim.state[RB.POS] - gate.c[0]) * gate.n[0] + (s.sim.state[RB.POS + 1] - gate.c[1]) * gate.n[1] > -1.5:
			_lap2_envelope = s.checkpoint()
			for _j in WINDOW_TICKS:
				flying = flying and _tick(s, pilot.command(s))
				_lap2_rows.append(s.sim.inputs.duplicate())
				_lap2_frames.append(_frame_bytes(s))
				_lap2_events.append(var_to_bytes(s.sim.last_events))
				crossed_in_window = crossed_in_window or _types(s.sim.last_events).contains("race_gate")
			# 10 RACE-15 (same session): restore the envelope and replay the recorded kernel input rows.
			log.mute = true
			same_session = s.restore_checkpoint(_lap2_envelope) and not s.paused
			for j in WINDOW_TICKS:
				same_session = same_session and s.tick_input(_lap2_rows[j]) and _frame_bytes(s) == _lap2_frames[j] \
					and var_to_bytes(s.sim.last_events) == _lap2_events[j]
			_ticks += WINDOW_TICKS
			log.mute = false
			continue
		flying = flying and _tick(s, pilot.command(s))
		if not flying or _phase(s) != Director.PHASE_RACING:
			break
	_check("10 RACE-15 a lap-2 checkpoint just before gate 2, restored into the same session, replays 480 rows byte-identically (frames and event lists)",
		not _lap2_envelope.is_empty() and crossed_in_window and same_session, "crossed %s" % crossed_in_window)
	var events: Array = log.events
	var gates := _of_type(events, "race_gate")
	var laps := _of_type(events, "race_lap")
	var finishes := _of_type(events, "race_finish")
	var go: Dictionary = _of_type(events, "race_go")[0].event
	var order_ok: bool = gates.size() == 18
	for i in gates.size():
		order_ok = order_ok and int(gates[i].event.gate) == i % 6 and int(gates[i].event.lap) == i / 6 + 1
	_check("4 the scripted pilot flies three valid laps: gates 0…5 three times in order, no crash, nothing unresolved",
		flying and order_ok and s.crash.is_empty() and s.sim.modes[RaceModel.MODE_UNRESOLVED] == 0,
		"%d gate events, crash %s" % [gates.size(), str(s.crash)])
	var lap_sum := 0.0
	var laps_ok: bool = laps.size() == 3
	for i in laps.size():
		laps_ok = laps_ok and int(laps[i].event.lap) == i + 1 and float(laps[i].event.duration_s) > 0.0
		lap_sum += float(laps[i].event.duration_s)
	_lap1_duration = float(laps[0].event.duration_s) if not laps.is_empty() else NAN
	var finish: Dictionary = finishes[0].event if finishes.size() == 1 else {}
	print("    lap times %s s, total %.6f s" % [str(laps.map(func(item: Dictionary) -> String: return "%.6f" % float(item.event.duration_s))),
		float(finish.get("total_s", NAN))])
	_check("4 three race_lap events with positive durations; one race_finish whose total is the lap sum and finish - GO",
		laps_ok and finishes.size() == 1 and absf(float(finish.total_s) - lap_sum) < 1e-9
		and float(finish.total_s) == float(finish.time_s) - float(go.time_s) and int(finish.laps) == 3
		and finish.lap_durations_s == PackedFloat64Array([laps[0].event.duration_s, laps[1].event.duration_s, laps[2].event.duration_s]))
	var race: Dictionary = s.telemetry().race
	_check("4 telemetry: FINISHED, three valid laps, elapsed total equals the finish total", race.phase == "FINISHED"
		and race.valid_laps == 3 and race.elapsed_total_s == float(finish.get("total_s", NAN)) and race.gates_passed == 18)
	var record: Dictionary = log.results[0] if log.results.size() == 1 else {}
	var durations_ok: bool = record.get("laps", []).size() == 3
	for i in mini(record.get("laps", []).size(), laps.size()):
		durations_ok = durations_ok and float(record.laps[i].duration_s) == float(laps[i].event.duration_s)
	_check("4 exactly one race_result: valid, three laps, the course identity, ruleset and path policy",
		log.results.size() == 1 and s.results.size() == 1 and record.valid and record.terminal and record.phase == "FINISHED"
		and durations_ok and record.total_s == finish.get("total_s") and record.course_identity == s.course.identity
		and record.ruleset == Track.RULESET and record.path_policy == Track.PATH_POLICY and record.track_id == s.course.track_id
		and record.session.data_sha256 == s.source_sha256 and record.session.collision_identity == s.collision_identity()
		and not record.saved, str(record).left(200))
	_check("4 every race event time lies inside its accepted tick", _inside_ticks(s, events))
	var off_boundary := false
	for item: Dictionary in gates:
		var ticks: float = float(item.event.time_s) / s.sim.dt()
		off_boundary = off_boundary or absf(ticks - roundf(ticks)) > 1e-6
	_check("4 crossing times are interpolated inside ticks: at least one gate time is not on a tick boundary", off_boundary)


# --- 5. persistence ---------------------------------------------------------------------------------------------------

func _case_results(s: Node, log: Dictionary) -> void:
	var directory := DIR + "/results"
	var pending: Dictionary = s.results[0].duplicate(true) if s.results.size() == 1 else {}
	var report: Dictionary = s.save_results(directory)
	var files: Array = Array(DirAccess.get_files_at(directory)) if DirAccess.dir_exists_absolute(directory) else []
	_check("5 save_results writes one JSON file per pending record and empties the outbox", report.saved == 1 and report.failed == 0
		and report.paths.size() == 1 and files.size() == 1 and str(files[0]).ends_with(".json") and s.results.is_empty()
		and s.telemetry().race.pending_results == 0, str(report))
	var stored: Variant = JSON.parse_string(FileAccess.get_file_as_string(report.paths[0])) if report.paths.size() == 1 else null
	var laps_ok: bool = typeof(stored) == TYPE_DICTIONARY and stored.get("laps", []).size() == 3 and not pending.is_empty()
	if laps_ok:
		for i in 3:
			laps_ok = laps_ok and int(stored.laps[i].lap) == i + 1 and absf(float(stored.laps[i].duration_s) - float(pending.laps[i].duration_s)) < 1e-12
	_check("5 the file parses and holds the lap list, validity and the course, ruleset, path-policy and session identities",
		laps_ok and stored.valid == true and stored.saved == true and stored.course_identity == s.course.identity
		and stored.ruleset == Track.RULESET and stored.path_policy == Track.PATH_POLICY and stored.session.data_sha256 == s.source_sha256
		and stored.session.controller == pending.session.controller and int(stored.attempt) == int(pending.attempt))
	var again: Dictionary = s.save_results(directory)
	_check("5 saving again is a no-op", again.saved == 0 and again.failed == 0 and again.paths.is_empty()
		and DirAccess.get_files_at(directory).size() == 1)


# --- 6 + 5 + 7c. outbox bound, failed save, discard, cancel during the countdown -------------------------------------

func _case_outbox(s: Node, log: Dictionary) -> void:
	_check("6 a pad reset after a finish publishes nothing new", s.reset_to_pad() and s.results.is_empty() and s.resume()
		and _phase(s) == Director.PHASE_IDLE)
	log.results.clear()
	var ok := true
	for _i in Session.MAX_PENDING_RESULTS:
		ok = ok and _tick(s, _idle_pilot(0), Director.ACTION_START) and _phase(s) == Director.PHASE_COUNTDOWN
		ok = ok and s.reset_to_pad() and s.resume()
	var records_ok: bool = ok and s.results.size() == Session.MAX_PENDING_RESULTS and log.results.size() == Session.MAX_PENDING_RESULTS
	for record: Dictionary in s.results:
		records_ok = records_ok and record.terminal and not record.valid and record.phase == "ABORTED" and record.reason == "pad_reset"
	_check("7 RACE-13 a pad reset during the countdown keeps an aborted record each time (%d pending)" % Session.MAX_PENDING_RESULTS,
		records_ok and s.telemetry().race.pending_results == Session.MAX_PENDING_RESULTS, "%d pending" % s.results.size())
	var frame := _frame_bytes(s)
	var tape: PackedFloat64Array = s.tape()
	var tick: int = s.sim.tick
	_check("6 RACE-14 a full outbox refuses a start request: tick_once returns false and nothing changes",
		not s.tick_once(_idle_pilot(0), Director.ACTION_START) and _frame_bytes(s) == frame and s.tape() == tape and s.sim.tick == tick
		and _phase(s) == Director.PHASE_IDLE and s.results.size() == Session.MAX_PENDING_RESULTS)
	_check("6 an ordinary tick is still accepted with a full outbox", _tick(s, _idle_pilot(0)) and _phase(s) == Director.PHASE_IDLE)
	var blocker := DIR + "/blocker"
	var file := FileAccess.open(blocker, FileAccess.WRITE)
	file.store_string("not a directory\n")
	file.close()
	var failed: Dictionary = s.save_results(blocker)
	_check("5 RACE-14 a save into an unwritable directory reports the failure and keeps every record pending",
		failed.saved == 0 and failed.failed == Session.MAX_PENDING_RESULTS and not failed.errors.is_empty()
		and s.results.size() == Session.MAX_PENDING_RESULTS, str(failed.errors).left(160))
	var directory := DIR + "/outbox"
	var saved: Dictionary = s.save_results(directory)
	var unique := {}
	for path: String in saved.paths:
		unique[path] = true
	var files := DirAccess.get_files_at(directory) if DirAccess.dir_exists_absolute(directory) else PackedStringArray()
	_check("5 RACE-14 the retry saves every record to its own file and empties the outbox",
		saved.saved == Session.MAX_PENDING_RESULTS and saved.failed == 0 and unique.size() == Session.MAX_PENDING_RESULTS
		and files.size() == Session.MAX_PENDING_RESULTS and s.results.is_empty(), "%d saved, %d distinct paths, %d files" % [saved.saved,
			unique.size(), files.size()])
	log.events.clear()
	var accepted: bool = _tick(s, _idle_pilot(0), Director.ACTION_START) and _phase(s) == Director.PHASE_COUNTDOWN
	_check("6 with room in the outbox a start is accepted again", accepted)
	ok = _tick(s, _idle_pilot(0)) and _tick(s, _idle_pilot(0), Director.ACTION_CANCEL)
	_check("7 a cancel action during the countdown returns to IDLE with race_cancelled and no record", ok
		and _types(log.events) == "race_countdown,race_cancelled" and _phase(s) == Director.PHASE_IDLE
		and s.telemetry().race.reason == "cancelled" and s.results.is_empty() and _inside_ticks(s, log.events), _types(log.events))
	ok = _tick(s, _idle_pilot(0), Director.ACTION_START) and s.reset_to_pad() and s.results.size() == 1
	s.discard_results()
	_check("5 discard_results empties the outbox", ok and s.results.is_empty() and s.telemetry().race.pending_results == 0)


# --- 10b. the lap-2 checkpoint in a second identically prepared session; course swap ----------------------------------

func _case_checkpoint() -> Node:
	var second := _session()
	var restored: bool = second.restore_checkpoint(_lap2_envelope)
	var same: bool = restored and not second.paused
	for j in _lap2_rows.size():
		same = same and second.tick_input(_lap2_rows[j]) and _frame_bytes(second) == _lap2_frames[j] \
			and var_to_bytes(second.sim.last_events) == _lap2_events[j]
	_ticks += _lap2_rows.size()
	_check("10 RACE-15 the lap-2 checkpoint restored into a second identically prepared session replays byte-identically",
		same and _lap2_rows.size() == WINDOW_TICKS)
	var moved := _session({race_track = DIR + "/moved-gate.json"})
	var before := _frame_bytes(moved)
	_check("10 RACE-03 a session on the track copy with gate 1 moved 0.5 m has another course identity and refuses the envelope",
		moved.prepared and moved.course.identity != second.course.identity and not moved.restore_checkpoint(_lap2_envelope)
		and _frame_bytes(moved) == before and moved.sim.tick == 0 and moved.telemetry().race.phase == "IDLE", moved.load_error)
	var foreign: Dictionary = moved.checkpoint()
	before = _frame_bytes(second)
	var tick: int = second.sim.tick
	_check("10 RACE-03 and the original session refuses the moved-track envelope with nothing changed",
		not foreign.is_empty() and not second.restore_checkpoint(foreign) and _frame_bytes(second) == before and second.sim.tick == tick
		and not second.paused)
	moved.queue_free()
	return second


# --- 7 + 8. pad reset and crash during RACING ---------------------------------------------------------------------------

func _case_aborts(s: Node) -> void:
	var log := _watch(s)
	var racing: bool = _phase(s) == Director.PHASE_RACING and s.sim.modes[RaceModel.MODE_VALID_LAPS] == 1
	var reset: bool = s.reset_to_pad()
	var record: Dictionary = log.results[0] if log.results.size() == 1 else {}
	_check("7 RACE-13 a pad reset during RACING keeps one aborted record with the completed lap slot and reason pad_reset",
		racing and reset and s.results.size() == 1 and not record.is_empty() and record.terminal and not record.valid
		and record.phase == "ABORTED" and record.reason == "pad_reset" and record.laps.size() == 1
		and float(record.laps[0].duration_s) == _lap1_duration and record.course_identity == s.course.identity, str(record).left(200))
	_check("7 and returns a disarmed quad on the pad in IDLE", s.paused and _on_pad(s) and s.sim.modes[FC.MODE_MOTOR] == FC.MOTOR_DISARMED
		and s.telemetry().race.phase == "IDLE" and s.telemetry().race.valid_laps == 0)
	# Restore lap 2 again (the envelope's outbox is empty), fly through gate 2, then along gate 3's south post line.
	log.results.clear()
	log.events.clear()
	var restored: bool = s.restore_checkpoint(_lap2_envelope) and s.results.is_empty()
	var g2: Dictionary = s.course.gates[2]
	var g3: Dictionary = s.course.gates[3]
	var post := PackedFloat64Array([g3.c[0] - (g3.w + 0.5 * Track.FRAME_SECTION_M) * g3.u[0], g3.c[1] - (g3.w + 0.5 * Track.FRAME_SECTION_M) * g3.u[1]])
	var pilot := Pilot.new()
	pilot.cruise_mps = 4.0
	pilot.airborne = true
	pilot.fly([PackedFloat64Array([g2.c[0] + 3.0 * g2.n[0], g2.c[1] + 3.0 * g2.n[1]]),
		PackedFloat64Array([post[0] - 8.0 * g3.n[0], post[1] - 8.0 * g3.n[1]]),
		PackedFloat64Array([post[0] + 5.0 * g3.n[0], post[1] + 5.0 * g3.n[1]])], PackedFloat64Array([s.sim.state[RB.POS], s.sim.state[RB.POS + 1]]))
	var crash_events := ""
	var crash_list: Array = []
	var ok := restored
	for _i in 240 * 15:
		ok = ok and _tick(s, pilot.command(s))
		if not s.crash.is_empty():
			crash_list = s.sim.last_events.duplicate(true)
			crash_events = _types(crash_list)
			break
	var strike_east: float = s.sim.state[RB.POS + 1]
	_check("8 RACE-02 gate frames are solid: flying into gate 3's post is an Obstacle strike before the centre reaches the post",
		ok and s.crash.get("reason", "") == "Obstacle strike" and strike_east > post[1] + 0.5 * Track.FRAME_SECTION_M
		and strike_east < post[1] + 1.0 and absf(s.sim.state[RB.POS] - post[0]) < 0.3,
		"crash %s at %.3f %.3f (post %.3f %.3f)" % [str(s.crash), s.sim.state[RB.POS], strike_east, post[0], post[1]])
	var abort: Dictionary = crash_list[1] if crash_list.size() == 2 else {}
	_check("7 RACE-13 the crash aborts the race: crash then race_abort in that tick's ordered list, at the crash time",
		crash_events == "crash,race_abort" and abort.reason == "crash" and float(abort.time_s) == float(crash_list[0].time_s)
		and int(abort.lap) == 2 and _phase(s) == Director.PHASE_ABORTED and _types(log.events).ends_with("race_gate,race_abort"), crash_events)
	record = log.results[0] if log.results.size() == 1 else {}
	_check("7 one aborted record: invalid, reason crash, completed lap 1 retained", s.results.size() == 1 and not record.is_empty()
		and not record.valid and record.phase == "ABORTED" and record.reason == "crash" and record.laps.size() == 1
		and float(record.laps[0].duration_s) == _lap1_duration, str(record).left(200))


# --- 9. a missed gate --------------------------------------------------------------------------------------------------

func _case_missed_gate(s: Node) -> void:
	var log := _watch(s)
	var restored: bool = s.restore_checkpoint(_go_envelope) and s.results.is_empty()
	var ok: bool = restored and _tick(s, _idle_pilot(1)) and _phase(s) == Director.PHASE_RACING
	var g: Array = s.course.gates
	var around := PackedFloat64Array([g[1].c[0] + 4.5, g[1].c[1]])
	var route: Array[PackedFloat64Array] = [
		_axis(g[0], -4.0), _axis(g[0], 3.0), # gate 0
		PackedFloat64Array([around[0], around[1] - 7.0]), PackedFloat64Array([around[0], around[1] + 5.0]), # past gate 1, outside
		_axis(g[2], -4.0), _axis(g[2], 3.0), # gate 2 out of order
		PackedFloat64Array([g[2].c[0] - 1.0, g[1].c[1] - 4.0]), _axis(g[1], -9.0), # back
		_axis(g[1], -4.0), _axis(g[1], 3.0), # gate 1
		_axis(g[2], -4.0), _axis(g[2], 3.0)] # gate 2
	var pilot := Pilot.new()
	pilot.cruise_mps = CRUISE_MPS
	pilot.fly(route, _pad_point(s))
	var after_miss: Dictionary = {}
	for _i in 240 * 60:
		ok = ok and _tick(s, pilot.command(s))
		if after_miss.is_empty() and pilot.index >= 6:
			after_miss = {next_gate = s.sim.modes[RaceModel.MODE_NEXT_GATE], gates = s.sim.modes[RaceModel.MODE_GATES_TOTAL],
				events = _types(log.events), north = s.sim.state[RB.POS]}
		if not ok or pilot.done() or not s.crash.is_empty():
			break
	_check("9 RACE-12 flying around gate 1 outside its aperture and then through gate 2 does not advance the sequence",
		ok and not after_miss.is_empty() and after_miss.next_gate == 1 and after_miss.gates == 1 and after_miss.events == "race_go,race_gate"
		and float(after_miss.north) > g[2].c[0], str(after_miss))
	var gates := _of_type(log.events, "race_gate")
	var sequence := PackedInt64Array()
	for item: Dictionary in gates:
		sequence.append(int(item.event.gate))
	_check("9 RACE-12 returning to cross gate 1 correctly scores it and the lap continues with gate 2",
		ok and s.crash.is_empty() and sequence == PackedInt64Array([0, 1, 2]) and _phase(s) == Director.PHASE_RACING
		and s.sim.modes[RaceModel.MODE_NEXT_GATE] == 3 and s.sim.modes[RaceModel.MODE_VALID_LAPS] == 0
		and s.sim.modes[RaceModel.MODE_UNRESOLVED] == 0, "sequence %s crash %s" % [str(sequence), str(s.crash)])


## The point `offset` metres along a gate's axis from its centre (negative: before the plane).
static func _axis(gate: Dictionary, offset: float) -> PackedFloat64Array:
	return PackedFloat64Array([gate.c[0] + offset * gate.n[0], gate.c[1] + offset * gate.n[1]])
