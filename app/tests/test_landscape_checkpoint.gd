extends SceneTree

const FlightSession: Script = preload("res://sim/flight_session.gd")
const CollisionWorld: Script = preload("res://scenery/collision_world.gd")
const Config: Script = preload("res://environment/time_of_day_config.gd")
const VisualTimeline: Script = preload("res://environment/visual_timeline.gd")
const ENVELOPE_PATH := "res://app_state/visual_checkpoint.gd"
const FIELD_IDENTITY := "field:landscape-checkpoint-test"

var checks := 0
var failures := 0
var envelope_script: Script


func _initialize() -> void:
	envelope_script = load(ENVELOPE_PATH) as Script
	if envelope_script == null:
		printerr("could not load VisualCheckpoint script at ", ENVELOPE_PATH)
		quit(1)
		return
	_run()


func _run() -> void:
	var world_result: Dictionary = _world(5.0)
	_check("test collision world builds", world_result.get("ok", false))
	if not world_result.get("ok", false):
		_finish()
		return
	var world: Dictionary = world_result.world
	var session: Node = _session(world)
	if session == null:
		_finish()
		return
	var physics: Dictionary = session.checkpoint()
	_check("real collision-enabled FlightSession emits physics v7", physics.get("format", "") == "openrc-flight-checkpoint v7"
		and physics.get("physics_format", "") in ["openrc-flight-checkpoint v1", "openrc-flight-checkpoint v2",
			"openrc-flight-checkpoint v3", "openrc-flight-checkpoint v4", "openrc-flight-checkpoint v5", "openrc-flight-checkpoint v6"])
	_check("FlightSession binds the actual world SHA-256", physics.get("collision_world_identity", "") == world.identity
		and str(world.identity).length() == 64)
	var timeline_result: Dictionary = VisualTimeline.create(Config.defaults(), int(physics.simulation.tick))
	_check("visual timeline creates at the actual physics tick", timeline_result.get("ok", false))
	var timeline: Dictionary = timeline_result.get("timeline", {})
	var made: Dictionary = envelope_script.make(physics, timeline, FIELD_IDENTITY)
	_check("v7 collision physics can be paired with a fixed visual timeline", made.get("ok", false), str(made.get("errors", [])))
	if not made.get("ok", false):
		session.free()
		_finish()
		return
	var paired: Dictionary = made.checkpoint
	var loaded: Dictionary = envelope_script.read(bytes_to_var(var_to_bytes(paired)), FIELD_IDENTITY)
	_check("v7 pair reads", loaded.get("ok", false), str(loaded.get("errors", [])))
	_check("v7 physics native bytes round-trip exactly", var_to_bytes(loaded.get("physics", {})) == var_to_bytes(physics))
	_check("visual timeline native bytes round-trip exactly", var_to_bytes(loaded.get("timeline", {})) == var_to_bytes(timeline))
	_check("matching collision world restores the paired physical checkpoint", session.restore_checkpoint(loaded.physics))

	var tampered: Dictionary = paired.duplicate(true)
	tampered.physics.collision_world_identity = "a".repeat(64)
	_check("changing the nested world identity invalidates the outer payload digest",
		not envelope_script.read(tampered, FIELD_IDENTITY).get("ok", false))
	tampered.payload_sha256 = _digest(tampered.physics, tampered.timeline, tampered.field_identity)
	var rebound: Dictionary = envelope_script.read(tampered, FIELD_IDENTITY)
	_check("resealed v7 envelope still validates structurally", rebound.get("ok", false), str(rebound.get("errors", [])))
	var before: PackedByteArray = var_to_bytes(session.sim.checkpoint())
	_check("FlightSession rejects a validly hashed checkpoint from another world without mutation",
		not session.restore_checkpoint(rebound.physics) and var_to_bytes(session.sim.checkpoint()) == before)

	var other_result: Dictionary = _world(6.0)
	var other_session: Node = _session(other_result.world) if other_result.get("ok", false) else null
	if other_session != null:
		var other_before: PackedByteArray = var_to_bytes(other_session.sim.checkpoint())
		_check("distinct installed collision world rejects the original paired checkpoint",
			not other_session.restore_checkpoint(loaded.physics)
			and var_to_bytes(other_session.sim.checkpoint()) == other_before)
		other_session.free()
	else:
		_check("second collision-world receiver installs", false)

	var invalid_format: Dictionary = physics.duplicate(true)
	invalid_format.physics_format = "openrc-flight-checkpoint v7"
	_check("inner physics_format outside v1-v6 is rejected", not envelope_script.make(invalid_format, timeline, FIELD_IDENTITY).get("ok", false))
	var invalid_identity: Dictionary = physics.duplicate(true)
	invalid_identity.collision_world_identity = "bad-hash"
	_check("malformed collision_world_identity is rejected", not envelope_script.make(invalid_identity, timeline, FIELD_IDENTITY).get("ok", false))
	var physics_v6: Dictionary = physics.duplicate(true)
	physics_v6.physics_format = "openrc-flight-checkpoint v6"
	var v6_pair: Dictionary = envelope_script.make(physics_v6, timeline, FIELD_IDENTITY)
	_check("v7 envelope validates inner physics format v6", v6_pair.get("ok", false)
		and envelope_script.read(v6_pair.get("checkpoint", {}), FIELD_IDENTITY).get("ok", false))

	session.free()
	_finish()


func _session(world: Dictionary) -> Node:
	var session: Node = FlightSession.new()
	session.physics_enabled = false
	session.setup()
	root.add_child(session)
	session.input_enabled = false
	if not session.set_collision_world(world):
		_check("collision world installs at FlightSession boundary", false)
		session.free()
		return null
	_check("FlightSession remains valid after installing collision world", session.is_flyable())
	return session


func _world(north: float) -> Dictionary:
	return CollisionWorld.build(
		{pilot = {north = 0.0, east = 0.0, down = 0.0}, objects = []}, {groups = []},
		{fixtures = [{id = "test-lamp", type = "flood", north = north, east = 0.0, height = 8.0}]})


func _digest(physics: Dictionary, timeline: Dictionary, field_identity: String) -> String:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(var_to_bytes([physics, timeline, field_identity]))
	return hashing.finish().hex_encode()


func _check(label: String, valid: bool, detail := "") -> void:
	checks += 1
	if not valid:
		failures += 1
		printerr("FAIL ", label, " ", detail)


func _finish() -> void:
	print("landscape checkpoint: %d checks, %d failed" % [checks, failures])
	quit(1 if failures > 0 else 0)
