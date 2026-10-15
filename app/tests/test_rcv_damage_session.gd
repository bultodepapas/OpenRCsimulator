extends SceneTree

const Session = preload("res://sim/ground_vehicle/session.gd")
const Vehicle = preload("res://physics/ground_vehicle/vehicle_dynamics.gd")
const Damage = preload("res://physics/ground_vehicle/vehicle_damage.gd")
const NEUTRAL := {"throttle":0.0, "steering":0.0, "brake":0.0, "reverse":false, "armed":true}
var checks := 0
var failures := 0

## A repeatable supported-start crash fixture, restored by the normal reset/replay path.
## The initial speed is seeded only at spawn; subsequent motion is the production kernel.
class ImpactSession extends Session:
	var entry_speed := 8.0
	var barrier := true
	func _make_road(_course_value: Dictionary) -> Callable:
		return func(_north: float, _east: float) -> Dictionary:
			return {"height_m":0.0, "normal_ned":PackedFloat64Array([0.0,0.0,-1.0]),
				"mu":0.85, "rolling":1.0, "surface_id":"asphalt", "walls": [{
					"id":"impact-fixture", "north_min_m":4.0, "north_max_m":4.5,
					"east_min_m":-5.0, "east_max_m":5.0, "bottom_up_m":0.0,
					"top_up_m":1.0, "mu":0.5}] if barrier else []}
	func _make_spawn_state(model: Dictionary, _course_value: Dictionary, _pose: Dictionary,
			road: Callable, _pose_up_delta_m: float) -> PackedFloat64Array:
		var initialized: Dictionary = VehicleDynamics.initialize(model, road, 0.0, 0.0)
		if not initialized.ok: return PackedFloat64Array()
		var value: PackedFloat64Array = initialized.state
		value[VehicleDynamics.VEL] = entry_speed
		for i in 4: value[VehicleDynamics.WHEEL_SPIN+i] = entry_speed / float(model.tire_radius_m)
		return value

func _initialize() -> void:
	_run.call_deferred()

func _check(label: String, passed: bool) -> void:
	checks += 1
	if not passed: failures += 1
	print(("PASS: " if passed else "FAIL: ") + label)

func _resume(session) -> bool:
	return session.tick_once(NEUTRAL) and session.resume()

func _run() -> void:
	var intact = ImpactSession.new()
	intact.entry_speed = 0.0
	intact.barrier = false
	_check("supported intact fixture prepares", intact.prepare_default() and _resume(intact))
	var reference: PackedFloat64Array = intact.state_snapshot()
	var command := {"throttle":0.4, "steering":0.0, "brake":0.0, "reverse":false}
	var sample := command.duplicate()
	sample.armed = true
	var identical := true
	for i in 480:
		reference = Vehicle.step(reference, intact._model, command, Session.DT, intact._road)
		identical = identical and intact.tick_once(sample) and intact.state_snapshot().to_byte_array() == reference.to_byte_array()
	_check("damage observer preserves intact trajectory byte-for-byte", identical)
	_check("ordinary supported acceleration does not wear the truck", intact.damage_visual_state().body_damage == 0.0
		and intact.damage_visual_state().suspension_damage == 0.0 and intact.damage_visual_state().drive_scale == 1.0)
	intact.free()
	var impact = ImpactSession.new()
	_check("rolling wall-impact fixture prepares", impact.prepare_default() and _resume(impact))
	var contacted := false
	var finite := true
	var contact_checkpoint := {}
	for i in 240:
		finite = finite and impact.tick_once(NEUTRAL)
		if not finite: break
		var telemetry: Dictionary = impact.telemetry_snapshot()
		if int(telemetry.get("wall_contact_count",0)) > 0:
			contacted = true
			if contact_checkpoint.is_empty() and impact.damage_visual_state().body_damage > 0.0:
				contact_checkpoint = impact.checkpoint()
	_check("real wall impact is finite and accumulates damage", finite and contacted and impact.damage_visual_state().body_damage > 0.0)
	print("Wall damage after one second: ", impact.damage_visual_state())
	var final_state: PackedFloat64Array = impact.state_snapshot()
	var final_damage: PackedFloat64Array = impact.damage_snapshot()
	var tape: PackedFloat64Array = impact.control_tape_snapshot()
	_check("same input tape replays body state and damage exactly", impact.replay(tape)
		and impact.state_snapshot().to_byte_array() == final_state.to_byte_array()
		and impact.damage_snapshot().to_byte_array() == final_damage.to_byte_array())
	var checkpoint_command := NEUTRAL.duplicate()
	checkpoint_command.throttle = 0.8
	_check("damaged checkpoint fixture accepts requested throttle", _resume(impact)
		and impact.tick_once(checkpoint_command))
	var control_checkpoint: Dictionary = impact.checkpoint()
	var checkpoint_applied := impact._decode_float64_blob(control_checkpoint.get("applied_controls_f64_base64", ""), 4)
	var tampered_applied := control_checkpoint.duplicate(true)
	if checkpoint_applied.size() == 4:
		checkpoint_applied[0] = 0.0
		tampered_applied.applied_controls_f64_base64 = impact._base64_bytes(checkpoint_applied.to_byte_array())
		tampered_applied.checkpoint_sha256 = impact._checkpoint_hash(tampered_applied)
	var checkpoint_state_before_tamper: PackedFloat64Array = impact.state_snapshot()
	var checkpoint_damage_before_tamper: PackedFloat64Array = impact.damage_snapshot()
	_check("checkpoint rejects impossible applied throttle after rehash", checkpoint_applied.size() == 4
		and not impact.can_restore_checkpoint(tampered_applied)
		and not impact.restore_checkpoint(tampered_applied)
		and impact.state_snapshot().to_byte_array() == checkpoint_state_before_tamper.to_byte_array()
		and impact.damage_snapshot().to_byte_array() == checkpoint_damage_before_tamper.to_byte_array())
	_check("post-impact checkpoint remains internally consistent", impact.can_restore_checkpoint(control_checkpoint)
		and impact.restore_checkpoint(control_checkpoint))
	var fork = ImpactSession.new()
	_check("checkpoint includes active impact episode", not contact_checkpoint.is_empty() and fork.prepare_default()
		and fork.restore_checkpoint(contact_checkpoint) and _resume(fork))
	if not contact_checkpoint.is_empty():
		var continuity := true
		for i in range(int(contact_checkpoint.tick),240):
			continuity = continuity and fork.tick_once(NEUTRAL)
		_check("active contact checkpoint matches uninterrupted continuation", continuity
			and fork.state_snapshot().to_byte_array() == final_state.to_byte_array()
			and fork.damage_snapshot().to_byte_array() == final_damage.to_byte_array())
		var corrupted := contact_checkpoint.duplicate(true)
		var bad: PackedFloat64Array = fork._decode_float64_blob(corrupted.damage_state_f64_base64, Damage.SNAPSHOT_SIZE)
		bad[0] = NAN
		corrupted.damage_state_f64_base64 = fork._base64_bytes(bad.to_byte_array())
		corrupted.damage_state_sha256 = fork._hash_bytes(bad.to_byte_array())
		corrupted.checkpoint_sha256 = fork._checkpoint_hash(corrupted)
		var before: PackedFloat64Array = fork.damage_snapshot()
		_check("invalid damage checkpoint is rejected transactionally", not fork.restore_checkpoint(corrupted)
			and fork.damage_snapshot() == before)
	fork.free()
	_check("damaged session recording starts", impact.start_recording())
	_check("damaged session resumes", _resume(impact))
	var requested := NEUTRAL.duplicate()
	requested.throttle = 0.8
	var controlled := true
	for i in 60:
		controlled = controlled and impact.tick_once(requested)
		controlled = controlled and impact._last_effective_controls.throttle <= requested.throttle
		controlled = controlled and impact._last_effective_controls.brake == 0.0 and impact._last_effective_controls.steering == 0.0
	_check("damage never adds throttle, braking or steering", controlled)
	impact.stop_recording()
	var name := "rcv-damage-test-%d" % Time.get_ticks_usec()
	var exported: Dictionary = impact.export_recording(name)
	_check("damage recording exports", exported.get("ok",false))
	if exported.get("ok",false):
		var metadata: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(exported.metadata_path))
		var csv := FileAccess.get_file_as_string(exported.csv_path)
		_check("recording preserves damage and applied control channels", metadata.version == 3
			and metadata.damage_state_layout.size() == Damage.SNAPSHOT_SIZE
			and csv.contains("drive_scale") and csv.contains("applied_controls")
			and not str(metadata.initial_damage_f64_base64).is_empty())
		DirAccess.remove_absolute(ProjectSettings.globalize_path(exported.csv_path))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(exported.metadata_path))
	_check("recovery repairs and marks the run assisted", impact.manual_recovery() and not impact.run_valid
		and impact.damage_visual_state().body_damage == 0.0 and impact.damage_visual_state().drive_scale == 1.0)
	_check("reset restores intact initial condition", impact.reset() and impact.tick == 0
		and impact.damage_visual_state().body_damage == 0.0)
	impact.free()
	print("RCV damage Session: %d/%d checks passed" % [checks-failures, checks])
	quit(1 if failures else 0)
