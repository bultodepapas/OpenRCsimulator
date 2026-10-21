extends SceneTree

const Pilot := preload("res://ai/companions/pilot.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const Math3D := preload("res://physics/math3d.gd")
const RigidBody := preload("res://physics/rigid_body.gd")

const SEED := 20261020
const TRIM := {"V": 15.0, "throttle": 0.45}
const NO_WIND := [0.0, 0.0, 0.0]
const NO_TURBULENCE := [0.0, 0.0, 0.0]

var _checks: int = 0
var _failures: int = 0


func _check(label: String, passed: bool, detail: String = "") -> void:
	_checks += 1
	print(("ok   " if passed else "FAIL ") + label + ("  " + detail if not detail.is_empty() else ""))
	if not passed:
		_failures += 1


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var loaded: Dictionary = FieldLoader.load_from()
	_check("accepted Club field loads", bool(loaded.get("ok", false)), str(loaded.get("errors", [])))
	if not loaded.get("ok", false):
		quit(1)
		return
	var field: Dictionary = loaded.field
	var reference := Pilot.new()
	_check("slot 0 accepts complete solved trim", reference.configure(0, 1, SEED, TRIM, field), reference.configure_error)
	_check("missing solved trim is refused", not Pilot.new().configure(0, 1, SEED, {}, field))
	_check("incomplete nonempty trim is refused", not Pilot.new().configure(0, 1, SEED, {"activity": "circuits"}, field))
	_check("slot outside requested count is refused", not Pilot.new().configure(1, 1, SEED, TRIM, field))
	_check("unsupported field is refused", not Pilot.new().configure(0, 1, SEED, TRIM, {"id": "workshop"}))
	_check("seed outside uint32 is refused", not Pilot.new().configure(0, 1, 4294967296, TRIM, field))
	if not reference.initial_pose().get("ok", false):
		quit(1)
		return

	var same_seed := Pilot.new()
	var other_seed := Pilot.new()
	var other_slot := Pilot.new()
	_check("same seed reproduces initial pose", same_seed.configure(0, 1, SEED, TRIM, field)
		and _poses_identical(reference.initial_pose(), same_seed.initial_pose()))
	_check("different seed changes initial circuit phase", other_seed.configure(0, 1, SEED + 1, TRIM, field)
		and not _poses_identical(reference.initial_pose(), other_seed.initial_pose()))
	_check("fleet slots occupy distinct height bands", other_slot.configure(1, 3, SEED, TRIM, field)
		and is_equal_approx(float(other_slot.initial_pose().height_agl_m) - float(reference.initial_pose().height_agl_m), 20.0))
	_check("initial pose reports AGL height and valid heading", float(reference.initial_pose().height_agl_m) >= 35.0
		and absf(float(reference.initial_pose().heading_rad)) <= PI)

	var own_pose: Dictionary = reference.initial_pose()
	var snapshot: Dictionary = _snapshot(own_pose)
	var baseline: Dictionary = reference.command(snapshot, 0)
	var repeated: Dictionary = reference.command(snapshot, 0)
	_check("controller command is deterministic for the same seeded observation",
		_packet_bytes(baseline) == _packet_bytes(repeated))
	_check("controller emits finite normalized controls", baseline.get("ok", false) and _packet_bounded(baseline))
	var invalid_snapshot: Dictionary = snapshot.duplicate(true)
	invalid_snapshot.state = PackedFloat64Array([0.0, 0.0, NAN])
	var invalid_packet: Dictionary = reference.command(invalid_snapshot, 0)
	_check("malformed state is refused with finite bounded fallback", not invalid_packet.get("ok", true) and _packet_bounded(invalid_packet))
	var strong_wind: Dictionary = snapshot.duplicate(true)
	strong_wind.wind_ned = PackedFloat64Array([6.0, 0.0, 0.0])
	var wind_packet: Dictionary = reference.command(strong_wind, 0)
	_check("unqualified strong wind is refused safely", not wind_packet.get("ok", true) and _packet_bounded(wind_packet))
	var strong_turbulence: Dictionary = snapshot.duplicate(true)
	strong_turbulence.turbulence_rms_m_s = PackedFloat64Array([1.0, 0.0, 0.0])
	var turbulence_packet: Dictionary = reference.command(strong_turbulence, 0)
	_check("unqualified turbulence is refused safely", not turbulence_packet.get("ok", true) and _packet_bounded(turbulence_packet))

	_check_encounters(reference, own_pose, snapshot, baseline, field)
	print("companion pilot: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _check_encounters(pilot: RefCounted, pose: Dictionary, snapshot: Dictionary, baseline: Dictionary, field: Dictionary) -> void:
	var own_state: PackedFloat64Array = snapshot.state
	var attitude: PackedFloat64Array = Math3D.quat(own_state[RigidBody.ATT], own_state[RigidBody.ATT + 1],
		own_state[RigidBody.ATT + 2], own_state[RigidBody.ATT + 3])
	var forward: PackedFloat64Array = Math3D.q_rotate(attitude, PackedFloat64Array([1.0, 0.0, 0.0]))
	var right_north: float = -forward[1]
	var right_east: float = forward[0]
	var north: float = own_state[RigidBody.POS]
	var east: float = own_state[RigidBody.POS + 1]
	var down: float = own_state[RigidBody.POS + 2]
	var heading: float = float(pose.heading_rad)

	var head_on_state: PackedFloat64Array = _traffic_state(
		north + 45.0 * forward[0], east + 45.0 * forward[1], down, wrapf(heading + PI, -PI, PI), 15.0)
	var head_on: Dictionary = pilot.command(snapshot, 0, [_traffic("player", -1, true, head_on_state)])
	_check("head-on closure activates player separation", _avoids(head_on) and not _same_roll(head_on, baseline))
	var reciprocal := Pilot.new()
	var reciprocal_configured: bool = reciprocal.configure(1, 2, SEED, TRIM, field)
	var reciprocal_snapshot: Dictionary = _snapshot_from_state(head_on_state, float(snapshot.ground_clearance_m))
	var reciprocal_baseline: Dictionary = {}
	var reciprocal_response: Dictionary = {}
	if reciprocal_configured:
		reciprocal_baseline = reciprocal.command(reciprocal_snapshot, 0)
		reciprocal_response = reciprocal.command(reciprocal_snapshot, 0,
			[_traffic("companion-0", 0, false, own_state)])
	var forward_delta: float = float(head_on.get("roll", 0.0)) - float(baseline.get("roll", 0.0))
	var reciprocal_delta: float = float(reciprocal_response.get("roll", 0.0)) - float(reciprocal_baseline.get("roll", 0.0))
	var own_right: PackedFloat64Array = Math3D.q_rotate(attitude, PackedFloat64Array([0.0, 1.0, 0.0]))
	var peer_attitude: PackedFloat64Array = Math3D.quat(head_on_state[6], head_on_state[7], head_on_state[8], head_on_state[9])
	var peer_right: PackedFloat64Array = Math3D.q_rotate(peer_attitude, PackedFloat64Array([0.0, 1.0, 0.0]))
	var world_turn_alignment: float = forward_delta * reciprocal_delta * (own_right[0] * peer_right[0] + own_right[1] * peer_right[1])
	_check("zero-CPA reciprocal head-on aircraft both emit bounded avoidance", reciprocal_configured
		and _avoids(head_on) and _avoids(reciprocal_response))
	_check("reciprocal zero-CPA fallback turns both aircraft toward opposite world sides",
		world_turn_alignment < -1e-8,
		"slot0_delta=%.5f slot1_delta=%.5f world_alignment=%.5f" % [forward_delta, reciprocal_delta, world_turn_alignment])

	var cross_right_state: PackedFloat64Array = _traffic_state(
		north + 30.0 * forward[0] + 20.0 * right_north,
		east + 30.0 * forward[1] + 20.0 * right_east,
		down, wrapf(heading - PI / 2.0, -PI, PI), 15.0)
	var cross_left_state: PackedFloat64Array = _traffic_state(
		north + 30.0 * forward[0] - 20.0 * right_north,
		east + 30.0 * forward[1] - 20.0 * right_east,
		down, wrapf(heading + PI / 2.0, -PI, PI), 15.0)
	# These are separate encounter fixtures. The reachable controller holds its
	# chosen maneuver, so reset before each instead of replaying tick0 on a latch.
	pilot.configure(0, 1, SEED, TRIM, field)
	var cross_right: Dictionary = pilot.command(snapshot, 0, [_traffic("companion-1", 1, false, cross_right_state)])
	pilot.configure(0, 1, SEED, TRIM, field)
	var cross_left: Dictionary = pilot.command(snapshot, 0, [_traffic("companion-1", 1, false, cross_left_state)])
	var right_response: float = float(cross_right.get("roll", 0.0)) - float(baseline.get("roll", 0.0))
	var left_response: float = float(cross_left.get("roll", 0.0)) - float(baseline.get("roll", 0.0))
	_check("crossing traffic from either side activates avoidance", _avoids(cross_right) and _avoids(cross_left))
	_check("mirrored crossings produce opposite roll corrections", right_response * left_response < -1e-8,
		"right_delta=%.5f left_delta=%.5f" % [right_response, left_response])

	var faster_behind_state: PackedFloat64Array = _traffic_state(
		north - 30.0 * forward[0], east - 30.0 * forward[1], down, heading, 20.0)
	pilot.configure(0, 1, SEED, TRIM, field)
	var faster_behind: Dictionary = pilot.command(snapshot, 0,
		[_traffic("companion-2", 2, false, faster_behind_state)])
	_check("faster aircraft closing from behind activates avoidance", _avoids(faster_behind)
		and not _same_roll(faster_behind, baseline))

	var own_traffic: Dictionary = _traffic("companion-0", 0, false, own_state)
	pilot.configure(0, 1, SEED, TRIM, field)
	var self_packet: Dictionary = pilot.command(snapshot, 0, [own_traffic])
	_check("self entry keyed by id and slot is ignored", not self_packet.get("avoidance_active", true)
		and _same_roll(self_packet, baseline))
	var player_alias: Dictionary = {"id": "player", "player": true, "state": head_on_state}
	var alias_packet: Dictionary = pilot.command(snapshot, 0, [player_alias])
	_check("traffic player alias activates avoidance", _avoids(alias_packet))


func _snapshot(pose: Dictionary) -> Dictionary:
	var heading: float = float(pose.heading_rad)
	var attitude: PackedFloat64Array = Math3D.q_from_euler(heading, 0.0, 0.0)
	var state: PackedFloat64Array = RigidBody.make_state(
		PackedFloat64Array([float(pose.north), float(pose.east), -float(pose.height_m)]),
		PackedFloat64Array([float(TRIM.V), 0.0, 0.0]), attitude, PackedFloat64Array([0.0, 0.0, 0.0]))
	return {
		"id": "companion-0", "player": false, "state": state,
		"airspeed_m_s": float(TRIM.V), "wind_ned": NO_WIND,
		"ground_clearance_m": float(pose.height_agl_m), "trim": TRIM,
		"turbulence_rms_m_s": NO_TURBULENCE,
	}


func _snapshot_from_state(state: PackedFloat64Array, clearance: float) -> Dictionary:
	return {
		"id": "companion-1", "player": false, "state": state.duplicate(),
		"airspeed_m_s": float(TRIM.V), "wind_ned": NO_WIND,
		"ground_clearance_m": clearance, "trim": TRIM,
		"turbulence_rms_m_s": NO_TURBULENCE,
	}


func _traffic(id: String, slot: int, player: bool, state: PackedFloat64Array) -> Dictionary:
	return {"id": id, "slot": slot, "is_player": player, "wingspan_m": 1.7, "state": state}


func _traffic_state(north: float, east: float, down: float, heading: float, speed_m_s: float) -> PackedFloat64Array:
	return RigidBody.make_state(PackedFloat64Array([north, east, down]),
		PackedFloat64Array([speed_m_s, 0.0, 0.0]), Math3D.q_from_euler(heading, 0.0, 0.0),
		PackedFloat64Array([0.0, 0.0, 0.0]))


func _poses_identical(first: Dictionary, second: Dictionary) -> bool:
	for key: String in ["north", "east", "height_m", "height_agl_m", "heading_rad"]:
		if float(first.get(key, NAN)) != float(second.get(key, NAN)):
			return false
	return true


func _packet_bytes(packet: Dictionary) -> PackedByteArray:
	var axes := PackedFloat64Array([
		float(packet.get("roll", NAN)), float(packet.get("pitch", NAN)),
		float(packet.get("yaw", NAN)), float(packet.get("throttle", NAN)),
	])
	return axes.to_byte_array()


func _same_roll(first: Dictionary, second: Dictionary) -> bool:
	return absf(float(first.get("roll", NAN)) - float(second.get("roll", NAN))) < 1e-10


func _avoids(packet: Dictionary) -> bool:
	return bool(packet.get("ok", false)) and bool(packet.get("avoidance_active", false)) and _packet_bounded(packet)


func _packet_bounded(packet: Dictionary) -> bool:
	for key: String in ["roll", "pitch", "yaw", "throttle"]:
		var value: Variant = packet.get(key, NAN)
		if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)):
			return false
	return absf(float(packet.roll)) <= 1.0 and absf(float(packet.pitch)) <= 1.0 \
		and absf(float(packet.yaw)) <= 1.0 and float(packet.throttle) >= 0.0 and float(packet.throttle) <= 1.0
